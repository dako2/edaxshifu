//
//  HandTrackingDetector.swift
//  LiveLearningCamera
//
//  Hand tracking implementation using Vision framework
//

import Foundation
import Vision
import CoreML
import CoreImage
import AVFoundation

// MARK: - Hand Detection Result
public struct HandDetection {
    public let hand: VNHumanHandPoseObservation
    public let chirality: VNChirality // .left, .right, or .unknown
    public let confidence: Float
    public let landmarks: HandLandmarks
    public let gestureType: HandGesture?
    public let boundingBox: CGRect
}

// MARK: - Hand Landmarks
public struct HandLandmarks {
    public let wrist: CGPoint
    public let thumbTip: CGPoint
    public let thumbIP: CGPoint
    public let thumbMP: CGPoint
    public let thumbCMC: CGPoint
    
    public let indexTip: CGPoint
    public let indexDIP: CGPoint
    public let indexPIP: CGPoint
    public let indexMCP: CGPoint
    
    public let middleTip: CGPoint
    public let middleDIP: CGPoint
    public let middlePIP: CGPoint
    public let middleMCP: CGPoint
    
    public let ringTip: CGPoint
    public let ringDIP: CGPoint
    public let ringPIP: CGPoint
    public let ringMCP: CGPoint
    
    public let littleTip: CGPoint
    public let littleDIP: CGPoint
    public let littlePIP: CGPoint
    public let littleMCP: CGPoint
    
    init(from observation: VNHumanHandPoseObservation, in imageSize: CGSize) {
        // Helper to get point safely - keep in normalized coordinates
        func getPoint(_ joint: VNHumanHandPoseObservation.JointName) -> CGPoint {
            guard let point = try? observation.recognizedPoint(joint) else {
                return .zero
            }
            // Keep points in normalized coordinates (0-1)
            // Vision framework already provides normalized coordinates
            return CGPoint(
                x: point.location.x,
                y: point.location.y  // Don't flip Y here, Vision uses top-left origin
            )
        }
        
        // Wrist
        wrist = getPoint(.wrist)
        
        // Thumb
        thumbTip = getPoint(.thumbTip)
        thumbIP = getPoint(.thumbIP)
        thumbMP = getPoint(.thumbMP)
        thumbCMC = getPoint(.thumbCMC)
        
        // Index
        indexTip = getPoint(.indexTip)
        indexDIP = getPoint(.indexDIP)
        indexPIP = getPoint(.indexPIP)
        indexMCP = getPoint(.indexMCP)
        
        // Middle
        middleTip = getPoint(.middleTip)
        middleDIP = getPoint(.middleDIP)
        middlePIP = getPoint(.middlePIP)
        middleMCP = getPoint(.middleMCP)
        
        // Ring
        ringTip = getPoint(.ringTip)
        ringDIP = getPoint(.ringDIP)
        ringPIP = getPoint(.ringPIP)
        ringMCP = getPoint(.ringMCP)
        
        // Little
        littleTip = getPoint(.littleTip)
        littleDIP = getPoint(.littleDIP)
        littlePIP = getPoint(.littlePIP)
        littleMCP = getPoint(.littleMCP)
    }
}

// MARK: - Hand Gestures
public enum HandGesture: String {
    case thumbsUp = "👍"
    case thumbsDown = "👎"
    case peace = "✌️"
    case ok = "👌"
    case pointingUp = "☝️"
    case openPalm = "🖐"
    case fist = "✊"
    case rock = "🤘"
    case pinch = "🤏"
    case wave = "👋"
    case unknown = "❓"
}

// MARK: - Hand Tracking Detector
class HandTrackingDetector: BaseDetector {
    override var modelName: String { "VisionHandPose" }
    override var supportsBatchProcessing: Bool { true }
    
    var handPoseRequest: VNDetectHumanHandPoseRequest?
    private let maximumHandCount = 2
    private let minimumConfidence: Float = 0.3
    
    // Gesture recognition
    private let gestureRecognizer = HandGestureRecognizer()
    
    // Tracking state
    private var previousHands: [VNChirality: HandDetection] = [:]
    
    override func loadModel() async throws {
        // Vision framework handles hand tracking internally
        handPoseRequest = VNDetectHumanHandPoseRequest()
        handPoseRequest?.maximumHandCount = maximumHandCount
        isModelLoaded = true
    }
    
    override func detect(in image: CIImage) async throws -> [Detection] {
        guard let request = handPoseRequest else {
            throw DetectorError.modelNotLoaded
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let handler = VNImageRequestHandler(ciImage: image, options: [:])
            
            do {
                try handler.perform([request])
                
                guard let observations = request.results else {
                    continuation.resume(returning: [])
                    return
                }
                
                let detections = processHandObservations(observations, imageSize: image.extent.size)
                let standardDetections = convertToStandardDetections(detections)
                continuation.resume(returning: standardDetections)
                
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    // MARK: - Process Hand Observations
    private func processHandObservations(_ observations: [VNHumanHandPoseObservation], 
                                        imageSize: CGSize) -> [HandDetection] {
        var detections = [HandDetection]()
        
        for observation in observations {
            // Get hand chirality (left/right)
            let chirality = observation.chirality
            
            // Extract landmarks
            let landmarks = HandLandmarks(from: observation, in: imageSize)
            
            // Calculate bounding box
            let boundingBox = calculateBoundingBox(from: observation, in: imageSize)
            
            // Recognize gesture
            let gesture = gestureRecognizer.recognizeGesture(from: observation)
            
            // Calculate confidence
            let confidence = calculateConfidence(from: observation)
            
            let detection = HandDetection(
                hand: observation,
                chirality: chirality,
                confidence: confidence,
                landmarks: landmarks,
                gestureType: gesture,
                boundingBox: boundingBox
            )
            
            detections.append(detection)
            
            // Update tracking state
            previousHands[chirality] = detection
        }
        
        return detections
    }
    
    // MARK: - Convert to Standard Detection Format
    private func convertToStandardDetections(_ handDetections: [HandDetection]) -> [Detection] {
        return handDetections.map { hand in
            let label = formatHandLabel(hand)
            
            return Detection(
                label: label,
                confidence: hand.confidence,
                boundingBox: normalizeRect(hand.boundingBox),
                classIndex: getClassIndex(for: hand.gestureType)
            )
        }
    }
    
    private func formatHandLabel(_ hand: HandDetection) -> String {
        let chiralityStr = hand.chirality == .left ? "Left" : 
                          hand.chirality == .right ? "Right" : "Hand"
        
        if let gesture = hand.gestureType, gesture != .unknown {
            return "\(chiralityStr): \(gesture.rawValue)"
        }
        
        return chiralityStr
    }
    
    private func getClassIndex(for gesture: HandGesture?) -> Int {
        guard let gesture = gesture else { return 100 } // Start at 100 to avoid COCO collision
        
        // Map gestures to class indices starting at 100 (COCO uses 0-79)
        switch gesture {
        case .thumbsUp: return 101
        case .thumbsDown: return 102
        case .peace: return 103
        case .ok: return 104
        case .pointingUp: return 105
        case .openPalm: return 106
        case .fist: return 107
        case .rock: return 108
        case .pinch: return 109
        case .wave: return 110
        case .unknown: return 100
        }
    }
    
    // MARK: - Helper Methods
    private func calculateBoundingBox(from observation: VNHumanHandPoseObservation, 
                                     in imageSize: CGSize) -> CGRect {
        var minX = CGFloat.infinity
        var minY = CGFloat.infinity
        var maxX = -CGFloat.infinity
        var maxY = -CGFloat.infinity
        
        // Iterate through all joint groups
        let jointGroups: [[VNHumanHandPoseObservation.JointName]] = [
            [.wrist],
            [.thumbTip, .thumbIP, .thumbMP, .thumbCMC],
            [.indexTip, .indexDIP, .indexPIP, .indexMCP],
            [.middleTip, .middleDIP, .middlePIP, .middleMCP],
            [.ringTip, .ringDIP, .ringPIP, .ringMCP],
            [.littleTip, .littleDIP, .littlePIP, .littleMCP]
        ]
        
        for group in jointGroups {
            for joint in group {
                if let point = try? observation.recognizedPoint(joint),
                   point.confidence > minimumConfidence {
                    // Keep in normalized coordinates
                    let x = point.location.x
                    let y = point.location.y
                    
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }
        
        // Add padding in normalized space
        let padding: CGFloat = 0.02 // 2% padding
        minX = max(0, minX - padding)
        minY = max(0, minY - padding)
        maxX = min(1, maxX + padding)
        maxY = min(1, maxY + padding)
        
        // Return normalized bounding box
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
    
    private func calculateConfidence(from observation: VNHumanHandPoseObservation) -> Float {
        var totalConfidence: Float = 0
        var jointCount = 0
        
        let allJoints: [VNHumanHandPoseObservation.JointName] = [
            .wrist, .thumbTip, .indexTip, .middleTip, .ringTip, .littleTip
        ]
        
        for joint in allJoints {
            if let point = try? observation.recognizedPoint(joint) {
                totalConfidence += point.confidence
                jointCount += 1
            }
        }
        
        return jointCount > 0 ? totalConfidence / Float(jointCount) : 0
    }
    
    private func normalizeRect(_ rect: CGRect) -> CGRect {
        // Already in normalized coordinates, just return as-is
        return rect
    }
}

// MARK: - Hand Gesture Recognizer
class HandGestureRecognizer {
    
    func recognizeGesture(from observation: VNHumanHandPoseObservation) -> HandGesture {
        // Get key points with confidence check
        guard let wrist = try? observation.recognizedPoint(.wrist),
              let thumbTip = try? observation.recognizedPoint(.thumbTip),
              let indexTip = try? observation.recognizedPoint(.indexTip),
              let middleTip = try? observation.recognizedPoint(.middleTip),
              let ringTip = try? observation.recognizedPoint(.ringTip),
              let littleTip = try? observation.recognizedPoint(.littleTip),
              let indexMCP = try? observation.recognizedPoint(.indexMCP),
              let middleMCP = try? observation.recognizedPoint(.middleMCP) else {
            return .unknown
        }
        
        // Check for specific gestures
        if isThumbsUp(wrist: wrist, thumbTip: thumbTip, indexTip: indexTip) {
            return .thumbsUp
        }
        
        if isPeaceSign(indexTip: indexTip, middleTip: middleTip, 
                       ringTip: ringTip, indexMCP: indexMCP) {
            return .peace
        }
        
        if isPointingUp(indexTip: indexTip, middleTip: middleTip, 
                        ringTip: ringTip, littleTip: littleTip) {
            return .pointingUp
        }
        
        if isOpenPalm(fingers: [indexTip, middleTip, ringTip, littleTip, thumbTip]) {
            return .openPalm
        }
        
        if isFist(fingers: [indexTip, middleTip, ringTip, littleTip], 
                 mcps: [indexMCP, middleMCP]) {
            return .fist
        }
        
        return .unknown
    }
    
    // Gesture detection helpers
    private func isThumbsUp(wrist: VNRecognizedPoint, thumbTip: VNRecognizedPoint, 
                           indexTip: VNRecognizedPoint) -> Bool {
        // Thumb is significantly higher than wrist and other fingers
        return thumbTip.location.y > wrist.location.y + 0.1 &&
               thumbTip.location.y > indexTip.location.y + 0.05
    }
    
    private func isPeaceSign(indexTip: VNRecognizedPoint, middleTip: VNRecognizedPoint,
                            ringTip: VNRecognizedPoint, indexMCP: VNRecognizedPoint) -> Bool {
        // Index and middle extended, others folded
        let indexExtended = indexTip.location.y > indexMCP.location.y + 0.1
        let middleExtended = middleTip.location.y > indexMCP.location.y + 0.1
        let ringFolded = ringTip.location.y < indexMCP.location.y
        
        return indexExtended && middleExtended && ringFolded
    }
    
    private func isPointingUp(indexTip: VNRecognizedPoint, middleTip: VNRecognizedPoint,
                             ringTip: VNRecognizedPoint, littleTip: VNRecognizedPoint) -> Bool {
        // Only index finger extended
        return indexTip.location.y > middleTip.location.y + 0.05 &&
               indexTip.location.y > ringTip.location.y + 0.05 &&
               indexTip.location.y > littleTip.location.y + 0.05
    }
    
    private func isOpenPalm(fingers: [VNRecognizedPoint]) -> Bool {
        // All fingers extended (high confidence and spread)
        return fingers.allSatisfy { $0.confidence > 0.5 }
    }
    
    private func isFist(fingers: [VNRecognizedPoint], mcps: [VNRecognizedPoint]) -> Bool {
        // All fingertips below MCPs (folded)
        for (finger, mcp) in zip(fingers, mcps) {
            if finger.location.y > mcp.location.y {
                return false
            }
        }
        return true
    }
}

// MARK: - Integration with Detection Pipeline
extension HandTrackingDetector {
    
    func detectWithTracking(in image: CIImage) async throws -> [HandTrackingResult] {
        guard let request = handPoseRequest else {
            throw DetectorError.modelNotLoaded
        }
        
        // Perform hand detection directly
        return try await withCheckedThrowingContinuation { continuation in
            let handler = VNImageRequestHandler(ciImage: image, options: [:])
            
            do {
                try handler.perform([request])
                
                guard let observations = request.results else {
                    continuation.resume(returning: [])
                    return
                }
                
                let handDetections = processHandObservations(observations, imageSize: image.extent.size)
                
                // Add tracking information
                let results = handDetections.map { hand in
                    let previousHand = previousHands[hand.chirality]
                    let movement = calculateMovement(current: hand, previous: previousHand)
                    
                    // Update tracking state
                    previousHands[hand.chirality] = hand
                    
                    return HandTrackingResult(
                        detection: hand,
                        movement: movement,
                        isTracked: previousHand != nil
                    )
                }
                
                continuation.resume(returning: results)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    private func calculateMovement(current: HandDetection, 
                                  previous: HandDetection?) -> CGVector {
        guard let previous = previous else { return .zero }
        
        let dx = current.landmarks.wrist.x - previous.landmarks.wrist.x
        let dy = current.landmarks.wrist.y - previous.landmarks.wrist.y
        
        return CGVector(dx: dx, dy: dy)
    }
}

// MARK: - Hand Tracking Result
public struct HandTrackingResult {
    public let detection: HandDetection
    public let movement: CGVector
    public let isTracked: Bool
}

// MARK: - Usage Example
/*
 
 // Add hand tracking to the pipeline
 let handTracker = HandTrackingDetector()
 await handTracker.loadModel()
 
 // Process frame
 let hands = try await handTracker.detect(in: frame)
 
 // Or with detailed tracking
 let trackedHands = try await handTracker.detectWithTracking(in: frame)
 
 for hand in trackedHands {
     print("Hand: \(hand.detection.chirality)")
     print("Gesture: \(hand.detection.gestureType?.rawValue ?? "none")")
     print("Movement: \(hand.movement)")
 }
 
*/