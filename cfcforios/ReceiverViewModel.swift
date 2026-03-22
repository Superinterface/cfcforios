import SwiftUI
import AVFoundation

// MARK: - 接收状态管理 (libcimbar 版)
class ReceiverViewModel: ObservableObject {
    
    enum State {
        case scanning
        case completed
    }
    
    @Published var state: State = .scanning
    @Published var progress: Double = 0
    @Published var receivedCount: Int = 0 // 为了兼容旧 UI，不一定全都能用
    @Published var totalCount: Int = 0    // 为了兼容旧 UI
    @Published var recoveredCount: Int = 0 // 为了兼容旧 UI
    @Published var speedText: String = "Decoding..."
    @Published var finalFileURL: URL?
    
    let cameraManager = CameraManager()
    
    // 我们现在不再需要 LTDecoder 和 PacketParser
    // 因为 C++ 层的 CimbarWrapper 会帮我们搞定一切：
    // 包括纠错、拼包、ZSTD 解压，最后直接吐出完整的 Data
    
    private var finalExtractedData: Data?
    
    init() {
        // 1. 挂载进度回调
        cameraManager.onProgressUpdate = { [weak self] currentProgress in
            DispatchQueue.main.async {
                self?.progress = currentProgress
                // 这里可以粗略地用百分比表示，或者保留 0
                self?.receivedCount = Int(currentProgress * 100)
                self?.totalCount = 100
                if currentProgress > 0 {
                    self?.speedText = String(format: "%.1f%%", currentProgress * 100)
                }
            }
        }
        
        // 2. 挂载最终文件完成回调
        cameraManager.onFileDecoded = { [weak self] data in
            DispatchQueue.main.async {
                self?.handleFileDecoded(data)
            }
        }
        
        cameraManager.configure()
        cameraManager.start()
    }
    
    private func handleFileDecoded(_ data: Data) {
        // 这一帧终于凑齐了，C++ 层的水槽也水满了！
        guard state == .scanning else { return } // 避免重复触发
        
        self.finalExtractedData = data
        self.progress = 1.0
        self.speedText = "Complete"
        
        finishTransfer()
    }
    
    private func finishTransfer() {
        cameraManager.stop()
        state = .completed
        AudioServicesPlaySystemSound(1001) // 播放成功提示音
    }
    
    func saveFile(name: String, ext: String) -> URL? {
        // 直接拿 C++ 吐给我们的无暇无损的完整二进制数据
        guard let data = finalExtractedData else { return nil }
        
        let fileName = ext.isEmpty ? name : "\(name).\(ext)"
        let url = FileAssembler.saveToTemporaryFile(data: data, fileName: fileName)
        finalFileURL = url
        return url
    }
    
    func reset() {
        state = .scanning
        progress = 0
        receivedCount = 0
        totalCount = 0
        recoveredCount = 0
        speedText = "Decoding..."
        finalFileURL = nil
        finalExtractedData = nil
        
        // C++ 的状态也需要清空
        cameraManager.resetDecoder()
        cameraManager.start()
    }
}

