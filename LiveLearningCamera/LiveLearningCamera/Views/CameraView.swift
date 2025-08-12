//
//  CameraView.swift
//  LiveLearningCamera
//
//  Camera preview with YOLO detection overlay
//
// A UI LAYER THAT NEEDS TO FOLLOW SRP
import SwiftUI
import AVFoundation

// MARK: - Camera Preview View
struct CameraPreview: UIViewRepresentable {
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

// MARK: - Professional Detection Overlay View
struct ProfessionalDetectionOverlay: View {
    let trackedObjects: [MemoryTrackedObject]
    let imageSize: CGSize
    @ObservedObject var settings = DetectionSettingsManager.shared
    
    var body: some View {
        GeometryReader { geometry in
            ForEach(trackedObjects, id: \.id) { object in
                let rect = normalizedRect(object.lastBoundingBox, in: geometry.size)
                
                ZStack(alignment: .topLeading) {
                    // Bounding box with color based on type
                    Rectangle()
                        .stroke(object.label.contains("Hand") ? 
                               colorForLabel(object.label) : 
                               colorForConfidence(object.confidence), 
                               lineWidth: object.label.contains("Hand") ? 3 : 2)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                    
                    // Label
                    HStack(spacing: 4) {
                        Text(object.label)
                            .font(.caption)
                        if settings.showConfidence {
                            Text(String(format: "%.0f%%", object.confidence * 100))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(3)
                    .background(Color.black.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(4)
                    .position(x: rect.minX + 40, y: rect.minY - 10)
                }
            }
        }
    }
    
    private func normalizedRect(_ bbox: CGRect, in size: CGSize) -> CGRect {
        // Vision returns normalized coordinates (0-1)
        // Account for aspect fill mode of AVCaptureVideoPreviewLayer
        
        // Camera outputs 1920x1080 (16:9) but in portrait mode it's rotated
        let videoAspect: CGFloat = 1080.0 / 1920.0  // Portrait video aspect
        let viewAspect = size.width / size.height
        
        var x: CGFloat
        var y: CGFloat
        var width: CGFloat
        var height: CGFloat
        
        if viewAspect > videoAspect {
            // View is wider than video - video fills height, crops width
            let videoWidth = size.height * videoAspect
            let xOffset = (size.width - videoWidth) / 2
            
            x = xOffset + bbox.minX * videoWidth
            y = (1 - bbox.maxY) * size.height
            width = bbox.width * videoWidth
            height = bbox.height * size.height
        } else {
            // View is narrower than video - video fills width, crops height
            let videoHeight = size.width / videoAspect
            let yOffset = (size.height - videoHeight) / 2
            
            x = bbox.minX * size.width
            y = yOffset + (1 - bbox.maxY) * videoHeight
            width = bbox.width * size.width
            height = bbox.height * videoHeight
        }
        
        return CGRect(x: x, y: y, width: width, height: height)
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
    
    private func colorForLabel(_ label: String) -> Color {
        // Special colors for hands
        if label.contains("Hand") {
            if label.contains("Left") {
                return .blue
            } else if label.contains("Right") {
                return .purple
            }
            return .cyan
        }
        // Default colors for objects
        return colorForConfidence(0.8)
    }
}

// MARK: - Legacy Detection Overlay (for backwards compatibility)
struct DetectionOverlay: View {
    let detections: [Detection] = [] // Deprecated
    let imageSize: CGSize
    @ObservedObject var settings = DetectionSettingsManager.shared
    
    var body: some View {
        GeometryReader { geometry in
            ForEach(detections.indices, id: \.self) { index in
                let detection = detections[index]
                let rect = normalizedRect(detection.boundingBox, in: geometry.size)
                
                ZStack(alignment: .topLeading) {
                    // Bounding box
                    Rectangle()
                        .stroke(Color.green, lineWidth: 2)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                    
                    // Label
                    Text(settings.showConfidence ? 
                         "\(detection.label): \(String(format: "%.2f", detection.confidence))" :
                         detection.label)
                        .font(.caption)
                        .padding(2)
                        .background(Color.green.opacity(0.7))
                        .foregroundColor(.white)
                        .position(x: rect.minX + 40, y: rect.minY - 10)
                }
            }
        }
    }
    
    private func normalizedRect(_ bbox: CGRect, in size: CGSize) -> CGRect {
        // Vision returns normalized coordinates (0-1)
        // Account for aspect fill mode of AVCaptureVideoPreviewLayer
        
        // Camera outputs 1920x1080 (16:9) but in portrait mode it's rotated
        let videoAspect: CGFloat = 1080.0 / 1920.0  // Portrait video aspect
        let viewAspect = size.width / size.height
        
        var x: CGFloat
        var y: CGFloat
        var width: CGFloat
        var height: CGFloat
        
        if viewAspect > videoAspect {
            // View is wider than video - video fills height, crops width
            let videoWidth = size.height * videoAspect
            let xOffset = (size.width - videoWidth) / 2
            
            x = xOffset + bbox.minX * videoWidth
            y = (1 - bbox.maxY) * size.height
            width = bbox.width * videoWidth
            height = bbox.height * size.height
        } else {
            // View is narrower than video - video fills width, crops height
            let videoHeight = size.width / videoAspect
            let yOffset = (size.height - videoHeight) / 2
            
            x = bbox.minX * size.width
            y = yOffset + (1 - bbox.maxY) * videoHeight
            width = bbox.width * size.width
            height = bbox.height * videoHeight
        }
        
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

// MARK: - Main Camera View
struct CameraView: View {
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var detectionPipeline = OptimizedDetectionPipeline()
    @StateObject private var settings = DetectionSettingsManager.shared
    @State private var trackedObjects: [MemoryTrackedObject] = []
    @State private var handDetections: [HandTrackingResult] = []
    @State private var sceneContext: AnalyzedScene?
    @State private var performanceMetrics = PerformanceMetrics()
    
    // Camera frame dimensions (standard iOS camera output)
    private let cameraFrameSize = CGSize(width: 1920, height: 1080)
    @State private var isProcessing = false
    @State private var showStats = true
    @State private var showSettings = false
    @State private var showHistory = false
    @State private var isRecording = false
    
    private let detectionTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Camera Preview
                CameraPreview(cameraManager: cameraManager)
                    .ignoresSafeArea()
                
                // Object Detection Overlay (YOLO)
                ProfessionalDetectionOverlay(
                    trackedObjects: trackedObjects,
                    imageSize: geometry.size
                )
                
                // Hand Tracking Overlay (MediaPipe-style)
                if settings.enableHandTracking {
                    HandLandmarkOverlay(
                        handDetections: handDetections,
                        imageSize: geometry.size
                    )
                }
                
                // Controls Overlay
                VStack {
                
                // Top Stats Bar
                if showStats {
                    HStack {
                        Label("\(trackedObjects.count) objects", systemImage: "eye")
                        Spacer()
                        if isProcessing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        }
                        if settings.showFPS {
                            Label(String(format: "%.1f FPS", performanceMetrics.fps), systemImage: "speedometer")
                        }
                        
                        // History Button
                        Button(action: {
                            showHistory = true
                        }) {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundColor(.white)
                        }
                        
                        // Settings Button
                        Button(action: {
                            showSettings = true
                        }) {
                            Image(systemName: "gearshape.fill")
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .cornerRadius(10)
                    .padding()
                }
                
                Spacer()
                
                // Bottom Control Bar
                HStack(spacing: 30) {
                    // Switch Camera
                    Button(action: {
                        cameraManager.switchCamera()
                    }) {
                        Image(systemName: "camera.rotate")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(Circle().fill(Color.black.opacity(0.5)))
                    }
                    
                    // Record Toggle Button
                    Button(action: toggleRecording) {
                        Circle()
                            .strokeBorder(isRecording ? Color.red : Color.white, lineWidth: 3)
                            .frame(width: 70, height: 70)
                            .overlay(
                                Circle()
                                    .fill(isRecording ? Color.red : Color.white)
                                    .frame(width: 60, height: 60)
                            )
                            .overlay(
                                Image(systemName: isRecording ? "stop.fill" : "record.circle")
                                    .foregroundColor(isRecording ? .white : .red)
                                    .font(.title2)
                            )
                    }
                    
                    // Analytics Button
                    Button(action: {
                        // Show analytics or export report
                        let report = detectionPipeline.exportAnalytics()
                        print(report.summary)
                    }) {
                        Image(systemName: "chart.bar.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(Circle().fill(Color.black.opacity(0.5)))
                    }
                }
                .padding(.bottom, 30)
            }
            } // End ZStack
        } // End GeometryReader
        .onAppear {
            cameraManager.startSession()
        }
        .onDisappear {
            cameraManager.stopSession()
        }
        .onReceive(detectionTimer) { _ in
            performDetection()
        }
        .alert("Camera Error", isPresented: .constant(cameraManager.alertError != nil)) {
            Button("OK") {
                cameraManager.alertError = nil
            }
        } message: {
            Text(cameraManager.alertError ?? "Unknown error")
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
                self.handDetections = result.handDetections
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
