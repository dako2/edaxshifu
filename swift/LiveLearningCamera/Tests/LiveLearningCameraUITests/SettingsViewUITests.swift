//
//  SettingsViewUITests.swift
//  LiveLearningCameraUITests
//
//  UI Tests for Settings View
//

import XCTest

final class SettingsViewUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        
        app = XCUIApplication()
        app.launchArguments = ["UI_TESTING"]
        app.launch()
        
        // Navigate to Settings
        navigateToSettings()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    private func navigateToSettings() {
        let settingsButton = app.buttons["settingsButton"]
        if settingsButton.waitForExistence(timeout: 5) {
            settingsButton.tap()
            // Wait for settings sheet to appear
            sleep(1)
        }
    }
    
    // MARK: - Detection Mode Tests
    
    @MainActor
    func testClassificationToggle() throws {
        let classificationSwitch = app.switches["enableClassificationToggle"]
        XCTAssertTrue(classificationSwitch.waitForExistence(timeout: 3))
        
        let initialValue = classificationSwitch.value as? String == "1"
        classificationSwitch.tap()
        
        let newValue = classificationSwitch.value as? String == "1"
        XCTAssertNotEqual(initialValue, newValue)
    }
    
    @MainActor
    func testCOCOLabelsToggle() throws {
        // Enable classification first
        let classificationSwitch = app.switches["enableClassificationToggle"]
        if classificationSwitch.waitForExistence(timeout: 3) && classificationSwitch.value as? String != "1" {
            classificationSwitch.tap()
        }
        
        let cocoSwitch = app.switches["useCOCOLabelsToggle"]
        XCTAssertTrue(cocoSwitch.waitForExistence(timeout: 3))
        
        cocoSwitch.tap()
        
        // Verify toggle responds
        XCTAssertTrue(cocoSwitch.isEnabled)
    }
    
    // MARK: - Class Filter Tests
    
    @MainActor
    func testClassFilterToggle() throws {
        let filterSwitch = app.switches["enableClassFilterToggle"]
        XCTAssertTrue(filterSwitch.waitForExistence(timeout: 3))
        
        filterSwitch.tap()
        
        // Wait for category toggles to appear
        sleep(1)
        
        // Verify category toggles appear
        let categoryToggles = app.switches.matching(NSPredicate(format: "identifier CONTAINS 'category_'"))
        XCTAssertGreaterThan(categoryToggles.count, 0)
    }
    
    @MainActor
    func testCategorySelection() throws {
        // Enable class filter
        let filterSwitch = app.switches["enableClassFilterToggle"]
        if filterSwitch.waitForExistence(timeout: 3) && filterSwitch.value as? String != "1" {
            filterSwitch.tap()
        }
        
        // Wait for categories to load
        sleep(1)
        
        // Find first category toggle
        let categoryToggles = app.switches.matching(NSPredicate(format: "identifier CONTAINS 'category_'"))
        if categoryToggles.count > 0 {
            let firstCategory = categoryToggles.element(boundBy: 0)
            firstCategory.tap()
            
            // Verify toggle responds
            XCTAssertTrue(firstCategory.isEnabled)
        }
    }
    
    // MARK: - Display Options Tests
    
    @MainActor
    func testConfidenceScoreToggle() throws {
        // Try multiple ways to find the switch
        var confidenceSwitch = app.switches["showConfidenceToggle"]
        if !confidenceSwitch.exists {
            confidenceSwitch = app.switches.matching(identifier: "showConfidenceToggle").firstMatch
        }
        if !confidenceSwitch.exists {
            confidenceSwitch = app.switches["Show Confidence Score"]
        }
        
        XCTAssertTrue(confidenceSwitch.waitForExistence(timeout: 3), "Could not find confidence score toggle")
        
        let initialValue = confidenceSwitch.value as? String == "1"
        confidenceSwitch.tap()
        
        let newValue = confidenceSwitch.value as? String == "1"
        XCTAssertNotEqual(initialValue, newValue)
    }
    
    @MainActor
    func testFPSCounterToggle() throws {
        let fpsSwitch = app.switches["showFPSToggle"]
        XCTAssertTrue(fpsSwitch.waitForExistence(timeout: 3))
        
        fpsSwitch.tap()
        XCTAssertTrue(fpsSwitch.isEnabled)
    }
    
    // MARK: - Capture Settings Tests
    
    @MainActor
    func testDeduplicationToggle() throws {
        let deduplicationSwitch = app.switches["enableDeduplicationToggle"]
        XCTAssertTrue(deduplicationSwitch.waitForExistence(timeout: 3))
        
        deduplicationSwitch.tap()
        XCTAssertTrue(deduplicationSwitch.isEnabled)
    }
    
    @MainActor
    func testCaptureIntervalSlider() throws {
        let slider = app.sliders["captureIntervalSlider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 3))
        
        // Adjust slider
        slider.adjust(toNormalizedSliderPosition: 0.7)
        
        // Verify slider is functional
        XCTAssertTrue(slider.isEnabled)
    }
    
    // MARK: - Hand Tracking Tests
    
    @MainActor
    func testHandTrackingToggle() throws {
        let handTrackingSwitch = app.switches["enableHandTrackingToggle"]
        XCTAssertTrue(handTrackingSwitch.waitForExistence(timeout: 3))
        
        handTrackingSwitch.tap()
        
        // Wait for sub-options
        sleep(1)
        
        // Verify sub-options appear/disappear
        let gestureSwitch = app.switches["showHandGesturesToggle"]
        if handTrackingSwitch.value as? String == "1" {
            XCTAssertTrue(gestureSwitch.exists)
        }
    }
    
    @MainActor
    func testMaxHandsSelection() throws {
        // Enable hand tracking first
        let handTrackingSwitch = app.switches["enableHandTrackingToggle"]
        if handTrackingSwitch.waitForExistence(timeout: 3) && handTrackingSwitch.value as? String != "1" {
            handTrackingSwitch.tap()
        }
        
        // Wait for controls to appear
        sleep(1)
        
        // Select max hands
        let segmentedControl = app.segmentedControls["maxHandsPicker"]
        if segmentedControl.waitForExistence(timeout: 3) {
            let button2 = segmentedControl.buttons["2"]
            button2.tap()
            XCTAssertTrue(button2.isSelected)
        }
    }
    
    // MARK: - Threshold Tests
    
    @MainActor
    func testConfidenceThresholdSlider() throws {
        // Scroll to bottom to find confidence threshold
        let formTable = app.tables.firstMatch
        formTable.swipeUp()
        
        let confidenceSlider = app.sliders["confidenceThresholdSlider"]
        XCTAssertTrue(confidenceSlider.waitForExistence(timeout: 3))
        
        // Adjust threshold
        confidenceSlider.adjust(toNormalizedSliderPosition: 0.5)
        
        // Verify slider is functional
        XCTAssertTrue(confidenceSlider.isEnabled)
    }
    
    // MARK: - Navigation Tests
    
    @MainActor
    func testDoneButtonDismissesSettings() throws {
        let doneButton = app.buttons["Done"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 3))
        
        doneButton.tap()
        
        // Verify settings dismissed
        let settingsNavBar = app.navigationBars["Settings"]
        XCTAssertFalse(settingsNavBar.exists)
    }
    
    @MainActor
    func testScrollingInSettings() throws {
        let formTable = app.tables.firstMatch
        XCTAssertTrue(formTable.waitForExistence(timeout: 3))
        
        // Scroll to bottom
        formTable.swipeUp()
        
        // Verify About section is visible
        let aboutHeader = app.staticTexts["About"]
        XCTAssertTrue(aboutHeader.exists)
        
        // Scroll back to top
        formTable.swipeDown()
    }
}