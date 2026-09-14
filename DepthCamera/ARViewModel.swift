//
//  ARViewModel.swift
//  DepthCamera
//
//  Created by iori on 2024/11/27.
//

import ARKit


class ARViewModel: NSObject, ARSessionDelegate, ObservableObject {
  private var latestDepthMap: CVPixelBuffer?
  private var latestImage: CVPixelBuffer?
  @Published var processedDepthImage: UIImage?
  @Published var processedConfidenceImage: UIImage?
  @Published var showDepthMap: Bool = true
  @Published var showConfidenceMap: Bool = true
  @Published var captureSuccessful: Bool = false
  @Published var lastCapture: UIImage? = nil {
    didSet {
      print("lastCapture was set.")
    }
  }
  @Published var lastCaptureURL: URL?
  
  private var lastDepthUpdate: TimeInterval = 0
  private let depthUpdateInterval: TimeInterval = 0.1 // 10fps (1/10秒)
  // Preview images are built off the main thread so ARKit's frames aren't held up
  private let previewQueue = DispatchQueue(label: "DepthCamera.preview", qos: .userInitiated)
  private var isProcessingPreview = false // main thread only

  func session(_ session: ARSession, didUpdate frame: ARFrame) {
    latestDepthMap = frame.sceneDepth?.depthMap
    latestImage = frame.capturedImage
    let currentTime = CACurrentMediaTime()

    guard currentTime - lastDepthUpdate >= depthUpdateInterval, !isProcessingPreview else { return }
    lastDepthUpdate = currentTime  // タイマーを更新

    // Copy the pixels now so the frame can be released before processing
    let depth = showDepthMap ? frame.sceneDepth.flatMap { copyPixels($0.depthMap, as: Float32.self) } : nil
    let confidence = showConfidenceMap ? frame.sceneDepth?.confidenceMap.flatMap { copyPixels($0, as: UInt8.self) } : nil
    guard depth != nil || confidence != nil else { return }

    isProcessingPreview = true
    previewQueue.async { [weak self] in
      // DepthMapの処理と表示
      let depthImage = depth.flatMap(makeDepthImage).flatMap { $0.rotate(radians: .pi/2) } // 画像を90度回転
      // ConfidenceMapの処理と表示
      let confidenceImage = confidence.flatMap(makeConfidenceImage).flatMap { $0.rotate(radians: .pi/2) }

      DispatchQueue.main.async {
        guard let self else { return }
        if let depthImage { self.processedDepthImage = depthImage }
        if let confidenceImage { self.processedConfidenceImage = confidenceImage }
        self.isProcessingPreview = false
      }
    }
  }
  
  func saveDepthMap() {
    guard let depthMap = latestDepthMap, let image = latestImage else {
      print("Depth map or image is not available.")
      return
    }
    
    let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyyMMdd"
    let dateString = dateFormatter.string(from: Date())
    let dateDirURL = documentsDir.appendingPathComponent(dateString)
    
    do {
      try FileManager.default.createDirectory(at: dateDirURL, withIntermediateDirectories: true, attributes: nil)
    } catch {
      print("Failed to create directory: \(error)")
      return
    }
    
    let timestamp = Date().timeIntervalSince1970
    let depthFileURL = dateDirURL.appendingPathComponent("\(timestamp)_depth.tiff")
    let imageFileURL = dateDirURL.appendingPathComponent("\(timestamp)_image.jpg")
    
    guard writeDepthMapToTIFFWithLibTIFF(depthMap: depthMap, url: depthFileURL) else {
      print("Failed to save depth map to \(depthFileURL)")
      return
    }
    saveImage(image: image, url: imageFileURL)
    
    
    
    
    
    let uiImage = UIImage(ciImage: CIImage(cvPixelBuffer: image))
    
    
    DispatchQueue.main.async {
      self.lastCapture = uiImage
      self.lastCaptureURL = imageFileURL
      self.captureSuccessful = true
      
      // Reset after animation
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
        self.captureSuccessful = false
      }
    }
    
    
    
    print("Depth map saved to \(depthFileURL)")
    print("Image saved to \(imageFileURL)")
  }
}



extension ARViewModel {
  func resizePixelBuffer(
    _ pixelBuffer: CVPixelBuffer,
    to size: CGSize
  ) -> CVPixelBuffer? {
    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
    let scale = min(
      size.width / CGFloat(CVPixelBufferGetWidth(pixelBuffer)),
      size.height / CGFloat(CVPixelBufferGetHeight(pixelBuffer))
    )
    let scaledImage = ciImage.transformed(by: CGAffineTransform(
      scaleX: scale,
      y: scale
    ))
    
    let context = CIContext(options: nil)
    var outputPixelBuffer: CVPixelBuffer?
    CVPixelBufferCreate(
      kCFAllocatorDefault,
      Int(size.width),
      Int(size.height),
      CVPixelBufferGetPixelFormatType(pixelBuffer),
      nil,
      &outputPixelBuffer
    )
    
    if let outputPixelBuffer = outputPixelBuffer {
      context.render(scaledImage, to: outputPixelBuffer)
      return outputPixelBuffer
    }
    return nil
  }
}

// DepthMapを可視化する関数を追加
struct PixelCopy<T> {
  let width: Int
  let height: Int
  let pixels: [T]
}

/// Copies a single-channel pixel buffer into an array, honoring row padding.
func copyPixels<T>(_ buffer: CVPixelBuffer, as type: T.Type) -> PixelCopy<T>? {
  CVPixelBufferLockBaseAddress(buffer, .readOnly)
  defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
  guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }

  let width = CVPixelBufferGetWidth(buffer)
  let height = CVPixelBufferGetHeight(buffer)
  let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
  var pixels = [T]()
  pixels.reserveCapacity(width * height)
  for y in 0..<height {
    let row = (base + y * bytesPerRow).assumingMemoryBound(to: T.self)
    pixels.append(contentsOf: UnsafeBufferPointer(start: row, count: width))
  }
  return PixelCopy(width: width, height: height, pixels: pixels)
}

// DepthMapを可視化する関数
/// Grayscale depth from 0 m (black) to 5 m (white), shared by the live preview and the gallery.
func makeDepthImage(_ depth: PixelCopy<Float32>) -> UIImage? {
  var normalizedData = [UInt8](repeating: 0, count: depth.pixels.count * 4)
  for (i, value) in depth.pixels.enumerated() {
    // 深度を0-1の範囲に正規化（例：0-5メートルを想定）
    let normalizedDepth = min(max(value / 5.0, 0.0), 1.0)
    let pixel = UInt8(normalizedDepth * 255.0)
    normalizedData[i * 4] = pixel     // R
    normalizedData[i * 4 + 1] = pixel // G
    normalizedData[i * 4 + 2] = pixel // B
    normalizedData[i * 4 + 3] = 255   // A
  }
  return makeImage(rgba: &normalizedData, width: depth.width, height: depth.height)
}

// ConfidenceMapを可視化する関数
func makeConfidenceImage(_ confidence: PixelCopy<UInt8>) -> UIImage? {
  var rgbaData = [UInt8](repeating: 0, count: confidence.pixels.count * 4)
  for (i, value) in confidence.pixels.enumerated() {
    let index = i * 4
    // 信頼度に基づいて色を設定
    switch value {
    case 0:  // 信頼度なし
      rgbaData[index] = 255    // R - 赤
    case 1:  // 低信頼度
      rgbaData[index] = 255    // R - 黄
      rgbaData[index + 1] = 255  // G
    case 2:  // 高信頼度
      rgbaData[index + 1] = 255  // G - 緑
    default:  // 最高信頼度
      rgbaData[index + 2] = 255  // B - 青
    }
    rgbaData[index + 3] = 255   // A - 完全な不透明度
  }
  return makeImage(rgba: &rgbaData, width: confidence.width, height: confidence.height)
}

private func makeImage(rgba: inout [UInt8], width: Int, height: Int) -> UIImage? {
  // Keep the pointer valid for both creating the context and copying out the image
  let cgImage = rgba.withUnsafeMutableBytes { bytes in
    CGContext(
      data: bytes.baseAddress,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: width * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )?.makeImage()
  }
  guard let cgImage else { return nil }
  return UIImage(cgImage: cgImage)
}

extension UIImage {
  func rotate(radians: Float) -> UIImage? {
    var newSize = CGRect(origin: CGPoint.zero, size: self.size)
      .applying(CGAffineTransform(rotationAngle: CGFloat(radians)))
      .size
    // Trim off the extremely small float value to prevent core graphics from rounding it up
    newSize.width = floor(newSize.width)
    newSize.height = floor(newSize.height)
    
    UIGraphicsBeginImageContextWithOptions(newSize, false, self.scale)
    let context = UIGraphicsGetCurrentContext()!
    
    // Move origin to middle
    context.translateBy(x: newSize.width/2, y: newSize.height/2)
    // Rotate around middle
    context.rotate(by: CGFloat(radians))
    // Draw the image at its center
    let rect = CGRect(
      x: -self.size.width/2,
      y: -self.size.height/2,
      width: self.size.width,
      height: self.size.height)
    
    self.draw(in: rect)
    
    let newImage = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    
    return newImage
  }
}

