//
//  AdaptiveDetectionTuner.swift
//  LiveLearningCamera
//
//  Dynamically adjusts detection parameters based on scene conditions
//

import Foundation
import CoreGraphics

// MARK: - Adaptive Detection Tuner
class AdaptiveDetectionTuner {
    
    // Performance metrics tracking
    private var recentFPS: [Double] = []
    private var recentDetectionCounts: [Int] = []
    private var recentConfidences: [Float] = []
    private let historySize = 10
    
    // Current adjustments
    private(set) var confidenceMultiplier: Float = 1.0
    private(set) var maxObjectsPerFrame: Int = 10
    private(set) var processingMode: ProcessingMode = .balanced
    
    // Scene characteristics
    private var isLowLight = false
    private var isHighMotion = false
    private var isCrowded = false
    
    enum ProcessingMode {
        case performance  // Prioritize speed
        case balanced     // Balance quality and speed
        case quality      // Prioritize detection quality
    }
    
    // MARK: - Update Scene Conditions
    func updateSceneConditions(
        fps: Double,
        detectionCount: Int,
        averageConfidence: Float,
        thermalState: ProcessInfo.ThermalState
    ) {
        // Update history
        recentFPS.append(fps)
        recentDetectionCounts.append(detectionCount)
        recentConfidences.append(averageConfidence)
        
        // Trim history
        if recentFPS.count > historySize {
            recentFPS.removeFirst()
        }
        if recentDetectionCounts.count > historySize {
            recentDetectionCounts.removeFirst()
        }
        if recentConfidences.count > historySize {
            recentConfidences.removeFirst()
        }
        
        // Analyze conditions
        analyzeSceneCharacteristics()
        
        // Adjust parameters
        adjustParameters(thermalState: thermalState)
    }
    
    // MARK: - Scene Analysis
    private func analyzeSceneCharacteristics() {
        guard !recentConfidences.isEmpty else { return }
        
        // Low light detection (low average confidence)
        let avgConfidence = recentConfidences.reduce(0, +) / Float(recentConfidences.count)
        isLowLight = avgConfidence < 0.4
        
        // High motion detection (varying detection counts)
        if recentDetectionCounts.count > 3 {
            let variance = calculateVariance(recentDetectionCounts)
            isHighMotion = variance > 5.0
        }
        
        // Crowded scene detection
        let avgDetections = recentDetectionCounts.isEmpty ? 0 : 
            recentDetectionCounts.reduce(0, +) / recentDetectionCounts.count
        isCrowded = avgDetections > 8
    }
    
    // MARK: - Parameter Adjustment
    private func adjustParameters(thermalState: ProcessInfo.ThermalState) {
        // Adjust based on thermal state
        switch thermalState {
        case .nominal:
            processingMode = .quality
            maxObjectsPerFrame = 15
        case .fair:
            processingMode = .balanced
            maxObjectsPerFrame = 10
        case .serious:
            processingMode = .performance
            maxObjectsPerFrame = 7
        case .critical:
            processingMode = .performance
            maxObjectsPerFrame = 5
        @unknown default:
            processingMode = .balanced
            maxObjectsPerFrame = 10
        }
        
        // Adjust confidence based on scene
        var multiplier: Float = 1.0
        
        if isLowLight {
            // Lower confidence threshold in low light
            multiplier *= 0.8
        }
        
        if isHighMotion {
            // Lower threshold for moving objects
            multiplier *= 0.9
        }
        
        if isCrowded {
            // Slightly higher threshold in crowded scenes
            multiplier *= 1.1
        }
        
        // Check FPS performance
        if !recentFPS.isEmpty {
            let avgFPS = recentFPS.reduce(0, +) / Double(recentFPS.count)
            if avgFPS < 15 {
                // Poor performance - be more selective
                multiplier *= 1.2
                maxObjectsPerFrame = max(5, maxObjectsPerFrame - 2)
            } else if avgFPS > 25 {
                // Good performance - can be less selective
                multiplier *= 0.95
            }
        }
        
        confidenceMultiplier = max(0.5, min(1.5, multiplier))
    }
    
    // MARK: - Get Adjusted Threshold
    func getAdjustedConfidenceThreshold(base: Float) -> Float {
        return base * confidenceMultiplier
    }
    
    // MARK: - Recommendations
    func getProcessingRecommendations() -> ProcessingRecommendations {
        return ProcessingRecommendations(
            skipFrames: processingMode == .performance,
            reduceResolution: processingMode == .performance && isCrowded,
            useSimplifiedTracking: isHighMotion && processingMode != .quality,
            maxObjects: maxObjectsPerFrame,
            confidenceThreshold: getAdjustedConfidenceThreshold(base: 0.5)
        )
    }
    
    // MARK: - Helpers
    private func calculateVariance(_ values: [Int]) -> Double {
        guard values.count > 1 else { return 0 }
        
        let mean = Double(values.reduce(0, +)) / Double(values.count)
        let squaredDiffs = values.map { pow(Double($0) - mean, 2) }
        return squaredDiffs.reduce(0, +) / Double(values.count - 1)
    }
    
    // MARK: - Statistics
    func getAdaptiveStats() -> AdaptiveStats {
        let avgFPS = recentFPS.isEmpty ? 0 : recentFPS.reduce(0, +) / Double(recentFPS.count)
        let avgDetections = recentDetectionCounts.isEmpty ? 0 : 
            recentDetectionCounts.reduce(0, +) / recentDetectionCounts.count
        let avgConfidence = recentConfidences.isEmpty ? 0 : 
            recentConfidences.reduce(0, +) / Float(recentConfidences.count)
        
        return AdaptiveStats(
            averageFPS: avgFPS,
            averageDetections: avgDetections,
            averageConfidence: avgConfidence,
            processingMode: processingMode,
            isLowLight: isLowLight,
            isHighMotion: isHighMotion,
            isCrowded: isCrowded,
            confidenceMultiplier: confidenceMultiplier
        )
    }
}

// MARK: - Supporting Types
struct ProcessingRecommendations {
    let skipFrames: Bool
    let reduceResolution: Bool
    let useSimplifiedTracking: Bool
    let maxObjects: Int
    let confidenceThreshold: Float
}

struct AdaptiveStats {
    let averageFPS: Double
    let averageDetections: Int
    let averageConfidence: Float
    let processingMode: AdaptiveDetectionTuner.ProcessingMode
    let isLowLight: Bool
    let isHighMotion: Bool
    let isCrowded: Bool
    let confidenceMultiplier: Float
}