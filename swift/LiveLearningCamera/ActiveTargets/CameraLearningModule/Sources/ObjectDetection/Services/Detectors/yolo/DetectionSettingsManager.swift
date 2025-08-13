//
//  DetectionSettingsManager.swift
//  LiveLearningCamera
//
//  Manager for detection settings and user preferences
//

import SwiftUI

public class DetectionSettingsManager: ObservableObject {
    @Published public var useCOCOLabels: Bool {
        didSet {
            UserDefaults.standard.set(useCOCOLabels, forKey: "useCOCOLabels")
        }
    }
    
    @Published public var showClassification: Bool = true {
        didSet {
            UserDefaults.standard.set(showClassification, forKey: "showClassification")
        }
    }
    
    @Published public var confidenceThreshold: Float {
        didSet {
            UserDefaults.standard.set(confidenceThreshold, forKey: "confidenceThreshold")
        }
    }
    
    @Published public var showConfidence: Bool {
        didSet {
            UserDefaults.standard.set(showConfidence, forKey: "showConfidence")
        }
    }
    
    @Published public var showFPS: Bool {
        didSet {
            UserDefaults.standard.set(showFPS, forKey: "showFPS")
        }
    }
    
    @Published public var enabledClasses: Set<Int> = Set(0...79) {
        didSet {
            UserDefaults.standard.set(Array(enabledClasses), forKey: "enabledClasses")
        }
    }
    
    @Published public var useClassFilter: Bool = false {
        didSet {
            UserDefaults.standard.set(useClassFilter, forKey: "useClassFilter")
        }
    }
    
    @Published public var captureInterval: TimeInterval = 1.0 {
        didSet {
            UserDefaults.standard.set(captureInterval, forKey: "captureInterval")
        }
    }
    
    @Published public var enableDeduplication: Bool = true {
        didSet {
            UserDefaults.standard.set(enableDeduplication, forKey: "enableDeduplication")
        }
    }
    
    @Published public var enableHandTracking: Bool = true {
        didSet {
            UserDefaults.standard.set(enableHandTracking, forKey: "enableHandTracking")
        }
    }
    
    @Published public var maxHandCount: Int = 2 {
        didSet {
            UserDefaults.standard.set(maxHandCount, forKey: "maxHandCount")
        }
    }
    
    @Published public var showHandGestures: Bool = true {
        didSet {
            UserDefaults.standard.set(showHandGestures, forKey: "showHandGestures")
        }
    }
    
    @Published public var showHandLandmarks: Bool = true {
        didSet {
            UserDefaults.standard.set(showHandLandmarks, forKey: "showHandLandmarks")
        }
    }
    
    public static let shared = DetectionSettingsManager()
    
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
