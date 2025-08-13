//
//  SimpleAggressiveDeduplication.swift
//  LiveLearningCamera
//
//  Simple but aggressive deduplication - no fancy ML, just smart rules
//

import Foundation
import CoreGraphics

/// Dead simple but aggressive deduplication
class SimpleAggressiveDeduplication {
    
    // MARK: - Recent Save
    private struct RecentSave {
        let label: String
        let confidence: Float
        let box: CGRect
        let savedAt: Date
        
        func isTooSimilar(to object: MemoryTrackedObject) -> Bool {
            // Different class? Not similar
            guard label == object.label else { return false }
            
            // How long since we saved this?
            let timeSince = Date().timeIntervalSince(savedAt)
            
            // MUCH MORE AGGRESSIVE:
            // - Within 30 seconds: Need 40% confidence change OR major movement
            // - Within 60 seconds: Need 30% confidence change OR significant movement  
            // - After 60 seconds: Still need meaningful change
            
            if timeSince > 60 {
                // Even after a minute, check for meaningful change
                let confChange = abs(confidence - object.confidence)
                let dx = abs(box.midX - object.lastBoundingBox.midX)
                let dy = abs(box.midY - object.lastBoundingBox.midY)
                let distance = sqrt(dx * dx + dy * dy)
                
                // Need at least 15% confidence change or notable movement
                return confChange < 0.15 && distance < 0.2
            }
            
            // Check confidence change
            let confChange = abs(confidence - object.confidence)
            
            // Check position change (simple center distance)
            let dx = abs(box.midX - object.lastBoundingBox.midX)
            let dy = abs(box.midY - object.lastBoundingBox.midY)
            let distance = sqrt(dx * dx + dy * dy)
            
            if timeSince < 30 {
                // Very recent - need HUGE changes
                return confChange < 0.4 && distance < 0.4
            } else {
                // Somewhat recent - still need big changes
                return confChange < 0.3 && distance < 0.3
            }
        }
    }
    
    // MARK: - Properties
    private var recentSaves: [RecentSave] = []
    private let maxHistory = 50
    
    // Stats
    private var totalChecked = 0
    private var totalSaved = 0
    
    // MARK: - Singleton
    static let shared = SimpleAggressiveDeduplication()
    
    // MARK: - Main Check
    func shouldSave(_ object: MemoryTrackedObject) -> (save: Bool, reason: String) {
        totalChecked += 1
        
        // Clean old saves
        let cutoff = Date().addingTimeInterval(-60)
        recentSaves = recentSaves.filter { $0.savedAt > cutoff }
        
        // Check against recent saves
        for recent in recentSaves {
            if recent.isTooSimilar(to: object) {
                let timeSince = Int(Date().timeIntervalSince(recent.savedAt))
                return (false, "Skip: Similar \(object.label) saved \(timeSince)s ago")
            }
        }
        
        // If we get here, it's not too similar to recent saves
        // Decide if we should save based on criteria
        
        let shouldSave: Bool
        let reason: String
        
        // First of this class?
        let hasClass = recentSaves.contains { $0.label == object.label }
        if !hasClass {
            // First time seeing this class - definitely save
            shouldSave = true
            reason = "New: First \(object.label)"
        }
        // High confidence and we don't have a high confidence example?
        else if object.confidence > 0.9 {
            let hasHighConf = recentSaves.contains { 
                $0.label == object.label && $0.confidence > 0.85 
            }
            if !hasHighConf {
                // First high confidence example - save it
                shouldSave = true
                reason = "Quality: High confidence \(object.label) (\(Int(object.confidence * 100))%)"
            } else {
                // Already have high confidence examples - skip
                shouldSave = false
                reason = "Skip: Already have high conf \(object.label)"
            }
        }
        // Regular confidence - only save periodically
        else {
            // We already have examples and this isn't special - skip it
            shouldSave = false
            reason = "Skip: Regular \(object.label) (\(Int(object.confidence * 100))%)"
        }
        
        // Only record if we're actually saving
        if shouldSave {
            recentSaves.append(RecentSave(
                label: object.label,
                confidence: object.confidence,
                box: object.lastBoundingBox,
                savedAt: Date()
            ))
            
            // Limit history size
            if recentSaves.count > maxHistory {
                recentSaves = Array(recentSaves.suffix(maxHistory - 10))
            }
            
            totalSaved += 1
            
            // Log save rate
            if totalSaved % 10 == 0 {
                let saveRate = Float(totalSaved) / Float(totalChecked) * 100
                print("📊 Save rate: \(Int(saveRate))% (\(totalSaved)/\(totalChecked))")
            }
        }
        
        return (shouldSave, reason)
    }
    
    func reset() {
        recentSaves.removeAll()
        totalChecked = 0
        totalSaved = 0
    }
}