//
//  SmartDeduplicationManager.swift
//  LiveLearningCamera
//
//  Aggressive deduplication for live learning - only save meaningful changes
//

import Foundation
import CoreGraphics

/// Manages smart deduplication to prevent redundant saves
class SmartDeduplicationManager {
    
    // MARK: - Saved Object Record
    private struct SavedObjectRecord {
        let id: UUID
        let label: String
        let confidence: Float
        let boundingBox: CGRect
        let savedAt: Date
        let thumbnailHash: Int?  // Hash of thumbnail for comparison
        
        func isSimilarTo(_ other: MemoryTrackedObject) -> Bool {
            // Same class check
            guard label == other.label else { return false }
            
            // Time check - don't save same object within 5 seconds
            let timeDiff = abs(Date().timeIntervalSince(savedAt))
            guard timeDiff > 5.0 else { return true }  // Too recent, skip
            
            // Confidence change check - need at least 20% change
            let confidenceDiff = abs(confidence - other.confidence)
            if confidenceDiff < 0.2 { return true }  // Not enough change
            
            // Position change check - need significant movement
            let iou = calculateIoU(boundingBox, other.lastBoundingBox)
            if iou > 0.7 { return true }  // Too similar position
            
            return false  // Different enough to save
        }
        
        private func calculateIoU(_ box1: CGRect, _ box2: CGRect) -> Float {
            let intersection = box1.intersection(box2)
            guard !intersection.isNull else { return 0 }
            
            let intersectionArea = intersection.width * intersection.height
            let unionArea = (box1.width * box1.height) + (box2.width * box2.height) - intersectionArea
            
            return Float(intersectionArea / unionArea)
        }
    }
    
    // MARK: - Properties
    private var recentlySaved: [SavedObjectRecord] = []
    private let maxRecords = 100
    private let saveThresholds = SaveThresholds()
    
    // MARK: - Save Thresholds
    private struct SaveThresholds {
        let minTimeBetweenSaves: TimeInterval = 5.0  // Don't save same object within 5 seconds
        let minConfidenceChange: Float = 0.2          // Need 20% confidence change
        let minPositionChange: Float = 0.3            // Need 30% position change (1 - IoU)
        let maxSimilarityScore: Float = 0.8           // Overall similarity threshold
    }
    
    // MARK: - Public Methods
    
    /// Determine if an object should be saved based on smart deduplication
    func shouldSaveObject(_ object: MemoryTrackedObject) -> (shouldSave: Bool, reason: String) {
        // Clean up old records
        pruneOldRecords()
        
        // Check against recently saved objects
        for record in recentlySaved {
            if record.isSimilarTo(object) {
                return (false, "Too similar to recently saved \(record.label)")
            }
        }
        
        // Check for meaningful events that warrant saving
        let saveReason = determineSaveReason(for: object)
        if let reason = saveReason {
            // Record this save
            recordSave(object)
            return (true, reason)
        }
        
        return (false, "No meaningful change detected")
    }
    
    // MARK: - Private Methods
    
    private func determineSaveReason(for object: MemoryTrackedObject) -> String? {
        // First appearance of this class
        let hasSimilarClass = recentlySaved.contains { $0.label == object.label }
        if !hasSimilarClass {
            return "First detection of \(object.label)"
        }
        
        // High confidence detection (>90%)
        if object.confidence > 0.9 {
            let hasHighConfidenceSave = recentlySaved.contains { 
                $0.label == object.label && $0.confidence > 0.9 
            }
            if !hasHighConfidenceSave {
                return "High confidence detection (>\(Int(object.confidence * 100))%)"
            }
        }
        
        // Check for significant state changes
        if let lastSimilar = findLastSimilarObject(to: object) {
            // Large confidence jump (>30%)
            let confJump = object.confidence - lastSimilar.confidence
            if confJump > 0.3 {
                return "Significant confidence increase (+\(Int(confJump * 100))%)"
            }
            
            // Object moved significantly
            let iou = calculateIoU(lastSimilar.boundingBox, object.lastBoundingBox)
            if iou < 0.3 {
                return "Object moved to new location"
            }
            
            // Long time since last save (>30 seconds)
            let timeSinceLast = Date().timeIntervalSince(lastSimilar.savedAt)
            if timeSinceLast > 30 {
                return "Periodic update (>30s since last save)"
            }
        }
        
        return nil
    }
    
    private func findLastSimilarObject(to object: MemoryTrackedObject) -> SavedObjectRecord? {
        return recentlySaved
            .filter { $0.label == object.label }
            .sorted { $0.savedAt > $1.savedAt }
            .first
    }
    
    private func recordSave(_ object: MemoryTrackedObject) {
        let record = SavedObjectRecord(
            id: object.id,
            label: object.label,
            confidence: object.confidence,
            boundingBox: object.lastBoundingBox,
            savedAt: Date(),
            thumbnailHash: object.thumbnail?.hashValue
        )
        
        recentlySaved.append(record)
        
        // Limit the size of records
        if recentlySaved.count > maxRecords {
            recentlySaved.removeFirst(20)
        }
    }
    
    private func pruneOldRecords() {
        let cutoff = Date().addingTimeInterval(-60)  // Remove records older than 1 minute
        recentlySaved = recentlySaved.filter { $0.savedAt > cutoff }
    }
    
    private func calculateIoU(_ box1: CGRect, _ box2: CGRect) -> Float {
        let intersection = box1.intersection(box2)
        guard !intersection.isNull else { return 0 }
        
        let intersectionArea = intersection.width * intersection.height
        let unionArea = (box1.width * box1.height) + (box2.width * box2.height) - intersectionArea
        
        return Float(intersectionArea / unionArea)
    }
    
    /// Get statistics about deduplication
    func getStatistics() -> String {
        let classGroups = Dictionary(grouping: recentlySaved, by: { $0.label })
        let stats = classGroups.map { "\($0.key): \($0.value.count)" }.joined(separator: ", ")
        return "Recently saved: \(recentlySaved.count) objects (\(stats))"
    }
}

// MARK: - Singleton
extension SmartDeduplicationManager {
    static let shared = SmartDeduplicationManager()
}