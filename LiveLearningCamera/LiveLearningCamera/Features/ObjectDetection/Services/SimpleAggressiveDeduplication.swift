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
            
            // For the same class:
            // - Within 10 seconds: Need 30% confidence change OR significant movement
            // - Within 30 seconds: Need 20% confidence change OR moderate movement  
            // - After 30 seconds: Allow saving
            
            if timeSince > 30 {
                return false // Been long enough, allow save
            }
            
            // Check confidence change
            let confChange = abs(confidence - object.confidence)
            
            // Check position change (simple center distance)
            let dx = abs(box.midX - object.lastBoundingBox.midX)
            let dy = abs(box.midY - object.lastBoundingBox.midY)
            let distance = sqrt(dx * dx + dy * dy)
            
            if timeSince < 10 {
                // Very recent - need BIG changes
                return confChange < 0.3 && distance < 0.3
            } else {
                // Somewhat recent - need moderate changes
                return confChange < 0.2 && distance < 0.2
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
        
        // Determine save reason
        let reason: String
        
        // First of this class?
        let hasClass = recentSaves.contains { $0.label == object.label }
        if !hasClass {
            reason = "New: First \(object.label)"
        }
        // High confidence?
        else if object.confidence > 0.9 {
            let hasHighConf = recentSaves.contains { 
                $0.label == object.label && $0.confidence > 0.85 
            }
            if !hasHighConf {
                reason = "Quality: High confidence \(object.label) (\(Int(object.confidence * 100))%)"
            } else {
                reason = "Update: \(object.label) (\(Int(object.confidence * 100))%)"
            }
        }
        // Normal save
        else {
            reason = "Track: \(object.label) (\(Int(object.confidence * 100))%)"
        }
        
        // Record the save
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
        
        return (true, reason)
    }
    
    func reset() {
        recentSaves.removeAll()
        totalChecked = 0
        totalSaved = 0
    }
}