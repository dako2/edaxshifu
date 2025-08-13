//
//  DetectionSettingsManager.swift
//  LiveLearningCamera
//
//  Manager for detection settings and user preferences
//

import SwiftUI

class DetectionSettingsManager: ObservableObject {
    @Published var useCOCOLabels: Bool {
        didSet {
            UserDefaults.standard.set(useCOCOLabels, forKey: "useCOCOLabels")
        }
    }
    
    @Published var showClassification: Bool = true {
        didSet {
            UserDefaults.standard.set(showClassification, forKey: "showClassification")
        }
    }
    
    @Published var confidenceThreshold: Float {
        didSet {
            UserDefaults.standard.set(confidenceThreshold, forKey: "confidenceThreshold")
        }
    }
    
    @Published var showConfidence: Bool {
        didSet {
            UserDefaults.standard.set(showConfidence, forKey: "showConfidence")
        }
    }
    
    @Published var showFPS: Bool {
        didSet {
            UserDefaults.standard.set(showFPS, forKey: "showFPS")
        }
    }
    
    @Published var enabledClasses: Set<Int> = Set(0...79) {
        didSet {
            UserDefaults.standard.set(Array(enabledClasses), forKey: "enabledClasses")
        }
    }
    
    @Published var useClassFilter: Bool = false {
        didSet {
            UserDefaults.standard.set(useClassFilter, forKey: "useClassFilter")
        }
    }
    
    @Published var captureInterval: TimeInterval = 1.0 {
        didSet {
            UserDefaults.standard.set(captureInterval, forKey: "captureInterval")
        }
    }
    
    @Published var enableDeduplication: Bool = true {
        didSet {
            UserDefaults.standard.set(enableDeduplication, forKey: "enableDeduplication")
        }
    }
    
    @Published var enableHandTracking: Bool = true {
        didSet {
            UserDefaults.standard.set(enableHandTracking, forKey: "enableHandTracking")
        }
    }
    
    @Published var maxHandCount: Int = 2 {
        didSet {
            UserDefaults.standard.set(maxHandCount, forKey: "maxHandCount")
        }
    }
    
    @Published var showHandGestures: Bool = true {
        didSet {
            UserDefaults.standard.set(showHandGestures, forKey: "showHandGestures")
        }
    }
    
    @Published var showHandLandmarks: Bool = true {
        didSet {
            UserDefaults.standard.set(showHandLandmarks, forKey: "showHandLandmarks")
        }
    }
    
    static let shared = DetectionSettingsManager()
    
    private init() {
        self.useCOCOLabels = UserDefaults.standard.object(forKey: "useCOCOLabels") as? Bool ?? true
        self.showClassification = UserDefaults.standard.object(forKey: "showClassification") as? Bool ?? true
        self.confidenceThreshold = UserDefaults.standard.object(forKey: "confidenceThreshold") as? Float ?? 0.25
        self.showConfidence = UserDefaults.standard.object(forKey: "showConfidence") as? Bool ?? true
        self.showFPS = UserDefaults.standard.object(forKey: "showFPS") as? Bool ?? true
        self.captureInterval = UserDefaults.standard.object(forKey: "captureInterval") as? TimeInterval ?? 1.0
        self.enableDeduplication = UserDefaults.standard.object(forKey: "enableDeduplication") as? Bool ?? true
        self.enableHandTracking = UserDefaults.standard.object(forKey: "enableHandTracking") as? Bool ?? true
        self.maxHandCount = UserDefaults.standard.object(forKey: "maxHandCount") as? Int ?? 2
        self.showHandGestures = UserDefaults.standard.object(forKey: "showHandGestures") as? Bool ?? true
        self.showHandLandmarks = UserDefaults.standard.object(forKey: "showHandLandmarks") as? Bool ?? true
        self.loadClassFilter()
    }
}

// Settings view moved to Views/SettingsView.swift
