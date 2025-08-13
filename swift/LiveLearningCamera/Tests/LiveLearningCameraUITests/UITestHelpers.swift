//
//  UITestHelpers.swift
//  LiveLearningCameraUITests
//
//  Helper utilities for UI testing
//

import XCTest

extension XCUIElement {
    
    /// Wait for element to exist with custom timeout
    func waitForExistenceWithTimeout(_ timeout: TimeInterval = 5) -> Bool {
        return self.waitForExistence(timeout: timeout)
    }
    
    /// Check if element is visible on screen
    var isVisible: Bool {
        return self.exists && self.isHittable
    }
    
    /// Tap element if it exists
    func tapIfExists() {
        if self.exists {
            self.tap()
        }
    }
    
    /// Clear text field and type new text
    func clearAndTypeText(_ text: String) {
        guard let stringValue = self.value as? String else {
            XCTFail("Tried to clear and type text into a non-text element")
            return
        }
        
        self.tap()
        
        // Select all and delete
        if stringValue.count > 0 {
            self.press(forDuration: 1.0)
            if let selectAll = self.menuItems["Select All"].exists ? self.menuItems["Select All"] : nil {
                selectAll.tap()
            }
            self.typeText(XCUIKeyboardKey.delete.rawValue)
        }
        self.typeText(text)
    }
}

extension XCUIApplication {
    
    /// Launch app with test configuration
    func launchForUITesting() {
        self.launchArguments = ["UI_TESTING"]
        self.launchArguments.append("-AppleLanguages")
        self.launchArguments.append("(en)")
        self.launchArguments.append("-AppleLocale")
        self.launchArguments.append("en_US")
        self.launch()
    }
    
    /// Dismiss keyboard if visible
    func dismissKeyboard() {
        if self.keyboards.count > 0 {
            self.toolbars["Toolbar"].buttons["Done"].tapIfExists()
            
            // Fallback: tap outside keyboard
            if self.keyboards.count > 0 {
                self.tap()
            }
        }
    }
    
    /// Take screenshot with description
    func takeScreenshotWithDescription(_ description: String) {
        let screenshot = self.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = description
        attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: "Screenshot: \(description)") { activity in
            activity.add(attachment)
        }
    }
}

/// Test data helpers
struct TestData {
    
    static let timeout: TimeInterval = 5.0
    static let shortTimeout: TimeInterval = 2.0
    static let longTimeout: TimeInterval = 10.0
    
    static let sampleDetectionClasses = [
        "person", "dog", "cat", "car", "bicycle",
        "bird", "horse", "sheep", "cow", "elephant"
    ]
    
    static func randomClass() -> String {
        return sampleDetectionClasses.randomElement() ?? "object"
    }
}

/// Performance test helpers
class PerformanceTestHelper {
    
    static func measureAppLaunch(app: XCUIApplication, iterations: Int = 5) -> [TimeInterval] {
        var measurements: [TimeInterval] = []
        
        for _ in 0..<iterations {
            let startTime = Date()
            app.launch()
            _ = app.buttons.firstMatch.waitForExistence(timeout: 10)
            let endTime = Date()
            
            measurements.append(endTime.timeIntervalSince(startTime))
            app.terminate()
        }
        
        return measurements
    }
    
    static func averageTime(measurements: [TimeInterval]) -> TimeInterval {
        return measurements.reduce(0, +) / Double(measurements.count)
    }
}

/// Accessibility test helpers
class AccessibilityTestHelper {
    
    static func verifyAccessibilityIdentifiers(in app: XCUIApplication) {
        let requiredIdentifiers = [
            "cameraPreview",
            "settingsButton",
            "historyButton",
            "recordButton",
            "switchCameraButton",
            "analyticsButton"
        ]
        
        for identifier in requiredIdentifiers {
            let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
            XCTAssertTrue(element.exists, "Missing accessibility identifier: \(identifier)")
        }
    }
    
    static func verifyVoiceOverLabels(in app: XCUIApplication) {
        // Check that important buttons have labels
        let buttons = app.buttons.allElementsBoundByIndex
        for button in buttons {
            if button.exists {
                XCTAssertNotNil(button.label, "Button missing accessibility label")
            }
        }
    }
}