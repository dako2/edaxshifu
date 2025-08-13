//
//  MemorySubsystems.swift
//  LiveLearningCamera
//
//  Different memory systems that work like human memory
//

import Foundation
import CoreData

// MARK: - Working Memory (Current Focus)
class WorkingMemory {
    private var currentObjects: [RecognizedObject] = []
    private let capacity = 7 // Miller's Magic Number
    
    func add(_ object: RecognizedObject) {
        // Remove if already present
        currentObjects.removeAll { $0.id == object.id }
        
        // Add to front
        currentObjects.insert(object, at: 0)
        
        // Maintain capacity limit
        if currentObjects.count > capacity {
            currentObjects.removeLast()
        }
    }
    
    func getCurrentObjects() -> [RecognizedObject] {
        return currentObjects
    }
    
    func getMostInteresting() -> RecognizedObject? {
        return currentObjects.max { ($0.interestScore ) < ($1.interestScore ) }
    }
    
    var isEmpty: Bool {
        return currentObjects.isEmpty
    }
    
    func clear() {
        currentObjects.removeAll()
    }
}

// MARK: - Short-Term Memory (Recent Observations)
class ShortTermMemory {
    private var recentObservations: [ObjectObservation] = []
    private let retentionPeriod: TimeInterval = 60 // 1 minute
    private let maxCapacity = 50
    
    func add(_ observation: ObjectObservation) {
        recentObservations.insert(observation, at: 0)
        
        if recentObservations.count > maxCapacity {
            recentObservations.removeLast()
        }
    }
    
    func cleanup() {
        let cutoff = Date().addingTimeInterval(-retentionPeriod)
        recentObservations.removeAll { 
            ($0.timestamp ?? Date.distantPast) < cutoff 
        }
    }
    
    func getRecent(count: Int = 10) -> [ObjectObservation] {
        return Array(recentObservations.prefix(count))
    }
    
    func consolidateToLongTerm() {
        // Find patterns in short-term memory
        let grouped = Dictionary(grouping: recentObservations) { 
            $0.recognizedObject?.id ?? UUID() 
        }
        
        for (_, observations) in grouped {
            if observations.count >= 3 {
                // Seen multiple times - worth remembering
                if let object = observations.first?.recognizedObject {
                    object.interestScore += 0.1
                    CoreDataManager.shared.saveContext()
                }
            }
        }
    }
}

// MARK: - Long-Term Memory (Persistent Storage)
class LongTermMemory {
    private let context = CoreDataManager.shared.context
    
    func findSimilar(to signature: Data?, threshold: Float) -> RecognizedObject? {
        guard let signature = signature else { return nil }
        
        // In a real implementation, would use feature matching
        // For now, simplified lookup
        let request: NSFetchRequest<RecognizedObject> = RecognizedObject.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "lastSeen", ascending: false)]
        request.fetchLimit = 10
        
        do {
            let recent = try context.fetch(request)
            
            // Simple similarity check (would use ML in production)
            for object in recent {
                if let objSignature = object.visualSignature {
                    let similarity = calculateSimilarity(signature, objSignature)
                    if similarity > threshold {
                        return object
                    }
                }
            }
        } catch {
            print("Failed to search long-term memory: \(error)")
        }
        
        return nil
    }
    
    func consolidate(_ object: RecognizedObject) {
        // Mark as important
        object.interestScore = max(object.interestScore, 0.7)
        
        CoreDataManager.shared.saveContext()
    }
    
    func getSeenCount(for label: String) -> Int {
        let request: NSFetchRequest<RecognizedObject> = RecognizedObject.fetchRequest()
        request.predicate = NSPredicate(format: "primaryLabel == %@", label)
        
        do {
            return try context.count(for: request)
        } catch {
            return 0
        }
    }
    
    func recall(objectId: UUID) -> RecognizedObject? {
        let request: NSFetchRequest<RecognizedObject> = RecognizedObject.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", objectId as CVarArg)
        request.fetchLimit = 1
        
        return try? context.fetch(request).first
    }
    
    func getMemoryStats() -> MemoryStatistics {
        let objectRequest: NSFetchRequest<RecognizedObject> = RecognizedObject.fetchRequest()
        let observationRequest: NSFetchRequest<ObjectObservation> = ObjectObservation.fetchRequest()
        
        do {
            let objectCount = try context.count(for: objectRequest)
            let observationCount = try context.count(for: observationRequest)
            
            // Get most seen object
            objectRequest.sortDescriptors = [NSSortDescriptor(key: "seenCount", ascending: false)]
            objectRequest.fetchLimit = 1
            let mostSeen = try context.fetch(objectRequest).first
            
            return MemoryStatistics(
                totalObjects: objectCount,
                totalObservations: observationCount,
                mostSeenObject: mostSeen?.primaryLabel,
                mostSeenCount: Int(mostSeen?.seenCount ?? 0)
            )
        } catch {
            return MemoryStatistics(
                totalObjects: 0,
                totalObservations: 0,
                mostSeenObject: nil,
                mostSeenCount: 0
            )
        }
    }
    
    private func calculateSimilarity(_ sig1: Data, _ sig2: Data) -> Float {
        // Simplified similarity calculation
        // In production, would use proper feature vectors
        let size1 = Float(sig1.count)
        let size2 = Float(sig2.count)
        let sizeSimilarity = min(size1, size2) / max(size1, size2)
        return sizeSimilarity
    }
}

// MARK: - Memory Statistics
struct MemoryStatistics {
    let totalObjects: Int
    let totalObservations: Int
    let mostSeenObject: String?
    let mostSeenCount: Int
}