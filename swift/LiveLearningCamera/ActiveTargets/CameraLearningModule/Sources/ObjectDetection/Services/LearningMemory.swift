//
//  LearningMemory.swift
//  LiveLearningCamera
//
//  Tracks what the camera has learned to become smarter over time
//

import Foundation
import CoreGraphics

/// Manages the camera's learning memory - what it knows and has seen
class LearningMemory {
    
    // MARK: - Learned Concept
    struct LearnedConcept {
        let className: String
        var observationCount: Int
        var averageConfidence: Float
        var firstSeen: Date
        var lastSeen: Date
        var bestConfidence: Float
        var typicalSize: CGSize  // Average bounding box size
        var locations: Set<String>  // Where we've seen this (top-left, center, etc.)
        
        mutating func update(with object: MemoryTrackedObject) {
            observationCount += 1
            
            // Update confidence stats
            let weight = 1.0 / Float(observationCount)
            averageConfidence = averageConfidence * (1 - weight) + object.confidence * weight
            bestConfidence = max(bestConfidence, object.confidence)
            
            // Update timing
            lastSeen = Date()
            
            // Update size understanding
            let newSize = object.lastBoundingBox.size
            let cgWeight = CGFloat(weight)
            typicalSize.width = typicalSize.width * (1 - cgWeight) + newSize.width * cgWeight
            typicalSize.height = typicalSize.height * (1 - cgWeight) + newSize.height * cgWeight
            
            // Track location
            locations.insert(getLocationQuadrant(object.lastBoundingBox))
        }
        
        private func getLocationQuadrant(_ box: CGRect) -> String {
            let x = box.midX
            let y = box.midY
            
            if x < 0.33 {
                if y < 0.33 { return "top-left" }
                else if y < 0.66 { return "mid-left" }
                else { return "bottom-left" }
            } else if x < 0.66 {
                if y < 0.33 { return "top-center" }
                else if y < 0.66 { return "center" }
                else { return "bottom-center" }
            } else {
                if y < 0.33 { return "top-right" }
                else if y < 0.66 { return "mid-right" }
                else { return "bottom-right" }
            }
        }
        
        var familiarityLevel: String {
            switch observationCount {
            case 0...5: return "new"
            case 6...20: return "learning"
            case 21...50: return "familiar"
            case 51...100: return "well-known"
            default: return "expert"
            }
        }
        
        var description: String {
            return "\(className): \(familiarityLevel) (seen \(observationCount)x, avg \(Int(averageConfidence * 100))%)"
        }
    }
    
    // MARK: - Properties
    private var learnedConcepts: [String: LearnedConcept] = [:]
    private var sessionStartTime = Date()
    private var totalObjectsSeen = 0
    private var uniqueClassesSeen = Set<String>()
    
    // MARK: - Public Methods
    
    /// Process an object and update learning memory
    func learn(from object: MemoryTrackedObject) -> (isNew: Bool, familiarityLevel: String) {
        totalObjectsSeen += 1
        uniqueClassesSeen.insert(object.label)
        
        if var concept = learnedConcepts[object.label] {
            // Update existing concept
            concept.update(with: object)
            learnedConcepts[object.label] = concept
            return (false, concept.familiarityLevel)
        } else {
            // Learn new concept
            let newConcept = LearnedConcept(
                className: object.label,
                observationCount: 1,
                averageConfidence: object.confidence,
                firstSeen: Date(),
                lastSeen: Date(),
                bestConfidence: object.confidence,
                typicalSize: object.lastBoundingBox.size,
                locations: [getLocationQuadrant(object.lastBoundingBox)]
            )
            learnedConcepts[object.label] = newConcept
            return (true, "new")
        }
    }
    
    /// Determine if we should save based on learning progress
    func shouldSaveForLearning(_ object: MemoryTrackedObject) -> (shouldSave: Bool, reason: String?) {
        guard let concept = learnedConcepts[object.label] else {
            // First time seeing this class - definitely save
            return (true, "Learning new class: \(object.label)")
        }
        
        // Save if significantly better confidence than we've seen
        if object.confidence > concept.bestConfidence + 0.1 {
            return (true, "New best confidence for \(object.label): \(Int(object.confidence * 100))%")
        }
        
        // Save if in a new location we haven't seen
        let currentLocation = getLocationQuadrant(object.lastBoundingBox)
        if !concept.locations.contains(currentLocation) {
            return (true, "\(object.label) in new location: \(currentLocation)")
        }
        
        // Save periodically for well-known objects (less frequently)
        let timeSinceLast = Date().timeIntervalSince(concept.lastSeen)
        switch concept.familiarityLevel {
        case "new":
            // Save frequently when learning
            if timeSinceLast > 2 {
                return (true, "Still learning \(object.label)")
            }
        case "learning":
            // Save moderately when becoming familiar
            if timeSinceLast > 10 {
                return (true, "Reinforcing \(object.label)")
            }
        case "familiar", "well-known", "expert":
            // Save rarely for well-known objects
            if timeSinceLast > 30 {
                return (true, "Periodic update for \(object.label)")
            }
        default:
            break
        }
        
        return (false, nil)
    }
    
    private func getLocationQuadrant(_ box: CGRect) -> String {
        let x = box.midX
        let y = box.midY
        
        if x < 0.5 && y < 0.5 { return "top-left" }
        else if x >= 0.5 && y < 0.5 { return "top-right" }
        else if x < 0.5 && y >= 0.5 { return "bottom-left" }
        else { return "bottom-right" }
    }
    
    /// Get learning statistics
    func getLearningStats() -> String {
        let sessionDuration = Date().timeIntervalSince(sessionStartTime)
        let minutes = Int(sessionDuration / 60)
        
        var stats = "🧠 Learning Stats (\(minutes)m):\n"
        stats += "  Total seen: \(totalObjectsSeen) objects\n"
        stats += "  Classes learned: \(uniqueClassesSeen.count)\n"
        
        if !learnedConcepts.isEmpty {
            stats += "  Knowledge:\n"
            for concept in learnedConcepts.values.sorted(by: { $0.observationCount > $1.observationCount }) {
                stats += "    • \(concept.description)\n"
            }
        }
        
        return stats
    }
    
    /// Reset learning for new session
    func startNewSession() {
        sessionStartTime = Date()
        totalObjectsSeen = 0
        // Keep learned concepts but reset session-specific stats
    }
}

// MARK: - Singleton
extension LearningMemory {
    static let shared = LearningMemory()
}