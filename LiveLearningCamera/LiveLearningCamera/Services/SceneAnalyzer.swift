import Foundation
import CoreML
import Vision
import Accelerate

class SceneAnalyzer {
    
    private let objectTracker: ObjectTracker
    private var sceneGraph: SceneGraph
    private let spatialIndex: SpatialIndex
    private var frameCount: Int = 0
    
    init() throws {
        self.objectTracker = try ObjectTracker()
        self.sceneGraph = SceneGraph()
        self.spatialIndex = SpatialIndex(gridSize: 10)
    }
    
    func analyzeFrame(_ detections: [Detection], image: CGImage) async throws -> SceneAnalysis {
        frameCount += 1
        
        var trackedObjects: [TrackedObject] = []
        for detection in detections {
            let tracked = try await objectTracker.processDetection(detection, image: image)
            trackedObjects.append(tracked)
            spatialIndex.insert(object: tracked)
        }
        
        objectTracker.pruneStaleObjects()
        
        let relationships = detectRelationships(among: trackedObjects)
        sceneGraph.update(objects: trackedObjects, relationships: relationships)
        
        let clusters = spatialIndex.findClusters(epsilon: 0.15)
        let activities = inferActivities(from: trackedObjects, relationships: relationships)
        
        return SceneAnalysis(
            frameNumber: frameCount,
            timestamp: Date(),
            objects: trackedObjects,
            relationships: relationships,
            clusters: clusters,
            activities: activities,
            sceneGraph: sceneGraph
        )
    }
    
    private func detectRelationships(among objects: [TrackedObject]) -> [SceneObjectRelationship] {
        var relationships: [SceneObjectRelationship] = []
        
        for i in 0..<objects.count {
            for j in (i+1)..<objects.count {
                let obj1 = objects[i]
                let obj2 = objects[j]
                
                guard let pos1 = obj1.lastPosition,
                      let pos2 = obj2.lastPosition else { continue }
                
                let distance = calculateDistance(pos1, pos2)
                let overlap = calculateIoU(pos1, pos2)
                
                if overlap > 0.1 {
                    relationships.append(SceneObjectRelationship(
                        from: obj1.id,
                        to: obj2.id,
                        type: .overlapping,
                        strength: overlap
                    ))
                } else if distance < 0.2 {
                    relationships.append(SceneObjectRelationship(
                        from: obj1.id,
                        to: obj2.id,
                        type: .nearby,
                        strength: Float(1.0 - distance / 0.2)
                    ))
                }
                
                if obj1.classLabel == "person" && obj2.classLabel == "phone" && distance < 0.3 {
                    relationships.append(SceneObjectRelationship(
                        from: obj1.id,
                        to: obj2.id,
                        type: .interacting,
                        strength: 0.9
                    ))
                }
                
                if abs(obj1.currentVelocity - obj2.currentVelocity) < 0.05 &&
                   abs(obj1.movementDirection - obj2.movementDirection) < 0.3 {
                    relationships.append(SceneObjectRelationship(
                        from: obj1.id,
                        to: obj2.id,
                        type: .movingTogether,
                        strength: 0.8
                    ))
                }
            }
        }
        
        return relationships
    }
    
    private func inferActivities(from objects: [TrackedObject], relationships: [SceneObjectRelationship]) -> [Activity] {
        var activities: [Activity] = []
        
        let personObjects = objects.filter { $0.classLabel == "person" }
        
        for person in personObjects {
            let relatedObjects = relationships
                .filter { $0.from == person.id || $0.to == person.id }
                .compactMap { rel in
                    objects.first { $0.id == (rel.from == person.id ? rel.to : rel.from) }
                }
            
            if relatedObjects.contains(where: { $0.classLabel == "phone" }) {
                activities.append(Activity(type: .usingPhone, confidence: 0.9, involvedObjects: [person.id]))
            }
            
            if relatedObjects.contains(where: { $0.classLabel == "laptop" || $0.classLabel == "keyboard" }) {
                activities.append(Activity(type: .working, confidence: 0.85, involvedObjects: [person.id]))
            }
            
            if relatedObjects.contains(where: { ["cup", "bottle", "wine glass"].contains($0.classLabel) }) {
                activities.append(Activity(type: .drinking, confidence: 0.8, involvedObjects: [person.id]))
            }
        }
        
        let movingObjects = objects.filter { !$0.isStationary }
        if movingObjects.count >= 2 {
            let movingIDs = movingObjects.map { $0.id }
            activities.append(Activity(type: .movement, confidence: 0.7, involvedObjects: movingIDs))
        }
        
        return activities
    }
    
    private func calculateDistance(_ box1: CGRect, _ box2: CGRect) -> CGFloat {
        let center1 = CGPoint(x: box1.midX, y: box1.midY)
        let center2 = CGPoint(x: box2.midX, y: box2.midY)
        
        return sqrt(pow(center1.x - center2.x, 2) + pow(center1.y - center2.y, 2))
    }
    
    private func calculateIoU(_ box1: CGRect, _ box2: CGRect) -> Float {
        let intersection = box1.intersection(box2)
        guard !intersection.isNull else { return 0 }
        
        let intersectionArea = intersection.width * intersection.height
        let unionArea = box1.width * box1.height + box2.width * box2.height - intersectionArea
        
        return Float(intersectionArea / unionArea)
    }
}

class SceneGraph {
    private var nodes: [UUID: SceneNode] = [:]
    private var edges: [SceneEdge] = []
    
    func update(objects: [TrackedObject], relationships: [SceneObjectRelationship]) {
        for object in objects {
            if let existingNode = nodes[object.id] {
                existingNode.update(from: object)
            } else {
                nodes[object.id] = SceneNode(from: object)
            }
        }
        
        edges = relationships.map { rel in
            SceneEdge(
                from: rel.from,
                to: rel.to,
                type: rel.type,
                weight: rel.strength
            )
        }
        
        let staleThreshold = Date().addingTimeInterval(-10)
        nodes = nodes.filter { $0.value.lastUpdated > staleThreshold }
    }
    
    func getNeighbors(of nodeID: UUID) -> [SceneNode] {
        let connectedEdges = edges.filter { $0.from == nodeID || $0.to == nodeID }
        let neighborIDs = connectedEdges.map { $0.from == nodeID ? $0.to : $0.from }
        return neighborIDs.compactMap { nodes[$0] }
    }
    
    func getSubgraph(around nodeID: UUID, depth: Int) -> (nodes: [SceneNode], edges: [SceneEdge]) {
        var visitedNodes = Set<UUID>()
        var resultNodes: [SceneNode] = []
        var resultEdges: [SceneEdge] = []
        
        var queue: [(UUID, Int)] = [(nodeID, 0)]
        
        while !queue.isEmpty {
            let (currentID, currentDepth) = queue.removeFirst()
            
            guard currentDepth <= depth,
                  !visitedNodes.contains(currentID),
                  let node = nodes[currentID] else { continue }
            
            visitedNodes.insert(currentID)
            resultNodes.append(node)
            
            let connectedEdges = edges.filter { $0.from == currentID || $0.to == currentID }
            resultEdges.append(contentsOf: connectedEdges)
            
            if currentDepth < depth {
                for edge in connectedEdges {
                    let neighborID = edge.from == currentID ? edge.to : edge.from
                    queue.append((neighborID, currentDepth + 1))
                }
            }
        }
        
        return (resultNodes, resultEdges)
    }
}

class SceneNode {
    let id: UUID
    let objectClass: String
    var position: CGPoint
    var velocity: CGVector
    var lastUpdated: Date
    var attributes: [String: Any] = [:]
    
    init(from object: TrackedObject) {
        self.id = object.id
        self.objectClass = object.classLabel
        self.position = object.lastPosition.map { CGPoint(x: $0.midX, y: $0.midY) } ?? .zero
        self.velocity = CGVector(
            dx: object.currentVelocity * cos(object.movementDirection),
            dy: object.currentVelocity * sin(object.movementDirection)
        )
        self.lastUpdated = Date()
    }
    
    func update(from object: TrackedObject) {
        if let pos = object.lastPosition {
            position = CGPoint(x: pos.midX, y: pos.midY)
        }
        velocity = CGVector(
            dx: object.currentVelocity * cos(object.movementDirection),
            dy: object.currentVelocity * sin(object.movementDirection)
        )
        lastUpdated = Date()
    }
}

struct SceneEdge {
    let from: UUID
    let to: UUID
    let type: RelationshipType
    let weight: Float
}

class SpatialIndex {
    private var grid: [[Set<UUID>]]
    private var objectPositions: [UUID: (Int, Int)] = [:]
    private let gridSize: Int
    
    init(gridSize: Int) {
        self.gridSize = gridSize
        self.grid = Array(repeating: Array(repeating: Set<UUID>(), count: gridSize), count: gridSize)
    }
    
    func insert(object: TrackedObject) {
        guard let position = object.lastPosition else { return }
        
        let gridX = min(Int(position.midX * CGFloat(gridSize)), gridSize - 1)
        let gridY = min(Int(position.midY * CGFloat(gridSize)), gridSize - 1)
        
        if let oldPosition = objectPositions[object.id] {
            grid[oldPosition.0][oldPosition.1].remove(object.id)
        }
        
        grid[gridX][gridY].insert(object.id)
        objectPositions[object.id] = (gridX, gridY)
    }
    
    func findClusters(epsilon: CGFloat) -> [ObjectCluster] {
        var clusters: [ObjectCluster] = []
        var visited = Set<UUID>()
        
        for (objectID, position) in objectPositions {
            guard !visited.contains(objectID) else { continue }
            
            var cluster = Set<UUID>()
            var queue = [objectID]
            
            while !queue.isEmpty {
                let currentID = queue.removeFirst()
                guard !visited.contains(currentID) else { continue }
                
                visited.insert(currentID)
                cluster.insert(currentID)
                
                if let currentPos = objectPositions[currentID] {
                    let neighbors = getNeighbors(at: currentPos, radius: epsilon)
                    queue.append(contentsOf: neighbors.filter { !visited.contains($0) })
                }
            }
            
            if cluster.count > 1 {
                clusters.append(ObjectCluster(objectIDs: Array(cluster)))
            }
        }
        
        return clusters
    }
    
    private func getNeighbors(at position: (Int, Int), radius: CGFloat) -> [UUID] {
        let gridRadius = Int(ceil(radius * CGFloat(gridSize)))
        var neighbors: [UUID] = []
        
        for dx in -gridRadius...gridRadius {
            for dy in -gridRadius...gridRadius {
                let x = position.0 + dx
                let y = position.1 + dy
                
                guard x >= 0, x < gridSize, y >= 0, y < gridSize else { continue }
                
                neighbors.append(contentsOf: grid[x][y])
            }
        }
        
        return neighbors
    }
}

struct SceneAnalysis {
    let frameNumber: Int
    let timestamp: Date
    let objects: [TrackedObject]
    let relationships: [SceneObjectRelationship]
    let clusters: [ObjectCluster]
    let activities: [Activity]
    let sceneGraph: SceneGraph
}

struct SceneObjectRelationship {
    let from: UUID
    let to: UUID
    let type: RelationshipType
    let strength: Float
}

enum RelationshipType {
    case nearby
    case overlapping
    case interacting
    case movingTogether
    case supporting
    case containing
}

struct ObjectCluster {
    let objectIDs: [UUID]
}

struct Activity {
    let type: ActivityType
    let confidence: Float
    let involvedObjects: [UUID]
}

enum ActivityType {
    case usingPhone
    case working
    case drinking
    case eating
    case walking
    case sitting
    case movement
    case conversation
}