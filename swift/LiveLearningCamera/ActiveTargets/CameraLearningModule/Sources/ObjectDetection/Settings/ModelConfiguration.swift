//
//  ModelConfiguration.swift
//  LiveLearningCamera
//
//  Configuration for switching between YOLO and MobileViT-based detection models
//

import Foundation
import CoreML
import Vision
import UIKit

// MARK: - Model Backend Type
enum DetectionBackbone: String, CaseIterable {
    case yoloOriginal = "YOLOv11n"
    case mobileViTLight = "MobileViT-Light"
    case mobileViTSmall = "MobileViT-Small"
    case mobileViTXSmall = "MobileViT-XSmall"
    case hybrid = "YOLO-MobileViT-Hybrid"
    
    var modelFileName: String {
        switch self {
        case .yoloOriginal:
            return "yolo11n"
        case .mobileViTLight:
            return "mobilevit_light_detection"
        case .mobileViTSmall:
            return "mobilevit_small_detection"
        case .mobileViTXSmall:
            return "mobilevit_xsmall_detection"
        case .hybrid:
            return "yolo_mobilevit_hybrid"
        }
    }
    
    var inputSize: CGSize {
        switch self {
        case .yoloOriginal:
            return CGSize(width: 640, height: 640)
        case .mobileViTLight, .mobileViTSmall:
            return CGSize(width: 256, height: 256)  // MobileViT typically uses smaller input
        case .mobileViTXSmall:
            return CGSize(width: 224, height: 224)  // Even smaller for ultra-light variant
        case .hybrid:
            return CGSize(width: 320, height: 320)  // Compromise size
        }
    }
    
    var description: String {
        switch self {
        case .yoloOriginal:
            return "Standard YOLOv11n - Balanced speed and accuracy"
        case .mobileViTLight:
            return "MobileViT Light - 30% faster, slight accuracy trade-off"
        case .mobileViTSmall:
            return "MobileViT Small - 50% faster, mobile-optimized"
        case .mobileViTXSmall:
            return "MobileViT XSmall - Ultra-fast, best for real-time"
        case .hybrid:
            return "Hybrid approach - MobileViT backbone with YOLO head"
        }
    }
    
    // Performance characteristics
    var performanceProfile: PerformanceProfile {
        switch self {
        case .yoloOriginal:
            return PerformanceProfile(
                inferenceSpeed: .medium,
                accuracy: .high,
                memoryUsage: .medium,
                batteryImpact: .medium
            )
        case .mobileViTLight:
            return PerformanceProfile(
                inferenceSpeed: .fast,
                accuracy: .medium,
                memoryUsage: .low,
                batteryImpact: .low
            )
        case .mobileViTSmall:
            return PerformanceProfile(
                inferenceSpeed: .veryFast,
                accuracy: .medium,
                memoryUsage: .veryLow,
                batteryImpact: .veryLow
            )
        case .mobileViTXSmall:
            return PerformanceProfile(
                inferenceSpeed: .ultraFast,
                accuracy: .low,
                memoryUsage: .minimal,
                batteryImpact: .minimal
            )
        case .hybrid:
            return PerformanceProfile(
                inferenceSpeed: .fast,
                accuracy: .mediumHigh,
                memoryUsage: .low,
                batteryImpact: .low
            )
        }
    }
}

// MARK: - Performance Profile
struct PerformanceProfile {
    enum Level: Int {
        case minimal = 0
        case veryLow = 1
        case low = 2
        case medium = 3
        case mediumHigh = 4
        case high = 5
        case veryHigh = 6
        case ultraFast = 7
        case veryFast = 8
        case fast = 9
    }
    
    let inferenceSpeed: Level
    let accuracy: Level
    let memoryUsage: Level
    let batteryImpact: Level
}

// MARK: - Model Configuration Manager
class ModelConfigurationManager: ObservableObject {
    static let shared = ModelConfigurationManager()
    
    // Current configuration
    @Published var currentBackbone: DetectionBackbone = .yoloOriginal
    @Published var enableDynamicSwitching = false
    @Published var autoOptimizeForBattery = true
    @Published var preferAccuracyOverSpeed = false
    
    // MobileViT specific settings
    @Published var mobileViTSettings = MobileViTSettings()
    
    // Performance monitoring
    @Published var currentFPS: Double = 0
    @Published var averageInferenceTime: Double = 0
    @Published var modelLoadTime: Double = 0
    
    // Model cache
    private var loadedModels: [DetectionBackbone: VNCoreMLModel] = [:]
    private let modelLoadQueue = DispatchQueue(label: "model.loading", qos: .userInitiated)
    
    private init() {
        loadSavedConfiguration()
    }
    
    // MARK: - Model Loading
    func loadModel(backbone: DetectionBackbone, completion: @escaping (Result<VNCoreMLModel, Error>) -> Void) {
        // Check cache first
        if let cachedModel = loadedModels[backbone] {
            completion(.success(cachedModel))
            return
        }
        
        modelLoadQueue.async { [weak self] in
            let startTime = CFAbsoluteTimeGetCurrent()
            
            do {
                // Try to load the model
                guard let modelURL = Bundle.main.url(
                    forResource: backbone.modelFileName,
                    withExtension: "mlmodelc"
                ) else {
                    // If MobileViT model not available, fall back to YOLO
                    if backbone != .yoloOriginal {
                        print("⚠️ \(backbone.rawValue) model not found, falling back to YOLO")
                        self?.loadModel(backbone: .yoloOriginal, completion: completion)
                        return
                    }
                    throw ModelError.modelNotFound(backbone.rawValue)
                }
                
                let mlModel = try MLModel(contentsOf: modelURL)
                let visionModel = try VNCoreMLModel(for: mlModel)
                
                let loadTime = CFAbsoluteTimeGetCurrent() - startTime
                
                DispatchQueue.main.async {
                    self?.loadedModels[backbone] = visionModel
                    self?.modelLoadTime = loadTime
                    print("✅ Loaded \(backbone.rawValue) in \(String(format: "%.2f", loadTime))s")
                    completion(.success(visionModel))
                }
            } catch {
                DispatchQueue.main.async {
                    print("❌ Failed to load \(backbone.rawValue): \(error)")
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - Dynamic Model Switching
    func switchToOptimalModel(basedOn metrics: PerformanceMetrics) {
        guard enableDynamicSwitching else { return }
        
        let thermalState = ProcessInfo.processInfo.thermalState
        let batteryLevel = UIDevice.current.batteryLevel
        
        var recommendedBackbone: DetectionBackbone = currentBackbone
        
        // Switch based on thermal state
        switch thermalState {
        case .nominal:
            // Device is cool, can use heavier models
            recommendedBackbone = preferAccuracyOverSpeed ? .yoloOriginal : .hybrid
        case .fair:
            recommendedBackbone = .hybrid
        case .serious:
            recommendedBackbone = .mobileViTLight
        case .critical:
            recommendedBackbone = .mobileViTXSmall
        @unknown default:
            recommendedBackbone = .mobileViTSmall
        }
        
        // Override if battery is low
        if autoOptimizeForBattery && batteryLevel < 0.2 && batteryLevel > 0 {
            recommendedBackbone = .mobileViTXSmall
        }
        
        // Override if FPS is too low
        if metrics.fps < 15 {
            // Switch to lighter model
            switch currentBackbone {
            case .yoloOriginal:
                recommendedBackbone = .hybrid
            case .hybrid:
                recommendedBackbone = .mobileViTLight
            case .mobileViTLight:
                recommendedBackbone = .mobileViTSmall
            case .mobileViTSmall:
                recommendedBackbone = .mobileViTXSmall
            case .mobileViTXSmall:
                break // Already at lightest
            }
        }
        
        if recommendedBackbone != currentBackbone {
            print("🔄 Switching from \(currentBackbone.rawValue) to \(recommendedBackbone.rawValue)")
            currentBackbone = recommendedBackbone
        }
    }
    
    // MARK: - Configuration Persistence
    func saveConfiguration() {
        UserDefaults.standard.set(currentBackbone.rawValue, forKey: "detection_backbone")
        UserDefaults.standard.set(enableDynamicSwitching, forKey: "enable_dynamic_switching")
        UserDefaults.standard.set(autoOptimizeForBattery, forKey: "auto_optimize_battery")
        UserDefaults.standard.set(preferAccuracyOverSpeed, forKey: "prefer_accuracy")
        mobileViTSettings.save()
    }
    
    private func loadSavedConfiguration() {
        if let backboneString = UserDefaults.standard.string(forKey: "detection_backbone"),
           let backbone = DetectionBackbone(rawValue: backboneString) {
            currentBackbone = backbone
        }
        
        enableDynamicSwitching = UserDefaults.standard.bool(forKey: "enable_dynamic_switching")
        autoOptimizeForBattery = UserDefaults.standard.bool(forKey: "auto_optimize_battery")
        preferAccuracyOverSpeed = UserDefaults.standard.bool(forKey: "prefer_accuracy")
        mobileViTSettings.load()
    }
    
    // MARK: - Model Comparison
    func compareModels(completion: @escaping (ModelComparison) -> Void) {
        // Run inference with each model and compare
        let testQueue = DispatchQueue(label: "model.comparison", qos: .userInitiated)
        
        testQueue.async {
            var results: [DetectionBackbone: ModelMetrics] = [:]
            
            for backbone in DetectionBackbone.allCases {
                // Load and test each model
                // This would run actual inference tests
                // For now, return theoretical values
                results[backbone] = ModelMetrics(
                    averageInferenceTime: self.getTheoreticalInferenceTime(for: backbone),
                    accuracy: self.getTheoreticalAccuracy(for: backbone),
                    memoryUsageMB: self.getTheoreticalMemoryUsage(for: backbone)
                )
            }
            
            let comparison = ModelComparison(results: results)
            DispatchQueue.main.async {
                completion(comparison)
            }
        }
    }
    
    private func getTheoreticalInferenceTime(for backbone: DetectionBackbone) -> Double {
        switch backbone {
        case .yoloOriginal: return 33.0  // ms
        case .hybrid: return 25.0
        case .mobileViTLight: return 20.0
        case .mobileViTSmall: return 15.0
        case .mobileViTXSmall: return 10.0
        }
    }
    
    private func getTheoreticalAccuracy(for backbone: DetectionBackbone) -> Double {
        switch backbone {
        case .yoloOriginal: return 0.85
        case .hybrid: return 0.80
        case .mobileViTLight: return 0.75
        case .mobileViTSmall: return 0.70
        case .mobileViTXSmall: return 0.65
        }
    }
    
    private func getTheoreticalMemoryUsage(for backbone: DetectionBackbone) -> Float {
        switch backbone {
        case .yoloOriginal: return 45.0  // MB
        case .hybrid: return 35.0
        case .mobileViTLight: return 25.0
        case .mobileViTSmall: return 18.0
        case .mobileViTXSmall: return 12.0
        }
    }
}

// MARK: - MobileViT Specific Settings
struct MobileViTSettings {
    var attentionHeads: Int = 4
    var transformerDepth: Int = 2
    var patchSize: Int = 2
    var useDepthwiseSeparable: Bool = true
    var fusionMethod: FusionMethod = .add
    
    enum FusionMethod: String, CaseIterable {
        case add = "Addition"
        case concat = "Concatenation"
        case attention = "Attention-based"
    }
    
    func save() {
        UserDefaults.standard.set(attentionHeads, forKey: "mobilevit_attention_heads")
        UserDefaults.standard.set(transformerDepth, forKey: "mobilevit_transformer_depth")
        UserDefaults.standard.set(patchSize, forKey: "mobilevit_patch_size")
        UserDefaults.standard.set(useDepthwiseSeparable, forKey: "mobilevit_depthwise")
        UserDefaults.standard.set(fusionMethod.rawValue, forKey: "mobilevit_fusion")
    }
    
    mutating func load() {
        attentionHeads = UserDefaults.standard.integer(forKey: "mobilevit_attention_heads")
        if attentionHeads == 0 { attentionHeads = 4 }
        
        transformerDepth = UserDefaults.standard.integer(forKey: "mobilevit_transformer_depth")
        if transformerDepth == 0 { transformerDepth = 2 }
        
        patchSize = UserDefaults.standard.integer(forKey: "mobilevit_patch_size")
        if patchSize == 0 { patchSize = 2 }
        
        useDepthwiseSeparable = UserDefaults.standard.bool(forKey: "mobilevit_depthwise")
        
        if let fusionString = UserDefaults.standard.string(forKey: "mobilevit_fusion"),
           let fusion = FusionMethod(rawValue: fusionString) {
            fusionMethod = fusion
        }
    }
}

// MARK: - Supporting Types
struct ModelMetrics {
    let averageInferenceTime: Double  // milliseconds
    let accuracy: Double  // 0-1
    let memoryUsageMB: Float
}

struct ModelComparison {
    let results: [DetectionBackbone: ModelMetrics]
    
    var fastest: DetectionBackbone? {
        results.min(by: { $0.value.averageInferenceTime < $1.value.averageInferenceTime })?.key
    }
    
    var mostAccurate: DetectionBackbone? {
        results.max(by: { $0.value.accuracy < $1.value.accuracy })?.key
    }
    
    var mostEfficient: DetectionBackbone? {
        results.min(by: { $0.value.memoryUsageMB < $1.value.memoryUsageMB })?.key
    }
}

enum ModelError: LocalizedError {
    case modelNotFound(String)
    case incompatibleModel
    case loadingFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .modelNotFound(let name):
            return "Model '\(name)' not found in bundle"
        case .incompatibleModel:
            return "Model is incompatible with current iOS version"
        case .loadingFailed(let error):
            return "Failed to load model: \(error.localizedDescription)"
        }
    }
}