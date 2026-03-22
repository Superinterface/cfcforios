import Foundation

// MARK: - 协议解析器
// 喷泉包格式：
//   L|K/fileSize/packetIndex|base64Payload
struct PacketParser {
    
    static func parseLT(_ text: String) -> LTPacket? {
        guard text.hasPrefix("L|") else { return nil }
        
        let parts = text.split(separator: "|", maxSplits: 2)
        guard parts.count == 3 else { return nil }
        
        let headerStr = String(parts[1])
        let base64Payload = String(parts[2])
        
        guard let payloadData = Data(base64Encoded: base64Payload) else { return nil }
        
        let h = headerStr.split(separator: "/")
        guard h.count == 3,
              let totalBlocks = Int(h[0]),
              let fileSize = Int(h[1]),
              let packetIndex = Int(h[2]) else { return nil }
        
        return LTPacket(totalBlocks: totalBlocks, fileSize: fileSize, packetIndex: packetIndex, payload: payloadData)
    }
}
