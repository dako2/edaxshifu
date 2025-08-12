//
//  OptimizedDetectionPipeline.swift
//  LiveLearningCamera
//
//  High-performance detection pipeline with integrated subsystems
//

import Foundation
import CoreImage
import Vision
import AVFoundation
import CoreML

// MARK: - Recording Session
class RecordingSession {
    var id: UUID = UUID()
    var startTime: Date = Date()
    var endTime: Date?
    var frameCount: Int = 0
    var totalDetections: Int = 0
    var capturedDetections: [CapturedDetection] = []
}

// MARK: - Optimized Detection Pipeline
@MainActor
class OptimizedDetectionPipeline: ObservableObject {
    
    // Core components
    private let yoloDetector = YOLODetectionService()
    private var handTracker: HandTrackingDetector? = nil
    private let memoryManager = ObjectMemoryManager.shared
    private let attentionSystem = AttentionSystem()
    private let sceneManager = SceneContextManager()
    private let detectionStabilizer = DetectionStabilizer()
    private let settings = DetectionSettingsManager.shared
    
    init() {
        setupHandTracker()
    }
    
    private func setupHandTracker() {
        if settings.enableHandTracking {
            handTracker = HandTrackingDetector()
            Task {
                try? await handTracker?.loadModel()
            }
        }
    }
    
    // Cached CIContext for performance
    private let ciContext = CIContext(options: [
        .priorityRequestLow: false,
        .useSoftwareRenderer: false
    ])
    
    // Performance tracking
    private var frameCount = 0
    private var lastFPSUpdate = Date()
    private var currentFPS: Double = 0
    
    // Recording state
    private var isRecording = false
    private var recordingSession: RecordingSession?
    private var coreDataSession: CaptureSession?
    
    // Processing queue
    private let processingQueue = DispatchQueue(
        label: "com.livelearning.detection",
        qos: .userInitiated
    )
    
    // MARK: - Main Processing
    func process(frame: CIImage) async -> ProcessingResult {
        let startTime = Date()
        
        // Step 1: Run detections (YOLO + optionally hands)
        var allDetections = [Detection]()
        var handTrackingResults = [HandTrackingResult]()
        
        // Always run YOLO
        let yoloDetections = await detectObjects(in: frame)
        allDetections.append(contentsOf: yoloDetections)
        
        // Run hand tracking if enabled
        if settings.enableHandTracking {
            handTrackingResults = await detectHandsWithTracking(in: frame)
            // Don't add hands to allDetections - keep them separate
        }
        
        // Step 2: Stabilize YOLO detections only
        let stabilizedDetections = detectionStabilizer.stabilize(allDetections)
        
        // Step 3: Apply attention filtering to YOLO detections
        let prioritized = attentionSystem.prioritize(
            stabilizedDetections,
            frameSize: CGSize(width: frame.extent.width, height: frame.extent.height)
        )
        
        // Step 4: Track and identify objects (YOLO only)
        let trackedObjects = await trackObjects(prioritized.map { $0.detection }, frame: frame)
        
        // Step 5: Analyze scene context
        let sceneContext = sceneManager.analyzeScene(trackedObjects)
        
        // Step 6: Update metrics
        let metrics = calculateMetrics(
            processingTime: Date().timeIntervalSince(startTime),
            objectCount: trackedObjects.count + handTrackingResults.count
        )
        
        // Step 7: Record if enabled
        if isRecording {
            recordFrame(trackedObjects, context: sceneContext)
        }
        
        // Step 8: Cleanup periodically
        if frameCount % 100 == 0 {
            performMaintenance()
        }
        
        frameCount += 1
        
        return ProcessingResult(
            trackedObjects: trackedObjects,
            handDetections: handTrackingResults,
            sceneContext: sceneContext,
            metrics: metrics
        )
    }
    
    // MARK: - Detection
    private func detectObjects(in frame: CIImage) async -> [Detection] {
        return await withCheckedContinuation { continuation in
            // Convert CIImage to format YOLO expects
            guard let pixelBuffer = frame.pixelBuffer ?? createPixelBuffer(from: frame) else {
                continuation.resume(returning: [])
                return
            }
            
            yoloDetector.detect(in: frame) { detections in
                continuation.resume(returning: detections)
            }
        }
    }
    
    // MARK: - Hand Detection with Tracking
    private func detectHandsWithTracking(in frame: CIImage) async -> [HandTrackingResult] {
        // Create hand tracker if needed
        if handTracker == nil {
            handTracker = HandTrackingDetector()
        }
        
        guard let tracker = handTracker else { return [] }
        
        // Initialize if needed
        if !tracker.isModelLoaded {
            try? await tracker.loadModel()
        }
        
        // Configure based on settings
        if let request = tracker.handPoseRequest {
            request.maximumHandCount = settings.maxHandCount
        }
        
        // Detect hands with full tracking info
        do {
            return try await tracker.detectWithTracking(in: frame)
        } catch {
            print("Hand detection error: \(error)")
            return []
        }
    }
    
    // MARK: - Tracking
    private func trackObjects(_ detections: [Detection], frame: CIImage) async -> [MemoryTrackedObject] {
        return await withTaskGroup(of: MemoryTrackedObject.self) { group in
            var tracked = [MemoryTrackedObject]()
            
            // Process detections in parallel
            for detection in detections {
                group.addTask { [weak self] in
                    guard let self = self else {
                        return MemoryTrackedObject(
                            id: UUID(),
                            label: detection.label,
                            firstSeen: Date(),
                            lastSeen: Date(),
                            boundingBox: detection.boundingBox,
                            confidence: detection.confidence
                        )
                    }
                    return self.memoryManager.process(detection, frame: frame)
                }
            }
            
            // Collect results
            for await object in group {
                tracked.append(object)
            }
            
            return tracked
        }
    }
    
    // MARK: - Metrics
    private func calculateMetrics(processingTime: TimeInterval, objectCount: Int) -> PerformanceMetrics {
        // Update FPS
        let now = Date()
        if now.timeIntervalSince(lastFPSUpdate) >= 1.0 {
            currentFPS = Double(frameCount) / now.timeIntervalSince(lastFPSUpdate)
            lastFPSUpdate = now
            frameCount = 0
        }
        
        // Get memory stats
        let memoryStats = memoryManager.getMemoryStats()
        
        // Get resource state
        let resources = ResourceState.current
        
        return PerformanceMetrics(
            fps: currentFPS,
            objectCount: objectCount,
            cpuUsage: resources.cpuUsage,
            cacheHitRate: memoryStats.cacheHitRate,
            processingTime: processingTime
        )
    }
    
    // MARK: - Recording
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
    
    private func recordFrame(_ objects: [MemoryTrackedObject], context: AnalyzedScene) {
        guard let session = recordingSession else { return }
        
        // Save frame data
        processingQueue.async { [weak self] in
            self?.saveFrameData(objects, context: context, to: session)
        }
    }
    
    private func createRecordingSession() -> RecordingSession {
        let session = RecordingSession()
        session.id = UUID()
        session.startTime = Date()
        session.frameCount = 0
        
        // Also create CoreData session for persistence
        let context = CoreDataManager.shared.context
        let cdSession = CaptureSession(context: context)
        cdSession.id = session.id
        coreDataSession = cdSession
        CoreDataManager.shared.saveContext()
        
        return session
    }
    
    private func finalizeRecordingSession() {
        guard let session = recordingSession else { return }
        
        session.endTime = Date()
        session.totalDetections = session.frameCount
        
        // Update CoreData session
        if let cdSession = coreDataSession {
            cdSession.totalDetections = Int32(session.totalDetections)
            CoreDataManager.shared.saveContext()
        }
        
        recordingSession = nil
        coreDataSession = nil
    }
    
    private func saveFrameData(_ objects: [MemoryTrackedObject], context: AnalyzedScene, to session: RecordingSession) {
        let context = CoreDataManager.shared.context
        
        for object in objects {
            let detection = CapturedDetection(context: context)
            detection.id = UUID()
            detection.captureDate = Date()
            detection.label = object.label
            detection.confidence = object.confidence
            // Store bounding box components
            let bbox = object.lastBoundingBox
            detection.boundingBoxX = Float(bbox.origin.x)
            detection.boundingBoxY = Float(bbox.origin.y)
            detection.boundingBoxWidth = Float(bbox.size.width)
            detection.boundingBoxHeight = Float(bbox.size.height)
            detection.session = coreDataSession
        }
        
        session.frameCount += 1
        
        // Save periodically to avoid memory buildup
        if session.frameCount % 10 == 0 {
            CoreDataManager.shared.saveContext()
        }
    }
    
    // MARK: - Maintenance
    private func performMaintenance() {
        processingQueue.async { [weak self] in
            // Clean up memory
            self?.memoryManager.cleanupMemory()
            
            // Update attention system
            self?.attentionSystem.updateFrame()
            
            // Persist important data
            CoreDataManager.shared.saveContext()
        }
    }
    
    // MARK: - Helper Methods
    private func createPixelBuffer(from ciImage: CIImage) -> CVPixelBuffer? {
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary
        
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(ciImage.extent.width),
            Int(ciImage.extent.height),
            kCVPixelFormatType_32BGRA,
            attrs,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        ciContext.render(ciImage, to: buffer)
        
        return buffer
    }
    
    // MARK: - Configuration
    func configure(settings: DetectionSettings) {
        // Apply settings to subsystems
        yoloDetector.confidenceThreshold = settings.confidenceThreshold
        // Additional configuration as needed
    }
    
    // MARK: - Export
    func exportAnalytics() -> AnalyticsReport {
        let memoryStats = memoryManager.getMemoryStats()
        let attentionStats = attentionSystem.getAttentionAnalytics()
        
        return AnalyticsReport(
            totalObjectsSeen: memoryStats.totalObjectsSeen,
            uniqueLabels: attentionStats.uniqueLabelsSeens,
            averageProcessingTime: memoryStats.avgProcessingTime,
            cacheHitRate: memoryStats.cacheHitRate,
            movingObjectCount: attentionStats.movingObjectCount
        )
    }
}

// MARK: - Processing Result
struct ProcessingResult {
    let trackedObjects: [MemoryTrackedObject]
    let handDetections: [HandTrackingResult]
    let sceneContext: AnalyzedScene?
    let metrics: PerformanceMetrics
}

// MARK: - Detection Settings
struct DetectionSettings {
    var confidenceThreshold: Float = 0.5
    var maxObjectsPerFrame: Int = 10
    var enableTracking: Bool = true
    var enableSceneAnalysis: Bool = true
}

// MARK: - Analytics Report
struct AnalyticsReport {
    let totalObjectsSeen: Int
    let uniqueLabels: Int
    let averageProcessingTime: TimeInterval
    let cacheHitRate: Double
    let movingObjectCount: Int
    
    var summary: String {
        """
        Detection Analytics:
        - Total Objects: \(totalObjectsSeen)
        - Unique Labels: \(uniqueLabels)
        - Avg Processing: \(String(format: "%.2fms", averageProcessingTime * 1000))
        - Cache Hit Rate: \(String(format: "%.1f%%", cacheHitRate * 100))
        - Moving Objects: \(movingObjectCount)
        """
    }
}

// MARK: - Extensions for CIImage
extension CIImage {
    // Shared CIContext for all CIImage operations
    private static let sharedContext = CIContext(options: [
        .priorityRequestLow: false,
        .useSoftwareRenderer: false
    ])
    
    var pixelBuffer: CVPixelBuffer? {
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary
        
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(extent.width),
            Int(extent.height),
            kCVPixelFormatType_32BGRA,
            attrs,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        CIImage.sharedContext.render(self, to: buffer)
        return buffer
    }
}