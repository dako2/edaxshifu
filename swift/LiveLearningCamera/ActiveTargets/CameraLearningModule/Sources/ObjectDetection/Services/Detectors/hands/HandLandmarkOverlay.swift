//
//  HandLandmarkOverlay.swift
//  LiveLearningCamera
//
//  MediaPipe-style hand landmark visualization
//

import SwiftUI
import Vision

// MARK: - Hand Landmark Overlay
public struct HandLandmarkOverlay: View {
    public let handDetections: [HandTrackingResult]
    public let imageSize: CGSize
    @ObservedObject var settings = DetectionSettingsManager.shared
    
    public init(handDetections: [HandTrackingResult], imageSize: CGSize) {
        self.handDetections = handDetections
        self.imageSize = imageSize
    }
    
    public var body: some View {
        let _ = print("HandLandmarkOverlay: Rendering \(handDetections.count) hands")
        return GeometryReader { geometry in
            ForEach(Array(handDetections.enumerated()), id: \.offset) { _, hand in
                if settings.showHandLandmarks {
                    // Draw skeleton connections
                    HandSkeletonView(
                        landmarks: hand.detection.landmarks,
                        chirality: hand.detection.chirality,
                        viewSize: geometry.size,
                        imageSize: imageSize
                    )
                    
                    // Draw landmark points
                    HandLandmarkPoints(
                        landmarks: hand.detection.landmarks,
                        chirality: hand.detection.chirality,
                        viewSize: geometry.size,
                        imageSize: imageSize
                    )
                }
                
                // Show gesture label if detected
                if settings.showHandGestures,
                   let gesture = hand.detection.gestureType,
                   gesture != .unknown {
                    GestureLabelView(
                        gesture: gesture,
                        wristPosition: hand.detection.landmarks.wrist,
                        chirality: hand.detection.chirality,
                        viewSize: geometry.size,
                        imageSize: imageSize
                    )
                }
            }
        }
    }
}

// MARK: - Hand Skeleton View (MediaPipe-style connections)
struct HandSkeletonView: View {
    let landmarks: HandLandmarks
    let chirality: VNChirality
    let viewSize: CGSize
    let imageSize: CGSize
    
    // MediaPipe hand connections
    let connections: [(from: KeyPath<HandLandmarks, CGPoint>, to: KeyPath<HandLandmarks, CGPoint>)] = [
        // Thumb
        (\.wrist, \.thumbCMC),
        (\.thumbCMC, \.thumbMP),
        (\.thumbMP, \.thumbIP),
        (\.thumbIP, \.thumbTip),
        
        // Index finger
        (\.wrist, \.indexMCP),
        (\.indexMCP, \.indexPIP),
        (\.indexPIP, \.indexDIP),
        (\.indexDIP, \.indexTip),
        
        // Middle finger
        (\.wrist, \.middleMCP),
        (\.middleMCP, \.middlePIP),
        (\.middlePIP, \.middleDIP),
        (\.middleDIP, \.middleTip),
        
        // Ring finger
        (\.wrist, \.ringMCP),
        (\.ringMCP, \.ringPIP),
        (\.ringPIP, \.ringDIP),
        (\.ringDIP, \.ringTip),
        
        // Little finger
        (\.wrist, \.littleMCP),
        (\.littleMCP, \.littlePIP),
        (\.littlePIP, \.littleDIP),
        (\.littleDIP, \.littleTip),
        
        // Palm connections
        (\.indexMCP, \.middleMCP),
        (\.middleMCP, \.ringMCP),
        (\.ringMCP, \.littleMCP),
        (\.thumbCMC, \.indexMCP)
    ]
    
    var body: some View {
        Canvas { context, size in
            for connection in connections {
                let fromPoint = convertPoint(landmarks[keyPath: connection.from])
                let toPoint = convertPoint(landmarks[keyPath: connection.to])
                
                var path = Path()
                path.move(to: fromPoint)
                path.addLine(to: toPoint)
                
                context.stroke(
                    path,
                    with: .color(colorForHand),
                    lineWidth: 2
                )
            }
        }
    }
    
    private func convertPoint(_ point: CGPoint) -> CGPoint {
        // Points are in normalized coordinates (0-1) from Vision framework
        // Vision uses bottom-left origin, UIKit uses top-left
        // For aspect fill, we need to account for cropping
        
        // Camera outputs 1920x1080 (16:9) but in portrait mode it's rotated
        let videoAspect: CGFloat = 1080.0 / 1920.0  // Portrait video aspect
        let viewAspect = viewSize.width / viewSize.height
        
        var scaledX: CGFloat
        var scaledY: CGFloat
        
        if viewAspect > videoAspect {
            // View is wider than video - video fills height, crops width
            let scale = viewSize.height
            let videoWidth = viewSize.height * videoAspect
            let xOffset = (viewSize.width - videoWidth) / 2
            
            scaledX = xOffset + point.x * videoWidth
            scaledY = (1 - point.y) * viewSize.height
        } else {
            // View is narrower than video - video fills width, crops height  
            let scale = viewSize.width
            let videoHeight = viewSize.width / videoAspect
            let yOffset = (viewSize.height - videoHeight) / 2
            
            scaledX = point.x * viewSize.width
            scaledY = yOffset + (1 - point.y) * videoHeight
        }
        
        return CGPoint(x: scaledX, y: scaledY)
    }
    
    private var colorForHand: Color {
        switch chirality {
        case .left:
            return .cyan
        case .right:
            return .mint
        default:
            return .green
        }
    }
}

// MARK: - Hand Landmark Points
struct HandLandmarkPoints: View {
    let landmarks: HandLandmarks
    let chirality: VNChirality
    let viewSize: CGSize
    let imageSize: CGSize
    
    var allPoints: [CGPoint] {
        [
            landmarks.wrist,
            landmarks.thumbTip, landmarks.thumbIP, landmarks.thumbMP, landmarks.thumbCMC,
            landmarks.indexTip, landmarks.indexDIP, landmarks.indexPIP, landmarks.indexMCP,
            landmarks.middleTip, landmarks.middleDIP, landmarks.middlePIP, landmarks.middleMCP,
            landmarks.ringTip, landmarks.ringDIP, landmarks.ringPIP, landmarks.ringMCP,
            landmarks.littleTip, landmarks.littleDIP, landmarks.littlePIP, landmarks.littleMCP
        ]
    }
    
    var body: some View {
        ForEach(Array(allPoints.enumerated()), id: \.offset) { index, point in
            let convertedPoint = convertPoint(point)
            
            Circle()
                .fill(colorForPoint(index))
                .frame(width: pointSize(index), height: pointSize(index))
                .position(convertedPoint)
        }
    }
    
    private func convertPoint(_ point: CGPoint) -> CGPoint {
        // Points are in normalized coordinates (0-1) from Vision framework
        // Vision uses bottom-left origin, UIKit uses top-left
        // For aspect fill, we need to account for cropping
        
        // Camera outputs 1920x1080 (16:9) but in portrait mode it's rotated
        let videoAspect: CGFloat = 1080.0 / 1920.0  // Portrait video aspect
        let viewAspect = viewSize.width / viewSize.height
        
        var scaledX: CGFloat
        var scaledY: CGFloat
        
        if viewAspect > videoAspect {
            // View is wider than video - video fills height, crops width
            let scale = viewSize.height
            let videoWidth = viewSize.height * videoAspect
            let xOffset = (viewSize.width - videoWidth) / 2
            
            scaledX = xOffset + point.x * videoWidth
            scaledY = (1 - point.y) * viewSize.height
        } else {
            // View is narrower than video - video fills width, crops height  
            let scale = viewSize.width
            let videoHeight = viewSize.width / videoAspect
            let yOffset = (viewSize.height - videoHeight) / 2
            
            scaledX = point.x * viewSize.width
            scaledY = yOffset + (1 - point.y) * videoHeight
        }
        
        return CGPoint(x: scaledX, y: scaledY)
    }
    
    private func colorForPoint(_ index: Int) -> Color {
        // Color code by finger
        switch index {
        case 0: // Wrist
            return .red
        case 1...4: // Thumb
            return .orange
        case 5...8: // Index
            return .yellow
        case 9...12: // Middle
            return .green
        case 13...16: // Ring
            return .blue
        case 17...20: // Little
            return .purple
        default:
            return .white
        }
    }
    
    private func pointSize(_ index: Int) -> CGFloat {
        // Fingertips are larger
        if [1, 5, 9, 13, 17].contains(index) {
            return 8
        }
        // Wrist is larger
        if index == 0 {
            return 10
        }
        return 6
    }
}

// MARK: - Gesture Label View
struct GestureLabelView: View {
    let gesture: HandGesture
    let wristPosition: CGPoint
    let chirality: VNChirality
    let viewSize: CGSize
    let imageSize: CGSize
    
    var body: some View {
        let position = convertPoint(wristPosition)
        
        VStack(spacing: 2) {
            Text(gesture.rawValue)
                .font(.largeTitle)
            
            Text(gesture.description)
                .font(.caption)
                .foregroundColor(.white)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.7))
        )
        .position(x: position.x, y: position.y - 60)
    }
    
    private func convertPoint(_ point: CGPoint) -> CGPoint {
        // Points are in normalized coordinates (0-1) from Vision framework
        // Vision uses bottom-left origin, UIKit uses top-left
        // For aspect fill, we need to account for cropping
        
        // Camera outputs 1920x1080 (16:9) but in portrait mode it's rotated
        let videoAspect: CGFloat = 1080.0 / 1920.0  // Portrait video aspect
        let viewAspect = viewSize.width / viewSize.height
        
        var scaledX: CGFloat
        var scaledY: CGFloat
        
        if viewAspect > videoAspect {
            // View is wider than video - video fills height, crops width
            let scale = viewSize.height
            let videoWidth = viewSize.height * videoAspect
            let xOffset = (viewSize.width - videoWidth) / 2
            
            scaledX = xOffset + point.x * videoWidth
            scaledY = (1 - point.y) * viewSize.height
        } else {
            // View is narrower than video - video fills width, crops height  
            let scale = viewSize.width
            let videoHeight = viewSize.width / videoAspect
            let yOffset = (viewSize.height - videoHeight) / 2
            
            scaledX = point.x * viewSize.width
            scaledY = yOffset + (1 - point.y) * videoHeight
        }
        
        return CGPoint(x: scaledX, y: scaledY)
    }
}

// MARK: - Hand Gesture Extensions
extension HandGesture {
    var description: String {
        switch self {
        case .thumbsUp: return "Thumbs Up"
        case .thumbsDown: return "Thumbs Down"
        case .peace: return "Peace"
        case .ok: return "OK"
        case .pointingUp: return "Pointing"
        case .openPalm: return "Open Palm"
        case .fist: return "Fist"
        case .rock: return "Rock"
        case .pinch: return "Pinch"
        case .wave: return "Wave"
        case .unknown: return ""
        }
    }
}

