//
//  DetectorProtocol.swift
//  LiveLearningCamera
//
//  Abstract detector interface for benchmarking different models
//

import Foundation
import Vision
import CoreML
import CoreImage

// MARK: - Detector Protocol
protocol ObjectDetector {
    var modelName: String { get }
    var isModelLoaded: Bool { get }
    var supportsBatchProcessing: Bool { get }
    var inputSize: CGSize { get }
    
    func loadModel() async throws
    func detect(in image: CIImage) async throws -> [Detection]
    func detectBatch(_ images: [CIImage]) async throws -> [[Detection]]
    func unloadModel()
}

// MARK: - Benchmark Metrics
struct BenchmarkMetrics {
    let modelName: String
    let avgInferenceTime: TimeInterval
    let avgPostProcessingTime: TimeInterval
    let totalTime: TimeInterval
    let fps: Double
    let memoryUsage: Float // MB
    let accuracy: Float // mAP
    let detectionCount: Int
}

// MARK: - Abstract Base Detector
class BaseDetector: ObjectDetector {
    var modelName: String { "Base" }
    var isModelLoaded: Bool = false
    var supportsBatchProcessing: Bool { false }
    var inputSize: CGSize { CGSize(width: 640, height: 640) }
    
    var model: VNCoreMLModel?
    let ciContext = CIContext(options: [
        .priorityRequestLow: false,
        .useSoftwareRenderer: false
    ])
    
    func loadModel() async throws {
        fatalError("Subclass must implement")
    }
    
    func detect(in image: CIImage) async throws -> [Detection] {
        fatalError("Subclass must implement")
    }
    
    func detectBatch(_ images: [CIImage]) async throws -> [[Detection]] {
        // Default: process sequentially
        var results = [[Detection]]()
        for image in images {
            let detections = try await detect(in: image)
            results.append(detections)
        }
        return results
    }
    
    func unloadModel() {
        model = nil
        isModelLoaded = false
    }
    
    // Common preprocessing
    func preprocessImage(_ image: CIImage) -> CVPixelBuffer? {
        let targetSize = inputSize
        
        // Resize to model input size
        let scaleX = targetSize.width / image.extent.width
        let scaleY = targetSize.height / image.extent.height
        let scaledImage = image.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        
        // Convert to pixel buffer
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary
        
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(targetSize.width),
            Int(targetSize.height),
            kCVPixelFormatType_32BGRA,
            attrs,
            &pixelBuffer
        )
        
        if let buffer = pixelBuffer {
            ciContext.render(scaledImage, to: buffer)
        }
        
        return pixelBuffer
    }
}

// MARK: - YOLO Detector Implementation
class YOLODetector: BaseDetector {
    override var modelName: String { "YOLOv11n" }
    override var inputSize: CGSize { CGSize(width: 640, height: 640) }
    
    private let confidenceThreshold: Float
    private let iouThreshold: Float
    
    init(confidenceThreshold: Float = 0.25, iouThreshold: Float = 0.45) {
        self.confidenceThreshold = confidenceThreshold
        self.iouThreshold = iouThreshold
    }
    
    override func loadModel() async throws {
        guard let modelURL = Bundle.main.url(forResource: "yolo11n", withExtension: "mlmodelc") else {
            throw DetectorError.modelNotFound("yolo11n.mlmodelc")
        }
        
        let mlModel = try MLModel(contentsOf: modelURL)
        self.model = try VNCoreMLModel(for: mlModel)
        self.isModelLoaded = true
    }
    
    override func detect(in image: CIImage) async throws -> [Detection] {
        guard let model = model else {
            throw DetectorError.modelNotLoaded
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNCoreMLRequest(model: model) { [weak self] request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                let detections = self?.processYOLOResults(request.results) ?? []
                continuation.resume(returning: detections)
            }
            
            request.imageCropAndScaleOption = .scaleFill
            
            let handler = VNImageRequestHandler(ciImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    private func processYOLOResults(_ results: [Any]?) -> [Detection] {
        // YOLO-specific post-processing
        // (Implementation from existing YOLODetectionService)
        return []
    }
}

// MARK: - SAM2 Detector Implementation
class SAM2Detector: BaseDetector {
    override var modelName: String { "SAM2-Mobile" }
    override var inputSize: CGSize { CGSize(width: 1024, height: 1024) }
    override var supportsBatchProcessing: Bool { true }
    
    private var encoder: VNCoreMLModel?
    private var decoder: VNCoreMLModel?
    
    override func loadModel() async throws {
        // Load SAM2 encoder and decoder
        guard let encoderURL = Bundle.main.url(forResource: "sam2_encoder", withExtension: "mlmodelc"),
              let decoderURL = Bundle.main.url(forResource: "sam2_decoder", withExtension: "mlmodelc") else {
            throw DetectorError.modelNotFound("sam2_encoder/decoder")
        }
        
        let encoderModel = try MLModel(contentsOf: encoderURL)
        let decoderModel = try MLModel(contentsOf: decoderURL)
        
        self.encoder = try VNCoreMLModel(for: encoderModel)
        self.decoder = try VNCoreMLModel(for: decoderModel)
        self.isModelLoaded = true
    }
    
    override func detect(in image: CIImage) async throws -> [Detection] {
        guard let encoder = encoder, let decoder = decoder else {
            throw DetectorError.modelNotLoaded
        }
        
        // SAM2 detection pipeline:
        // 1. Encode image features
        let features = try await encodeImage(image, with: encoder)
        
        // 2. Generate point prompts or box prompts
        let prompts = generateAutomaticPrompts(for: image)
        
        // 3. Decode masks for each prompt
        let masks = try await decodeMasks(features, prompts: prompts, with: decoder)
        
        // 4. Convert masks to detections
        return convertMasksToDetections(masks)
    }
    
    private func encodeImage(_ image: CIImage, with encoder: VNCoreMLModel) async throws -> MLMultiArray {
        // SAM2 image encoding
        fatalError("Implement SAM2 encoding")
    }
    
    private func generateAutomaticPrompts(for image: CIImage) -> [SAMPrompt] {
        // Generate grid of points or use edge detection for automatic prompts
        return []
    }
    
    private func decodeMasks(_ features: MLMultiArray, prompts: [SAMPrompt], with decoder: VNCoreMLModel) async throws -> [Mask] {
        // SAM2 mask decoding
        return []
    }
    
    private func convertMasksToDetections(_ masks: [Mask]) -> [Detection] {
        // Convert segmentation masks to bounding boxes
        return masks.map { mask in
            Detection(
                label: "object", // SAM2 is class-agnostic
                confidence: mask.confidence,
                boundingBox: mask.boundingBox,
                classIndex: 0
            )
        }
    }
}

// MARK: - Benchmark Runner
class DetectorBenchmark {
    private var detectors: [ObjectDetector] = []
    private let testImages: [CIImage]
    private let groundTruth: [[Detection]]?
    
    init(testImages: [CIImage], groundTruth: [[Detection]]? = nil) {
        self.testImages = testImages
        self.groundTruth = groundTruth
    }
    
    func addDetector(_ detector: ObjectDetector) {
        detectors.append(detector)
    }
    
    func runBenchmark() async -> [BenchmarkMetrics] {
        var results = [BenchmarkMetrics]()
        
        for detector in detectors {
            print("🏃 Benchmarking \(detector.modelName)...")
            
            // Load model
            let loadStart = Date()
            try? await detector.loadModel()
            let loadTime = Date().timeIntervalSince(loadStart)
            print("  📦 Model load time: \(String(format: "%.2f", loadTime))s")
            
            // Warmup
            if let firstImage = testImages.first {
                _ = try? await detector.detect(in: firstImage)
            }
            
            // Benchmark inference
            var inferenceTimes = [TimeInterval]()
            var allDetections = [[Detection]]()
            let memoryBefore = reportMemory()
            
            for image in testImages {
                let start = Date()
                let detections = (try? await detector.detect(in: image)) ?? []
                let elapsed = Date().timeIntervalSince(start)
                
                inferenceTimes.append(elapsed)
                allDetections.append(detections)
            }
            
            let memoryAfter = reportMemory()
            let memoryUsed = memoryAfter - memoryBefore
            
            // Calculate metrics
            let avgInference = inferenceTimes.reduce(0, +) / Double(inferenceTimes.count)
            let fps = 1.0 / avgInference
            let totalDetections = allDetections.flatMap { $0 }.count
            
            // Calculate accuracy if ground truth provided
            let accuracy: Float = 0.0 // TODO: Implement mAP calculation
            
            let metrics = BenchmarkMetrics(
                modelName: detector.modelName,
                avgInferenceTime: avgInference,
                avgPostProcessingTime: 0, // TODO: Separate measurement
                totalTime: avgInference,
                fps: fps,
                memoryUsage: Float(memoryUsed),
                accuracy: accuracy,
                detectionCount: totalDetections
            )
            
            results.append(metrics)
            
            // Cleanup
            detector.unloadModel()
            
            print("  ⚡️ Avg inference: \(String(format: "%.2f", avgInference * 1000))ms")
            print("  🎯 FPS: \(String(format: "%.1f", fps))")
            print("  📊 Detections: \(totalDetections)")
            print("  💾 Memory: \(String(format: "%.1f", Float(memoryUsed)))MB\n")
        }
        
        return results
    }
    
    private func reportMemory() -> Float {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        return result == KERN_SUCCESS ? Float(info.resident_size) / 1024 / 1024 : 0
    }
}

// MARK: - Supporting Types
enum DetectorError: Error {
    case modelNotFound(String)
    case modelNotLoaded
    case preprocessingFailed
    case inferenceFailed(String)
}

struct SAMPrompt {
    enum PromptType {
        case point(CGPoint, isPositive: Bool)
        case box(CGRect)
        case mask(CVPixelBuffer)
    }
    let type: PromptType
}

struct Mask {
    let pixelBuffer: CVPixelBuffer
    let confidence: Float
    var boundingBox: CGRect {
        // Calculate bounding box from mask
        return .zero
    }
}

// MARK: - Usage Example
/*
 
 let benchmark = DetectorBenchmark(testImages: testImages)
 
 // Add detectors to compare
 benchmark.addDetector(YOLODetector())
 benchmark.addDetector(SAM2Detector())
 
 // Run benchmark
 let results = await benchmark.runBenchmark()
 
 // Compare results
 for metric in results {
     print("\(metric.modelName): \(metric.fps) FPS, \(metric.accuracy) mAP")
 }
 
*/