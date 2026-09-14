//
//  DepthMapDetailView.swift
//  DepthCamera
//
//  Created by Assistant on 2025/01/07.
//

import SwiftUI
import CoreGraphics
import SwiftTiff

struct DepthMapDetailView: View {
    let depthURL: URL
    @Environment(\.dismiss) var dismiss
    @State private var depthImage: UIImage?
    @State private var tapLocation: CGPoint = .zero
    @State private var depthValue: Float?
    @State private var showCrosshair = false
    @State private var imageSize: CGSize = .zero
    @State private var depthData: [[Float]] = []
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                GeometryReader { geometry in
                    if let depthImage = depthImage {
                        ZStack {
                            // Depth画像
                            Image(uiImage: depthImage)
                                .resizable()
                                .scaledToFit()
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .background(
                                    GeometryReader { imageGeometry in
                                        Color.clear.onAppear {
                                            imageSize = imageGeometry.size
                                        }
                                    }
                                )
                                .onTapGesture { location in
                                    tapLocation = location
                                    showCrosshair = true
                                    updateDepthValue(at: location, in: geometry.size)
                                }
                            
                            // クロスヘア表示
                            if showCrosshair {
                                CrosshairView(location: tapLocation)
                            }
                        }
                    } else {
                        ProgressView("Loading depth map...")
                            .foregroundColor(.white)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                }
                
                // Depth値表示
                if let depth = depthValue {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            VStack(alignment: .trailing, spacing: 8) {
                                Text("Depth Distance")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Text(String(format: "%.2f m", depth))
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.black.opacity(0.8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.blue.opacity(0.5), lineWidth: 1)
                                    )
                            )
                            .shadow(color: Color.blue.opacity(0.3), radius: 10, x: 0, y: 5)
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Depth Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .onAppear {
                loadDepthData()
            }
        }
    }
    
    private func loadDepthData() {
        DispatchQueue.global(qos: .userInitiated).async {
            // まず表示用の画像を読み込む
            if let image = UIImage(contentsOfFile: depthURL.path) {
                DispatchQueue.main.async {
                    self.depthImage = image
                }
            }
            
            // TIFFからDepthデータを読み込む
            loadDepthValuesFromTIFF()
        }
    }
    
    private func loadDepthValuesFromTIFF() {
        do {
            let image = try TIFFReader.read(fromFile: depthURL.path)
            guard let directory = image.fileDirectories.first else {
                print("Depth TIFF has no image directory")
                return
            }
            let rasters = try directory.readRasters()
            
            // 32-bit float depth in meters, as written by writeDepthMapToTIFFWithLibTIFF
            let values = (0..<rasters.height).map { y in
                (0..<rasters.width).map { x in Float(rasters.firstPixelSample(x: x, y: y)) }
            }
            
            DispatchQueue.main.async {
                self.depthData = values
            }
        } catch {
            print("Failed to read depth TIFF: \(error)")
        }
    }
    
    private func updateDepthValue(at location: CGPoint, in viewSize: CGSize) {
        guard let image = depthImage,
              !depthData.isEmpty else { return }
        
        let imageAspectRatio = image.size.width / image.size.height
        let viewAspectRatio = viewSize.width / viewSize.height
        
        var imageFrame: CGRect
        if imageAspectRatio > viewAspectRatio {
            // 画像の幅に合わせる
            let height = viewSize.width / imageAspectRatio
            imageFrame = CGRect(x: 0, y: (viewSize.height - height) / 2, width: viewSize.width, height: height)
        } else {
            // 画像の高さに合わせる
            let width = viewSize.height * imageAspectRatio
            imageFrame = CGRect(x: (viewSize.width - width) / 2, y: 0, width: width, height: viewSize.height)
        }
        
        // タップ位置を画像座標に変換
        let normalizedX = (location.x - imageFrame.origin.x) / imageFrame.width
        let normalizedY = (location.y - imageFrame.origin.y) / imageFrame.height
        
        // 範囲チェック
        guard normalizedX >= 0, normalizedX <= 1,
              normalizedY >= 0, normalizedY <= 1 else {
            return
        }
        
        // ピクセル座標に変換
        let pixelX = Int(normalizedX * CGFloat(depthData[0].count))
        let pixelY = Int(normalizedY * CGFloat(depthData.count))
        
        // 境界チェック
        guard pixelY < depthData.count,
              pixelX < depthData[pixelY].count else {
            return
        }
        
        depthValue = depthData[pixelY][pixelX]
    }
}

struct CrosshairView: View {
    let location: CGPoint
    
    var body: some View {
        ZStack {
            // 水平線
            Rectangle()
                .fill(Color.white.opacity(0.8))
                .frame(width: 40, height: 1)
                .position(location)
            
            // 垂直線
            Rectangle()
                .fill(Color.white.opacity(0.8))
                .frame(width: 1, height: 40)
                .position(location)
            
            // 中心点
            Circle()
                .fill(Color.clear)
                .stroke(Color.white, lineWidth: 2)
                .frame(width: 12, height: 12)
                .position(location)
        }
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.2), value: location)
    }
}