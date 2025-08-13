//
//  YOLODetectionService.swift
//  LiveLearningCamera
//
//  Service for object detection using YOLOv11n CoreML model
//

import Vision
import CoreML
import UIKit
import CoreImage
import SwiftUI

// MARK: - Detection Result
public struct Detection {
    public let label: String
    public let confidence: Float
    public let boundingBox: CGRect
    public let classIndex: Int
    public var id: Int? // Optional tracking ID
    // MobileViT fields disabled - see DualClassificationPipeline.swift for implementation
    // let mobileViTLabel: String?
    // let mobileViTConfidence: Float?
}

// MARK: - YOLO Detection Service
public class YOLODetectionService: ObservableObject {
    
    // Use proper COCO dataset
    private let cocoDataset = COCODataset.shared
    
    private var visionModel: VNCoreMLModel?
    // MobileViT disabled - see DualClassificationPipeline.swift for dual classification
    // private var mobileViTModel: VNCoreMLModel?
    var confidenceThreshold: Float
    private let iouThreshold: Float
    private static var hasLoggedShape = false
    private static var hasLoggedOutputs = false
    private static var hasLoggedAllClasses = false
    
    // Settings
    private let settings = DetectionSettingsManager.shared
    private let coreDataManager = CoreDataManager.shared
    
    @Published var isModelLoaded = false
    @Published var lastDetections: [Detection] = []
    @Published var processingTime: Double = 0
    @Published var isCaptureEnabled = false
    
    // Deduplication tracking
    private var recentCaptures: [(classIndex: Int, boundingBox: CGRect, timestamp: Date)] = []
    private let captureDeduplicationWindow: TimeInterval = 2.0 // seconds
    private let boundingBoxSimilarityThreshold: Float = 0.7 // IoU threshold for similarity
    private var lastCaptureTime: Date = Date.distantPast
    
    init(iouThreshold: Float = 0.4) {
        // Lower confidence threshold to catch more detections
        // The stabilizer will handle false positives
        self.confidenceThreshold = max(0.15, settings.confidenceThreshold * 0.5)
        self.iouThreshold = iouThreshold
        loadModel()
    }
    
    // MARK: - Model Loading
    private func loadModel() {
        do {
            // Load YOLO model
            if let modelURL = Bundle.main.url(forResource: "yolo11n", withExtension: "mlmodelc") {
                let model = try MLModel(contentsOf: modelURL)
                self.visionModel = try VNCoreMLModel(for: model)
                isModelLoaded = true
                print("✅ YOLOv11n model loaded successfully")
            } else {
                print("⚠️ YOLOv11n model not found. Please add yolo11n.mlpackage to the project")
            }
            
            // MobileViT loading disabled - see DualClassificationPipeline.swift for dual classification
        } catch {
            print("❌ Failed to load model: \(error)")
        }
    }
    
    // MARK: - Detection
    func detect(in image: CIImage, completion: @escaping ([Detection]) -> Void) {
        guard let model = visionModel else {
            print("Model not loaded")
            completion([])
            return
        }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let request = VNCoreMLRequest(model: model) { [weak self] request, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Detection error: \(error)")
                completion([])
                return
            }
            
            let detections = self.processResults(request.results)
            
            DispatchQueue.main.async {
                self.processingTime = CFAbsoluteTimeGetCurrent() - startTime
                self.lastDetections = detections
                
                // Capture detections to Core Data if enabled
                if self.isCaptureEnabled {
                    self.captureDetections(detections, from: image)
                }
                
                // Detections are now processed by OptimizedDetectionPipeline
                // No need for additional processing here
                
                completion(detections)
            }
        }
        
        // Configure for YOLO
        request.imageCropAndScaleOption = VNImageCropAndScaleOption.scaleFill
        
        // Perform detection
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            print("Failed to perform detection: \(error)")
            completion([])
        }
    }
    
    // MARK: - Process Results
    private func processResults(_ results: [Any]?) -> [Detection] {
        guard let results = results as? [VNRecognizedObjectObservation] else {
            // For YOLOv11, results might be VNCoreMLFeatureValueObservation
            return processYOLOv11Results(results)
        }
        
        // Process standard VNRecognizedObjectObservation
        return results.compactMap { observation in
            guard observation.confidence >= confidenceThreshold else { return nil }
            
            // VNRecognizedObjectObservation provides labels with identifiers
            // The identifier should contain the class index
            var classIndex = 0
            if let firstLabel = observation.labels.first {
                // Try to extract class index from identifier
                if let index = Int(firstLabel.identifier) {
                    classIndex = index
                } else {
                    // Fallback: Try to parse from label if it's in format "class_X"
                    let components = firstLabel.identifier.components(separatedBy: "_")
                    if components.count > 1, let index = Int(components.last ?? "") {
                        classIndex = index
                    }
                }
            }
            
            guard classIndex < 80 else { return nil } // COCO has 80 classes
            
            // Skip filtered classes
            guard settings.isClassEnabled(classIndex) else { return nil }
            
            // Always use COCO labels if available, since model is trained on COCO
            let label = !settings.showClassification ? "object" :
                cocoDataset.getClassName(byID: classIndex)
            
            return Detection(
                label: label,
                confidence: observation.confidence,
                boundingBox: observation.boundingBox,
                classIndex: classIndex
            )
        }
    }
    
    // MARK: - Process YOLOv11 Specific Results
    private func processYOLOv11Results(_ results: [Any]?) -> [Detection] {
        guard let results = results as? [VNCoreMLFeatureValueObservation] else {
            return []
        }
        
        // YOLOv11 has two outputs: confidence and coordinates
        var confidenceArray: MLMultiArray?
        var coordinatesArray: MLMultiArray?
        
        // Debug: Log what outputs we receive
        if !YOLODetectionService.hasLoggedOutputs {
            print("🔍 YOLO Model has \(results.count) outputs:")
            for (i, result) in results.enumerated() {
                print("   Output \(i): \(result.featureName ?? "unnamed")")
            }
            YOLODetectionService.hasLoggedOutputs = true
        }
        
        for result in results {
            let featureName = result.featureName ?? ""
            if featureName.contains("confidence") {
                confidenceArray = result.featureValue.multiArrayValue
            } else if featureName.contains("coordinates") {
                coordinatesArray = result.featureValue.multiArrayValue
            }
        }
        
        // If we don't have named outputs, assume it's the raw format
        if confidenceArray == nil && coordinatesArray == nil && results.count > 0 {
            let multiArray = results[0].featureValue.multiArrayValue
            return processYOLOv11RawOutput(multiArray)
        }
        
        // Process the confidence and coordinates arrays
        guard let confidence = confidenceArray,
              let coordinates = coordinatesArray else {
            print("⚠️ YOLO: Missing confidence or coordinates output")
            return []
        }
        
        return processYOLOv11SeparateOutputs(confidence: confidence, coordinates: coordinates)
    }
    
    // Process when we have separate confidence and coordinates
    private func processYOLOv11SeparateOutputs(confidence: MLMultiArray, coordinates: MLMultiArray) -> [Detection] {
        var detections: [Detection] = []
        
        // Log shapes
        print("📦 YOLO Outputs - Confidence shape: \(confidence.shape), Coordinates shape: \(coordinates.shape)")
        
        // confidence shape: [num_boxes, num_classes]
        // coordinates shape: [num_boxes, 4]
        
        let numBoxes = confidence.shape[0].intValue
        let numClasses = confidence.shape[1].intValue
        
        print("   Processing \(numBoxes) boxes with \(numClasses) classes")
        
        for i in 0..<min(numBoxes, 100) {  // Limit to first 100 boxes
            // Get coordinates [x, y, width, height] - already normalized
            let x = coordinates[[i as NSNumber, 0]].floatValue
            let y = coordinates[[i as NSNumber, 1]].floatValue
            let w = coordinates[[i as NSNumber, 2]].floatValue
            let h = coordinates[[i as NSNumber, 3]].floatValue
            
            // Find best class
            var maxScore: Float = 0
            var maxClass = 0
            
            for c in 0..<numClasses {
                let score = confidence[[i as NSNumber, c as NSNumber]].floatValue
                if score > maxScore {
                    maxScore = score
                    maxClass = c
                }
            }
            
            // Check threshold
            guard maxScore >= settings.confidenceThreshold else { continue }
            
            // Skip filtered classes
            guard settings.isClassEnabled(maxClass) else { continue }
            
            let bbox = CGRect(
                x: CGFloat(x - w/2),
                y: CGFloat(y - h/2),
                width: CGFloat(w),
                height: CGFloat(h)
            )
            
            let label = cocoDataset.getClassName(byID: maxClass)
            
            detections.append(Detection(
                label: label,
                confidence: maxScore,
                boundingBox: bbox,
                classIndex: maxClass
            ))
            
            // Log non-person detections
            if maxClass != 0 {
                print("🎯 Found: \(label) with \(Int(maxScore * 100))% confidence")
            }
        }
        
        return applyNMS(to: detections)
    }
    
    // Original processing for raw output
    private func processYOLOv11RawOutput(_ multiArray: MLMultiArray?) -> [Detection] {
        guard let multiArray = multiArray else { return [] }
        
        // YOLOv11 output format: [1, 84, 8400] or similar
        // 84 = 4 (bbox) + 80 (classes)
        // 8400 = number of predictions
        
        var detections: [Detection] = []
        let shape = multiArray.shape
        
        // Debug: Log model output shape once
        if !YOLODetectionService.hasLoggedShape {
            print("🔍 YOLO Model Output Shape: \(shape)")
            print("   Dimensions: \(multiArray.shape.map { $0.intValue })")
            YOLODetectionService.hasLoggedShape = true
        }
        
        // Parse based on output shape
        if shape.count == 3 {
            let batchSize = shape[0].intValue  // Should be 1
            let featureSize = shape[1].intValue  // Should be 84 (4 bbox + 80 classes)
            let numPredictions = shape[2].intValue  // Should be 8400
            let numClasses = featureSize - 4  // Should be 80
            
            print("📊 Processing YOLO output: batch=\(batchSize), features=\(featureSize), predictions=\(numPredictions), classes=\(numClasses)")
            
            // Process only top predictions to avoid processing thousands of low-confidence boxes
            for i in 0..<min(numPredictions, 300) {
                // Extract bbox - coordinates are at indices 0-3 for each prediction
                let x = multiArray[[0, 0, i] as [NSNumber]].floatValue
                let y = multiArray[[0, 1, i] as [NSNumber]].floatValue
                let w = multiArray[[0, 2, i] as [NSNumber]].floatValue
                let h = multiArray[[0, 3, i] as [NSNumber]].floatValue
                
                // Find best class - class scores start at index 4
                var maxScore: Float = 0
                var maxClass = 0
                var topClasses: [(class: Int, score: Float)] = []
                
                for c in 0..<numClasses {
                    let score = multiArray[[0, 4 + c, i] as [NSNumber]].floatValue
                    
                    // Track top scoring classes for debugging
                    if score > 0.2 {
                        topClasses.append((class: c, score: score))
                    }
                    
                    if score > maxScore {
                        maxScore = score
                        maxClass = c
                    }
                }
                
                // Debug: Log high-confidence detections with multiple class options
                if topClasses.count > 1 && maxScore > 0.3 {
                    print("🔍 Box \(i) has multiple high-confidence classes:")
                    for (cls, score) in topClasses.sorted(by: { $0.score > $1.score }).prefix(3) {
                        let className = cocoDataset.getClassName(byID: cls)
                        print("   - \(className) (class \(cls)): \(Int(score * 100))%")
                    }
                }
                
                // Check confidence threshold
                guard maxScore >= settings.confidenceThreshold else { continue }
                
                // Skip filtered classes
                guard settings.isClassEnabled(maxClass) else { continue }
                
                // Convert to normalized coordinates (YOLO uses center coordinates)
                let bbox = CGRect(
                    x: CGFloat(x - w/2) / 640.0,
                    y: CGFloat(y - h/2) / 640.0,
                    width: CGFloat(w) / 640.0,
                    height: CGFloat(h) / 640.0
                )
                
                // Ensure bounding box is within valid range
                guard bbox.minX >= 0, bbox.minY >= 0,
                      bbox.maxX <= 1, bbox.maxY <= 1,
                      bbox.width > 0, bbox.height > 0 else { continue }
                
                let label = !settings.showClassification ? "object" :
                    cocoDataset.getClassName(byID: maxClass)
                
                // Log non-person detections for debugging
                if maxClass != 0 {
                    print("✅ Detected: \(label) (class \(maxClass)) with \(Int(maxScore * 100))% confidence at box \(i)")
                }
                
                detections.append(Detection(
                    label: label,
                    confidence: maxScore,
                    boundingBox: bbox,
                    classIndex: maxClass
                ))
            }
            
            print("📦 Total detections before NMS: \(detections.count)")
            if detections.count > 0 {
                let classDistribution = Dictionary(grouping: detections, by: { $0.classIndex })
                print("📊 Class distribution:")
                for (classId, dets) in classDistribution {
                    let className = cocoDataset.getClassName(byID: classId)
                    print("   - \(className): \(dets.count) detections")
                }
            }
        }
        
        // Apply NMS
        return applyNMS(to: detections)
    }
    
    // MARK: - Non-Maximum Suppression
    private func applyNMS(to detections: [Detection]) -> [Detection] {
        // Group by class
        var detectionsByClass: [Int: [Detection]] = [:]
        for detection in detections {
            detectionsByClass[detection.classIndex, default: []].append(detection)
        }
        
        var finalDetections: [Detection] = []
        
        // Apply NMS per class
        for (_, classDetections) in detectionsByClass {
            let sorted = classDetections.sorted { $0.confidence > $1.confidence }
            var keep: [Detection] = []
            
            for detection in sorted {
                var shouldKeep = true
                
                for kept in keep {
                    let iou = calculateIoU(detection.boundingBox, kept.boundingBox)
                    if iou > iouThreshold {
                        shouldKeep = false
                        break
                    }
                }
                
                if shouldKeep {
                    keep.append(detection)
                }
            }
            
            finalDetections.append(contentsOf: keep)
        }
        
        return finalDetections
    }
    
    // MARK: - MobileViT Classification (Disabled - see DualClassificationPipeline.swift)
    /*
    private func classifyWithMobileViT(cgImage: CGImage, boundingBox: CGRect, completion: @escaping (String?, Float?) -> Void) {
        guard let mobileViTModel = mobileViTModel else {
            completion(nil, nil)
            return
        }
        
        // Crop image to bounding box
        guard let croppedImage = cropImage(cgImage, to: boundingBox) else {
            completion(nil, nil)
            return
        }
        
        let request = VNCoreMLRequest(model: mobileViTModel) { request, error in
            guard let observations = request.results as? [VNClassificationObservation],
                  let topResult = observations.first else {
                completion(nil, nil)
                return
            }
            
            completion(topResult.identifier, topResult.confidence)
        }
        
        // MobileViT expects 256x256 input
        request.imageCropAndScaleOption = .centerCrop
        
        let handler = VNImageRequestHandler(cgImage: croppedImage, options: [:])
        try? handler.perform([request])
    }
    
    // MARK: - Image Cropping
    private func cropImage(_ image: CGImage, to boundingBox: CGRect) -> CGImage? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        
        // Convert normalized coordinates to pixel coordinates
        let x = boundingBox.origin.x * width
        let y = (1 - boundingBox.origin.y - boundingBox.height) * height
        let cropWidth = boundingBox.width * width
        let cropHeight = boundingBox.height * height
        
        let cropRect = CGRect(x: x, y: y, width: cropWidth, height: cropHeight)
        
        return image.cropping(to: cropRect)
    }
    */
    
    // MARK: - IoU Calculation
    private func calculateIoU(_ box1: CGRect, _ box2: CGRect) -> Float {
        let intersection = box1.intersection(box2)
        guard !intersection.isNull else { return 0 }
        
        let intersectionArea = intersection.width * intersection.height
        let unionArea = box1.width * box1.height + box2.width * box2.height - intersectionArea
        
        return Float(intersectionArea / unionArea)
    }
    
    // MARK: - Capture Methods
    func startCaptureSession() {
        _ = coreDataManager.startNewSession()
        isCaptureEnabled = true
    }
    
    func stopCaptureSession() {
        isCaptureEnabled = false
        coreDataManager.endCurrentSession()
    }
    
    private func captureDetections(_ detections: [Detection], from ciImage: CIImage) {
        guard isCaptureEnabled else { return }
        
        let now = Date()
        
        // Check capture interval throttling
        guard now.timeIntervalSince(lastCaptureTime) >= settings.captureInterval else {
            return // Too soon since last capture
        }
        
        // Clean up old captures from deduplication tracking
        if settings.enableDeduplication {
            recentCaptures = recentCaptures.filter { 
                now.timeIntervalSince($0.timestamp) < captureDeduplicationWindow 
            }
        }
        
        // Convert CIImage to UIImage for storage
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        let uiImage = UIImage(cgImage: cgImage)
        
        // Track if we captured anything this cycle
        var capturedAny = false
        
        // Capture each detection with deduplication
        for detection in detections {
            // Check if this detection is similar to a recent capture
            if settings.enableDeduplication && isDuplicateDetection(detection) {
                continue // Skip duplicate
            }
            
            // Crop image to bounding box
            let croppedImage = cropImage(uiImage, to: detection.boundingBox)
            let imageData = croppedImage?.jpegData(compressionQuality: 0.8)
            
            // Debug logging
            if let imageData = imageData {
                print("Captured \(detection.label): image size = \(imageData.count) bytes")
            } else {
                print("Warning: Failed to capture image for \(detection.label)")
            }
            
            // Get supercategory
            let supercategory = cocoDataset.getSupercategory(byID: detection.classIndex)
            
            // Save to Core Data
            let capturedDetection = coreDataManager.captureDetection(
                label: detection.label,
                confidence: detection.confidence,
                boundingBox: detection.boundingBox,
                classIndex: detection.classIndex,
                supercategory: supercategory,
                imageData: imageData
            )
            
            print("Saved detection: \(capturedDetection.label ?? "unknown") with image: \(capturedDetection.imageData != nil)")
            
            // Add to recent captures for deduplication
            recentCaptures.append((
                classIndex: detection.classIndex,
                boundingBox: detection.boundingBox,
                timestamp: now
            ))
            
            capturedAny = true
        }
        
        // Update last capture time only if we captured something
        if capturedAny {
            lastCaptureTime = now
        }
    }
    
    private func isDuplicateDetection(_ detection: Detection) -> Bool {
        // Check against recent captures
        for recent in recentCaptures {
            // Must be same class
            if recent.classIndex != detection.classIndex {
                continue
            }
            
            // Check if bounding boxes are similar (high IoU)
            let iou = calculateIoU(detection.boundingBox, recent.boundingBox)
            if iou > boundingBoxSimilarityThreshold {
                return true // Found a duplicate
            }
        }
        return false
    }
    
    private func getCGImage(from ciImage: CIImage) -> CGImage? {
        let context = CIContext()
        return context.createCGImage(ciImage, from: ciImage.extent)
    }
    
    private func cropImage(_ image: UIImage, to boundingBox: CGRect) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        
        // Convert normalized coordinates to pixel coordinates
        // YOLO uses center-based coordinates, already converted to top-left in detection
        // Add small padding to ensure we capture the full object
        let padding: CGFloat = 10
        
        let x = max(0, boundingBox.origin.x * width - padding)
        let y = max(0, boundingBox.origin.y * height - padding)
        let cropWidth = min(width - x, boundingBox.width * width + padding * 2)
        let cropHeight = min(height - y, boundingBox.height * height + padding * 2)
        
        // Ensure crop rect is valid
        guard cropWidth > 0 && cropHeight > 0 else { 
            print("Invalid crop rect: width=\(cropWidth), height=\(cropHeight)")
            return nil 
        }
        
        let cropRect = CGRect(x: x, y: y, width: cropWidth, height: cropHeight)
        
        guard let croppedCGImage = cgImage.cropping(to: cropRect) else { 
            print("Failed to crop image with rect: \(cropRect)")
            return nil 
        }
        
        // Debug: Verify cropped image
        let croppedImage = UIImage(cgImage: croppedCGImage)
        print("Successfully cropped image: \(croppedImage.size)")
        
        return croppedImage
    }
    
    // MARK: - Drawing
    func drawDetections(on image: UIImage) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(at: .zero)
        
        guard let context = UIGraphicsGetCurrentContext() else {
            return image
        }
        
        let imageHeight = image.size.height
        let imageWidth = image.size.width
        
        for detection in lastDetections {
            // Convert normalized coordinates to image coordinates
            let rect = CGRect(
                x: detection.boundingBox.minX * imageWidth,
                y: (1 - detection.boundingBox.maxY) * imageHeight,
                width: detection.boundingBox.width * imageWidth,
                height: detection.boundingBox.height * imageHeight
            )
            
            // Draw bounding box
            context.setStrokeColor(UIColor.green.cgColor)
            context.setLineWidth(2)
            context.stroke(rect)
            
            // Draw label
            let label = settings.showConfidence ? 
                "\(detection.label): \(String(format: "%.2f", detection.confidence))" :
                detection.label
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .bold),
                .foregroundColor: UIColor.white,
                .backgroundColor: UIColor.green.withAlphaComponent(0.7)
            ]
            
            let labelSize = label.size(withAttributes: attributes)
            let labelRect = CGRect(
                x: rect.minX,
                y: rect.minY - labelSize.height,
                width: labelSize.width + 4,
                height: labelSize.height
            )
            
            label.draw(in: labelRect, withAttributes: attributes)
        }
        
        let resultImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return resultImage ?? image
    }
}