import Foundation
import CoreData
import Vision
import CoreML

class ObjectTracker {
    
    private let featureExtractor: VisualFeatureExtractor
    private let persistenceManager: PersistenceManager
    private var trackedObjects: [UUID: TrackedObject] = [:]
    private let kalmanFilters: [UUID: KalmanFilter] = [:]
    
    init() throws {
        self.featureExtractor = try VisualFeatureExtractor()
        self.persistenceManager = PersistenceManager()
    }
    
    func processDetection(_ detection: Detection, image: CGImage) async throws -> TrackedObject {
        let features = try await featureExtractor.extractFeatures(from: image, boundingBox: detection.boundingBox)
        
        if let existingObject = findExistingObject(matching: features, in: detection.boundingBox) {
            updateObject(existingObject, with: detection, features: features)
            return existingObject
        } else {
            return createNewObject(from: detection, features: features)
        }
    }
    
    private func findExistingObject(matching features: FeatureVector, in boundingBox: CGRect) -> TrackedObject? {
        let searchRadius: CGFloat = 0.2
        
        let candidates = trackedObjects.values.filter { object in
            guard let lastPosition = object.lastPosition else { return false }
            
            let distance = sqrt(
                pow(lastPosition.midX - boundingBox.midX, 2) +
                pow(lastPosition.midY - boundingBox.midY, 2)
            )
            
            return distance < searchRadius
        }
        
        var bestMatch: (object: TrackedObject, similarity: Float)?
        
        for candidate in candidates {
            guard let candidateFeatures = candidate.visualFeatures else { continue }
            
            let similarity = featureExtractor.calculateSimilarity(features, candidateFeatures)
            
            if similarity > 0.85 {
                if bestMatch == nil || similarity > bestMatch!.similarity {
                    bestMatch = (candidate, similarity)
                }
            }
        }
        
        return bestMatch?.object
    }
    
    private func updateObject(_ object: TrackedObject, with detection: Detection, features: FeatureVector) {
        object.observationCount += 1
        object.lastSeen = Date()
        object.lastPosition = detection.boundingBox
        object.lastConfidence = detection.confidence
        
        if let movement = featureExtractor.detectMovement(
            objectID: object.id,
            currentBox: detection.boundingBox,
            currentFeatures: features
        ) {
            object.currentVelocity = movement.velocity
            object.movementDirection = movement.direction
            object.isStationary = movement.isStationary
        }
        
        object.updateConfidenceAverage(detection.confidence)
        object.visualFeatures = features
        
        persistenceManager.updateObject(object)
    }
    
    private func createNewObject(from detection: Detection, features: FeatureVector) -> TrackedObject {
        let object = TrackedObject(
            id: UUID(),
            classLabel: detection.label,
            classIndex: detection.classIndex,
            firstSeen: Date(),
            lastSeen: Date(),
            visualFeatures: features
        )
        
        object.lastPosition = detection.boundingBox
        object.lastConfidence = detection.confidence
        
        trackedObjects[object.id] = object
        persistenceManager.saveNewObject(object)
        
        return object
    }
    
    func pruneStaleObjects() {
        let staleThreshold = Date().addingTimeInterval(-5.0)
        
        trackedObjects = trackedObjects.filter { _, object in
            object.lastSeen > staleThreshold
        }
    }
}

class TrackedObject {
    let id: UUID
    let classLabel: String
    let classIndex: Int
    let firstSeen: Date
    var lastSeen: Date
    
    var visualFeatures: FeatureVector?
    var lastPosition: CGRect?
    var lastConfidence: Float = 0
    
    var observationCount: Int = 1
    var averageConfidence: Float = 0
    
    var currentVelocity: CGFloat = 0
    var movementDirection: CGFloat = 0
    var isStationary: Bool = true
    
    var persistentObjectID: NSManagedObjectID?
    
    init(id: UUID, classLabel: String, classIndex: Int, firstSeen: Date, lastSeen: Date, visualFeatures: FeatureVector?) {
        self.id = id
        self.classLabel = classLabel
        self.classIndex = classIndex
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.visualFeatures = visualFeatures
    }
    
    func updateConfidenceAverage(_ newConfidence: Float) {
        let weight = 1.0 / Float(observationCount)
        averageConfidence = averageConfidence * (1 - weight) + newConfidence * weight
    }
}

class PersistenceManager {
    private let context: NSManagedObjectContext
    
    init() {
        self.context = CoreDataManager.shared.context
    }
    
    func saveNewObject(_ trackedObject: TrackedObject) {
        let entity = RecognizedObject(context: context)
        entity.id = trackedObject.id
        entity.firstSeen = trackedObject.firstSeen
        entity.lastSeen = trackedObject.lastSeen
        entity.primaryLabel = trackedObject.classLabel
        entity.seenCount = Int32(trackedObject.observationCount)
        entity.averageConfidence = trackedObject.averageConfidence
        
        if let features = trackedObject.visualFeatures {
            entity.visualSignature = Data(bytes: features.values, count: features.dimensions * MemoryLayout<Float>.size)
        }
        
        do {
            try context.save()
            trackedObject.persistentObjectID = entity.objectID
        } catch {
            print("Failed to save tracked object: \(error)")
        }
    }
    
    func updateObject(_ trackedObject: TrackedObject) {
        guard let objectID = trackedObject.persistentObjectID,
              let entity = try? context.existingObject(with: objectID) as? RecognizedObject else {
            return
        }
        
        entity.lastSeen = trackedObject.lastSeen
        entity.seenCount = Int32(trackedObject.observationCount)
        entity.averageConfidence = trackedObject.averageConfidence
        
        if let features = trackedObject.visualFeatures {
            entity.visualSignature = Data(bytes: features.values, count: features.dimensions * MemoryLayout<Float>.size)
        }
        
        do {
            try context.save()
        } catch {
            print("Failed to update tracked object: \(error)")
        }
    }
}

class KalmanFilter {
    private var x: simd_float4
    private var P: simd_float4x4
    private let Q: simd_float4x4
    private let R: simd_float2x2
    
    init() {
        x = simd_float4(0, 0, 0, 0)
        P = matrix_identity_float4x4
        Q = matrix_identity_float4x4 * 0.01
        R = matrix_identity_float2x2 * 0.1
    }
    
    func predict() {
        let F = simd_float4x4(
            simd_float4(1, 0, 1, 0),
            simd_float4(0, 1, 0, 1),
            simd_float4(0, 0, 1, 0),
            simd_float4(0, 0, 0, 1)
        )
        
        x = F * x
        P = F * P * F.transpose + Q
    }
    
    func update(measurement: simd_float2) {
        // Observation matrix H maps state to measurement space
        // H is 2x4: transforms 4D state to 2D measurement
        let H = simd_float2x4(
            simd_float4(1, 0, 0, 0),
            simd_float4(0, 1, 0, 0)
        )
        
        // Predicted measurement: use matrix_multiply for correct order
        let Hx = matrix_multiply(x, H)  // 4x1 * 2x4 (transposed) = 2x1
        
        // Innovation/residual
        let y = measurement - Hx
        
        // Innovation covariance: S = H * P * H^T + R
        let HP = matrix_multiply(P, H)  // 4x4 * 2x4 (transposed) = 2x4
        let HPHt = matrix_multiply(H.transpose, HP)  // 4x2 * 2x4 (transposed) = 2x2
        let S = HPHt + R
        
        // Kalman gain: K = P * H^T * S^-1
        let PHt = matrix_multiply(H.transpose, P)  // 4x2 * 4x4 (transposed) = 4x2
        let K = matrix_multiply(S.inverse, PHt)  // 2x2 * 4x2 (transposed) = 4x2
        
        // State update
        let Ky = matrix_multiply(y, K)  // 2x1 * 4x2 (transposed) = 4x1
        x = x + Ky
        
        // Covariance update: P = (I - K * H) * P
        let KH = matrix_multiply(H, K)  // 2x4 * 4x2 (transposed) = 4x4
        let I = matrix_identity_float4x4
        P = matrix_multiply(P, I - KH)
    }
    
    func getPosition() -> simd_float2 {
        return simd_float2(x[0], x[1])
    }
    
    func getVelocity() -> simd_float2 {
        return simd_float2(x[2], x[3])
    }
}