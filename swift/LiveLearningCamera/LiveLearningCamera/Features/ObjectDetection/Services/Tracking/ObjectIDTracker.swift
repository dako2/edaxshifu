//
//  ObjectIDTracker.swift
//  LiveLearningCamera
//
//  Maintains persistent object IDs across frames based on position and class
//

import Foundation
import CoreGraphics

/// Tracks object identities across frames using position and class matching
class ObjectIDTracker {
    
    // MARK: - Tracked Object Info
    private struct TrackedObjectInfo {
        let id: UUID
        let label: String
        var lastBoundingBox: CGRect
        var lastSeen: Date
        let firstSeen: Date
        var confidenceHistory: [Float] = []
    }
    
    // MARK: - Properties
    private var trackedObjects: [TrackedObjectInfo] = []
    private let positionThreshold: CGFloat = 0.15  // Max distance for same object
    private let staleTimeout: TimeInterval = 2.0   // Remove objects not seen for 2 seconds
    
    // MARK: - Public Methods
    
    /// Get or create a persistent ID for a detection
    func getOrCreateID(for detection: Detection) -> UUID {
        // Clean up stale objects
        pruneStaleObjects()
        
        // Find best matching existing object
        if let matchingObject = findBestMatch(for: detection) {
            // Update the existing object
            updateTrackedObject(matchingObject, with: detection)
            return matchingObject.id
        } else {
            // Create new tracked object
            let newObject = createNewTrackedObject(for: detection)
            return newObject.id
        }
    }
    
    /// Get the first seen date for an object ID
    func getFirstSeen(for id: UUID) -> Date {
        return trackedObjects.first { $0.id == id }?.firstSeen ?? Date()
    }
    
    // MARK: - Private Methods
    
    private func findBestMatch(for detection: Detection) -> TrackedObjectInfo? {
        let candidates = trackedObjects.filter { tracked in
            // Must be same class
            tracked.label == detection.label &&
            // Must be within position threshold
            calculateDistance(tracked.lastBoundingBox, detection.boundingBox) < positionThreshold
        }
        
        // Return the closest match
        return candidates.min { obj1, obj2 in
            calculateDistance(obj1.lastBoundingBox, detection.boundingBox) <
            calculateDistance(obj2.lastBoundingBox, detection.boundingBox)
        }
    }
    
    private func calculateDistance(_ box1: CGRect, _ box2: CGRect) -> CGFloat {
        let dx = box1.midX - box2.midX
        let dy = box1.midY - box2.midY
        return sqrt(dx * dx + dy * dy)
    }
    
    private func calculateIoU(_ box1: CGRect, _ box2: CGRect) -> CGFloat {
        let intersection = box1.intersection(box2)
        guard !intersection.isNull else { return 0 }
        
        let intersectionArea = intersection.width * intersection.height
        let unionArea = (box1.width * box1.height) + (box2.width * box2.height) - intersectionArea
        
        return intersectionArea / unionArea
    }
    
    private func updateTrackedObject(_ object: TrackedObjectInfo, with detection: Detection) {
        if let index = trackedObjects.firstIndex(where: { $0.id == object.id }) {
            trackedObjects[index].lastBoundingBox = detection.boundingBox
            trackedObjects[index].lastSeen = Date()
            trackedObjects[index].confidenceHistory.append(detection.confidence)
            
            // Limit confidence history
            if trackedObjects[index].confidenceHistory.count > 30 {
                trackedObjects[index].confidenceHistory.removeFirst()
            }
        }
    }
    
    private func createNewTrackedObject(for detection: Detection) -> TrackedObjectInfo {
        let now = Date()
        let newObject = TrackedObjectInfo(
            id: UUID(),
            label: detection.label,
            lastBoundingBox: detection.boundingBox,
            lastSeen: now,
            firstSeen: now,
            confidenceHistory: [detection.confidence]
        )
        trackedObjects.append(newObject)
        
        print("ObjectIDTracker: Created new ID for \(detection.label) at \(detection.boundingBox)")
        
        return newObject
    }
    
    private func pruneStaleObjects() {
        let cutoff = Date().addingTimeInterval(-staleTimeout)
        let beforeCount = trackedObjects.count
        
        trackedObjects = trackedObjects.filter { object in
            object.lastSeen > cutoff
        }
        
        let removed = beforeCount - trackedObjects.count
        if removed > 0 {
            print("ObjectIDTracker: Pruned \(removed) stale objects")
        }
    }
    
    /// Get summary statistics
    func getSummary() -> String {
        let activeCount = trackedObjects.count
        let labels = Set(trackedObjects.map { $0.label })
        return "Tracking \(activeCount) objects across \(labels.count) classes"
    }
}