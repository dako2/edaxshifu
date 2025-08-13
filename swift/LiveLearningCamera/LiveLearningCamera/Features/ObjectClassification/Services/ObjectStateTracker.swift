//
//  ObjectStateTracker.swift
//  LiveLearningCamera
//
//  Tracks object states using visual features and KNN for deduplication
//

import Foundation
import CoreML
import Vision
import simd
import UIKit

// MARK: - Object State
enum ObjectState {
    case new           // First time seeing this object
    case stationary    // Object hasn't moved or changed
    case moved         // Same object, new location  
    case changed       // Object appearance changed (lighting, angle, etc)
    case reappeared    // Object was gone, now back
}

// MARK: - Visual Object Record
struct VisualObjectRecord {
    let id: UUID
    let label: String
    let features: [Float]  // Visual features from ViT
    let boundingBox: CGRect
    let thumbnail: Data?
    let timestamp: Date
    let confidence: Float
    
    // Compute visual similarity using cosine distance
    func visualSimilarity(to other: VisualObjectRecord) -> Float {
        guard features.count == other.features.count else { return 0 }
        
        // Cosine similarity
        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        
        for i in 0..<features.count {
            dotProduct += features[i] * other.features[i]
            normA += features[i] * features[i]
            normB += other.features[i] * other.features[i]
        }
        
        guard normA > 0 && normB > 0 else { return 0 }
        return dotProduct / (sqrt(normA) * sqrt(normB))
    }
    
    // Compute spatial overlap (IoU)
    func spatialOverlap(with other: VisualObjectRecord) -> Float {
        let intersection = boundingBox.intersection(other.boundingBox)
        guard !intersection.isNull else { return 0 }
        
        let intersectionArea = intersection.width * intersection.height
        let unionArea = (boundingBox.width * boundingBox.height) + 
                       (other.boundingBox.width * other.boundingBox.height) - 
                       intersectionArea
        
        return Float(intersectionArea / unionArea)
    }
}

// MARK: - KNN Object Matcher
class KNNObjectMatcher {
    fileprivate var objectDatabase: [VisualObjectRecord] = []  // Made fileprivate for logging
    private let k = 5  // Number of neighbors to consider
    private let visualSimilarityThreshold: Float = 0.85  // High similarity = same object
    private let spatialOverlapThreshold: Float = 0.3     // Moderate overlap = nearby
    
    func findSimilarObjects(to query: VisualObjectRecord, withinLabel: Bool = true) -> [(record: VisualObjectRecord, similarity: Float, state: ObjectState)] {
        var candidates = objectDatabase
        
        // Filter by label if requested
        if withinLabel {
            candidates = candidates.filter { $0.label == query.label }
        }
        
        // Compute similarities
        let similarities = candidates.map { record in
            (
                record: record,
                visualSim: query.visualSimilarity(to: record),
                spatialOverlap: query.spatialOverlap(with: record),
                timeDiff: abs(query.timestamp.timeIntervalSince(record.timestamp))
            )
        }
        
        // Sort by visual similarity
        let sorted = similarities.sorted { $0.visualSim > $1.visualSim }
        
        // Take top K and determine states
        let topK = sorted.prefix(k).map { match -> (record: VisualObjectRecord, similarity: Float, state: ObjectState) in
            let state: ObjectState
            
            if match.visualSim > visualSimilarityThreshold {
                // Very similar visually
                if match.spatialOverlap > spatialOverlapThreshold {
                    // Same location = stationary
                    state = .stationary
                } else {
                    // Different location = moved
                    state = .moved
                }
            } else if match.visualSim > 0.6 {
                // Somewhat similar = changed (different angle/lighting)
                state = .changed
            } else if match.timeDiff > 60 {
                // Long time gap = reappeared
                state = .reappeared
            } else {
                // Different object
                state = .new
            }
            
            return (record: match.record, similarity: match.visualSim, state: state)
        }
        
        return Array(topK)
    }
    
    func addToDatabase(_ record: VisualObjectRecord) {
        objectDatabase.append(record)
        
        // Limit database size
        if objectDatabase.count > 1000 {
            // Remove oldest entries
            objectDatabase = Array(objectDatabase.suffix(800))
        }
    }
    
    func shouldSaveObject(_ record: VisualObjectRecord) -> (save: Bool, state: ObjectState) {
        let matches = findSimilarObjects(to: record)
        
        if matches.isEmpty {
            // No similar objects found
            print("  KNN: No similar objects found for \(record.label)")
            return (true, .new)
        }
        
        let bestMatch = matches[0]
        print("  KNN: Best match for \(record.label): similarity=\(bestMatch.similarity), state=\(bestMatch.state)")
        
        switch bestMatch.state {
        case .new:
            return (true, .new)
        case .stationary:
            // Don't save duplicates of stationary objects
            return (false, .stationary)
        case .moved:
            // Save if moved significantly
            return (bestMatch.record.spatialOverlap(with: record) < 0.1, .moved)
        case .changed:
            // Save if appearance changed significantly
            return (bestMatch.similarity < 0.7, .changed)
        case .reappeared:
            return (true, .reappeared)
        }
    }
}

// MARK: - Object State Tracker
@MainActor
class ObjectStateTracker: ObservableObject {
    static let shared = ObjectStateTracker()
    
    private let featureExtractor: VisualFeatureExtractor?
    private let knnMatcher = KNNObjectMatcher()
    @Published var trackedStates: [UUID: ObjectState] = [:]
    
    private init() {
        // Initialize feature extractor
        do {
            self.featureExtractor = try VisualFeatureExtractor()
        } catch {
            print("Failed to initialize VisualFeatureExtractor: \(error)")
            self.featureExtractor = nil
        }
    }
    
    func processObject(_ object: MemoryTrackedObject, from frame: CIImage) async -> (shouldSave: Bool, state: ObjectState) {
        // Extract visual features if possible
        guard let extractor = featureExtractor else {
            print("ObjectStateTracker WARNING: No feature extractor available, saving all objects")
            // Fallback to simple deduplication
            return (true, .new)
        }
        
        // Extract features from the object's region
        let context = CIContext()
        guard let cgImage = context.createCGImage(frame, from: frame.extent) else {
            print("ObjectStateTracker ERROR: Failed to create CGImage from CIImage")
            return (true, .new)
        }
        
        do {
            let features = try await extractor.extractFeatures(
                from: cgImage,
                boundingBox: object.lastBoundingBox
            )
            
            // Create visual record
            let record = VisualObjectRecord(
                id: object.id,
                label: object.label,
                features: features.values,
                boundingBox: object.lastBoundingBox,
                thumbnail: object.thumbnail,
                timestamp: Date(),
                confidence: object.confidence
            )
            
            // Check if we should save
            let (shouldSave, state) = knnMatcher.shouldSaveObject(record)
            
            print("ObjectStateTracker: \(object.label) - State: \(state), Save: \(shouldSave)")
            
            // Update tracked state
            trackedStates[object.id] = state
            
            // Add to database if saving
            if shouldSave {
                knnMatcher.addToDatabase(record)
                print("  -> Added to KNN database (now \(knnMatcher.objectDatabase.count) objects)")
            }
            
            return (shouldSave, state)
            
        } catch {
            print("ObjectStateTracker ERROR: Feature extraction failed - \(error)")
            print("  Object: \(object.label) at \(object.lastBoundingBox)")
            // If feature extraction fails, fallback to saving everything
            return (true, .new)
        }
    }
    
    func getObjectStateSummary() -> [ObjectState: Int] {
        var summary: [ObjectState: Int] = [:]
        for state in trackedStates.values {
            summary[state, default: 0] += 1
        }
        return summary
    }
}