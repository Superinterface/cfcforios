import Foundation

// MARK: - Fountain Code 包类型
struct LTPacket {
    let totalBlocks: Int
    let fileSize: Int
    let packetIndex: Int
    let payload: Data
}

struct LTRuntimeEquation {
    var indices: Set<Int>
    var data: Data
}

// MARK: - LT PRNG 工具
struct PRNG {
    var state: UInt32
    init(seed: UInt32) { self.state = seed }
    mutating func next() -> UInt32 {
        state = (state &* 1103515245 &+ 12345) & 0x7FFFFFFF
        return state
    }
    mutating func nextRange(min: Int, max: Int) -> Int {
        return min + Int(next() % UInt32(max - min + 1))
    }
}

class LTDecoder {
    
    static let chunkSize = 500
    
    private(set) var knownChunks: [Int: Data] = [:]
    private var equations: [LTRuntimeEquation] = []
    
    private(set) var totalChunks: Int = 0
    private(set) var fileSize: Int = 0
    private(set) var recoveredCount: Int = 0 // 通过公式推导出来的包数（非原文接收到的）
    
    var receivedCount: Int { knownChunks.count }
    var isComplete: Bool { totalChunks > 0 && knownChunks.count >= totalChunks }
    var progress: Double {
        guard totalChunks > 0 else { return 0 }
        return Double(knownChunks.count) / Double(totalChunks)
    }
    
    // 我们用一个已接收 Set 避免处理完全重复的 original index
    private var processedOriginalIndices: Set<Int> = []
    
    func reset() {
        knownChunks.removeAll()
        equations.removeAll()
        processedOriginalIndices.removeAll()
        totalChunks = 0
        fileSize = 0
        recoveredCount = 0
    }
    
    @discardableResult
    func addPacket(_ p: LTPacket) -> Bool {
        if self.totalChunks == 0 {
            self.totalChunks = p.totalBlocks
            self.fileSize = p.fileSize
        }
        
        // 解析该 packet 对应的度数和图谱
        let K = p.totalBlocks
        let idx = p.packetIndex
        
        var d = 1
        var indices = [Int]()
        
        if idx < K {
            // Source block (Degree 1)
            d = 1
            indices = [idx]
            
            // 快速去重判定
            if processedOriginalIndices.contains(idx) { return false }
            processedOriginalIndices.insert(idx)
        } else {
            // Fountain block (Degree > 1)
            var prngDegree = PRNG(seed: UInt32(idx) + 100000)
            let pVal = prngDegree.nextRange(min: 1, max: 100)
            if pVal <= 30 { d = min(2, K) }
            else if pVal <= 60 { d = min(3, K) }
            else if pVal <= 80 { d = min(4, K) }
            else if pVal <= 90 { d = min(5, K) }
            else { d = max(1, K / 2) }
            
            var prngIndices = PRNG(seed: UInt32(idx))
            var pool = Array(0..<K)
            for i in 0..<d {
                let r = prngIndices.nextRange(min: i, max: K - 1)
                pool.swapAt(i, r)
                indices.append(pool[i])
            }
        }
        
        // 构建初始 Equation，先把我们已知的 Chunk 异或掉以降低度数
        var eq = LTRuntimeEquation(indices: Set(indices), data: p.payload)
        
        for idx in eq.indices {
            if let knownData = knownChunks[idx] {
                eq.indices.remove(idx)
                eq.data = xorBytes(eq.data, paddedData(knownData))
            }
        }
        
        // 开始信念传播推导
        if eq.indices.isEmpty {
            // 无新信息
            return false
        } else if eq.indices.count == 1 {
            // 我们直接获得了一个新块
            let learnedIdx = eq.indices.first!
            processLearnedChunk(index: learnedIdx, data: eq.data, isDirect: (idx < K))
            return true
        } else {
            // 存入方程池等待将来降维
            equations.append(eq)
            return true
        }
    }
    
    private func processLearnedChunk(index: Int, data: Data, isDirect: Bool) {
        if knownChunks[index] != nil { return }
        
        let actualSize = chunkSizeFor(index: index)
        knownChunks[index] = data.prefix(actualSize)
        processedOriginalIndices.insert(index) // 防止 Source Block 再次处理
        
        if !isDirect { recoveredCount += 1 }
        
        // 反向传播给现有方程
        var q = [index]
        while !q.isEmpty {
            let k = q.removeFirst()
            let knownData = paddedData(knownChunks[k]!)
            
            // 倒序遍历方程集合以支持安全删除
            for i in stride(from: equations.count - 1, through: 0, by: -1) {
                if equations[i].indices.contains(k) {
                    equations[i].indices.remove(k)
                    equations[i].data = xorBytes(equations[i].data, knownData)
                    
                    if equations[i].indices.count == 1 {
                        let newlyLearned = equations[i].indices.first!
                        let actual = chunkSizeFor(index: newlyLearned)
                        knownChunks[newlyLearned] = equations[i].data.prefix(actual)
                        processedOriginalIndices.insert(newlyLearned)
                        recoveredCount += 1
                        q.append(newlyLearned)
                        equations.remove(at: i) // 方程已解，移除
                    } else if equations[i].indices.isEmpty {
                        equations.remove(at: i) // 冗余方程
                    }
                }
            }
        }
    }
    
    // MARK: - 工具
    private func paddedData(_ data: Data) -> Data {
        if data.count >= LTDecoder.chunkSize { return data.prefix(LTDecoder.chunkSize) }
        var padded = data
        padded.append(Data(count: LTDecoder.chunkSize - data.count))
        return padded
    }
    
    private func xorBytes(_ a: Data, _ b: Data) -> Data {
        let len = max(a.count, b.count)
        var result = Data(count: len)
        let aBytes = [UInt8](a)
        let bBytes = [UInt8](b)
        for i in 0..<len {
            let va: UInt8 = i < aBytes.count ? aBytes[i] : 0
            let vb: UInt8 = i < bBytes.count ? bBytes[i] : 0
            result[i] = va ^ vb
        }
        return result
    }
    
    private func chunkSizeFor(index: Int) -> Int {
        guard fileSize > 0, totalChunks > 0 else { return LTDecoder.chunkSize }
        if index == totalChunks - 1 {
            let remainder = fileSize % LTDecoder.chunkSize
            return remainder == 0 ? LTDecoder.chunkSize : remainder
        }
        return LTDecoder.chunkSize
    }
    
    func assembleData() -> Data? {
        guard isComplete else { return nil }
        var result = Data()
        for i in 0..<totalChunks {
            if let chunk = knownChunks[i] {
                result.append(chunk)
            } else {
                return nil // 不应该发生
            }
        }
        if fileSize > 0 && result.count > fileSize {
            result = result.prefix(fileSize)
        }
        return result
    }
}
