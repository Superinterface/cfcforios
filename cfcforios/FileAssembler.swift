import Foundation

// MARK: - 文件组装器
struct FileAssembler {
    
    /// 将数据保存到临时文件，返回文件 URL
    /// - Parameters:
    ///   - data: 文件二进制数据
    ///   - fileName: 用户指定的文件名（含扩展名，如 "photo.jpg"）
    /// - Returns: 临时文件的 URL，保存失败返回 nil
    static func saveToTemporaryFile(data: Data, fileName: String) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        do {
            // 如果同名文件已存在，先删除
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            try data.write(to: fileURL)
            return fileURL
        } catch {
            print("[FileAssembler] 保存失败: \(error)")
            return nil
        }
    }
}
