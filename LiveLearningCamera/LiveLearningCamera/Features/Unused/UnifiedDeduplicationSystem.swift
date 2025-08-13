//
//  UnifiedDeduplicationSystem.swift
//  LiveLearningCamera
//
//  Unified deduplication using KNN, visual features, and smart rules
//

import Foundation
import CoreGraphics
import UIKit
import CoreImage

/// Unified deduplication system that combines KNN, visual features, and smart rules
@MainActor
class UnifiedDeduplicationSystem: ObservableObject {
    
    // MARK: - Visual Memory Record
    private struct VisualMemoryRecord {
        let id: UUID
        let label: String
        let confidence: Float
        let boundingBox: CGRect
        let savedAt: Date
        let visualFeatures: [Float]?  // Visual features if available
        let thumbnailHash: Int?
        
        func calculateSimilarity(to other: VisualMemoryRecord) -> Float {
            // If we have visual features, use them
            if let myFeatures = visualFeatures,
               let otherFeatures = other.visualFeatures,
               !myFeatures.isEmpty && !otherFeatures.isEmpty {
                return calculateCosineSimilarity(myFeatures, otherFeatures)
            }
            
            // Fallback to position and confidence similarity
            let iou = calculateIoU(boundingBox, other.boundingBox)
            let confDiff = 1.0 - abs(confidence - other.confidence)
            return (iou + confDiff) / 2.0
        }
        
        private func calculateCosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
            guard a.count == b.count else { return 0 }
            
            var dotProduct: Float = 0
            var normA: Float = 0
            var normB: Float = 0
            
            for i in 0..<a.count {
                dotProduct += a[i] * b[i]
                normA += a[i] * a[i]
                normB += b[i] * b[i]
            }
            
            guard normA > 0 && normB > 0 else { return 0 }
            return dotProduct / (sqrt(normA) * sqrt(normB))
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
    private var knnDatabase: [VisualMemoryRecord] = []
    private let k = 5  // Number of neighbors for KNN
    private let maxDatabaseSize = 500
    
    // Thresholds
    private let visualSimilarityThreshold: Float = 0.85
    private let minTimeBetweenSaves: TimeInterval = 5.0
    private let minConfidenceChange: Float = 0.15
    
    // Feature extractor (optional)
    private let featureExtractor: VisualFeatureExtractor?
    
    // Learning stats
    @Published var totalProcessed = 0
    @Published var totalSaved = 0
    @Published var knnSize = 0
    
    // MARK: - Singleton
    static let shared = UnifiedDeduplicationSystem()
    
    private init() {
        // Try to initialize feature extractor
        do {
            self.featureExtractor = try VisualFeatureExtractor()
            print("UnifiedDeduplication: Visual feature extractor initialized")
        } catch {
            print("UnifiedDeduplication: No visual features available - using position-based matching")
            self.featureExtractor = nil
        }
    }
    
    // MARK: - Main Processing
    
    /// Process an object and determine if it should be saved
    func processObject(_ object: MemoryTrackedObject, from frame: CIImage) async -> (shouldSave: Bool, reason: String) {
        totalProcessed += 1
        
        // Extract visual features if possible
        var visualFeatures: [Float]? = nil
        
        if let extractor = featureExtractor {
            let context = CIContext()
            if let cgImage = context.createCGImage(frame, from: frame.extent) {
                do {
                    let features = try await extractor.extractFeatures(
                        from: cgImage,
                        boundingBox: object.lastBoundingBox
                    )
                    visualFeatures = features.values
                    print("UnifiedDedup: Extracted \(features.values.count) visual features for \(object.label)")
                } catch {
                    print("UnifiedDedup: Feature extraction failed, using fallback")
                }
            }
        }
        
        // Create record for this object
        let record = VisualMemoryRecord(
            id: object.id,
            label: object.label,
            confidence: object.confidence,
            boundingBox: object.lastBoundingBox,
            savedAt: Date(),
            visualFeatures: visualFeatures,
            thumbnailHash: object.thumbnail?.hashValue
        )
        
        // Find K nearest neighbors
        let neighbors = findKNearestNeighbors(for: record)
        
        // Determine if we should save based on KNN results
        let (shouldSave, reason) = analyzeNeighbors(neighbors, for: record)
        
        if shouldSave {
            // Add to KNN database - THIS IS THE LIVE UPDATE!
            addToKNNDatabase(record)
            totalSaved += 1
            
            // Log learning progress
            if totalSaved % 10 == 0 {
                print("📊 KNN Database: \(knnDatabase.count) records, \(totalSaved) total saved")
            }
        }
        
        return (shouldSave, reason)
    }
    
    // MARK: - KNN Operations
    
    private func findKNearestNeighbors(for query: VisualMemoryRecord) -> [(record: VisualMemoryRecord, similarity: Float)] {
        // Filter to same class for better matching
        let candidates = knnDatabase.filter { $0.label == query.label }
        
        // Calculate similarities
        let similarities = candidates.map { record in
            (record: record, similarity: query.calculateSimilarity(to: record))
        }
        
        // Sort by similarity and take top K
        return Array(similarities.sorted { $0.similarity > $1.similarity }.prefix(k))
    }
    
    private func analyzeNeighbors(_ neighbors: [(record: VisualMemoryRecord, similarity: Float)], 
                                  for query: VisualMemoryRecord) -> (shouldSave: Bool, reason: String) {
        
        // No neighbors - this is new
        if neighbors.isEmpty {
            return (true, "🆕 First \(query.label) detected")
        }
        
        // Check best match
        let bestMatch = neighbors[0]
        
        // Very similar - likely duplicate
        if bestMatch.similarity > visualSimilarityThreshold {
            let timeSince = Date().timeIntervalSince(bestMatch.record.savedAt)
            
            if timeSince < minTimeBetweenSaves {
                return (false, "⏭️ Too similar to recent save (\(Int(bestMatch.similarity * 100))% match)")
            }
            
            // Check if confidence improved significantly
            let confImprovement = query.confidence - bestMatch.record.confidence
            if confImprovement > minConfidenceChange {
                return (true, "📈 Better confidence (+\(Int(confImprovement * 100))%)")
            }
            
            // Periodic update for known objects
            if timeSince > 30 {
                return (true, "🔄 Periodic update (30s elapsed)")
            }
            
            return (false, "⏭️ Too similar (\(Int(bestMatch.similarity * 100))% match)")
        }
        
        // Moderate similarity - check for meaningful changes
        if bestMatch.similarity > 0.6 {
            // Position changed significantly
            let iou = calculateIoU(query.boundingBox, bestMatch.record.boundingBox)
            if iou < 0.3 {
                return (true, "📍 Object moved to new location")
            }
            
            // Visual appearance changed
            if let queryFeatures = query.visualFeatures,
               let matchFeatures = bestMatch.record.visualFeatures {
                return (true, "🎨 Visual appearance changed")
            }
        }
        
        // Low similarity - treat as new variation
        return (true, "🔄 New variation of \(query.label)")
    }
    
    private func addToKNNDatabase(_ record: VisualMemoryRecord) {
        knnDatabase.append(record)
        knnSize = knnDatabase.count
        
        // Maintain database size with smart pruning
        if knnDatabase.count > maxDatabaseSize {
            pruneDatabase()
        }
        
        print("💾 KNN: Added \(record.label) (database size: \(knnDatabase.count))")
    }
    
    private func pruneDatabase() {
        // Remove oldest entries but keep diverse examples
        let grouped = Dictionary(grouping: knnDatabase, by: { $0.label })
        var newDatabase: [VisualMemoryRecord] = []
        
        for (label, records) in grouped {
            // Keep most recent and most confident examples
            let sorted = records.sorted { $0.savedAt > $1.savedAt }
            let toKeep = min(100, sorted.count)  // Max 100 per class
            newDatabase.append(contentsOf: sorted.prefix(toKeep))
        }
        
        // Sort by date and take most recent
        knnDatabase = newDatabase.sorted { $0.savedAt > $1.savedAt }
        if knnDatabase.count > maxDatabaseSize {
            knnDatabase = Array(knnDatabase.prefix(maxDatabaseSize))
        }
        
        knnSize = knnDatabase.count
        print("🧹 KNN: Pruned database to \(knnDatabase.count) records")
    }
    
    private func calculateIoU(_ box1: CGRect, _ box2: CGRect) -> Float {
        let intersection = box1.intersection(box2)
        guard !intersection.isNull else { return 0 }
        
        let intersectionArea = intersection.width * intersection.height
        let unionArea = (box1.width * box1.height) + (box2.width * box2.height) - intersectionArea
        
        return Float(intersectionArea / unionArea)
    }
    
    // MARK: - Statistics
    
    func getStatistics() -> String {
        let grouped = Dictionary(grouping: knnDatabase, by: { $0.label })
        let classStats = grouped.map { "\($0.key): \($0.value.count)" }.joined(separator: ", ")
        
        let saveRate = totalProcessed > 0 ? Float(totalSaved) / Float(totalProcessed) * 100 : 0
        
        return """
        🧠 KNN Statistics:
          Database: \(knnDatabase.count) records
          Classes: \(grouped.count) (\(classStats))
          Save rate: \(Int(saveRate))% (\(totalSaved)/\(totalProcessed))
          Feature extraction: \(featureExtractor != nil ? "Active" : "Disabled")
        """
    }
    
    func reset() {
        knnDatabase.removeAll()
        totalProcessed = 0
        totalSaved = 0
        knnSize = 0
        print("🔄 KNN: Database reset")
    }
}