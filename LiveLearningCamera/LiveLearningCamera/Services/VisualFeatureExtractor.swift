import Vision
import CoreML
import UIKit
import Accelerate

class VisualFeatureExtractor {
    
    private let featureExtractor: VNCoreMLModel
    private var previousFrameFeatures: [UUID: FeatureVector] = [:]
    private let frameBuffer = FrameBuffer(capacity: 10)
    
    init() throws {
        guard let modelURL = Bundle.main.url(forResource: "MobileViT", withExtension: "mlmodelc") else {
            throw FeatureExtractionError.modelNotFound
        }
        let model = try MLModel(contentsOf: modelURL)
        self.featureExtractor = try VNCoreMLModel(for: model)
    }
    
    func extractFeatures(from image: CGImage, boundingBox: CGRect) async throws -> FeatureVector {
        guard let croppedImage = cropAndNormalize(image, to: boundingBox) else {
            throw FeatureExtractionError.preprocessingFailed
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNCoreMLRequest(model: featureExtractor) { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let results = request.results as? [VNCoreMLFeatureValueObservation],
                      let firstResult = results.first,
                      let multiArray = firstResult.featureValue.multiArrayValue else {
                    continuation.resume(throwing: FeatureExtractionError.extractionFailed)
                    return
                }
                
                let features = self.multiArrayToVector(multiArray)
                continuation.resume(returning: features)
            }
            
            request.imageCropAndScaleOption = .centerCrop
            
            let handler = VNImageRequestHandler(cgImage: croppedImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    func calculateSimilarity(_ features1: FeatureVector, _ features2: FeatureVector) -> Float {
        var dotProduct: Float = 0
        var magnitude1: Float = 0
        var magnitude2: Float = 0
        
        vDSP_dotpr(features1.values, 1, features2.values, 1, &dotProduct, vDSP_Length(features1.dimensions))
        vDSP_svesq(features1.values, 1, &magnitude1, vDSP_Length(features1.dimensions))
        vDSP_svesq(features2.values, 1, &magnitude2, vDSP_Length(features2.dimensions))
        
        let denominator = sqrt(magnitude1) * sqrt(magnitude2)
        guard denominator > 0 else { return 0 }
        
        return dotProduct / denominator
    }
    
    func detectMovement(objectID: UUID, currentBox: CGRect, currentFeatures: FeatureVector) -> MovementVector? {
        guard let previousFeatures = previousFrameFeatures[objectID] else {
            previousFrameFeatures[objectID] = currentFeatures
            return nil
        }
        
        guard let previousFrame = frameBuffer.getFrame(for: objectID),
              let previousBox = previousFrame.boundingBox else {
            return nil
        }
        
        let deltaX = currentBox.midX - previousBox.midX
        let deltaY = currentBox.midY - previousBox.midY
        let deltaSize = (currentBox.width * currentBox.height) - (previousBox.width * previousBox.height)
        
        let velocity = sqrt(deltaX * deltaX + deltaY * deltaY)
        let direction = atan2(deltaY, deltaX)
        
        let featureDrift = 1.0 - calculateSimilarity(currentFeatures, previousFeatures)
        
        previousFrameFeatures[objectID] = currentFeatures
        frameBuffer.addFrame(objectID: objectID, box: currentBox, features: currentFeatures)
        
        return MovementVector(
            velocity: velocity,
            direction: direction,
            deltaSize: deltaSize,
            featureDrift: featureDrift,
            isStationary: velocity < 0.01
        )
    }
    
    private func cropAndNormalize(_ image: CGImage, to boundingBox: CGRect) -> CGImage? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        
        let x = boundingBox.origin.x * width
        let y = (1 - boundingBox.origin.y - boundingBox.height) * height
        let cropWidth = boundingBox.width * width
        let cropHeight = boundingBox.height * height
        
        let cropRect = CGRect(x: x, y: y, width: cropWidth, height: cropHeight)
        
        guard let cropped = image.cropping(to: cropRect) else { return nil }
        
        let targetSize = CGSize(width: 256, height: 256)
        
        guard let context = CGContext(
            data: nil,
            width: Int(targetSize.width),
            height: Int(targetSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        
        context.interpolationQuality = .high
        context.draw(cropped, in: CGRect(origin: .zero, size: targetSize))
        
        return context.makeImage()
    }
    
    private func multiArrayToVector(_ multiArray: MLMultiArray) -> FeatureVector {
        let dimensions = multiArray.count
        var values = [Float](repeating: 0, count: dimensions)
        
        for i in 0..<dimensions {
            values[i] = multiArray[i].floatValue
        }
        
        var normalized = [Float](repeating: 0, count: dimensions)
        var magnitude: Float = 0
        vDSP_svesq(values, 1, &magnitude, vDSP_Length(dimensions))
        let norm = sqrt(magnitude)
        
        if norm > 0 {
            var divisor = norm
            vDSP_vsdiv(values, 1, &divisor, &normalized, 1, vDSP_Length(dimensions))
        } else {
            normalized = values
        }
        
        return FeatureVector(values: normalized, dimensions: dimensions)
    }
}

struct FeatureVector {
    let values: [Float]
    let dimensions: Int
    
    func distance(to other: FeatureVector) -> Float {
        guard dimensions == other.dimensions else { return Float.infinity }
        
        var result: Float = 0
        vDSP_distancesq(values, 1, other.values, 1, &result, vDSP_Length(dimensions))
        return sqrt(result)
    }
}

struct MovementVector {
    let velocity: CGFloat
    let direction: CGFloat
    let deltaSize: CGFloat
    let featureDrift: Float
    let isStationary: Bool
}

class FrameBuffer {
    private struct Frame {
        let timestamp: Date
        let boundingBox: CGRect?
        let features: FeatureVector?
    }
    
    private var buffer: [UUID: [Frame]] = [:]
    private let capacity: Int
    
    init(capacity: Int) {
        self.capacity = capacity
    }
    
    func addFrame(objectID: UUID, box: CGRect, features: FeatureVector) {
        var frames = buffer[objectID] ?? []
        frames.append(Frame(timestamp: Date(), boundingBox: box, features: features))
        
        if frames.count > capacity {
            frames.removeFirst()
        }
        
        buffer[objectID] = frames
    }
    
    func getFrame(for objectID: UUID, offset: Int = 1) -> (boundingBox: CGRect?, features: FeatureVector?)? {
        guard let frames = buffer[objectID],
              frames.count > offset else { return nil }
        
        let frame = frames[frames.count - 1 - offset]
        return (frame.boundingBox, frame.features)
    }
    
    func getTrajectory(for objectID: UUID) -> [CGPoint] {
        guard let frames = buffer[objectID] else { return [] }
        
        return frames.compactMap { frame in
            guard let box = frame.boundingBox else { return nil }
            return CGPoint(x: box.midX, y: box.midY)
        }
    }
}

enum FeatureExtractionError: Error {
    case modelNotFound
    case preprocessingFailed
    case extractionFailed
}