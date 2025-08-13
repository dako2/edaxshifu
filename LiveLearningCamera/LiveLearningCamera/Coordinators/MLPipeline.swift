//
//  MLPipeline.swift
//  LiveLearningCamera
//
//  Main ML Pipeline Coordinator that orchestrates detection and classification services
//

import Foundation
import CoreImage
import Vision
import Combine
import CoreVideo
import UIKit

/// Main ML Pipeline that coordinates all detection and classification tasks
/// This is the central orchestrator for the entire ML system
@MainActor
class MLPipeline: ObservableObject {
    
    // MARK: - Singleton
    static let shared = MLPipeline()
    
    // MARK: - Services from Features
    
    // Detection Services
    private var yoloDetector: YOLODetectionService?
    private var handTracker: HandTrackingDetector?
    private let detectionStabilizer = DetectionStabilizer()
    private var objectTracker: ObjectTracker?
    
    // Classification Services  
    private var visualFeatureExtractor: VisualFeatureExtractor?
    private var sceneAnalyzer: SceneAnalyzer?
    private let objectMemory = ObjectMemoryManager.shared
    private let attentionSystem = AttentionSystem()
    
    // Memory Services
    private let sceneContextManager = SceneContextManager()
    
    // MARK: - Published State
    @Published var isProcessing = false
    @Published var lastProcessingTime: TimeInterval = 0
    @Published var currentFPS: Double = 0
    @Published var detectedObjects: [Detection] = []
    @Published var trackedObjects: [MemoryTrackedObject] = []
    @Published var handDetections: [HandTrackingResult] = []
    @Published var sceneContext: AnalyzedScene?
    @Published var performanceMetrics = PerformanceMetrics()
    
    // MARK: - Recording State
    private var isRecording = false
    private var recordingSession: MLRecordingSession?
    private var coreDataSession: CaptureSession?
    
    // MARK: - Analytics
    private var analyticsData = AnalyticsData()
    private var frameCount = 0
    
    // MARK: - Intelligent State Tracking
    private let simpleDedup = SimpleAggressiveDeduplication.shared
    private let learningMemory = LearningMemory.shared
    
    // MARK: - Pipeline Configuration
    struct PipelineConfiguration {
        var enableYOLO = true
        var enableHandTracking = true
        var enableSceneAnalysis = true
        var enableMemory = true
        var enableStabilization = true
        var maxConcurrentOperations = 3
    }
    
    private var configuration = PipelineConfiguration()
    
    // MARK: - Processing Queue
    private let processingQueue = DispatchQueue(label: "com.app.mlpipeline", qos: .userInitiated)
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    private init() {
        setupPipeline()
    }
    
    private func setupPipeline() {
        // Initialize services that can throw
        do {
            // Initialize YOLO detector
            self.yoloDetector = YOLODetectionService()
            
            // Initialize hand tracking
            self.handTracker = try HandTrackingDetector()
            
            // Load the hand tracking model immediately
            Task { @MainActor in
                do {
                    try await self.handTracker?.loadModel()
                    print("MLPipeline: Hand tracking model loaded successfully")
                } catch {
                    print("MLPipeline: Failed to load hand tracking model: \(error)")
                }
            }
            
            // Initialize object tracker
            self.objectTracker = try ObjectTracker()
            
            // Initialize visual feature extractor
            self.visualFeatureExtractor = try VisualFeatureExtractor()
            
            // Initialize scene analyzer
            self.sceneAnalyzer = try SceneAnalyzer()
            
            print("ML Pipeline initialized with all services")
        } catch {
            print("Failed to initialize some services: \(error)")
            // Services that failed will remain nil and be skipped during processing
        }
    }
    
    // MARK: - Image Processing Utilities
    private func createPixelBuffer(from ciImage: CIImage) -> CVPixelBuffer? {
        let width = Int(ciImage.extent.width)
        let height = Int(ciImage.extent.height)
        
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
                     kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                        width,
                                        height,
                                        kCVPixelFormatType_32BGRA,
                                        attrs,
                                        &pixelBuffer)
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        let context = CIContext()
        context.render(ciImage, to: buffer)
        return buffer
    }
    
    // MARK: - Thumbnail Extraction
    private func extractThumbnail(from ciImage: CIImage, boundingBox: CGRect, padding: CGFloat = 10) -> Data? {
        // Convert normalized coordinates to pixel coordinates
        let imageWidth = ciImage.extent.width
        let imageHeight = ciImage.extent.height
        
        // Calculate crop rectangle with padding
        let x = max(0, boundingBox.origin.x * imageWidth - padding)
        let y = max(0, boundingBox.origin.y * imageHeight - padding)
        let width = min(imageWidth - x, boundingBox.width * imageWidth + padding * 2)
        let height = min(imageHeight - y, boundingBox.height * imageHeight + padding * 2)
        
        let cropRect = CGRect(x: x, y: y, width: width, height: height)
        
        // Crop the image
        let croppedImage = ciImage.cropped(to: cropRect)
        
        // Scale down to thumbnail size (max 200x200)
        let targetSize: CGFloat = 200
        let scale = min(targetSize / width, targetSize / height)
        let scaledImage = croppedImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        // Convert to UIImage and then to Data
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }
        
        let uiImage = UIImage(cgImage: cgImage)
        return uiImage.jpegData(compressionQuality: 0.7)
    }
    
    // MARK: - Main Processing Entry Point
    // Match OptimizedDetectionPipeline signature for compatibility
    func process(frame ciImage: CIImage) async -> ProcessingResult {
        let startTime = Date()
        
        // Mark as processing
        await MainActor.run {
            self.isProcessing = true
        }
        
        // Run detection and classification in parallel
        async let detectionResults = runDetection(ciImage)
        async let classificationResults = runClassification(ciImage)
        
        // Await both results
        let (detections, classifications) = await (detectionResults, classificationResults)
        
        // Combine and stabilize results
        let stabilized = stabilizeResults(detections: detections, classifications: classifications, frame: ciImage)
        
        // Update memory and context
        if configuration.enableMemory {
            await updateMemory(stabilized)
        }
        
        // Calculate metrics
        let processingTime = Date().timeIntervalSince(startTime)
        let metrics = calculateMetrics(processingTime: processingTime, objectCount: stabilized.trackedObjects.count)
        
        // Update analytics data
        analyticsData.totalFrames += 1
        analyticsData.totalDetections += stabilized.trackedObjects.count
        analyticsData.totalFPS += metrics.fps
        frameCount += 1
        
        // Intelligently save objects based on visual state
        await saveIntelligentlyFiltered(stabilized.trackedObjects, frame: ciImage)
        
        // Record if enabled (for session tracking)
        if isRecording {
            recordFrame(stabilized.trackedObjects, context: classifications.scene)
        }
        
        // Update published state
        await MainActor.run {
            self.detectedObjects = detections.yoloDetections
            self.trackedObjects = stabilized.trackedObjects
            self.handDetections = detections.handDetections
            self.sceneContext = classifications.scene
            self.performanceMetrics = metrics
            self.lastProcessingTime = processingTime
            self.isProcessing = false
        }
        
        return ProcessingResult(
            trackedObjects: stabilized.trackedObjects,
            handDetections: detections.handDetections,
            sceneContext: classifications.scene,
            metrics: metrics
        )
    }
    
    // Keep original signature for backward compatibility
    func process(_ ciImage: CIImage) async -> ProcessingResult {
        return await process(frame: ciImage)
    }
    
    // MARK: - Detection Pipeline
    private func runDetection(_ ciImage: CIImage) async -> (yoloDetections: [Detection], handDetections: [HandTrackingResult]) {
        var yoloDetections: [Detection] = []
        var handDetections: [HandTrackingResult] = []
        
        // Run YOLO detection
        if configuration.enableYOLO, let detector = yoloDetector {
            yoloDetections = await withCheckedContinuation { continuation in
                detector.detect(in: ciImage) { detections in
                    continuation.resume(returning: detections)
                }
            }
        }
        
        // Run hand tracking
        if configuration.enableHandTracking, let tracker = handTracker {
            do {
                handDetections = try await tracker.detectWithTracking(in: ciImage)
                if !handDetections.isEmpty {
                    print("MLPipeline: Detected \(handDetections.count) hands")
                }
            } catch {
                print("Hand tracking failed: \(error)")
                handDetections = []
            }
        } else {
            print("MLPipeline: Hand tracking disabled or tracker not available")
        }
        
        return (yoloDetections, handDetections)
    }
    
    // MARK: - Classification Pipeline
    private func runClassification(_ ciImage: CIImage) async -> (features: [FeatureVector], scene: AnalyzedScene?) {
        var features: [FeatureVector] = []
        var scene: AnalyzedScene?
        
        // Extract visual features - skip if extractor not available
        // Note: VisualFeatureExtractor needs CGImage and bounding boxes, not CIImage directly
        // For now, we'll skip feature extraction in the pipeline
        
        // Analyze scene (SceneAnalyzer needs CGImage and detections)
        // Note: We need to convert CIImage to CGImage for SceneAnalyzer
        if configuration.enableSceneAnalysis, let analyzer = sceneAnalyzer {
            let context = CIContext()
            if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                do {
                    let analysis = try await analyzer.analyzeFrame(self.detectedObjects, image: cgImage)
                    // Convert SceneAnalysis to AnalyzedScene
                    // Note: SceneAnalysis and AnalyzedScene have different structures
                    // For now, create a basic AnalyzedScene
                    scene = AnalyzedScene(
                        timestamp: analysis.timestamp,
                        sceneType: .unknown, // Default scene type
                        objects: [], // Would need to convert TrackedObject to MemoryTrackedObject
                        relationships: [],
                        activities: analysis.activities.map { activity in
                            DetectedActivity(
                                type: .moving, // Default activity type
                                participants: [], // Empty participants for now
                                confidence: 0.5
                            )
                        },
                        graph: SceneGraphData(nodes: [], edges: [])
                    )
                } catch {
                    print("Scene analysis failed: \(error)")
                }
            }
        }
        
        return (features, scene)
    }
    
    // MARK: - Object ID Tracking
    // Maintain a mapping of object positions to IDs across frames
    private var objectIDTracker = ObjectIDTracker()
    
    // MARK: - Stabilization
    private func stabilizeResults(detections: (yoloDetections: [Detection], handDetections: [HandTrackingResult]), 
                                 classifications: (features: [FeatureVector], scene: AnalyzedScene?),
                                 frame: CIImage) 
                                 -> (trackedObjects: [MemoryTrackedObject], stabilizedDetections: [Detection]) {
        
        // Apply stabilization if enabled
        let stabilized = configuration.enableStabilization ? 
            detectionStabilizer.stabilize(detections.yoloDetections) : 
            detections.yoloDetections
        
        // Track objects with persistent IDs
        var tracked: [MemoryTrackedObject] = []
        
        if let tracker = objectTracker {
            // Use ObjectTracker for proper tracking with visual features
            let context = CIContext()
            guard let cgImage = context.createCGImage(frame, from: frame.extent) else {
                // Fallback if we can't create CGImage
                let fallbackTracked = stabilized.map { detection in
                    let persistentID = objectIDTracker.getOrCreateID(for: detection)
                    let thumbnail = extractThumbnail(from: frame, boundingBox: detection.boundingBox)
                    return MemoryTrackedObject(
                        id: persistentID,
                        label: detection.label,
                        firstSeen: objectIDTracker.getFirstSeen(for: persistentID),
                        lastSeen: Date(),
                        boundingBox: detection.boundingBox,
                        confidence: detection.confidence,
                        thumbnail: thumbnail
                    )
                }
                return (fallbackTracked, stabilized)
            }
            
            // Process each detection through simple ID tracking
            // (ObjectTracker.processDetection is async, can't use it in sync context)
            for detection in stabilized {
                let persistentID = objectIDTracker.getOrCreateID(for: detection)
                let thumbnail = extractThumbnail(from: frame, boundingBox: detection.boundingBox)
                let memoryObj = MemoryTrackedObject(
                    id: persistentID,
                    label: detection.label,
                    firstSeen: objectIDTracker.getFirstSeen(for: persistentID),
                    lastSeen: Date(),
                    boundingBox: detection.boundingBox,
                    confidence: detection.confidence,
                    thumbnail: thumbnail
                )
                tracked.append(memoryObj)
            }
            
            // Prune stale objects periodically
            tracker.pruneStaleObjects()
            
        } else {
            // Fallback: Use simple position-based ID tracking
            tracked = stabilized.map { detection in
                let persistentID = objectIDTracker.getOrCreateID(for: detection)
                let thumbnail = extractThumbnail(from: frame, boundingBox: detection.boundingBox)
                return MemoryTrackedObject(
                    id: persistentID,
                    label: detection.label,
                    firstSeen: objectIDTracker.getFirstSeen(for: persistentID),
                    lastSeen: Date(),
                    boundingBox: detection.boundingBox,
                    confidence: detection.confidence,
                    thumbnail: thumbnail
                )
            }
        }
        
        return (tracked, stabilized)
    }
    
    // MARK: - Memory Update
    private func updateMemory(_ results: (trackedObjects: [MemoryTrackedObject], stabilizedDetections: [Detection])) async {
        // ObjectMemoryManager processes Detection objects with the frame
        // Since we already have tracked objects, we'll skip additional memory processing
        
        // SceneContextManager.analyzeScene creates a new AnalyzedScene
        // We could call it here if needed:
        // let analyzedScene = sceneContextManager.analyzeScene(results.trackedObjects)
        
        // Update attention system frame counter
        attentionSystem.updateFrame()
    }
    
    // MARK: - Metrics Calculation
    private func calculateMetrics(processingTime: TimeInterval, objectCount: Int) -> PerformanceMetrics {
        // Calculate FPS
        let fps = processingTime > 0 ? 1.0 / processingTime : 0.0
        
        // Get system resources
        let cpuUsage = Double(SystemMonitor.shared.getCPUUsage())
        
        return PerformanceMetrics(
            fps: fps,
            objectCount: objectCount,
            cpuUsage: cpuUsage,
            cacheHitRate: 0.0, // TODO: Implement cache metrics
            processingTime: processingTime
        )
    }
    
    // MARK: - Configuration
    func configure(_ config: PipelineConfiguration) {
        self.configuration = config
    }
    
    func enableService(_ service: ServiceType, enabled: Bool) {
        switch service {
        case .yolo:
            configuration.enableYOLO = enabled
        case .handTracking:
            configuration.enableHandTracking = enabled
        case .sceneAnalysis:
            configuration.enableSceneAnalysis = enabled
        case .memory:
            configuration.enableMemory = enabled
        case .stabilization:
            configuration.enableStabilization = enabled
        }
    }
    
    enum ServiceType {
        case yolo
        case handTracking
        case sceneAnalysis
        case memory
        case stabilization
    }
    
    // MARK: - Simple Aggressive Deduplication
    private func saveIntelligentlyFiltered(_ objects: [MemoryTrackedObject], frame: CIImage) async {
        var savedCount = 0
        var skippedCount = 0
        
        for object in objects {
            // Update learning memory for stats
            let (isNew, familiarity) = learningMemory.learn(from: object)
            
            // Use simple aggressive deduplication
            let (shouldSave, reason) = simpleDedup.shouldSave(object)
            
            if shouldSave {
                // Save to Core Data
                let detection = CoreDataManager.shared.captureDetection(
                    label: object.label,
                    confidence: object.confidence,
                    boundingBox: object.lastBoundingBox,
                    classIndex: 0,
                    supercategory: "object",
                    imageData: object.thumbnail
                )
                
                savedCount += 1
                print("✅ \(reason)")
            } else {
                skippedCount += 1
                // Log skips less frequently
                if skippedCount % 10 == 0 {
                    print("⏭️ \(reason)")
                }
            }
        }
        
        // Log summary every 30 seconds
        if frameCount % 900 == 0 && frameCount > 0 {  // ~30 fps * 30 sec
            print(learningMemory.getLearningStats())
        }
    }
    
    // MARK: - Recording Methods
    func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        recordingSession = createRecordingSession()
    }
    
    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        finalizeRecordingSession()
    }
    
    private func createRecordingSession() -> MLRecordingSession {
        let session = MLRecordingSession()
        
        // Create Core Data session
        coreDataSession = CaptureSession(context: CoreDataManager.shared.context)
        coreDataSession?.startDate = Date()
        coreDataSession?.id = session.id
        
        CoreDataManager.shared.saveContext()
        
        return session
    }
    
    private func finalizeRecordingSession() {
        guard let session = recordingSession else { return }
        
        session.endTime = Date()
        
        // Update Core Data session
        coreDataSession?.endDate = Date()
        coreDataSession?.totalDetections = Int32(session.totalDetections)
        CoreDataManager.shared.saveContext()
        
        recordingSession = nil
        coreDataSession = nil
    }
    
    private func recordFrame(_ objects: [MemoryTrackedObject], context: AnalyzedScene?) {
        guard let session = recordingSession else { return }
        
        session.frameCount += 1
        session.totalDetections += objects.count
        
        // Save frame data if needed
        if session.frameCount % 10 == 0 {  // Save every 10th frame
            saveFrameData(objects, context: context, to: session)
        }
    }
    
    private func saveFrameData(_ objects: [MemoryTrackedObject], context: AnalyzedScene?, to session: MLRecordingSession) {
        for object in objects {
            let captured = MLCapturedDetection(
                id: UUID(),
                timestamp: Date(),
                label: object.label,
                confidence: object.confidence,
                boundingBox: object.lastBoundingBox,
                thumbnail: object.thumbnail  // Now using actual thumbnail data
            )
            session.capturedDetections.append(captured)
            
            // Note: Objects are already saved via saveUniqueObjects()
            // This just tracks them in the recording session
        }
        
        if session.capturedDetections.count > 100 {
            // Limit memory usage by removing old detections
            session.capturedDetections.removeFirst(50)
        }
        
        CoreDataManager.shared.saveContext()
    }
    
    // MARK: - Analytics Export
    func exportAnalytics() -> MLAnalyticsReport {
        let totalFrames = analyticsData.totalFrames
        let totalDetections = analyticsData.totalDetections
        let avgFPS = analyticsData.totalFrames > 0 ? analyticsData.totalFPS / Double(analyticsData.totalFrames) : 0
        
        let classDistribution = Dictionary(grouping: trackedObjects, by: { $0.label })
            .mapValues { $0.count }
        
        return MLAnalyticsReport(
            totalFrames: totalFrames,
            totalDetections: totalDetections,
            averageFPS: avgFPS,
            classDistribution: classDistribution,
            timeRange: (start: analyticsData.startTime, end: Date()),
            summary: "Processed \(totalFrames) frames with \(totalDetections) total detections at avg \(String(format: "%.1f", avgFPS)) FPS"
        )
    }
}

// MARK: - Supporting Types
struct ProcessingResult {
    let trackedObjects: [MemoryTrackedObject]
    let handDetections: [HandTrackingResult]
    let sceneContext: AnalyzedScene?
    let metrics: PerformanceMetrics
}

// MARK: - Recording Types
class MLRecordingSession {
    var id: UUID = UUID()
    var startTime: Date = Date()
    var endTime: Date?
    var frameCount: Int = 0
    var totalDetections: Int = 0
    var capturedDetections: [MLCapturedDetection] = []
}

struct MLCapturedDetection {
    let id: UUID
    let timestamp: Date
    let label: String
    let confidence: Float
    let boundingBox: CGRect
    let thumbnail: Data?
}

// MARK: - Analytics Types
struct AnalyticsData {
    var startTime: Date = Date()
    var totalFrames: Int = 0
    var totalDetections: Int = 0
    var totalFPS: Double = 0.0
}

struct MLAnalyticsReport {
    let totalFrames: Int
    let totalDetections: Int
    let averageFPS: Double
    let classDistribution: [String: Int]
    let timeRange: (start: Date, end: Date)
    let summary: String
}