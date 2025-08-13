//
//  CaptureSession+CoreDataProperties.swift
//  LiveLearningCamera
//
//  Managed object properties for capture session entity
//

import Foundation
import CoreData

extension CaptureSession {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CaptureSession> {
        return NSFetchRequest<CaptureSession>(entityName: "CaptureSession")
    }
    
    @NSManaged public var id: UUID?
    @NSManaged public var startDate: Date?
    @NSManaged public var endDate: Date?
    @NSManaged public var totalDetections: Int32
    @NSManaged public var detections: NSSet?
}

// MARK: Generated accessors for detections
extension CaptureSession {
    
    @objc(addDetectionsObject:)
    @NSManaged public func addToDetections(_ value: CapturedDetection)
    
    @objc(removeDetectionsObject:)
    @NSManaged public func removeFromDetections(_ value: CapturedDetection)
    
    @objc(addDetections:)
    @NSManaged public func addToDetections(_ values: NSSet)
    
    @objc(removeDetections:)
    @NSManaged public func removeFromDetections(_ values: NSSet)
}