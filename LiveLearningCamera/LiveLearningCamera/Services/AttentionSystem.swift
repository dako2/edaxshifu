//
//  AttentionSystem.swift
//  LiveLearningCamera
//
//  Efficient attention-based resource allocation for detection processing
//

import Foundation
import CoreGraphics
import Accelerate

// MARK: - Attention System
class AttentionSystem {
    
    // Attention weights
    private let sizeWeight: Float = 0.25
    private let confidenceWeight: Float = 0.20
    private let centerWeight: Float = 0.15
    private let motionWeight: Float = 0.30
    private let noveltyWeight: Float = 0.10
    
    // Processing limits
    private let maxConcurrentProcessing = 10
    private let minConfidenceThreshold: Float = 0.3
    
    // Motion tracking
    private var previousFrameObjects = [String: CGRect]()
    private var objectVelocities = [String: CGVector]()
    
    // Novelty tracking
    private var seenLabels = Set<String>()
    private var labelFrequency = [String: Int]()
    
    // MARK: - Main Attention Scoring
    func prioritize(_ detections: [Detection], frameSize: CGSize) -> [PrioritizedDetection] {
        var prioritized = [PrioritizedDetection]()
        
        for detection in detections {
            // Skip low confidence detections
            guard detection.confidence >= minConfidenceThreshold else { continue }
            
            // Calculate attention score components
            let sizeScore = calculateSizeScore(detection.boundingBox, frameSize: frameSize)
            let confidenceScore = detection.confidence
            let centerScore = calculateCenterScore(detection.boundingBox)
            let motionScore = calculateMotionScore(for: detection)
            let noveltyScore = calculateNoveltyScore(for: detection.label)
            
            // Weighted combination
            let attentionScore = (
                sizeScore * sizeWeight +
                confidenceScore * confidenceWeight +
                centerScore * centerWeight +
                motionScore * motionWeight +
                noveltyScore * noveltyWeight
            )
            
            prioritized.append(PrioritizedDetection(
                detection: detection,
                attentionScore: attentionScore,
                components: AttentionComponents(
                    size: sizeScore,
                    confidence: confidenceScore,
                    center: centerScore,
                    motion: motionScore,
                    novelty: noveltyScore
                )
            ))
        }
        
        // Sort by attention score and limit to processing capacity
        return Array(prioritized
            .sorted { $0.attentionScore > $1.attentionScore }
            .prefix(maxConcurrentProcessing))
    }
    
    // MARK: - Batch Optimization
    func selectForProcessing(_ detections: [Detection], 
                           availableResources: ResourceState) -> [Detection] {
        // Adjust processing capacity based on system resources
        let capacity = adjustCapacityForResources(availableResources)
        
        // Get prioritized detections
        let prioritized = prioritize(detections, frameSize: CGSize(width: 1920, height: 1080))
        
        // Return top N based on adjusted capacity
        return Array(prioritized.prefix(capacity).map { $0.detection })
    }
    
    // MARK: - Component Calculations
    private func calculateSizeScore(_ bbox: CGRect, frameSize: CGSize) -> Float {
        let frameArea = Float(frameSize.width * frameSize.height)
        let bboxArea = Float(bbox.width * bbox.height)
        let relativeSize = bboxArea / frameArea
        
        // Normalize to 0-1 with diminishing returns for very large objects
        return min(1.0, sqrt(relativeSize * 100))
    }
    
    private func calculateCenterScore(_ bbox: CGRect) -> Float {
        // Distance from center (normalized coordinates)
        let centerX = bbox.midX
        let centerY = bbox.midY
        let distanceFromCenter = sqrt(pow(centerX - 0.5, 2) + pow(centerY - 0.5, 2))
        
        // Closer to center = higher score
        let maxDistance = sqrt(0.5) // Corner to center
        return Float(1.0 - (distanceFromCenter / maxDistance))
    }
    
    private func calculateMotionScore(for detection: Detection) -> Float {
        let key = "\(detection.label)_\(detection.id ?? 0)"
        
        // Check if we've seen this object before
        guard let previousBox = previousFrameObjects[key] else {
            // New object - moderate motion score
            previousFrameObjects[key] = detection.boundingBox
            return 0.5
        }
        
        // Calculate motion vector
        let dx = detection.boundingBox.midX - previousBox.midX
        let dy = detection.boundingBox.midY - previousBox.midY
        let velocity = CGVector(dx: dx, dy: dy)
        
        // Update tracking
        previousFrameObjects[key] = detection.boundingBox
        objectVelocities[key] = velocity
        
        // Calculate motion magnitude (normalized)
        let motionMagnitude = sqrt(Float(dx * dx + dy * dy))
        
        // Fast motion gets higher attention
        return min(1.0, motionMagnitude * 10)
    }
    
    private func calculateNoveltyScore(for label: String) -> Float {
        // Update frequency tracking
        labelFrequency[label, default: 0] += 1
        let frequency = labelFrequency[label]!
        
        // First time seeing this label
        if !seenLabels.contains(label) {
            seenLabels.insert(label)
            return 1.0
        }
        
        // Decay novelty based on frequency
        // Uses inverse log to create smooth decay
        let novelty = 1.0 / (1.0 + log(Float(frequency)))
        return max(0.0, novelty)
    }
    
    // MARK: - Resource Management
    private func adjustCapacityForResources(_ resources: ResourceState) -> Int {
        var capacity = maxConcurrentProcessing
        
        // Adjust for CPU usage
        if resources.cpuUsage > 0.8 {
            capacity = capacity / 2
        } else if resources.cpuUsage > 0.6 {
            capacity = Int(Float(capacity) * 0.75)
        }
        
        // Adjust for memory pressure
        switch resources.memoryPressure {
        case .normal:
            break
        case .warning:
            capacity = Int(Float(capacity) * 0.75)
        case .critical:
            capacity = max(3, capacity / 3)
        }
        
        // Adjust for thermal state
        switch resources.thermalState {
        case .nominal, .fair:
            break
        case .serious:
            capacity = Int(Float(capacity) * 0.6)
        case .critical:
            capacity = max(2, capacity / 4)
        @unknown default:
            break
        }
        
        return max(1, capacity)
    }
    
    // MARK: - Frame Management
    func updateFrame() {
        // Clean up old motion tracking data
        let currentObjects = Set(previousFrameObjects.keys)
        let staleThreshold = 10 // frames
        
        // Remove objects not seen recently
        for key in currentObjects {
            if let velocity = objectVelocities[key] {
                // Check if object has been stationary too long
                if abs(velocity.dx) < 0.001 && abs(velocity.dy) < 0.001 {
                    objectVelocities.removeValue(forKey: key)
                    previousFrameObjects.removeValue(forKey: key)
                }
            }
        }
        
        // Reset novelty scores periodically
        if labelFrequency.values.max() ?? 0 > 1000 {
            // Decay all frequencies to prevent overflow
            for (label, freq) in labelFrequency {
                labelFrequency[label] = freq / 2
            }
        }
    }
    
    // MARK: - Analytics
    func getAttentionAnalytics() -> AttentionAnalytics {
        let avgNovelty: Int
        if labelFrequency.isEmpty {
            avgNovelty = 0
        } else {
            let total = labelFrequency.values.reduce(0, +)
            avgNovelty = total / labelFrequency.count
        }
        
        let movingObjectCount = objectVelocities.filter { 
            abs($0.value.dx) > 0.01 || abs($0.value.dy) > 0.01 
        }.count
        
        return AttentionAnalytics(
            uniqueLabelsSeens: seenLabels.count,
            averageLabelFrequency: avgNovelty,
            movingObjectCount: movingObjectCount,
            totalObjectsTracked: previousFrameObjects.count
        )
    }
}

// MARK: - Supporting Types
struct PrioritizedDetection {
    let detection: Detection
    let attentionScore: Float
    let components: AttentionComponents
}

struct AttentionComponents {
    let size: Float
    let confidence: Float
    let center: Float
    let motion: Float
    let novelty: Float
}

struct ResourceState {
    let cpuUsage: Float
    let memoryPressure: MemoryPressure
    let thermalState: ProcessInfo.ThermalState
    
    enum MemoryPressure {
        case normal
        case warning
        case critical
    }
    
    static var current: ResourceState {
        return SystemMonitor.shared.getCurrentResourceState()
    }
}

struct AttentionAnalytics {
    let uniqueLabelsSeens: Int
    let averageLabelFrequency: Int
    let movingObjectCount: Int
    let totalObjectsTracked: Int
}