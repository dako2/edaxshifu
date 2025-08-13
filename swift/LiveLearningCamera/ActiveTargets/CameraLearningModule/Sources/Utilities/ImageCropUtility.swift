//
//  ImageCropUtility.swift
//  CameraLearningModule
//
//  Utility for cropping images and generating thumbnails from detections
//

import Foundation
import CoreImage
import UIKit
import Vision

public class ImageCropUtility {
    
    // MARK: - Properties
    private let context = CIContext()
    private let thumbnailSize: CGSize
    private let jpegQuality: Float
    
    // MARK: - Initialization
    public init(thumbnailSize: CGSize = CGSize(width: 128, height: 128), jpegQuality: Float = 0.7) {
        self.thumbnailSize = thumbnailSize
        self.jpegQuality = jpegQuality
    }
    
    // MARK: - Public Methods
    
    /// Extract thumbnail from CIImage for a given bounding box
    /// - Parameters:
    ///   - ciImage: The source CIImage
    ///   - boundingBox: Normalized bounding box (0-1 coordinates)
    ///   - padding: Additional padding around the bounding box in pixels
    /// - Returns: JPEG data of the thumbnail, or nil if extraction fails
    public func extractThumbnail(from ciImage: CIImage, boundingBox: CGRect, padding: CGFloat = 10) -> Data? {
        // Convert normalized bounding box to pixel coordinates
        let imageExtent = ciImage.extent
        let width = imageExtent.width
        let height = imageExtent.height
        
        // Calculate crop rectangle with padding
        let x = max(0, boundingBox.origin.x * width - padding)
        let y = max(0, (1 - boundingBox.origin.y - boundingBox.height) * height - padding)
        let cropWidth = min(width - x, boundingBox.width * width + padding * 2)
        let cropHeight = min(height - y, boundingBox.height * height + padding * 2)
        
        let cropRect = CGRect(x: x, y: y, width: cropWidth, height: cropHeight)
        
        // Crop the image
        let croppedImage = ciImage.cropped(to: cropRect)
        
        // Scale to thumbnail size
        let scale = min(thumbnailSize.width / cropWidth, thumbnailSize.height / cropHeight)
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        let scaledImage = croppedImage.transformed(by: transform)
        
        // Convert to JPEG data
        return convertToJPEG(scaledImage)
    }
    
    /// Extract thumbnail from UIImage for a given bounding box
    /// - Parameters:
    ///   - uiImage: The source UIImage
    ///   - boundingBox: Normalized bounding box (0-1 coordinates)
    ///   - padding: Additional padding around the bounding box in pixels
    /// - Returns: JPEG data of the thumbnail, or nil if extraction fails
    public func extractThumbnail(from uiImage: UIImage, boundingBox: CGRect, padding: CGFloat = 10) -> Data? {
        guard let cgImage = uiImage.cgImage else { return nil }
        
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        
        // Calculate crop rectangle with padding
        let x = max(0, boundingBox.origin.x * width - padding)
        let y = max(0, (1 - boundingBox.origin.y - boundingBox.height) * height - padding)
        let cropWidth = min(width - x, boundingBox.width * width + padding * 2)
        let cropHeight = min(height - y, boundingBox.height * height + padding * 2)
        
        let cropRect = CGRect(x: x, y: y, width: cropWidth, height: cropHeight)
        
        // Crop the image
        guard let croppedCGImage = cgImage.cropping(to: cropRect) else { return nil }
        
        // Create UIImage from cropped CGImage
        let croppedUIImage = UIImage(cgImage: croppedCGImage)
        
        // Scale to thumbnail size
        let renderer = UIGraphicsImageRenderer(size: thumbnailSize)
        let thumbnail = renderer.image { context in
            croppedUIImage.draw(in: CGRect(origin: .zero, size: thumbnailSize))
        }
        
        return thumbnail.jpegData(compressionQuality: CGFloat(jpegQuality))
    }
    
    /// Crop image to bounding box without resizing
    /// - Parameters:
    ///   - ciImage: The source CIImage
    ///   - boundingBox: Normalized bounding box (0-1 coordinates)
    ///   - padding: Additional padding around the bounding box in pixels
    /// - Returns: Cropped CIImage, or nil if cropping fails
    public func cropImage(_ ciImage: CIImage, to boundingBox: CGRect, padding: CGFloat = 10) -> CIImage? {
        let imageExtent = ciImage.extent
        let width = imageExtent.width
        let height = imageExtent.height
        
        // Calculate crop rectangle with padding
        let x = max(0, boundingBox.origin.x * width - padding)
        let y = max(0, (1 - boundingBox.origin.y - boundingBox.height) * height - padding)
        let cropWidth = min(width - x, boundingBox.width * width + padding * 2)
        let cropHeight = min(height - y, boundingBox.height * height + padding * 2)
        
        let cropRect = CGRect(x: x, y: y, width: cropWidth, height: cropHeight)
        
        return ciImage.cropped(to: cropRect)
    }
    
    /// Crop image to bounding box without resizing
    /// - Parameters:
    ///   - uiImage: The source UIImage
    ///   - boundingBox: Normalized bounding box (0-1 coordinates)
    ///   - padding: Additional padding around the bounding box in pixels
    /// - Returns: Cropped UIImage, or nil if cropping fails
    public func cropImage(_ uiImage: UIImage, to boundingBox: CGRect, padding: CGFloat = 10) -> UIImage? {
        guard let cgImage = uiImage.cgImage else { return nil }
        
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        
        // Calculate crop rectangle with padding
        let x = max(0, boundingBox.origin.x * width - padding)
        let y = max(0, (1 - boundingBox.origin.y - boundingBox.height) * height - padding)
        let cropWidth = min(width - x, boundingBox.width * width + padding * 2)
        let cropHeight = min(height - y, boundingBox.height * height + padding * 2)
        
        let cropRect = CGRect(x: x, y: y, width: cropWidth, height: cropHeight)
        
        guard let croppedCGImage = cgImage.cropping(to: cropRect) else { return nil }
        
        return UIImage(cgImage: croppedCGImage)
    }
    
    // MARK: - Private Methods
    
    private func convertToJPEG(_ ciImage: CIImage) -> Data? {
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        
        let uiImage = UIImage(cgImage: cgImage)
        return uiImage.jpegData(compressionQuality: CGFloat(jpegQuality))
    }
}

// MARK: - Shared Instance
extension ImageCropUtility {
    public static let shared = ImageCropUtility()
}