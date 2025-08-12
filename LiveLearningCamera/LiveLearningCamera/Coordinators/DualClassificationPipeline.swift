import CoreML
import Vision
import UIKit

/// Coordinator for dual classification pipeline using YOLO for object detection and MobileViT for detailed classification
/// This coordinator orchestrates multiple ML models to provide enriched object classification
class DualClassificationPipeline {
    
    // MARK: - Properties
    private var yoloModel: VNCoreMLModel?
    private var mobileViTModel: VNCoreMLModel?
    
    // MARK: - Classification Results
    struct ClassificationResult {
        let boundingBox: CGRect
        let yoloClass: String           // COCO class (80 classes)
        let yoloConfidence: Float
        let mobileViTClass: String?      // ImageNet class (1000 classes)
        let mobileViTConfidence: Float?
    }
    
    // MARK: - Initialization
    init() {
        loadModels()
    }
    
    private func loadModels() {
        // Load YOLO model
        if let yoloURL = Bundle.main.url(forResource: "yolo11n", withExtension: "mlmodelc") {
            do {
                let yolo = try MLModel(contentsOf: yoloURL)
                yoloModel = try VNCoreMLModel(for: yolo)
                print("YOLO model loaded successfully")
            } catch {
                print("Failed to load YOLO model: \(error)")
            }
        }
        
        // Load MobileViT model
        if let mobileViTURL = Bundle.main.url(forResource: "MobileViT", withExtension: "mlmodelc") {
            do {
                let mobileViT = try MLModel(contentsOf: mobileViTURL)
                mobileViTModel = try VNCoreMLModel(for: mobileViT)
                print("MobileViT model loaded successfully")
            } catch {
                print("Failed to load MobileViT model: \(error)")
            }
        }
    }
    
    // MARK: - Classification Pipeline
    func classifyImage(_ image: UIImage, completion: @escaping ([ClassificationResult]) -> Void) {
        guard let yoloModel = yoloModel,
              let mobileViTModel = mobileViTModel,
              let cgImage = image.cgImage else {
            completion([])
            return
        }
        
        var results: [ClassificationResult] = []
        let group = DispatchGroup()
        
        // Step 1: Run YOLO for object detection
        let yoloRequest = VNCoreMLRequest(model: yoloModel) { [weak self] request, error in
            guard let observations = request.results as? [VNRecognizedObjectObservation] else {
                completion([])
                return
            }
            
            // Step 2: For each detected object, crop and run MobileViT
            for observation in observations {
                group.enter()
                
                // Get YOLO classification
                let yoloClass = observation.labels.first?.identifier ?? "Unknown"
                let yoloConfidence = observation.labels.first?.confidence ?? 0.0
                
                // Crop the detected region
                if let croppedImage = self?.cropImage(cgImage, to: observation.boundingBox) {
                    // Run MobileViT on cropped region
                    self?.classifyWithMobileViT(croppedImage) { mobileViTClass, mobileViTConfidence in
                        let result = ClassificationResult(
                            boundingBox: observation.boundingBox,
                            yoloClass: yoloClass,
                            yoloConfidence: yoloConfidence,
                            mobileViTClass: mobileViTClass,
                            mobileViTConfidence: mobileViTConfidence
                        )
                        results.append(result)
                        group.leave()
                    }
                } else {
                    let result = ClassificationResult(
                        boundingBox: observation.boundingBox,
                        yoloClass: yoloClass,
                        yoloConfidence: yoloConfidence,
                        mobileViTClass: nil,
                        mobileViTConfidence: nil
                    )
                    results.append(result)
                    group.leave()
                }
            }
            
            group.notify(queue: .main) {
                completion(results)
            }
        }
        
        // Configure YOLO request
        yoloRequest.imageCropAndScaleOption = .scaleFill
        
        // Execute YOLO
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([yoloRequest])
    }
    
    // MARK: - MobileViT Classification
    private func classifyWithMobileViT(_ image: CGImage, completion: @escaping (String?, Float?) -> Void) {
        guard let mobileViTModel = mobileViTModel else {
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
        
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try? handler.perform([request])
    }
    
    // MARK: - Helper Methods
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
}

// MARK: - Usage Example
/*
 let pipeline = DualClassificationPipeline()
 
 pipeline.classifyImage(yourUIImage) { results in
     for result in results {
         print("Object detected:")
         print("  YOLO: \(result.yoloClass) (\(result.yoloConfidence * 100)%)")
         if let mobileViTClass = result.mobileViTClass,
            let mobileViTConfidence = result.mobileViTConfidence {
             print("  MobileViT: \(mobileViTClass) (\(mobileViTConfidence * 100)%)")
         }
         print("  Location: \(result.boundingBox)")
     }
 }
 
 Example output:
 - YOLO detects "dog" (COCO class)
 - MobileViT refines it to "golden retriever" (ImageNet class)
 */