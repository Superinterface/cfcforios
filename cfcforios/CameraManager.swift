import SwiftUI
import AVFoundation

// MARK: - 相机管理器（libcimbar 版）
class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    let session = AVCaptureSession()
    
    /// 解码进度回调 (0.0 - 1.0)
    var onProgressUpdate: ((Double) -> Void)?
    
    /// 当一整个文件被喷泉码彻底收集并解压完成后回调
    var onFileDecoded: ((Data) -> Void)?
    
    private let cameraQueue = DispatchQueue(label: "cfc.camera.queue")
    private var isConfigured = false
    private var isProcessing = false
    private var frameSkipCounter = 0
    
    // 实例化刚刚写好的 Objective-C++ 保安中介
    private let cimbarDecoder = CimbarWrapper()
    
    // MARK: - 配置
    func configure() {
        if isConfigured { return }
        isConfigured = true
        
        // Cimbar 需要相对清晰的图像，1080p 是个好选择
        session.sessionPreset = .hd1920x1080
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device)
        else { return }
        
        // 连续自动对焦
        try? device.lockForConfiguration()
        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }
        device.unlockForConfiguration()
        
        if session.canAddInput(input) {
            session.addInput(input)
        }
        
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        // CimbarWrapper 里面是将 BGRA 转换为 RGB，所以这里直接输出 BGRA 格式
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        output.setSampleBufferDelegate(self, queue: cameraQueue)
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
    }
    
    func start() {
        cameraQueue.async { [weak self] in
            // 每次启动重置 Decoder 状态
            self?.cimbarDecoder.reset()
            self?.session.startRunning()
        }
    }
    
    func stop() {
        cameraQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }
    
    func resetDecoder() {
        cameraQueue.async { [weak self] in
            self?.cimbarDecoder.reset()
        }
    }
    
    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        
        // 降低手机发热：Cimbar 计算量大，可以考虑每秒处理 15-20 帧即可，根据机型调整
        frameSkipCounter += 1
        guard frameSkipCounter % 2 == 0 else { return }
        
        guard !isProcessing else { return }
        isProcessing = true
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            isProcessing = false
            return
        }
        
        // 在相机线程同步调用 C++ 解码，避免画面积压
        let finalData = cimbarDecoder.decode(pixelBuffer)
        let currentProgress = cimbarDecoder.getProgress()
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 回调进度
            self.onProgressUpdate?(currentProgress)
            
            // 如果返回了非空数据，说明完整文件解压完啦！
            if let data = finalData, !data.isEmpty {
                self.onFileDecoded?(data)
            }
            
            self.isProcessing = false
        }
    }
}

// MARK: - 相机预览（SwiftUI 封装）
struct CameraPreview: UIViewControllerRepresentable {
    let session: AVCaptureSession
    
    func makeUIViewController(context: Context) -> CameraPreviewVC {
        let vc = CameraPreviewVC()
        vc.session = session
        return vc
    }
    
    func updateUIViewController(_ vc: CameraPreviewVC, context: Context) {}
}

class CameraPreviewVC: UIViewController {
    var session: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        guard let session = session else { return }
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        previewLayer = layer
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }
}

