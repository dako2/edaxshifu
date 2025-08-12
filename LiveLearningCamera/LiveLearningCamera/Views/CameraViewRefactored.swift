//
//  CameraViewRefactored.swift
//  LiveLearningCamera
//
//  Professional camera view with performance metrics and scene analysis
//

import SwiftUI
import AVFoundation

// MARK: - Camera Preview View
struct OptimizedCameraPreview: UIViewRepresentable {
    @ObservedObject var cameraManager: CameraManager
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: AVCaptureSession())
        previewLayer.frame = view.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        
        context.coordinator.previewLayer = previewLayer
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.previewLayer?.session = cameraManager.session
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
    }
}

// MARK: - Detection Overlay View
struct OptimizedDetectionOverlay: View {
    let trackedObjects: [MemoryTrackedObject]
    let imageSize: CGSize
    let settings = DetectionSettingsManager.shared
    let showTrackingId: Bool = false  // Can be made configurable if needed
    
    var body: some View {
        GeometryReader { geometry in
            ForEach(trackedObjects, id: \.id) { object in
                let rect = normalizedRect(object.lastBoundingBox, in: geometry.size)
                
                ZStack(alignment: .topLeading) {
                    // Bounding box with confidence-based color
                    Rectangle()
                        .stroke(colorForConfidence(object.confidence), lineWidth: 2)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                    
                    // Professional label with tracking info
                    Group {
                        makeLabel(for: object)
                    }
                    .position(x: rect.minX + 50, y: rect.minY - 15)
                }
            }
        }
    }
    
    private func normalizedRect(_ bbox: CGRect, in size: CGSize) -> CGRect {
        CGRect(
            x: bbox.minX * size.width,
            y: (1 - bbox.maxY) * size.height,
            width: bbox.width * size.width,
            height: bbox.height * size.height
        )
    }
    
    private func colorForConfidence(_ confidence: Float) -> Color {
        if confidence > 0.8 {
            return .green
        } else if confidence > 0.6 {
            return .yellow
        } else {
            return .orange
        }
    }
    
    @ViewBuilder
    private func makeLabel(for object: MemoryTrackedObject) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(object.label)
                    .font(.system(size: 11, weight: .medium))
                
                if settings.showConfidence {
                    Text("\(Int(object.confidence * 100))%")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
            }
            
            if showTrackingId {
                Text("ID: \(object.id.uuidString.prefix(8))")
                    .font(.system(size: 9))
                    .foregroundColor(.gray)
            }
            
            if object.observationCount > 1 {
                Text("Seen: \(object.observationCount)x")
                    .font(.system(size: 9))
                    .foregroundColor(.blue)
            }
        }
        .padding(4)
        .background(Color.black.opacity(0.7))
        .foregroundColor(.white)
        .cornerRadius(4)
    }
}

// MARK: - Performance Metrics View
struct PerformanceMetricsView: View {
    let metrics: PerformanceMetrics
    
    var body: some View {
        HStack(spacing: 16) {
            MetricBadge(
                icon: "speedometer",
                value: String(format: "%.1f", metrics.fps),
                label: "FPS"
            )
            
            MetricBadge(
                icon: "eye",
                value: "\(metrics.objectCount)",
                label: "Objects"
            )
            
            MetricBadge(
                icon: "cpu",
                value: String(format: "%.0f%%", metrics.cpuUsage * 100),
                label: "CPU"
            )
            
            MetricBadge(
                icon: "memorychip",
                value: String(format: "%.0f%%", metrics.cacheHitRate * 100),
                label: "Cache"
            )
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .cornerRadius(10)
    }
}

struct MetricBadge: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 14))
            Text(value)
                .font(.system(size: 12, weight: .semibold))
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Scene Analysis Panel
struct SceneAnalysisPanel: View {
    let context: AnalyzedScene?
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Scene Analysis", systemImage: "camera.metering.matrix")
                    .font(.system(size: 14, weight: .medium))
                
                Spacer()
                
                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                }
            }
            
            if isExpanded, let context = context {
                VStack(alignment: .leading, spacing: 6) {
                    // Scene type
                    HStack {
                        Text("Scene:")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text(context.sceneType.description)
                            .font(.system(size: 12, weight: .medium))
                    }
                    
                    // Detected activities
                    if !context.activities.isEmpty {
                        Text("Activities:")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        
                        ForEach(context.activities, id: \.type) { activity in
                            HStack {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 4, height: 4)
                                Text(activity.type.description)
                                    .font(.system(size: 11))
                                Text("(\(Int(activity.confidence * 100))%)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // Key relationships
                    if !context.relationships.isEmpty {
                        Text("Relationships: \(context.relationships.count)")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(10)
    }
}

// MARK: - Main Camera View
struct CameraViewRefactored: View {
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var detectionPipeline = OptimizedDetectionPipeline()
    @StateObject private var settings = DetectionSettingsManager.shared
    
    @State private var trackedObjects: [MemoryTrackedObject] = []
    @State private var sceneContext: AnalyzedScene?
    @State private var performanceMetrics = PerformanceMetrics()
    @State private var isProcessing = false
    @State private var showSettings = false
    @State private var showHistory = false
    @State private var isRecording = false
    @State private var showAnalysis = true
    @State private var showMetrics = true
    
    private let detectionTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            // Camera Preview
            OptimizedCameraPreview(cameraManager: cameraManager)
                .ignoresSafeArea()
            
            // Detection Overlay
            OptimizedDetectionOverlay(
                trackedObjects: trackedObjects,
                imageSize: UIScreen.main.bounds.size
            )
            .ignoresSafeArea()
            
            // UI Overlay
            VStack {
                // Top Bar - Performance Metrics
                if showMetrics {
                    PerformanceMetricsView(metrics: performanceMetrics)
                        .padding(.top)
                }
                
                // Scene Analysis
                if showAnalysis {
                    SceneAnalysisPanel(context: sceneContext)
                        .padding(.horizontal)
                }
                
                Spacer()
                
                // Bottom Control Bar
                HStack(spacing: 30) {
                    // Settings
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color.black.opacity(0.5)))
                    }
                    
                    // Record/Capture
                    Button(action: toggleRecording) {
                        ZStack {
                            Circle()
                                .strokeBorder(isRecording ? Color.red : Color.white, lineWidth: 3)
                                .frame(width: 70, height: 70)
                            
                            Circle()
                                .fill(isRecording ? Color.red : Color.white)
                                .frame(width: 60, height: 60)
                            
                            if isRecording {
                                Rectangle()
                                    .fill(Color.white)
                                    .frame(width: 24, height: 24)
                                    .cornerRadius(4)
                            }
                        }
                    }
                    
                    // History
                    Button(action: { showHistory = true }) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color.black.opacity(0.5)))
                    }
                }
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            cameraManager.startSession()
        }
        .onDisappear {
            cameraManager.stopSession()
        }
        .onReceive(detectionTimer) { _ in
            performDetection()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(isPresented: $showSettings)
        }
        .sheet(isPresented: $showHistory) {
            DetectionHistoryView()
                .environment(\.managedObjectContext, CoreDataManager.shared.context)
        }
    }
    
    private func performDetection() {
        guard !isProcessing,
              let frame = cameraManager.currentFrame else { return }
        
        isProcessing = true
        
        Task {
            let result = await detectionPipeline.process(frame: frame)
            
            await MainActor.run {
                self.trackedObjects = result.trackedObjects
                self.sceneContext = result.sceneContext
                self.performanceMetrics = result.metrics
                self.isProcessing = false
            }
        }
    }
    
    private func toggleRecording() {
        if isRecording {
            detectionPipeline.stopRecording()
        } else {
            detectionPipeline.startRecording()
        }
        isRecording.toggle()
    }
}

// MARK: - Supporting Types
struct PerformanceMetrics {
    var fps: Double = 0
    var objectCount: Int = 0
    var cpuUsage: Float = 0
    var cacheHitRate: Double = 0
    var processingTime: TimeInterval = 0
}

extension SceneType {
    var description: String {
        switch self {
        case .unknown: return "Unknown"
        case .indoor: return "Indoor"
        case .outdoor: return "Outdoor"
        case .street: return "Street"
        case .office: return "Office"
        case .park: return "Park"
        case .dining: return "Dining"
        }
    }
}

extension DetectedActivityType {
    var description: String {
        switch self {
        case .working: return "Working"
        case .phoneUse: return "Using Phone"
        case .drinking: return "Drinking"
        case .reading: return "Reading"
        case .walking: return "Walking"
        case .cycling: return "Cycling"
        case .moving: return "Moving"
        case .interacting: return "Interacting"
        }
    }
}