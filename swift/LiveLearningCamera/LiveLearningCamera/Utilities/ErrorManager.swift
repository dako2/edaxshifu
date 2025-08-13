//
//  ErrorManager.swift
//  LiveLearningCamera
//
//  Centralized error handling with user feedback
//

import Foundation
import SwiftUI

// MARK: - App Error Types
enum AppError: LocalizedError {
    case modelLoadingFailed(String)
    case detectionFailed(String)
    case coreDataError(String)
    case cameraAccessDenied
    case memoryPressure
    case thermalStateCritical
    case storageError(String)
    case networkError(String)
    
    var errorDescription: String? {
        switch self {
        case .modelLoadingFailed(let details):
            return "Failed to load AI model: \(details)"
        case .detectionFailed(let details):
            return "Detection error: \(details)"
        case .coreDataError(let details):
            return "Database error: \(details)"
        case .cameraAccessDenied:
            return "Camera access is required for this app"
        case .memoryPressure:
            return "Low memory - reducing detection quality"
        case .thermalStateCritical:
            return "Device is overheating - pausing detection"
        case .storageError(let details):
            return "Storage error: \(details)"
        case .networkError(let details):
            return "Network error: \(details)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .modelLoadingFailed:
            return "Please reinstall the app or contact support"
        case .detectionFailed:
            return "Try restarting the app"
        case .coreDataError:
            return "Try clearing app data in Settings"
        case .cameraAccessDenied:
            return "Enable camera access in Settings > Privacy > Camera"
        case .memoryPressure:
            return "Close other apps to free up memory"
        case .thermalStateCritical:
            return "Let your device cool down"
        case .storageError:
            return "Free up storage space on your device"
        case .networkError:
            return "Check your internet connection"
        }
    }
    
    var severity: ErrorSeverity {
        switch self {
        case .modelLoadingFailed, .cameraAccessDenied:
            return .critical
        case .detectionFailed, .coreDataError, .storageError, .networkError:
            return .error
        case .memoryPressure, .thermalStateCritical:
            return .warning
        }
    }
}

enum ErrorSeverity {
    case warning
    case error
    case critical
    
    var color: Color {
        switch self {
        case .warning: return .orange
        case .error: return .red
        case .critical: return .purple
        }
    }
    
    var icon: String {
        switch self {
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.circle"
        case .critical: return "exclamationmark.octagon"
        }
    }
}

// MARK: - Error Manager
@MainActor
class ErrorManager: ObservableObject {
    static let shared = ErrorManager()
    
    @Published var currentError: AppError?
    @Published var showError = false
    @Published var errorHistory: [ErrorRecord] = []
    
    private let maxHistorySize = 50
    
    private init() {}
    
    // MARK: - Error Handling
    func handle(_ error: Error, context: String? = nil) {
        // Convert to AppError if needed
        let appError: AppError
        if let err = error as? AppError {
            appError = err
        } else {
            // Map common errors
            let errorString = error.localizedDescription
            if errorString.contains("Core Data") || errorString.contains("NSManagedObject") {
                appError = .coreDataError(errorString)
            } else if errorString.contains("memory") {
                appError = .memoryPressure
            } else {
                appError = .detectionFailed(errorString)
            }
        }
        
        // Log error
        logError(appError, context: context)
        
        // Show to user if appropriate
        if appError.severity != .warning || shouldShowWarning() {
            currentError = appError
            showError = true
        }
        
        // Take automatic recovery actions
        performAutomaticRecovery(for: appError)
    }
    
    func handleSilently(_ error: Error, context: String? = nil) {
        // Log without showing to user
        if let appError = error as? AppError {
            logError(appError, context: context)
            performAutomaticRecovery(for: appError)
        }
    }
    
    // MARK: - Error Logging
    private func logError(_ error: AppError, context: String?) {
        let record = ErrorRecord(
            error: error,
            context: context,
            timestamp: Date()
        )
        
        errorHistory.append(record)
        
        // Trim history if needed
        if errorHistory.count > maxHistorySize {
            errorHistory.removeFirst(errorHistory.count - maxHistorySize)
        }
        
        // Log to console
        print("❌ [\(error.severity)] \(error.localizedDescription) - Context: \(context ?? "none")")
    }
    
    // MARK: - Recovery Actions
    private func performAutomaticRecovery(for error: AppError) {
        switch error {
        case .memoryPressure:
            // Notify components to reduce memory usage
            NotificationCenter.default.post(
                name: .memoryPressureDetected,
                object: nil
            )
            
        case .thermalStateCritical:
            // Notify components to reduce processing
            NotificationCenter.default.post(
                name: .thermalThrottlingRequired,
                object: nil
            )
            
        case .coreDataError:
            // Attempt to reset Core Data context
            CoreDataManager.shared.context.reset()
            
        default:
            break
        }
    }
    
    private func shouldShowWarning() -> Bool {
        // Don't spam warnings - show max 1 per minute
        let recentWarnings = errorHistory.filter {
            $0.error.severity == .warning &&
            $0.timestamp.timeIntervalSinceNow > -60
        }
        return recentWarnings.count < 2
    }
    
    // MARK: - Error Dismissal
    func dismissError() {
        showError = false
        currentError = nil
    }
    
    // MARK: - Error Statistics
    func getErrorStatistics() -> ErrorStatistics {
        let now = Date()
        let last24Hours = errorHistory.filter {
            $0.timestamp.timeIntervalSince(now) > -86400
        }
        
        let byType = Dictionary(grouping: last24Hours) { $0.error.severity }
        
        return ErrorStatistics(
            totalErrors: errorHistory.count,
            last24HourErrors: last24Hours.count,
            warningCount: byType[.warning]?.count ?? 0,
            errorCount: byType[.error]?.count ?? 0,
            criticalCount: byType[.critical]?.count ?? 0
        )
    }
}

// MARK: - Supporting Types
struct ErrorRecord: Identifiable {
    let id = UUID()
    let error: AppError
    let context: String?
    let timestamp: Date
}

struct ErrorStatistics {
    let totalErrors: Int
    let last24HourErrors: Int
    let warningCount: Int
    let errorCount: Int
    let criticalCount: Int
}

// MARK: - Notification Names
extension Notification.Name {
    static let memoryPressureDetected = Notification.Name("memoryPressureDetected")
    static let thermalThrottlingRequired = Notification.Name("thermalThrottlingRequired")
}

// MARK: - Error Alert View
struct ErrorAlertView: View {
    @ObservedObject var errorManager = ErrorManager.shared
    
    var body: some View {
        EmptyView()
            .alert(isPresented: $errorManager.showError) {
                guard let error = errorManager.currentError else {
                    return Alert(title: Text("Error"))
                }
                
                return Alert(
                    title: Text(severityTitle(error.severity)),
                    message: Text(error.localizedDescription),
                    primaryButton: .default(Text("OK")) {
                        errorManager.dismissError()
                    },
                    secondaryButton: .default(Text("Help")) {
                        // Show recovery suggestion
                        if let suggestion = error.recoverySuggestion {
                            print("Recovery: \(suggestion)")
                        }
                    }
                )
            }
    }
    
    private func severityTitle(_ severity: ErrorSeverity) -> String {
        switch severity {
        case .warning: return "Warning"
        case .error: return "Error"
        case .critical: return "Critical Error"
        }
    }
}