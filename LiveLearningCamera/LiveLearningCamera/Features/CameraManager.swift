//
//  CameraManager.swift
//  LiveLearningCamera
//
//  Camera management using AVFoundation
//

import AVFoundation
import CoreImage
import UIKit
import Combine

class CameraManager: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    @Published var isSessionRunning = false
    @Published var videoOutput: AVCaptureVideoDataOutput?
    @Published var currentFrame: CIImage?
    @Published var capturedImage: UIImage?
    @Published var cameraPosition: AVCaptureDevice.Position = .back
    @Published var isAuthorized = false
    @Published var alertError: String?
    
    // MARK: - Session Management
    let session = AVCaptureSession()
    private var currentInput: AVCaptureDeviceInput?
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let videoQueue = DispatchQueue(label: "videoQueue", qos: .userInitiated)
    
    // MARK: - Initialization
    override init() {
        super.init()
        checkAuthorization()
        setupMemoryWarningObserver()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupMemoryWarningObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }
    
    @objc private func handleMemoryWarning() {
        // Clear current frame to free memory
        currentFrame = nil
        capturedImage = nil
    }
    
    // MARK: - Authorization
    func checkAuthorization() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isAuthorized = granted
                    if granted {
                        self?.setupSession()
                    }
                }
            }
        case .denied, .restricted:
            isAuthorized = false
            alertError = "Camera access denied. Please enable in Settings."
        @unknown default:
            break
        }
    }
    
    // MARK: - Session Setup
    private func setupSession() {
        session.beginConfiguration()
        
        // Set session preset
        if session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
        }
        
        // Add video input
        guard let camera = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: cameraPosition
        ) else {
            alertError = "Camera not available"
            session.commitConfiguration()
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(input) {
                session.addInput(input)
                currentInput = input
            }
        } catch {
            alertError = "Failed to create camera input: \(error.localizedDescription)"
            session.commitConfiguration()
            return
        }
        
        // Add video output
        videoDataOutput.setSampleBufferDelegate(self, queue: videoQueue)
        videoDataOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoDataOutput.alwaysDiscardsLateVideoFrames = true  // Drop frames if processing is slow
        
        if session.canAddOutput(videoDataOutput) {
            session.addOutput(videoDataOutput)
            videoOutput = videoDataOutput
        }
        
        // Configure connection
        if let connection = videoDataOutput.connection(with: .video) {
            connection.videoOrientation = .portrait
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = (cameraPosition == .front)
            }
        }
        
        session.commitConfiguration()
    }
    
    // MARK: - Session Control
    func startSession() {
        guard isAuthorized else {
            checkAuthorization()
            return
        }
        
        if !session.isRunning {
            videoQueue.async { [weak self] in
                self?.session.startRunning()
                DispatchQueue.main.async {
                    self?.isSessionRunning = true
                }
            }
        }
    }
    
    func stopSession() {
        if session.isRunning {
            videoQueue.async { [weak self] in
                self?.session.stopRunning()
                DispatchQueue.main.async {
                    self?.isSessionRunning = false
                }
            }
        }
    }
    
    // MARK: - Camera Control
    func switchCamera() {
        cameraPosition = cameraPosition == .back ? .front : .back
        
        session.beginConfiguration()
        
        // Remove current input
        if let currentInput = currentInput {
            session.removeInput(currentInput)
        }
        
        // Add new input
        guard let camera = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: cameraPosition
        ) else {
            session.commitConfiguration()
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(input) {
                session.addInput(input)
                currentInput = input
            }
        } catch {
            print("Failed to switch camera: \(error)")
        }
        
        // Update video connection
        if let connection = videoDataOutput.connection(with: .video) {
            connection.videoOrientation = .portrait
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = (cameraPosition == .front)
            }
        }
        
        session.commitConfiguration()
    }
    
    // MARK: - Capture
    func capturePhoto() {
        guard let currentFrame = currentFrame else { return }
        
        let context = CIContext()
        guard let cgImage = context.createCGImage(currentFrame, from: currentFrame.extent) else { return }
        
        let image = UIImage(cgImage: cgImage)
        
        DispatchQueue.main.async {
            self.capturedImage = image
        }
    }
    
    // MARK: - Focus
    func focus(at point: CGPoint) {
        guard let device = currentInput?.device,
              device.isFocusPointOfInterestSupported else { return }
        
        do {
            try device.lockForConfiguration()
            device.focusPointOfInterest = point
            device.focusMode = .autoFocus
            device.exposurePointOfInterest = point
            device.exposureMode = .autoExpose
            device.unlockForConfiguration()
        } catch {
            print("Failed to focus: \(error)")
        }
    }
    
    // MARK: - Zoom
    func setZoomFactor(_ factor: CGFloat) {
        guard let device = currentInput?.device else { return }
        
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = max(1.0, min(factor, device.maxAvailableVideoZoomFactor))
            device.unlockForConfiguration()
        } catch {
            print("Failed to set zoom: \(error)")
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Create CIImage in autorelease pool to ensure cleanup
        autoreleasepool {
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            
            DispatchQueue.main.async { [weak self] in
                // Only keep the latest frame, release previous
                self?.currentFrame = ciImage
            }
        }
    }
}