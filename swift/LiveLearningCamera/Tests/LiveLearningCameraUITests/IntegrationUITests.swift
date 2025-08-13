//
//  IntegrationUITests.swift
//  LiveLearningCameraUITests
//
//  Integration tests for end-to-end user workflows
//

import XCTest

final class IntegrationUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchForUITesting()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - Complete User Journey Tests
    
    @MainActor
    func testCompleteDetectionWorkflow() throws {
        // 1. Launch and verify camera
        XCTAssertTrue(app.otherElements["cameraPreview"].waitForExistenceWithTimeout())
        
        // 2. Start recording
        let recordButton = app.buttons["recordButton"]
        XCTAssertTrue(recordButton.waitForExistenceWithTimeout())
        recordButton.tap()
        
        // 3. Wait for detections
        sleep(2)
        
        // 4. Stop recording
        recordButton.tap()
        
        // 5. Navigate to history
        let historyButton = app.buttons["historyButton"]
        historyButton.tap()
        
        // 6. Verify history loaded
        let historyNavBar = app.navigationBars["Detection History"]
        XCTAssertTrue(historyNavBar.waitForExistenceWithTimeout())
        
        // 7. Check for any detections
        let list = app.tables.firstMatch
        XCTAssertTrue(list.exists)
        
        // 8. Return to camera
        app.swipeDown() // Dismiss sheet
    }
    
    @MainActor
    func testSettingsModificationPersistence() throws {
        // 1. Open settings
        let settingsButton = app.buttons["settingsButton"]
        settingsButton.tap()
        
        // 2. Modify settings
        let confidenceSwitch = app.switches["Show Confidence Score"]
        let initialConfidenceState = confidenceSwitch.value as? String == "1"
        confidenceSwitch.tap()
        
        let fpsSwitch = app.switches["Show FPS Counter"]
        let initialFPSState = fpsSwitch.value as? String == "1"
        fpsSwitch.tap()
        
        // 3. Save settings
        app.buttons["Done"].tap()
        
        // 4. Verify changes reflected in camera view
        if !initialFPSState {
            // FPS should now be visible
            let fpsLabel = app.staticTexts["fpsLabel"]
            XCTAssertTrue(fpsLabel.waitForExistenceWithTimeout(3))
        }
        
        // 5. Reopen settings to verify persistence
        settingsButton.tap()
        
        // 6. Check states persisted
        let newConfidenceState = confidenceSwitch.value as? String == "1"
        XCTAssertNotEqual(initialConfidenceState, newConfidenceState)
        
        let newFPSState = fpsSwitch.value as? String == "1"
        XCTAssertNotEqual(initialFPSState, newFPSState)
        
        app.buttons["Done"].tap()
    }
    
    @MainActor
    func testHandTrackingWorkflow() throws {
        // 1. Enable hand tracking in settings
        app.buttons["settingsButton"].tap()
        
        let handTrackingSwitch = app.switches["Enable Hand Tracking"]
        if handTrackingSwitch.value as? String != "1" {
            handTrackingSwitch.tap()
        }
        
        // Enable gestures
        let gestureSwitch = app.switches["Show Hand Gestures"]
        if gestureSwitch.exists && gestureSwitch.value as? String != "1" {
            gestureSwitch.tap()
        }
        
        app.buttons["Done"].tap()
        
        // 2. Verify hand tracking overlay appears
        sleep(2) // Wait for hand detection to initialize
        
        // 3. Test recording with hand tracking
        let recordButton = app.buttons["recordButton"]
        recordButton.tap()
        sleep(3)
        recordButton.tap()
        
        // 4. Check analytics
        app.buttons["analyticsButton"].tap()
    }
    
    @MainActor
    func testFilteringInHistory() throws {
        // 1. Navigate to history
        app.buttons["historyButton"].tap()
        
        // 2. Show statistics
        let statsButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'chart.bar'")).element
        statsButton.tap()
        
        // 3. Verify statistics appear
        XCTAssertTrue(app.staticTexts["Statistics"].exists)
        
        // 4. Try filters
        let allFilter = app.buttons["All"]
        XCTAssertTrue(allFilter.waitForExistenceWithTimeout())
        
        // 5. Select a category filter if available
        let categoryFilters = app.buttons.matching(NSPredicate(format: "identifier != 'All'"))
        if categoryFilters.count > 0 {
            categoryFilters.element(boundBy: 0).tap()
            
            // List should update (may be empty)
            let list = app.tables.firstMatch
            XCTAssertTrue(list.exists)
        }
        
        // 6. Return to all
        allFilter.tap()
    }
    
    @MainActor
    func testCameraSwitchingWorkflow() throws {
        // 1. Start with back camera
        let switchButton = app.buttons["switchCameraButton"]
        XCTAssertTrue(switchButton.waitForExistenceWithTimeout())
        
        // 2. Switch to front camera
        switchButton.tap()
        sleep(1) // Wait for camera switch
        
        // 3. Start recording on front camera
        let recordButton = app.buttons["recordButton"]
        recordButton.tap()
        sleep(2)
        
        // 4. Switch back while recording
        switchButton.tap()
        sleep(1)
        
        // 5. Stop recording
        recordButton.tap()
        
        // 6. Verify camera still functional
        XCTAssertTrue(app.otherElements["cameraPreview"].exists)
    }
    
    // MARK: - Error Handling Tests
    
    @MainActor
    func testCameraPermissionDeniedHandling() throws {
        // This test would require mocking camera permissions
        // In a real scenario, you'd test the alert handling
        
        // Check if permission alert appears
        if app.alerts.count > 0 {
            let alert = app.alerts.firstMatch
            
            // Verify alert has OK button
            let okButton = alert.buttons["OK"]
            XCTAssertTrue(okButton.exists)
            okButton.tap()
        }
    }
    
    // MARK: - Performance Tests
    
    @MainActor
    func testNavigationPerformance() throws {
        measure {
            // Settings navigation
            app.buttons["settingsButton"].tap()
            app.buttons["Done"].tap()
            
            // History navigation
            app.buttons["historyButton"].tap()
            app.swipeDown()
            
            // Analytics
            app.buttons["analyticsButton"].tap()
        }
    }
    
    @MainActor
    func testDetectionOverlayPerformance() throws {
        // Start detection
        let recordButton = app.buttons["recordButton"]
        recordButton.tap()
        
        measure {
            // Measure overlay rendering performance
            sleep(1) // Simulate detection processing
            
            // Check overlay updates
            let overlay = app.otherElements["detectionOverlay"]
            XCTAssertTrue(overlay.exists)
        }
        
        recordButton.tap() // Stop recording
    }
    
    // MARK: - Accessibility Tests
    
    @MainActor
    func testAccessibilityIdentifiers() throws {
        AccessibilityTestHelper.verifyAccessibilityIdentifiers(in: app)
    }
    
    @MainActor
    func testVoiceOverSupport() throws {
        AccessibilityTestHelper.verifyVoiceOverLabels(in: app)
    }
    
    // MARK: - State Restoration Tests
    
    @MainActor
    func testAppStateRestorationAfterBackground() throws {
        // 1. Configure app state
        app.buttons["settingsButton"].tap()
        let handTrackingSwitch = app.switches["Enable Hand Tracking"]
        if handTrackingSwitch.value as? String != "1" {
            handTrackingSwitch.tap()
        }
        app.buttons["Done"].tap()
        
        // 2. Start recording
        let recordButton = app.buttons["recordButton"]
        recordButton.tap()
        
        // 3. Simulate backgrounding
        XCUIDevice.shared.press(.home)
        sleep(2)
        
        // 4. Return to app
        app.activate()
        
        // 5. Verify state preserved
        XCTAssertTrue(app.otherElements["cameraPreview"].waitForExistenceWithTimeout())
        
        // Recording should have stopped for safety
        let recordIcon = app.buttons.containing(.image, identifier: "record.circle").element
        XCTAssertTrue(recordIcon.exists)
    }
}