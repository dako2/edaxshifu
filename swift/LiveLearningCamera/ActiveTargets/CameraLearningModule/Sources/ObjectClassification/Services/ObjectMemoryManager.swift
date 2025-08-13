//
//  ObjectMemoryManager.swift
//  LiveLearningCamera
//
//  Pragmatic object memory system with efficient caching and tracking
//

import Foundation
import CoreML
import Vision
import UIKit
import CoreData

// MARK: - Object Memory Manager
class ObjectMemoryManager {
    
    // Singleton
    static let shared = ObjectMemoryManager()
    
    // Memory configuration - REDUCED FOR MEMORY
    private let shortTermCapacity = 20  // Reduced from 100
    private let shortTermTTL: TimeInterval = 30  // Reduced from 60
    private let longTermThreshold = 10 // Increased from 5 to reduce persistence
    
    // Caches - REDUCED SIZES
    private var shortTermCache = ObjectLRUCache(capacity: 20)  // Reduced from 100
    private var identityMap = [String: UUID]() // Visual signature -> Object ID
    private let identityMapLock = NSLock()
    private let maxIdentityMapSize = 50  // Limit identity map size
    
    // Performance metrics
    private(set) var processingTime: TimeInterval = 0
    private(set) var cacheHitRate: Double = 0
    private var cacheHits = 0
    private var cacheMisses = 0
    private let metricsLock = NSLock()
    
    private init() {}
    
    // MARK: - Main Processing Pipeline
    func process(_ detection: Detection, frame: CIImage) -> MemoryTrackedObject {
        let startTime = Date()
        defer {
            metricsLock.lock()
            processingTime = Date().timeIntervalSince(startTime)
            metricsLock.unlock()
        }
        
        // Extract visual features
        let signature = extractSignature(from: frame, bbox: detection.boundingBox)
        
        // Try to match with existing objects
        identityMapLock.lock()
        let existingId = identityMap[signature]
        identityMapLock.unlock()
        
        if let existingId = existingId,
           let tracked = shortTermCache.get(existingId) {
            // Cache hit - update existing object
            metricsLock.lock()
            cacheHits += 1
            metricsLock.unlock()
            
            updateTrackedObject(tracked, with: detection)
            return tracked
        }
        
        // Cache miss - create new or load from persistent storage
        metricsLock.lock()
        cacheMisses += 1
        metricsLock.unlock()
        
        let tracked = findOrCreateTrackedObject(for: detection, signature: signature)
        
        // Update cache
        shortTermCache.set(tracked.id, tracked)
        
        identityMapLock.lock()
        identityMap[signature] = tracked.id
        // Limit identity map size
        if identityMap.count > maxIdentityMapSize {
            // Remove oldest entries
            let toRemove = identityMap.count - maxIdentityMapSize
            for _ in 0..<toRemove {
                if let firstKey = identityMap.keys.first {
                    identityMap.removeValue(forKey: firstKey)
                }
            }
        }
        identityMapLock.unlock()
        
        // Update metrics
        updateCacheMetrics()
        
        return tracked
    }
    
    // MARK: - Batch Processing
    func processBatch(_ detections: [Detection], frame: CIImage) -> [MemoryTrackedObject] {
        // Limit batch size for memory
        let maxBatchSize = 10
        let limitedDetections = Array(detections.prefix(maxBatchSize))
        
        // Sort by confidence and size for priority processing
        let prioritized = limitedDetections.sorted { det1, det2 in
            let score1 = det1.confidence * Float(det1.boundingBox.width * det1.boundingBox.height)
            let score2 = det2.confidence * Float(det2.boundingBox.width * det2.boundingBox.height)
            return score1 > score2
        }
        
        // Process top N based on available resources
        let maxProcess = min(prioritized.count, getMaxProcessingCapacity())
        return prioritized.prefix(maxProcess).map { process($0, frame: frame) }
    }
    
    // MARK: - Memory Management
    func cleanupMemory() {
        // Remove expired short-term objects
        let cutoff = Date().addingTimeInterval(-shortTermTTL)
        shortTermCache.removeExpired(before: cutoff)
        
        // Clean up identity map for expired objects
        let remainingObjects = shortTermCache.getAllValues()
        let remainingIds = Set(remainingObjects.map { $0.id })
        
        identityMapLock.lock()
        identityMap = identityMap.filter { remainingIds.contains($0.value) }
        identityMapLock.unlock()
        
        // Persist frequently seen objects
        persistFrequentObjects()
    }
    
    func getMemoryStats() -> MemoryStats {
        metricsLock.lock()
        let hitRate = cacheHitRate
        let avgTime = processingTime
        metricsLock.unlock()
        
        identityMapLock.lock()
        let totalSeen = identityMap.count
        identityMapLock.unlock()
        
        return MemoryStats(
            shortTermCount: shortTermCache.count,
            cacheHitRate: hitRate,
            avgProcessingTime: avgTime,
            totalObjectsSeen: totalSeen
        )
    }
    
    // MARK: - Private Methods
    private func extractSignature(from frame: CIImage, bbox: CGRect) -> String {
        // Simple signature based on bbox and basic image features
        // In production, would use perceptual hashing or feature vectors
        let x = Int(bbox.minX * 1000)
        let y = Int(bbox.minY * 1000)
        let w = Int(bbox.width * 1000)
        let h = Int(bbox.height * 1000)
        return "\(x)_\(y)_\(w)_\(h)"
    }
    
    private func updateTrackedObject(_ object: MemoryTrackedObject, with detection: Detection) {
        object.lastSeen = Date()
        object.observationCount += 1
        object.lastBoundingBox = detection.boundingBox
        object.confidence = (object.confidence * Float(object.observationCount - 1) + detection.confidence) / Float(object.observationCount)
        
        // Update position for tracking
        if let tracker = object.tracker {
            tracker.update(bbox: detection.boundingBox)
        }
    }
    
    private func findOrCreateTrackedObject(for detection: Detection, signature: String) -> MemoryTrackedObject {
        // Check persistent storage for similar objects
        if let persisted = loadFromPersistentStorage(matching: signature) {
            return persisted
        }
        
        // Create new tracked object
        let tracked = MemoryTrackedObject(
            id: UUID(),
            label: detection.label,
            firstSeen: Date(),
            lastSeen: Date(),
            boundingBox: detection.boundingBox,
            confidence: detection.confidence
        )
        
        // Initialize tracker
        tracked.tracker = KalmanTracker(initialBbox: detection.boundingBox)
        
        return tracked
    }
    
    private func loadFromPersistentStorage(matching signature: String) -> MemoryTrackedObject? {
        // Simplified - would query CoreData in production
        return nil
    }
    
    private func persistFrequentObjects() {
        let frequent = shortTermCache.getAllValues().filter { $0.observationCount >= longTermThreshold }
        
        for object in frequent {
            persistObject(object)
        }
    }
    
    private func persistObject(_ object: MemoryTrackedObject) {
        // Save to CoreData
        let context = CoreDataManager.shared.context
        let entity = RecognizedObject(context: context)
        entity.id = object.id
        entity.primaryLabel = object.label
        entity.firstSeen = object.firstSeen
        entity.lastSeen = object.lastSeen
        entity.seenCount = Int32(object.observationCount)
        entity.averageConfidence = object.confidence
        
        CoreDataManager.shared.saveContext()
    }
    
    private func updateCacheMetrics() {
        metricsLock.lock()
        defer { metricsLock.unlock() }
        
        let total = cacheHits + cacheMisses
        cacheHitRate = total > 0 ? Double(cacheHits) / Double(total) : 0
    }
    
    private func getMaxProcessingCapacity() -> Int {
        // More conservative limits
        let memoryPressure = ProcessInfo.processInfo.thermalState
        switch memoryPressure {
        case .nominal:
            return 8  // Reduced from 10
        case .fair:
            return 5  // Reduced from 10
        case .serious:
            return 3  // Reduced from 5
        case .critical:
            return 1  // Reduced from 3
        @unknown default:
            return 4  // Reduced from 7
        }
    }
}

// MARK: - Memory Tracked Object
public class MemoryTrackedObject {
    public let id: UUID
    public let label: String
    public let firstSeen: Date
    
    // Thread-safe mutable properties
    private let lock = NSLock()
    private var _lastSeen: Date
    private var _lastBoundingBox: CGRect
    private var _confidence: Float
    private var _observationCount: Int = 1
    private var _tracker: KalmanTracker?
    private var _thumbnail: Data?
    
    var lastSeen: Date {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _lastSeen
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _lastSeen = newValue
        }
    }
    
    public var lastBoundingBox: CGRect {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _lastBoundingBox
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _lastBoundingBox = newValue
        }
    }
    
    public var confidence: Float {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _confidence
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _confidence = newValue
        }
    }
    
    var observationCount: Int {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _observationCount
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _observationCount = newValue
        }
    }
    
    var tracker: KalmanTracker? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _tracker
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _tracker = newValue
        }
    }
    
    var thumbnail: Data? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _thumbnail
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _thumbnail = newValue
        }
    }
    
    init(id: UUID, label: String, firstSeen: Date, lastSeen: Date, boundingBox: CGRect, confidence: Float, thumbnail: Data? = nil) {
        self.id = id
        self.label = label
        self.firstSeen = firstSeen
        self._lastSeen = lastSeen
        self._lastBoundingBox = boundingBox
        self._confidence = confidence
        self._thumbnail = thumbnail
    }
}

// MARK: - Kalman Tracker
class KalmanTracker {
    private var x: Float
    private var y: Float
    private var vx: Float = 0
    private var vy: Float = 0
    private var predictedBox: CGRect
    
    init(initialBbox: CGRect) {
        self.x = Float(initialBbox.midX)
        self.y = Float(initialBbox.midY)
        self.predictedBox = initialBbox
    }
    
    func predict() -> CGRect {
        // Simple linear prediction
        x += vx
        y += vy
        
        return CGRect(
            x: CGFloat(x) - predictedBox.width/2,
            y: CGFloat(y) - predictedBox.height/2,
            width: predictedBox.width,
            height: predictedBox.height
        )
    }
    
    func update(bbox: CGRect) {
        let newX = Float(bbox.midX)
        let newY = Float(bbox.midY)
        
        // Update velocity
        vx = 0.8 * vx + 0.2 * (newX - x)
        vy = 0.8 * vy + 0.2 * (newY - y)
        
        // Update position
        x = newX
        y = newY
        predictedBox = bbox
    }
}

// MARK: - LRU Cache (Specialized for MemoryTrackedObject)
class ObjectLRUCache {
    private var cache = [UUID: MemoryTrackedObject]()
    private var order = [UUID]()
    private let capacity: Int
    private let lock = NSLock()
    
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return cache.count
    }
    
    init(capacity: Int) {
        self.capacity = capacity
    }
    
    func get(_ key: UUID) -> MemoryTrackedObject? {
        lock.lock()
        defer { lock.unlock() }
        
        guard let value = cache[key] else { return nil }
        
        // Move to front
        order.removeAll { $0 == key }
        order.insert(key, at: 0)
        
        return value
    }
    
    func set(_ key: UUID, _ value: MemoryTrackedObject) {
        lock.lock()
        defer { lock.unlock() }
        
        // Remove if exists
        if cache[key] != nil {
            order.removeAll { $0 == key }
        }
        
        // Add to front
        cache[key] = value
        order.insert(key, at: 0)
        
        // Evict if over capacity
        if order.count > capacity {
            if let evicted = order.popLast() {
                cache.removeValue(forKey: evicted)
            }
        }
    }
    
    func removeExpired(before date: Date) {
        lock.lock()
        defer { lock.unlock() }
        
        let keysToRemove = cache.compactMap { (key, value) -> UUID? in
            if value.lastSeen < date {
                return key
            }
            return nil
        }
        
        for key in keysToRemove {
            cache.removeValue(forKey: key)
            order.removeAll { $0 == key }
        }
    }
    
    func getAllValues() -> [MemoryTrackedObject] {
        lock.lock()
        defer { lock.unlock() }
        return Array(cache.values)
    }
}

// MARK: - Memory Stats
struct MemoryStats {
    let shortTermCount: Int
    let cacheHitRate: Double
    let avgProcessingTime: TimeInterval
    let totalObjectsSeen: Int
}