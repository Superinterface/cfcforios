#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>

NS_ASSUME_NONNULL_BEGIN

/// Objective-C++ 包装器，负责将 iOS 相机的 CVPixelBuffer 转换为 OpenCV cv::Mat 并交给 C++ libCimbar 处理
@interface CimbarWrapper : NSObject

/// 初始化 Cimbar 解码器
- (instancetype)init;

/// 处理一帧图像
/// @param pixelBuffer 摄像头输出的原始缓冲
/// @return 如果解码完成则返回文件的完整二进制数据，否则返回 nil 继续等待下一帧
- (nullable NSData *)decodePixelBuffer:(CVPixelBufferRef)pixelBuffer;

/// 重置解码状态（例如开始接收新文件）
- (void)reset;

/// 获取当前接收进度（0.0 - 1.0）
- (double)getProgress;

@end

NS_ASSUME_NONNULL_END
