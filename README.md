# cfcforios - Cimbar 解码器 for iOS

本项目是一个基于 iOS 的动态高密度二维码（Cimbar）解码应用程序。通过系统摄像头捕捉动态视频流，利用底层 C++ 库 (`libcimbar`) 进行极速解码和文件恢复。

## 🌟 核心功能
*   **实时扫描**：通过 `AVFoundation` 捕捉 1080p 视频流，并实时处理。
*   **高效解码**：集成 `libcimbar` C++ 核心，利用喷泉码（Fountain Codes）技术，即使在丢失部分帧的情况下也能恢复完整文件。
*   **状态反馈**：实时显示解码进度、百分比以及速度提示。
*   **自动存储**：文件解码完成后自动保存至系统临时目录，并支持结果预览。

## 🛠️ 技术栈
*   **Frontend**: SwiftUI (ReceiverView, ReceiverViewModel)
*   **Backend**: Swift & Objective-C++ 混合编程
*   **Engine**: `libcimbar` (C++20)
*   **Vision**: OpenCV & Accelerate Framework (图像预处理)

## 📂 项目结构
*   `cfcforios/`：主源代码文件夹。
    *   `CimbarWrapper.mm/.h`：Objective-C++ 包装器，负责将 iOS `CVPixelBuffer` 转换为 `cv::Mat` 并喂给解码器。
    *   `CameraManager.swift`：相机流管理与预览组件。
    *   `ReceiverViewModel.swift`：业务逻辑与状态同步。
    *   `ScanCode-Bridging-Header.h`：桥接头文件，将 C++ 接口暴露给 Swift。
*   `cfcforios.xcodeproj/`：Xcode 工程配置文件。

## 🚀 运行环境
*   **iOS SDK**: 18.5+
*   **Xcode**: 16.4+
*   **硬件**: 需要真机运行（摄像头驱动需硬件支持）

## ⚠️ 注意事项
1.  **权限**：运行前请确保已开启摄像头权限（在 `Info.plist` 中已配置 `NSCameraUsageDescription`）。
2.  **构建环境**：由于使用了 OpenCV，建议确保工程内的 `HEADER_SEARCH_PATHS` 和 `FRAMEWORK_SEARCH_PATHS` 正确配置。

## 📄 License
基于开源项目 [cimbar](https://github.com/sz3/cimbar) 的 iOS 实现。