//
//  PerformanceMetrics.swift
//  LiveLearningCamera
//
//  Performance metrics for tracking detection pipeline efficiency
//

import Foundation

struct PerformanceMetrics {
    var fps: Double = 0.0
    var objectCount: Int = 0
    var cpuUsage: Double = 0.0
    var cacheHitRate: Double = 0.0
    var processingTime: TimeInterval = 0.0
    var memoryUsage: Double = 0.0
    var gpuUsage: Double = 0.0
    var thermalState: String = "nominal"
    
    init() {}
    
    init(fps: Double, 
         objectCount: Int, 
         cpuUsage: Double, 
         cacheHitRate: Double, 
         processingTime: TimeInterval,
         memoryUsage: Double = 0.0,
         gpuUsage: Double = 0.0,
         thermalState: String = "nominal") {
        self.fps = fps
        self.objectCount = objectCount
        self.cpuUsage = cpuUsage
        self.cacheHitRate = cacheHitRate
        self.processingTime = processingTime
        self.memoryUsage = memoryUsage
        self.gpuUsage = gpuUsage
        self.thermalState = thermalState
    }
    
    var formattedFPS: String {
        String(format: "%.1f FPS", fps)
    }
    
    var formattedProcessingTime: String {
        String(format: "%.1f ms", processingTime * 1000)
    }
    
    var formattedCPU: String {
        String(format: "CPU: %.1f%%", cpuUsage * 100)
    }
    
    var formattedMemory: String {
        String(format: "Mem: %.1f%%", memoryUsage * 100)
    }
    
    var formattedGPU: String {
        String(format: "GPU: %.1f%%", gpuUsage * 100)
    }
    
    var formattedCacheHitRate: String {
        String(format: "Cache: %.1f%%", cacheHitRate * 100)
    }
}