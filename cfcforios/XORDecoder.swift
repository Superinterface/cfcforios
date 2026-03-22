import Foundation

// MARK: - XOR 冗余解码器
class XORDecoder {
    
    /// 协议常量：每个 chunk 的最大字节数（与发送端一致）
    static let chunkSize = 500
    /// XOR 分组大小
    static let groupSize = 4
    
    // MARK: - 状态
    private var dataChunks: [Int: Data] = [:]
    private var xorGroups: [Int: Data] = [:]   // key = groupStart
    private(set) var totalChunks: Int = 0
    private(set) var fileSize: Int = 0
    private(set) var recoveredCount: Int = 0
    
    var receivedCount: Int { dataChunks.count }
    var isComplete: Bool { totalChunks > 0 && dataChunks.count >= totalChunks }
    var progress: Double {
        guard totalChunks > 0 else { return 0 }
        return Double(dataChunks.count) / Double(totalChunks)
    }
    
    // MARK: - 添加数据包
    
    /// 添加一个数据包，返回 true 如果是新包
    @discardableResult
    func addDataChunk(index: Int, total: Int, fileSize: Int, data: Data) -> Bool {
        if self.totalChunks == 0 {
            self.totalChunks = total
            self.fileSize = fileSize
        }
        guard dataChunks[index] == nil else { return false }
        dataChunks[index] = data
        tryRecover()
        return true
    }
    
    /// 添加一个 XOR 校验包
    func addXORChunk(groupStart: Int, groupEnd: Int, total: Int, data: Data) {
        if self.totalChunks == 0 { self.totalChunks = total }
        xorGroups[groupStart] = data
        tryRecover()
    }
    
    // MARK: - XOR 恢复
    
    /// 尝试通过 XOR 恢复缺失的包
    private func tryRecover() {
        for (groupStart, xorData) in xorGroups {
            let groupEnd = min(groupStart + XORDecoder.groupSize - 1, totalChunks - 1)
            let indices = Array(groupStart...groupEnd)
            let missing = indices.filter { dataChunks[$0] == nil }
            
            // 只能恢复恰好缺 1 个包的情况
            guard missing.count == 1 else { continue }
            let missingIndex = missing[0]
            
            // 用 XOR 数据和其他已有包做 XOR 运算恢复
            var recovered = paddedData(xorData)
            for idx in indices where idx != missingIndex {
                if let chunk = dataChunks[idx] {
                    recovered = xorBytes(recovered, paddedData(chunk))
                }
            }
            
            // 确定恢复数据的实际长度
            let actualSize = chunkSizeFor(index: missingIndex)
            dataChunks[missingIndex] = recovered.prefix(actualSize)
            recoveredCount += 1
        }
    }
    
    /// 将 Data 填充到 chunkSize 长度
    private func paddedData(_ data: Data) -> Data {
        if data.count >= XORDecoder.chunkSize { return data.prefix(XORDecoder.chunkSize) }
        var padded = data
        padded.append(Data(count: XORDecoder.chunkSize - data.count))
        return padded
    }
    
    /// 两段等长 Data 做 XOR
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
    
    /// 某个 chunk 的实际大小（最后一个 chunk 可能小于 chunkSize）
    private func chunkSizeFor(index: Int) -> Int {
        guard fileSize > 0, totalChunks > 0 else { return XORDecoder.chunkSize }
        if index == totalChunks - 1 {
            let remainder = fileSize % XORDecoder.chunkSize
            return remainder == 0 ? XORDecoder.chunkSize : remainder
        }
        return XORDecoder.chunkSize
    }
    
    // MARK: - 组装 & 重置
    
    /// 按序拼接所有 chunk，截断到 fileSize
    func assembleData() -> Data? {
        guard isComplete else { return nil }
        var result = Data()
        for i in 0..<totalChunks {
            if let chunk = dataChunks[i] {
                result.append(chunk)
            }
        }
        // 截断到实际文件大小（去除最后一个 chunk 的 padding）
        if fileSize > 0 && result.count > fileSize {
            result = result.prefix(fileSize)
        }
        return result
    }
    
    /// 重置所有状态，准备接收下一个文件
    func reset() {
        dataChunks.removeAll()
        xorGroups.removeAll()
        totalChunks = 0
        fileSize = 0
        recoveredCount = 0
    }
}
