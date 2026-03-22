import SwiftUI

// MARK: - 系统分享面板
struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - 接收主界面
struct ReceiverView: View {
    @StateObject private var viewModel = ReceiverViewModel()
    @Environment(\.scenePhase) var scenePhase
    @State private var fileName: String = ""
    @State private var fileExt: String = ""
    @State private var showShareSheet = false
    @State private var shareURL: URL?
    @State private var showCompletedAnimation = false
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            // 相机预览（全屏底层）
            CameraPreview(session: viewModel.cameraManager.session)
                .edgesIgnoringSafeArea(.all)
            
            // 半透明渐变遮罩
            if viewModel.state == .completed {
                LinearGradient(
                    colors: [.black.opacity(0.7), .black.opacity(0.4), .black.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .edgesIgnoringSafeArea(.all)
                .transition(.opacity)
            }
            
            // 覆盖层
            VStack(spacing: 0) {
                headerBar
                    .padding(.top, 8)
                
                Spacer()
                
                if viewModel.state == .scanning {
                    scanningOverlay
                } else {
                    completedOverlay
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.8).combined(with: .opacity),
                            removal: .opacity
                        ))
                }
                
                Spacer()
                
                if viewModel.state == .scanning {
                    progressBar
                        .padding(.bottom, 8)
                }
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: viewModel.state == .completed)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showShareSheet) {
            if let url = shareURL {
                ShareSheet(items: [url])
            }
        }
        .onAppear {
            if viewModel.state == .completed {
                resetTransfer()
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active && viewModel.state == .scanning {
                viewModel.cameraManager.start()
            }
        }
        .onChange(of: viewModel.state) { newState in
            if newState == .completed {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                    showCompletedAnimation = true
                }
            } else {
                showCompletedAnimation = false
            }
        }
    }
    
    // MARK: - 顶部标题栏
    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "wave.3.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.green)
            
            Text("CimBar 接收器")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
    }
    
    // MARK: - 扫描中
    private var scanningOverlay: some View {
        VStack(spacing: 16) {
            // 扫描框（四角标记线）
            ZStack {
                // 四个角落的 L 形标记线
                ScanCorners()
                    .stroke(
                        LinearGradient(
                            colors: [.green, .green.opacity(0.5)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 280, height: 280)
                
                // 脉冲动画
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.green.opacity(0.15), lineWidth: 1.5)
                    .frame(width: 280, height: 280)
                    .scaleEffect(pulseScale)
                    .opacity(2 - Double(pulseScale))
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                            pulseScale = 1.15
                        }
                    }
            }
            
            // 进度百分比（扫描时显示）
            if viewModel.progress > 0 {
                Text(String(format: "%.1f%%", viewModel.progress * 100))
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: viewModel.progress)
            }
            
            Text("请将摄像头对准发送端的动态码")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.black.opacity(0.4), in: Capsule())
        }
    }
    
    // MARK: - 传输完成
    private var completedOverlay: some View {
        VStack(spacing: 0) {
            // 成功图标 + 文字
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.green.opacity(0.3), .clear],
                                center: .center,
                                startRadius: 20,
                                endRadius: 60
                            )
                        )
                        .frame(width: 120, height: 120)
                    
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.green, .mint],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .scaleEffect(showCompletedAnimation ? 1.0 : 0.3)
                        .opacity(showCompletedAnimation ? 1.0 : 0)
                }
                
                Text("传输完成")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                
                Text("文件已成功解码并解压")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.bottom, 24)
            
            // 保存卡片
            VStack(spacing: 16) {
                // 文件名输入区域
                VStack(alignment: .leading, spacing: 8) {
                    Text("文件名称")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                        .textCase(.uppercase)
                        .tracking(0.5)
                    
                    HStack(spacing: 6) {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.4))
                        
                        TextField("输入文件名", text: $fileName)
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(.white)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        
                        Text(".")
                            .foregroundColor(.white.opacity(0.3))
                            .font(.system(size: 16, weight: .bold))
                        
                        TextField("扩展名", text: $fileExt)
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(.white)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .frame(width: 65)
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                }
                
                // 操作按钮
                HStack(spacing: 12) {
                    // 保存 / 分享
                    Button(action: saveAndShare) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .semibold))
                            Text("保存 / 分享")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: fileName.isEmpty
                                    ? [.gray.opacity(0.3), .gray.opacity(0.2)]
                                    : [Color(red: 0.2, green: 0.5, blue: 1.0), Color(red: 0.4, green: 0.3, blue: 0.9)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(14)
                        .shadow(color: fileName.isEmpty ? .clear : .blue.opacity(0.3), radius: 8, y: 4)
                    }
                    .disabled(fileName.isEmpty)
                    
                    // 重新接收
                    Button(action: resetTransfer) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 48, height: 48)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
                            )
                    }
                }
            }
            .padding(20)
            .background(.ultraThinMaterial)
            .cornerRadius(24)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
            .padding(.horizontal, 24)
        }
    }
    
    // MARK: - 底部进度条
    private var progressBar: some View {
        VStack(spacing: 8) {
            // 自定义进度条
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // 背景轨道
                    Capsule()
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 6)
                    
                    // 进度填充
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.green, .mint],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, geo.size.width * viewModel.progress), height: 6)
                        .animation(.easeInOut(duration: 0.3), value: viewModel.progress)
                    
                    // 发光端点
                    if viewModel.progress > 0.01 {
                        Circle()
                            .fill(.green)
                            .frame(width: 10, height: 10)
                            .shadow(color: .green.opacity(0.6), radius: 6)
                            .offset(x: max(0, geo.size.width * viewModel.progress - 5))
                            .animation(.easeInOut(duration: 0.3), value: viewModel.progress)
                    }
                }
            }
            .frame(height: 10)
            
            HStack {
                Text(String(format: "%.0f%%", viewModel.progress * 100))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.green)
                
                Spacer()
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                    Text("接收中")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .padding(.horizontal, 16)
    }
    
    // MARK: - 操作
    private func saveAndShare() {
        guard let url = viewModel.saveFile(name: fileName, ext: fileExt) else { return }
        shareURL = url
        showShareSheet = true
    }
    
    private func resetTransfer() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            viewModel.reset()
            fileName = ""
            fileExt = ""
            shareURL = nil
            showCompletedAnimation = false
        }
    }
}

// MARK: - 扫描框四角标记线
struct ScanCorners: Shape {
    func path(in rect: CGRect) -> Path {
        let cornerLength: CGFloat = 30
        let cornerRadius: CGFloat = 16
        
        var path = Path()
        
        // 左上角
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + cornerLength))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cornerRadius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + cornerRadius, y: rect.minY),
                          control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + cornerLength, y: rect.minY))
        
        // 右上角
        path.move(to: CGPoint(x: rect.maxX - cornerLength, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + cornerRadius),
                          control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cornerLength))
        
        // 右下角
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerLength))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY),
                          control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - cornerLength, y: rect.maxY))
        
        // 左下角
        path.move(to: CGPoint(x: rect.minX + cornerLength, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - cornerRadius),
                          control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - cornerLength))
        
        return path
    }
}
