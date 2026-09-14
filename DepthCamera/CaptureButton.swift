//
//  CaptureButton.swift
//  DepthCamera
//
//  Created by iori on 2024/11/27.
//

import SwiftUI


struct CaptureButton: View {
    static let outerDiameter: CGFloat = 80
    static let strokeWidth: CGFloat = 4
    static let innerPadding: CGFloat = 10
    static let innerDiameter: CGFloat = CaptureButton.outerDiameter -
    CaptureButton.strokeWidth - CaptureButton.innerPadding
    static let rootTwoOverTwo: CGFloat = CGFloat(2.0.squareRoot() / 2.0)
    static let squareDiameter: CGFloat = CaptureButton.innerDiameter * CaptureButton.rootTwoOverTwo -
    CaptureButton.innerPadding
    
    @ObservedObject var model: ARViewModel
    @State private var isPressed = false
    @State private var pulseCount = 0
    
    init(model: ARViewModel) {
        self.model = model
    }
    
    
    var body: some View {
        ZStack {
            // Pulse animation effect, played each time pulseCount changes
            Circle()
                .stroke(Color.white.opacity(0.8), lineWidth: 2)
                .frame(width: CaptureButton.outerDiameter + 20, height: CaptureButton.outerDiameter + 20)
                .keyframeAnimator(initialValue: 0.0, trigger: pulseCount) { circle, progress in
                    circle
                        .scaleEffect(1.0 + 0.5 * progress)
                        .opacity(progress == 0 ? 0 : 1 - progress)
                } keyframes: { _ in
                    MoveKeyframe(0.001)
                    LinearKeyframe(1.0, duration: 0.6, timingCurve: .easeOut)
                }
                .allowsHitTesting(false)
            
            Button(action: {
                // Haptic feedback
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isPressed = true
                }
                pulseCount += 1
                
                model.saveDepthMap()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        isPressed = false
                    }
                }
            }, label: {
                ManualCaptureButtonView()
                    .scaleEffect(isPressed ? 0.9 : 1.0)
            })
        }
    }
}

