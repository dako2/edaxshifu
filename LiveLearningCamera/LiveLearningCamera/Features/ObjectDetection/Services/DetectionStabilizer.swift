//
//  DetectionStabilizer.swift
//  LiveLearningCamera
//
//  Improves detection stability and handles dropped objects
//  DetectionStabilizer.swift is actively used by MLPipeline.swift at line 28. The MLPipeline creates an instance of DetectionStabilizer to help stabilize object detections across frames, reducing flickering and false positives.

import Foundation
import CoreGraphics
import Vision

// MARK: - Detection Stabilizer
class DetectionStabilizer {
    
    // Configuration - REDUCED FOR MEMORY
    private let maxFramesWithoutDetection = 2  // Reduced from 5
    private let minDetectionStreak = 2
    private let confidenceDecayRate: Float = 0.9  // Faster decay
    private let iouThresholdForMatch: Float = 0.3
    private let positionSmoothingFactor: Float = 0.7
    private let confidenceSmoothingFactor: Float = 0.8
    private let maxTrackedObjects = 15  // Hard limit
    private let maxCandidates = 10  // Hard limit
    
    // Tracking state - with memory limits
    private var trackedObjects = [UUID: StabilizedObject]()
    private var candidateObjects = [UUID: CandidateObject]()
    private var frameCount = 0
    private var lastCleanupFrame = 0
    
    // MARK: - Main Stabilization
    func stabilize(_ detections: [Detection]) -> [Detection] {
        frameCount += 1
        
        // Step 1: Match detections to existing tracked objects
        var matchedDetectionIndices = Set<Int>()
        var matchedObjectIds = Set<UUID>()
        
        for (index, detection) in detections.enumerated() {
            if let matchedObject = findBestMatch(for: detection) {
                // Update existing object
                updateTrackedObject(matchedObject, with: detection)
                matchedDetectionIndices.insert(index)
                matchedObjectIds.insert(matchedObject.id)
            }
        }
        
        // Step 2: Handle unmatched detections (potential new objects)
        for (index, detection) in detections.enumerated() {
            if !matchedDetectionIndices.contains(index) {
                handleNewDetection(detection)
            }
        }
        
        // Step 3: Update objects that weren't detected this frame
        updateMissingObjects(matchedObjectIds)
        
        // Step 4: Promote confirmed candidates to tracked
        promoteConfirmedCandidates()
        
        // Step 5: Clean up stale objects
        cleanupStaleObjects()
        
        // Step 6: Generate stabilized detections
        return generateStabilizedDetections()
    }
    
    // MARK: - Object Matching
    private func findBestMatch(for detection: Detection) -> StabilizedObject? {
        var bestMatch: StabilizedObject?
        var bestScore: Float = 0
        
        for (_, trackedObject) in trackedObjects {
            // Skip if different class
            guard trackedObject.label == detection.label else { continue }
            
            // Calculate matching score
            let iou = calculateIOU(trackedObject.predictedBox, detection.boundingBox)
            let distanceScore = calculateDistanceScore(trackedObject.predictedBox, detection.boundingBox)
            let sizeScore = calculateSizeScore(trackedObject.lastBox, detection.boundingBox)
            
            // Combined score with weights
            let score = (iou * 0.5) + (distanceScore * 0.3) + (sizeScore * 0.2)
            
            if score > iouThresholdForMatch && score > bestScore {
                bestMatch = trackedObject
                bestScore = score
            }
        }
        
        return bestMatch
    }
    
    // MARK: - Object Updates
    private func updateTrackedObject(_ object: StabilizedObject, with detection: Detection) {
        // Smooth position update
        let smoothedBox = smoothBoundingBox(
            current: object.lastBox,
            new: detection.boundingBox,
            factor: positionSmoothingFactor
        )
        
        // Smooth confidence update
        let smoothedConfidence = smoothConfidence(
            current: object.confidence,
            new: detection.confidence,
            factor: confidenceSmoothingFactor
        )
        
        // Update object state
        object.lastBox = smoothedBox
        object.confidence = smoothedConfidence
        object.lastSeenFrame = frameCount
        object.detectionStreak += 1
        object.totalDetections += 1
        
        // Update velocity for prediction
        object.velocity = calculateVelocity(
            from: object.predictedBox,
            to: smoothedBox
        )
        
        // Update predicted position for next frame
        object.predictedBox = predictNextPosition(
            current: smoothedBox,
            velocity: object.velocity
        )
    }
    
    private func handleNewDetection(_ detection: Detection) {
        // Don't add if at capacity
        guard candidateObjects.count < maxCandidates else { return }
        
        // Check if it matches a candidate
        for (id, candidate) in candidateObjects {
            if candidate.label == detection.label {
                let iou = calculateIOU(candidate.lastBox, detection.boundingBox)
                if iou > iouThresholdForMatch {
                    // Update candidate
                    candidate.detectionCount += 1
                    candidate.lastBox = detection.boundingBox
                    candidate.confidence = detection.confidence
                    candidate.lastSeenFrame = frameCount
                    return
                }
            }
        }
        
        // Create new candidate only if under limit
        let candidate = CandidateObject(
            id: UUID(),
            label: detection.label,
            firstBox: detection.boundingBox,
            lastBox: detection.boundingBox,
            confidence: detection.confidence,
            firstSeenFrame: frameCount,
            lastSeenFrame: frameCount,
            detectionCount: 1
        )
        candidateObjects[candidate.id] = candidate
    }
    
    private func updateMissingObjects(_ matchedIds: Set<UUID>) {
        for (id, object) in trackedObjects {
            guard !matchedIds.contains(id) else { continue }
            
            // Object not detected this frame
            object.missedFrames += 1
            object.detectionStreak = 0
            
            // Decay confidence
            object.confidence *= confidenceDecayRate
            
            // Update position based on velocity (prediction)
            if object.missedFrames <= 2 {
                // Only predict for first 2 missed frames
                object.lastBox = object.predictedBox
                object.predictedBox = predictNextPosition(
                    current: object.predictedBox,
                    velocity: object.velocity
                )
            }
        }
    }
    
    // MARK: - Candidate Promotion
    private func promoteConfirmedCandidates() {
        // Don't promote if at tracked object limit
        guard trackedObjects.count < maxTrackedObjects else { return }
        
        var toPromote = [UUID]()
        
        for (id, candidate) in candidateObjects {
            if candidate.detectionCount >= minDetectionStreak {
                // Promote to tracked object
                let tracked = StabilizedObject(
                    id: id,
                    label: candidate.label,
                    lastBox: candidate.lastBox,
                    predictedBox: candidate.lastBox,
                    confidence: candidate.confidence,
                    velocity: CGVector.zero,
                    firstSeenFrame: candidate.firstSeenFrame,
                    lastSeenFrame: candidate.lastSeenFrame,
                    missedFrames: 0,
                    detectionStreak: candidate.detectionCount,
                    totalDetections: candidate.detectionCount
                )
                trackedObjects[id] = tracked
                toPromote.append(id)
                
                // Stop if we hit the limit
                if trackedObjects.count >= maxTrackedObjects {
                    break
                }
            }
        }
        
        // Remove promoted candidates
        for id in toPromote {
            candidateObjects.removeValue(forKey: id)
        }
    }
    
    // MARK: - Cleanup
    private func cleanupStaleObjects() {
        // Remove objects that haven't been seen for too long
        var toRemove = [UUID]()
        
        for (id, object) in trackedObjects {
            if object.missedFrames > maxFramesWithoutDetection {
                toRemove.append(id)
            }
        }
        
        for id in toRemove {
            trackedObjects.removeValue(forKey: id)
        }
        
        // Enforce max tracked objects limit
        if trackedObjects.count > maxTrackedObjects {
            let sorted = trackedObjects.sorted { $0.value.confidence > $1.value.confidence }
            let toKeep = sorted.prefix(maxTrackedObjects)
            trackedObjects = Dictionary(uniqueKeysWithValues: toKeep.map { ($0.key, $0.value) })
        }
        
        // Remove old candidates
        var staleCandidates = [UUID]()
        for (id, candidate) in candidateObjects {
            if frameCount - candidate.lastSeenFrame > 2 {  // Reduced from 3
                staleCandidates.append(id)
            }
        }
        
        for id in staleCandidates {
            candidateObjects.removeValue(forKey: id)
        }
        
        // Enforce max candidates limit
        if candidateObjects.count > maxCandidates {
            let sorted = candidateObjects.sorted { $0.value.lastSeenFrame > $1.value.lastSeenFrame }
            let toKeep = sorted.prefix(maxCandidates)
            candidateObjects = Dictionary(uniqueKeysWithValues: toKeep.map { ($0.key, $0.value) })
        }
    }
    
    // MARK: - Detection Generation
    private func generateStabilizedDetections() -> [Detection] {
        var stabilizedDetections = [Detection]()
        
        for (_, object) in trackedObjects {
            // Only include objects with sufficient confidence
            guard object.confidence > 0.2 else { continue }
            
            let detection = Detection(
                label: object.label,
                confidence: object.confidence,
                boundingBox: object.lastBox,
                classIndex: 0,  // You might want to store this
                id: Int(truncating: object.id.uuid.0 as NSNumber)
            )
            stabilizedDetections.append(detection)
        }
        
        return stabilizedDetections
    }
    
    // MARK: - Helper Methods
    private func calculateIOU(_ box1: CGRect, _ box2: CGRect) -> Float {
        let intersection = box1.intersection(box2)
        guard !intersection.isNull else { return 0 }
        
        let intersectionArea = intersection.width * intersection.height
        let unionArea = (box1.width * box1.height) + (box2.width * box2.height) - intersectionArea
        
        return Float(intersectionArea / unionArea)
    }
    
    private func calculateDistanceScore(_ box1: CGRect, _ box2: CGRect) -> Float {
        let center1 = CGPoint(x: box1.midX, y: box1.midY)
        let center2 = CGPoint(x: box2.midX, y: box2.midY)
        
        let distance = sqrt(pow(center1.x - center2.x, 2) + pow(center1.y - center2.y, 2))
        let maxDistance: CGFloat = 1.414  // Max distance in normalized coordinates
        
        return Float(1.0 - min(distance / maxDistance, 1.0))
    }
    
    private func calculateSizeScore(_ box1: CGRect, _ box2: CGRect) -> Float {
        let area1 = box1.width * box1.height
        let area2 = box2.width * box2.height
        
        let ratio = min(area1, area2) / max(area1, area2)
        return Float(ratio)
    }
    
    private func smoothBoundingBox(current: CGRect, new: CGRect, factor: Float) -> CGRect {
        let f = CGFloat(factor)
        return CGRect(
            x: current.origin.x * f + new.origin.x * (1 - f),
            y: current.origin.y * f + new.origin.y * (1 - f),
            width: current.width * f + new.width * (1 - f),
            height: current.height * f + new.height * (1 - f)
        )
    }
    
    private func smoothConfidence(current: Float, new: Float, factor: Float) -> Float {
        return current * factor + new * (1 - factor)
    }
    
    private func calculateVelocity(from: CGRect, to: CGRect) -> CGVector {
        return CGVector(
            dx: to.midX - from.midX,
            dy: to.midY - from.midY
        )
    }
    
    private func predictNextPosition(current: CGRect, velocity: CGVector) -> CGRect {
        return CGRect(
            x: current.origin.x + velocity.dx,
            y: current.origin.y + velocity.dy,
            width: current.width,
            height: current.height
        )
    }
    
    // MARK: - Statistics
    func getStabilizationStats() -> StabilizationStats {
        let avgConfidence = trackedObjects.values.reduce(0) { $0 + $1.confidence } / Float(max(trackedObjects.count, 1))
        let stableObjects = trackedObjects.values.filter { $0.detectionStreak > 3 }.count
        
        return StabilizationStats(
            trackedObjectCount: trackedObjects.count,
            candidateObjectCount: candidateObjects.count,
            averageConfidence: avgConfidence,
            stableObjectCount: stableObjects
        )
    }
}

// MARK: - Supporting Types
private class StabilizedObject {
    let id: UUID
    let label: String
    var lastBox: CGRect
    var predictedBox: CGRect
    var confidence: Float
    var velocity: CGVector
    let firstSeenFrame: Int
    var lastSeenFrame: Int
    var missedFrames: Int
    var detectionStreak: Int
    var totalDetections: Int
    
    init(id: UUID, label: String, lastBox: CGRect, predictedBox: CGRect,
         confidence: Float, velocity: CGVector, firstSeenFrame: Int,
         lastSeenFrame: Int, missedFrames: Int, detectionStreak: Int,
         totalDetections: Int) {
        self.id = id
        self.label = label
        self.lastBox = lastBox
        self.predictedBox = predictedBox
        self.confidence = confidence
        self.velocity = velocity
        self.firstSeenFrame = firstSeenFrame
        self.lastSeenFrame = lastSeenFrame
        self.missedFrames = missedFrames
        self.detectionStreak = detectionStreak
        self.totalDetections = totalDetections
    }
}

private class CandidateObject {
    let id: UUID
    let label: String
    let firstBox: CGRect
    var lastBox: CGRect
    var confidence: Float
    let firstSeenFrame: Int
    var lastSeenFrame: Int
    var detectionCount: Int
    
    init(id: UUID, label: String, firstBox: CGRect, lastBox: CGRect,
         confidence: Float, firstSeenFrame: Int, lastSeenFrame: Int,
         detectionCount: Int) {
        self.id = id
        self.label = label
        self.firstBox = firstBox
        self.lastBox = lastBox
        self.confidence = confidence
        self.firstSeenFrame = firstSeenFrame
        self.lastSeenFrame = lastSeenFrame
        self.detectionCount = detectionCount
    }
}

struct StabilizationStats {
    let trackedObjectCount: Int
    let candidateObjectCount: Int
    let averageConfidence: Float
    let stableObjectCount: Int
}
