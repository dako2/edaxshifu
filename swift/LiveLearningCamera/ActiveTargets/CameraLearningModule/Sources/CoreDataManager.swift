//
//  CoreDataManager.swift
//  LiveLearningCamera
//
//  Core Data stack and persistence manager for captured detections
//

import CoreData
import UIKit

public class CoreDataManager {
    public static let shared = CoreDataManager()
    
    private init() {}
    
    // MARK: - Core Data Stack
    lazy var persistentContainer: NSPersistentContainer = {
        // Get the bundle for CameraLearningModule
        let bundle = Bundle(for: CoreDataManager.self)
        
        // Load the model from the module's bundle
        guard let modelURL = bundle.url(forResource: "ObjectMemory", withExtension: "momd") else {
            fatalError("Failed to find ObjectMemory model in bundle")
        }
        
        guard let model = NSManagedObjectModel(contentsOf: modelURL) else {
            fatalError("Failed to load ObjectMemory model from \(modelURL)")
        }
        
        let container = NSPersistentContainer(name: "ObjectMemory", managedObjectModel: model)
        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                print("Core Data failed to load: \(error), \(error.userInfo)")
            }
        }
        return container
    }()
    
    public var context: NSManagedObjectContext {
        return persistentContainer.viewContext
    }
    
    // MARK: - Current Session Management
    private var currentSession: CaptureSession?
    
    public func startNewSession() -> CaptureSession {
        let session = CaptureSession(context: context)
        session.id = UUID()
        session.startDate = Date()
        session.totalDetections = 0
        currentSession = session
        saveContext()
        return session
    }
    
    public func endCurrentSession() {
        currentSession?.endDate = Date()
        saveContext()
        currentSession = nil
    }
    
    // MARK: - Detection Capture
    public func captureDetection(
        label: String,
        confidence: Float,
        boundingBox: CGRect,
        classIndex: Int,
        supercategory: String,
        imageData: Data?
    ) -> CapturedDetection {
        let detection = CapturedDetection(context: context)
        detection.id = UUID()
        detection.captureDate = Date()
        detection.label = label
        detection.confidence = confidence
        detection.classIndex = Int16(classIndex)
        detection.supercategory = supercategory
        detection.imageData = imageData
        
        // Store bounding box
        detection.boundingBoxX = Float(boundingBox.origin.x)
        detection.boundingBoxY = Float(boundingBox.origin.y)
        detection.boundingBoxWidth = Float(boundingBox.width)
        detection.boundingBoxHeight = Float(boundingBox.height)
        
        // Link to current session
        if let session = currentSession {
            detection.session = session
            session.totalDetections += 1
        }
        
        saveContext()
        return detection
    }
    
    // MARK: - Fetching
    func fetchRecentDetections(limit: Int = 100) -> [CapturedDetection] {
        let request: NSFetchRequest<CapturedDetection> = CapturedDetection.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "captureDate", ascending: false)]
        request.fetchLimit = limit
        
        do {
            return try context.fetch(request)
        } catch {
            print("Failed to fetch detections: \(error)")
            return []
        }
    }
    
    func fetchDetectionsByClass(_ classIndex: Int) -> [CapturedDetection] {
        let request: NSFetchRequest<CapturedDetection> = CapturedDetection.fetchRequest()
        request.predicate = NSPredicate(format: "classIndex == %d", classIndex)
        request.sortDescriptors = [NSSortDescriptor(key: "captureDate", ascending: false)]
        
        do {
            return try context.fetch(request)
        } catch {
            print("Failed to fetch detections by class: \(error)")
            return []
        }
    }
    
    func fetchAllSessions() -> [CaptureSession] {
        let request: NSFetchRequest<CaptureSession> = CaptureSession.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "startDate", ascending: false)]
        
        do {
            return try context.fetch(request)
        } catch {
            print("Failed to fetch sessions: \(error)")
            return []
        }
    }
    
    // MARK: - Statistics
    public func getDetectionStatistics() -> DetectionStatistics {
        let request: NSFetchRequest<CapturedDetection> = CapturedDetection.fetchRequest()
        
        do {
            let detections = try context.fetch(request)
            
            // Count by class
            var classCounts: [String: Int] = [:]
            var totalConfidence: Float = 0
            
            for detection in detections {
                let label = detection.label ?? "unknown"
                classCounts[label, default: 0] += 1
                totalConfidence += detection.confidence
            }
            
            let avgConfidence = detections.isEmpty ? 0 : totalConfidence / Float(detections.count)
            
            return DetectionStatistics(
                totalDetections: detections.count,
                classCounts: classCounts,
                averageConfidence: avgConfidence,
                mostCommonClass: classCounts.max(by: { $0.value < $1.value })?.key
            )
        } catch {
            print("Failed to calculate statistics: \(error)")
            return DetectionStatistics(
                totalDetections: 0,
                classCounts: [:],
                averageConfidence: 0,
                mostCommonClass: nil
            )
        }
    }
    
    // MARK: - Cleanup
    func deleteOldDetections(olderThan days: Int = 30) {
        let request: NSFetchRequest<CapturedDetection> = CapturedDetection.fetchRequest()
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        request.predicate = NSPredicate(format: "captureDate < %@", cutoffDate as NSDate)
        
        do {
            let oldDetections = try context.fetch(request)
            for detection in oldDetections {
                context.delete(detection)
            }
            saveContext()
        } catch {
            print("Failed to delete old detections: \(error)")
        }
    }
    
    // MARK: - Save Context
    public func saveContext() {
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                let nsError = error as NSError
                print("Failed to save context: \(nsError), \(nsError.userInfo)")
                // Report error through ErrorManager
                Task { @MainActor in
                    ErrorManager.shared.handle(
                        AppError.coreDataError("Failed to save: \(error.localizedDescription)"),
                        context: "CoreDataManager.saveContext"
                    )
                }
            }
        }
    }
}

// MARK: - Statistics Model
public struct DetectionStatistics {
    public let totalDetections: Int
    public let classCounts: [String: Int]
    public let averageConfidence: Float
    public let mostCommonClass: String?
    
    public init(totalDetections: Int, classCounts: [String: Int], averageConfidence: Float, mostCommonClass: String?) {
        self.totalDetections = totalDetections
        self.classCounts = classCounts
        self.averageConfidence = averageConfidence
        self.mostCommonClass = mostCommonClass
    }
}
