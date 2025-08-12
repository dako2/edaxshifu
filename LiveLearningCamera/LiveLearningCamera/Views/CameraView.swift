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

// MARK: - Detection Overlay View
struct DetectionOverlay: View {
    let detections: [Detection]
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
        CGRect(
            x: bbox.minX * size.width,
            y: (1 - bbox.maxY) * size.height,
            width: bbox.width * size.width,
            height: bbox.height * size.height
        )
    }
}

// MARK: - Main Camera View
struct CameraView: View {
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var yoloDetector = YOLODetectionService()
    @StateObject private var settings = DetectionSettingsManager.shared
    @State private var detections: [Detection] = []
    @State private var isProcessing = false
    @State private var showStats = true
    @State private var showSettings = false
    @State private var showHistory = false
    @State private var isCapturing = false
    
    private let detectionTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            // Camera Preview
            CameraPreview(cameraManager: cameraManager)
                .ignoresSafeArea()
            
            // Detection Overlay
            DetectionOverlay(
                detections: detections,
                imageSize: UIScreen.main.bounds.size
            )
            .ignoresSafeArea()
            
            // Controls Overlay
            VStack {
                // Top Stats Bar
                if showStats {
                    HStack {
                        Label("\(detections.count) objects", systemImage: "eye")
                        Spacer()
                        if isProcessing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        }
                        if settings.showFPS {
                            Label(String(format: "%.1f FPS", 1.0 / max(0.001, yoloDetector.processingTime)), systemImage: "speedometer")
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
                    
                    // Capture Toggle Button
                    Button(action: {
                        if isCapturing {
                            yoloDetector.stopCaptureSession()
                        } else {
                            yoloDetector.startCaptureSession()
                        }
                        isCapturing.toggle()
                    }) {
                        Circle()
                            .strokeBorder(isCapturing ? Color.red : Color.white, lineWidth: 3)
                            .frame(width: 70, height: 70)
                            .overlay(
                                Circle()
                                    .fill(isCapturing ? Color.red : Color.white)
                                    .frame(width: 60, height: 60)
                            )
                            .overlay(
                                Image(systemName: isCapturing ? "stop.fill" : "record.circle")
                                    .foregroundColor(isCapturing ? .white : .red)
                                    .font(.title2)
                            )
                    }
                    
                    // Toggle Stats
                    Button(action: {
                        showStats.toggle()
                    }) {
                        Image(systemName: showStats ? "info.circle.fill" : "info.circle")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
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
              let frame = cameraManager.currentFrame,
              yoloDetector.isModelLoaded else { return }
        
        isProcessing = true
        
        yoloDetector.detect(in: frame) { newDetections in
            self.detections = newDetections
            self.isProcessing = false
        }
    }
}
