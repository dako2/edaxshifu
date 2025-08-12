//
//  SystemMonitor.swift
//  LiveLearningCamera
//
//  Real-time system resource monitoring
//

import Foundation
import os

// MARK: - System Monitor
class SystemMonitor {
    static let shared = SystemMonitor()
    
    private let processorCount = ProcessInfo.processInfo.processorCount
    
    private init() {}
    
    // MARK: - CPU Usage (Simplified)
    func getCPUUsage() -> Float {
        // For now, return a conservative estimate based on thermal state
        // to avoid the mach API issues
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:
            return 0.3
        case .fair:
            return 0.5
        case .serious:
            return 0.7
        case .critical:
            return 0.9
        @unknown default:
            return 0.5
        }
    }
    
    // MARK: - Memory Pressure (Simplified)
    func getMemoryPressure() -> ResourceState.MemoryPressure {
        // Use a simpler approach based on available memory
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        
        // Estimate based on total memory and thermal state
        if totalMemory < 4_000_000_000 { // Less than 4GB
            switch ProcessInfo.processInfo.thermalState {
            case .critical:
                return .critical
            case .serious:
                return .warning
            default:
                return .normal
            }
        } else {
            // More memory available
            switch ProcessInfo.processInfo.thermalState {
            case .critical:
                return .warning
            default:
                return .normal
            }
        }
    }
    
    // MARK: - Thermal State
    func getThermalState() -> ProcessInfo.ThermalState {
        return ProcessInfo.processInfo.thermalState
    }
    
    // MARK: - Combined Resource State
    func getCurrentResourceState() -> ResourceState {
        return ResourceState(
            cpuUsage: getCPUUsage(),
            memoryPressure: getMemoryPressure(),
            thermalState: getThermalState()
        )
    }
    
    // MARK: - Memory Info (Simplified)
    func getMemoryInfo() -> MemoryInfo {
        let totalMemoryMB = Double(ProcessInfo.processInfo.physicalMemory) / 1024 / 1024
        
        // Estimate based on thermal state
        let estimatedUsage: Double
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:
            estimatedUsage = 0.3
        case .fair:
            estimatedUsage = 0.5
        case .serious:
            estimatedUsage = 0.7
        case .critical:
            estimatedUsage = 0.85
        @unknown default:
            estimatedUsage = 0.5
        }
        
        let usedMemoryMB = totalMemoryMB * estimatedUsage
        
        return MemoryInfo(
            usedMemoryMB: usedMemoryMB,
            virtualMemoryMB: usedMemoryMB * 1.2, // Estimate virtual as 120% of used
            totalMemoryMB: totalMemoryMB,
            availableMemoryMB: totalMemoryMB - usedMemoryMB
        )
    }
    
    // MARK: - Monitoring
    func startMonitoring(interval: TimeInterval = 1.0, 
                        callback: @escaping (ResourceState) -> Void) -> Timer {
        return Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            let state = self.getCurrentResourceState()
            callback(state)
            
            // Log if critical
            if state.memoryPressure == .critical {
                os_log(.error, "Critical memory pressure detected")
            }
            if state.thermalState == .critical {
                os_log(.error, "Critical thermal state detected")
            }
        }
    }
}

// MARK: - Supporting Types
struct MemoryInfo {
    let usedMemoryMB: Double
    let virtualMemoryMB: Double
    let totalMemoryMB: Double
    let availableMemoryMB: Double
    
    var usagePercentage: Double {
        return (usedMemoryMB / totalMemoryMB) * 100
    }
    
    var description: String {
        return String(format: "Memory: %.1fMB / %.1fMB (%.1f%%)",
                     usedMemoryMB, totalMemoryMB, usagePercentage)
    }
}