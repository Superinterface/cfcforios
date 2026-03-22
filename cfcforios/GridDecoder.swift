import CoreImage
import UIKit
import AVFoundation

/// ColorGrid 解码器：从摄像头帧中检测绿色角标、透视校正、采样色块、输出二进制数据
class GridDecoder {
    
    // MARK: - 常量（与发送端一致）
    static let gridSize = 80
    static let markerSize = 5
    static let cellSize = 9
    static let bytesPerFrame = 1575  // 6300 data cells × 2 bits ÷ 8
    
    // 数据颜色参考值 (R, G, B)
    // 00=黑, 01=红, 10=蓝, 11=白
    private static let refColors: [(r: Int, g: Int, b: Int)] = [
        (0, 0, 0),       // 00
        (255, 0, 0),     // 01
        (0, 0, 255),     // 10
        (255, 255, 255)  // 11
    ]
    
    // 预计算数据格位置（行优先，跳过角标）
    private static let dataCells: [(row: Int, col: Int)] = {
        var cells: [(Int, Int)] = []
        let m = markerSize, g = gridSize
        for r in 0..<g {
            for c in 0..<g {
                if r < m && c < m { continue }
                if r < m && c >= g - m { continue }
                if r >= g - m && c < m { continue }
                if r >= g - m && c >= g - m { continue }
                cells.append((r, c))
            }
        }
        return cells
    }()
    
    // MARK: - 主解码方法
    
    /// 从 CVPixelBuffer 解码一帧 ColorGrid 数据
    /// - Returns: 560 字节的二进制数据，或 nil（检测失败）
    func decode(pixelBuffer: CVPixelBuffer) -> Data? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let buf = base.assumingMemoryBound(to: UInt8.self)
        
        // 1. 在 4 个象限中检测绿色角标质心
        guard let corners = findGreenCorners(buf: buf, width: width, height: height, bytesPerRow: bytesPerRow) else {
            return nil
        }
        
        // 2. 从角标质心外推到网格实际四角
        let gridCorners = extrapolateGridCorners(markerCentroids: corners, gridSize: GridDecoder.gridSize, markerSize: GridDecoder.markerSize)
        
        // 3. 对每个数据格，用双线性插值算出在摄像头图像中的像素位置，采样颜色
        return sampleAndDecode(buf: buf, width: width, height: height, bytesPerRow: bytesPerRow, gridCorners: gridCorners)
    }
    
    // MARK: - 绿色角标检测
    
    private func findGreenCorners(buf: UnsafePointer<UInt8>, width: Int, height: Int, bytesPerRow: Int) -> [CGPoint]? {
        let midX = width / 2
        let midY = height / 2
        let step = 6
        
        // 搜索完整的 4 个象限（用大步长保证速度）
        let quadrants: [(xLo: Int, xHi: Int, yLo: Int, yHi: Int)] = [
            (0, midX, 0, midY),
            (midX, width, 0, midY),
            (0, midX, midY, height),
            (midX, width, midY, height)
        ]
        
        var corners: [CGPoint] = []
        
        for q in quadrants {
            var sumX: Double = 0, sumY: Double = 0, count: Double = 0
            
            var y = q.yLo
            while y < q.yHi {
                var x = q.xLo
                while x < q.xHi {
                    let off = y * bytesPerRow + x * 4
                    let b = Int(buf[off])
                    let g = Int(buf[off + 1])
                    let r = Int(buf[off + 2])
                    
                    // 宽松的绿色检测（相机白平衡会偏移颜色）
                    if g > 80 && g > r + 30 && g > b + 30 {
                        sumX += Double(x)
                        sumY += Double(y)
                        count += 1
                    }
                    x += step
                }
                y += step
            }
            
            guard count > 3 else { return nil }
            corners.append(CGPoint(x: sumX / count, y: sumY / count))
        }
        
        return corners
    }
    
    // MARK: - 从角标质心外推网格四角
    
    private func extrapolateGridCorners(markerCentroids: [CGPoint], gridSize: Int, markerSize: Int) -> (tl: CGPoint, tr: CGPoint, bl: CGPoint, br: CGPoint) {
        let tl = markerCentroids[0]
        let tr = markerCentroids[1]
        let bl = markerCentroids[2]
        let br = markerCentroids[3]
        
        // 角标质心之间跨越 (gridSize - markerSize) = 44 格
        // 每格的向量
        let span = CGFloat(gridSize - markerSize) // 44
        let halfMarker = CGFloat(markerSize) / 2.0 // 2
        
        // 顶边方向向量 (每格)
        let topVecX = (tr.x - tl.x) / span
        let topVecY = (tr.y - tl.y) / span
        // 左边方向向量 (每格)
        let leftVecX = (bl.x - tl.x) / span
        let leftVecY = (bl.y - tl.y) / span
        
        // 网格左上角 = TL质心 - halfMarker*(topVec + leftVec)
        let gridTL = CGPoint(
            x: tl.x - halfMarker * topVecX - halfMarker * leftVecX,
            y: tl.y - halfMarker * topVecY - halfMarker * leftVecY
        )
        let gridTR = CGPoint(
            x: tr.x + halfMarker * topVecX - halfMarker * leftVecX,
            y: tr.y + halfMarker * topVecY - halfMarker * leftVecY
        )
        let gridBL = CGPoint(
            x: bl.x - halfMarker * topVecX + halfMarker * leftVecX,
            y: bl.y - halfMarker * topVecY + halfMarker * leftVecY
        )
        let gridBR = CGPoint(
            x: br.x + halfMarker * topVecX + halfMarker * leftVecX,
            y: br.y + halfMarker * topVecY + halfMarker * leftVecY
        )
        
        return (gridTL, gridTR, gridBL, gridBR)
    }
    
    // MARK: - 采样与解码
    
    private func sampleAndDecode(buf: UnsafePointer<UInt8>, width: Int, height: Int, bytesPerRow: Int, gridCorners: (tl: CGPoint, tr: CGPoint, bl: CGPoint, br: CGPoint)) -> Data? {
        
        let g = CGFloat(GridDecoder.gridSize)
        var result = Data(count: GridDecoder.bytesPerFrame)
        
        for (cellIndex, cell) in GridDecoder.dataCells.enumerated() {
            // 归一化坐标 (0~1)
            let u = (CGFloat(cell.col) + 0.5) / g
            let v = (CGFloat(cell.row) + 0.5) / g
            
            // 双线性插值: 在摄像头图像中的像素位置
            let topX = gridCorners.tl.x * (1 - u) + gridCorners.tr.x * u
            let topY = gridCorners.tl.y * (1 - u) + gridCorners.tr.y * u
            let botX = gridCorners.bl.x * (1 - u) + gridCorners.br.x * u
            let botY = gridCorners.bl.y * (1 - u) + gridCorners.br.y * u
            
            let px = Int(topX * (1 - v) + botX * v)
            let py = Int(topY * (1 - v) + botY * v)
            
            // 边界检查：越界的格子用黑色(0)，不要拒绝整帧
            guard px >= 0 && px < width && py >= 0 && py < height else { continue }
            
            let off = py * bytesPerRow + px * 4
            let bVal = Int(buf[off])
            let gVal = Int(buf[off + 1])
            let rVal = Int(buf[off + 2])
            
            // 最近颜色匹配
            let bits = classifyColor(r: rVal, g: gVal, b: bVal)
            
            // 打包到字节: 每 4 个格 = 1 字节
            let byteIdx = cellIndex / 4
            let shift = 6 - (cellIndex % 4) * 2
            if byteIdx < result.count {
                result[byteIdx] |= UInt8(bits << shift)
            }
        }
        
        return result
    }
    
    // MARK: - 颜色分类
    
    /// 返回最接近的颜色索引 (0-3)
    private func classifyColor(r: Int, g: Int, b: Int) -> Int {
        var minDist = Int.max
        var best = 0
        for (i, ref) in GridDecoder.refColors.enumerated() {
            let dr = r - ref.r
            let dg = g - ref.g
            let db = b - ref.b
            let dist = dr * dr + dg * dg + db * db
            if dist < minDist {
                minDist = dist
                best = i
            }
        }
        return best
    }
}
