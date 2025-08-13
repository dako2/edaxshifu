//
//  SceneContextManager.swift
//  LiveLearningCamera
//
//  Practical scene understanding and relationship inference
//

import Foundation
import CoreGraphics

// MARK: - Scene Context Manager
class SceneContextManager {
    
    // Spatial relationship thresholds
    private let nearThreshold: CGFloat = 0.1 // 10% of frame width/height
    private let overlapThreshold: CGFloat = 0.2 // 20% overlap for containment
    
    // Temporal relationship tracking
    private var coOccurrenceMatrix = [String: [String: Int]]()
    private var spatialRelationships = [RelationshipKey: SpatialRelation]()
    private var temporalPatterns = [TemporalPattern]()
    
    // Scene classification
    private var sceneConfidence: [SceneType: Float] = [:]
    private var dominantScene: SceneType = .unknown
    
    // MARK: - Scene Analysis
    func analyzeScene(_ trackedObjects: [MemoryTrackedObject]) -> AnalyzedScene {
        // Extract spatial relationships
        let spatial = extractSpatialRelationships(trackedObjects)
        
        // Update co-occurrence patterns
        updateCoOccurrenceMatrix(trackedObjects)
        
        // Infer scene type
        let sceneType = inferSceneType(from: trackedObjects, relationships: spatial)
        
        // Detect activities
        let activities = detectActivities(trackedObjects, relationships: spatial)
        
        // Build scene graph
        let graph = buildSceneGraph(trackedObjects, relationships: spatial)
        
        return AnalyzedScene(
            timestamp: Date(),
            sceneType: sceneType,
            objects: trackedObjects,
            relationships: spatial,
            activities: activities,
            graph: graph
        )
    }
    
    // MARK: - Spatial Relationships
    private func extractSpatialRelationships(_ objects: [MemoryTrackedObject]) -> [SpatialRelation] {
        var relationships = [SpatialRelation]()
        
        for i in 0..<objects.count {
            for j in (i+1)..<objects.count {
                let obj1 = objects[i]
                let obj2 = objects[j]
                
                if let relation = determineSpatialRelation(obj1, obj2) {
                    relationships.append(relation)
                    
                    // Cache for temporal analysis
                    let key = RelationshipKey(id1: obj1.id, id2: obj2.id)
                    spatialRelationships[key] = relation
                }
            }
        }
        
        return relationships
    }
    
    private func determineSpatialRelation(_ obj1: MemoryTrackedObject, _ obj2: MemoryTrackedObject) -> SpatialRelation? {
        let box1 = obj1.lastBoundingBox
        let box2 = obj2.lastBoundingBox
        
        // Calculate spatial metrics
        let distance = calculateDistance(box1, box2)
        let overlap = calculateOverlap(box1, box2)
        let relativePosition = getRelativePosition(box1, box2)
        
        // Determine relationship type
        let type: SpatialRelationType
        if overlap > overlapThreshold {
            type = .overlapping
        } else if distance < nearThreshold {
            type = .near
        } else if isContained(box1, in: box2) {
            type = .inside
        } else if isAbove(box1, box2) {
            type = .above
        } else if isBelow(box1, box2) {
            type = .below
        } else {
            type = .distant
        }
        
        // Filter out uninteresting relationships
        guard type != .distant else { return nil }
        
        return SpatialRelation(
            object1: obj1,
            object2: obj2,
            type: type,
            distance: Float(distance),
            confidence: calculateRelationConfidence(obj1, obj2, type: type)
        )
    }
    
    // MARK: - Scene Type Inference
    private func inferSceneType(from objects: [MemoryTrackedObject], 
                               relationships: [SpatialRelation]) -> SceneType {
        // Reset confidences
        sceneConfidence = [:]
        
        // Extract object labels
        let labels = Set(objects.map { $0.label })
        
        // Indoor/Outdoor classification
        if labels.intersection(["person", "chair", "table", "laptop", "cup"]).count >= 2 {
            sceneConfidence[.indoor] = 0.7
        }
        
        if labels.intersection(["car", "truck", "bicycle", "traffic light"]).count >= 2 {
            sceneConfidence[.outdoor] = 0.8
            sceneConfidence[.street] = 0.9
        }
        
        // Specific scene detection
        if labels.contains("person") && labels.contains("laptop") {
            sceneConfidence[.office] = 0.6
        }
        
        if labels.contains("person") && labels.contains("dog") {
            sceneConfidence[.park] = 0.5
        }
        
        if labels.intersection(["cup", "fork", "knife", "pizza", "sandwich"]).count >= 2 {
            sceneConfidence[.dining] = 0.7
        }
        
        // Return highest confidence scene
        return sceneConfidence.max(by: { $0.value < $1.value })?.key ?? .unknown
    }
    
    // MARK: - Activity Detection
    private func detectActivities(_ objects: [MemoryTrackedObject], 
                                 relationships: [SpatialRelation]) -> [DetectedActivity] {
        var activities = [DetectedActivity]()
        
        // Person-object interactions
        let people = objects.filter { $0.label == "person" }
        
        for person in people {
            // Find objects near person
            let nearbyRelations = relationships.filter { 
                ($0.object1.id == person.id || $0.object2.id == person.id) && 
                $0.type == .near 
            }
            
            for relation in nearbyRelations {
                let otherObject = relation.object1.id == person.id ? relation.object2 : relation.object1
                
                // Infer activity based on object
                if let activity = inferActivity(person: person, object: otherObject) {
                    activities.append(activity)
                }
            }
        }
        
        // Vehicle motion patterns
        let vehicles = objects.filter { ["car", "truck", "bicycle"].contains($0.label) }
        for vehicle in vehicles {
            if let tracker = vehicle.tracker {
                let velocity = tracker.predict() // Get predicted position
                // If moving significantly, add driving/riding activity
                if abs(velocity.minX - vehicle.lastBoundingBox.minX) > 0.01 {
                    activities.append(DetectedActivity(
                        type: .moving,
                        participants: [vehicle],
                        confidence: 0.8
                    ))
                }
            }
        }
        
        return activities
    }
    
    private func inferActivity(person: MemoryTrackedObject, object: MemoryTrackedObject) -> DetectedActivity? {
        let activityMap: [String: DetectedActivityType] = [
            "laptop": .working,
            "phone": .phoneUse,
            "cup": .drinking,
            "book": .reading,
            "dog": .walking,
            "bicycle": .cycling
        ]
        
        guard let activityType = activityMap[object.label] else { return nil }
        
        return DetectedActivity(
            type: activityType,
            participants: [person, object],
            confidence: 0.7
        )
    }
    
    // MARK: - Scene Graph
    private func buildSceneGraph(_ objects: [MemoryTrackedObject], 
                                relationships: [SpatialRelation]) -> SceneGraphData {
        var nodes = [SceneNodeData]()
        var edges = [SceneEdgeData]()
        
        // Create nodes for objects
        for object in objects {
            nodes.append(SceneNodeData(
                id: object.id,
                label: object.label,
                attributes: [
                    "confidence": object.confidence,
                    "observations": Float(object.observationCount)
                ]
            ))
        }
        
        // Create edges for relationships
        for relation in relationships {
            edges.append(SceneEdgeData(
                from: relation.object1.id,
                to: relation.object2.id,
                type: relation.type,
                weight: relation.confidence
            ))
        }
        
        return SceneGraphData(nodes: nodes, edges: edges)
    }
    
    // MARK: - Temporal Patterns
    private func updateCoOccurrenceMatrix(_ objects: [MemoryTrackedObject]) {
        for obj1 in objects {
            if coOccurrenceMatrix[obj1.label] == nil {
                coOccurrenceMatrix[obj1.label] = [:]
            }
            
            for obj2 in objects where obj1.id != obj2.id {
                coOccurrenceMatrix[obj1.label]?[obj2.label, default: 0] += 1
            }
        }
    }
    
    func getCoOccurrenceScore(label1: String, label2: String) -> Int {
        return coOccurrenceMatrix[label1]?[label2] ?? 0
    }
    
    // MARK: - Helper Methods
    private func calculateDistance(_ box1: CGRect, _ box2: CGRect) -> CGFloat {
        let centerX1 = box1.midX
        let centerY1 = box1.midY
        let centerX2 = box2.midX
        let centerY2 = box2.midY
        
        return sqrt(pow(centerX2 - centerX1, 2) + pow(centerY2 - centerY1, 2))
    }
    
    private func calculateOverlap(_ box1: CGRect, _ box2: CGRect) -> CGFloat {
        let intersection = box1.intersection(box2)
        guard !intersection.isNull else { return 0 }
        
        let intersectionArea = intersection.width * intersection.height
        let minArea = min(box1.width * box1.height, box2.width * box2.height)
        
        return intersectionArea / minArea
    }
    
    private func getRelativePosition(_ box1: CGRect, _ box2: CGRect) -> CGPoint {
        return CGPoint(
            x: box1.midX - box2.midX,
            y: box1.midY - box2.midY
        )
    }
    
    private func isContained(_ box1: CGRect, in box2: CGRect) -> Bool {
        return box2.contains(box1)
    }
    
    private func isAbove(_ box1: CGRect, _ box2: CGRect) -> Bool {
        return box1.maxY < box2.minY
    }
    
    private func isBelow(_ box1: CGRect, _ box2: CGRect) -> Bool {
        return box1.minY > box2.maxY
    }
    
    private func calculateRelationConfidence(_ obj1: MemoryTrackedObject, 
                                           _ obj2: MemoryTrackedObject, 
                                           type: SpatialRelationType) -> Float {
        // Base confidence on object detection confidence
        var confidence = (obj1.confidence + obj2.confidence) / 2
        
        // Boost confidence for stable relationships
        if let previousRelation = spatialRelationships[RelationshipKey(id1: obj1.id, id2: obj2.id)],
           previousRelation.type == type {
            confidence *= 1.2
        }
        
        return min(1.0, confidence)
    }
}

// MARK: - Supporting Types
struct AnalyzedScene {
    let timestamp: Date
    let sceneType: SceneType
    let objects: [MemoryTrackedObject]
    let relationships: [SpatialRelation]
    let activities: [DetectedActivity]
    let graph: SceneGraphData
}

enum SceneType {
    case unknown
    case indoor
    case outdoor
    case street
    case office
    case park
    case dining
}

struct SpatialRelation {
    let object1: MemoryTrackedObject
    let object2: MemoryTrackedObject
    let type: SpatialRelationType
    let distance: Float
    let confidence: Float
}

enum SpatialRelationType {
    case near
    case overlapping
    case inside
    case above
    case below
    case leftOf
    case rightOf
    case distant
}

struct DetectedActivity {
    let type: DetectedActivityType
    let participants: [MemoryTrackedObject]
    let confidence: Float
}

enum DetectedActivityType {
    case working
    case phoneUse
    case drinking
    case reading
    case walking
    case cycling
    case moving
    case interacting
}

struct SceneGraphData {
    let nodes: [SceneNodeData]
    let edges: [SceneEdgeData]
}

struct SceneNodeData {
    let id: UUID
    let label: String
    let attributes: [String: Float]
}

struct SceneEdgeData {
    let from: UUID
    let to: UUID
    let type: SpatialRelationType
    let weight: Float
}

struct RelationshipKey: Hashable {
    let id1: UUID
    let id2: UUID
    
    init(id1: UUID, id2: UUID) {
        // Order doesn't matter for relationships
        if id1.uuidString < id2.uuidString {
            self.id1 = id1
            self.id2 = id2
        } else {
            self.id1 = id2
            self.id2 = id1
        }
    }
}

struct TemporalPattern {
    let objects: [String]
    let frequency: Int
    let averageDuration: TimeInterval
}