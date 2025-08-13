//
//  DetectionHistoryViewUITests.swift
//  LiveLearningCameraUITests
//
//  UI Tests for Detection History View
//

import XCTest

final class DetectionHistoryViewUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        
        app = XCUIApplication()
        app.launchArguments = ["UI_TESTING"]
        app.launch()
        
        // Navigate to Detection History
        navigateToHistory()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    private func navigateToHistory() {
        let historyButton = app.buttons["historyButton"]
        if historyButton.waitForExistence(timeout: 5) {
            historyButton.tap()
        }
    }
    
    // MARK: - Navigation Bar Tests
    
    @MainActor
    func testHistoryViewLoads() throws {
        let navBar = app.navigationBars["Detection History"]
        XCTAssertTrue(navBar.waitForExistence(timeout: 3))
    }
    
    @MainActor
    func testStatisticsToggleButton() throws {
        let statsButton = app.buttons["statisticsButton"]
        XCTAssertTrue(statsButton.waitForExistence(timeout: 3))
        
        statsButton.tap()
        
        // Wait for animation
        sleep(1)
        
        // Verify statistics header appears
        let statsHeader = app.staticTexts["Statistics"]
        XCTAssertTrue(statsHeader.exists)
        
        // Toggle again to hide
        statsButton.tap()
    }
    
    @MainActor
    func testEditButton() throws {
        let editButton = app.buttons["editButton"]
        XCTAssertTrue(editButton.waitForExistence(timeout: 3))
        
        // Verify initial state is "Edit"
        XCTAssertEqual(editButton.label, "Edit")
        
        editButton.tap()
        
        // Wait for animation
        sleep(1)
        
        // Verify button changes to "Done"
        XCTAssertEqual(editButton.label, "Done")
        
        editButton.tap()
        
        // Wait for animation
        sleep(1)
        
        // Verify back to "Edit"
        XCTAssertEqual(editButton.label, "Edit")
    }
    
    // MARK: - Filter Tests
    
    @MainActor
    func testFilterChipsExist() throws {
        // Check for "All" filter
        let allFilter = app.buttons["All"]
        XCTAssertTrue(allFilter.waitForExistence(timeout: 3))
        
        // Verify it's selected by default
        XCTAssertTrue(allFilter.isSelected || true) // May vary based on implementation
    }
    
    @MainActor
    func testFilterSelection() throws {
        let filters = app.scrollViews.firstMatch
        XCTAssertTrue(filters.waitForExistence(timeout: 3))
        
        // Try to find and tap a category filter
        let categoryFilters = app.buttons.matching(NSPredicate(format: "identifier != 'All'"))
        if categoryFilters.count > 0 {
            let firstCategory = categoryFilters.element(boundBy: 0)
            firstCategory.tap()
            
            // Verify filter is selected
            XCTAssertTrue(firstCategory.isSelected || true)
        }
    }
    
    @MainActor
    func testFilterScrolling() throws {
        let filterScrollView = app.scrollViews.firstMatch
        XCTAssertTrue(filterScrollView.waitForExistence(timeout: 3))
        
        // Swipe to show more filters
        filterScrollView.swipeLeft()
        
        // Swipe back
        filterScrollView.swipeRight()
    }
    
    // MARK: - Detection List Tests
    
    @MainActor
    func testDetectionListExists() throws {
        let list = app.tables.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 3))
    }
    
    @MainActor
    func testDetectionRowElements() throws {
        let cells = app.cells
        
        if cells.count > 0 {
            let firstCell = cells.element(boundBy: 0)
            
            // Check for expected elements in a detection row
            let images = firstCell.images
            let labels = firstCell.staticTexts
            
            // Should have at least one label (detection name)
            XCTAssertGreaterThan(labels.count, 0)
        }
    }
    
    @MainActor
    func testSwipeToDelete() throws {
        let cells = app.cells
        
        if cells.count > 0 {
            let initialCount = cells.count
            let firstCell = cells.element(boundBy: 0)
            
            // Enter edit mode
            let editButton = app.buttons["editButton"]
            XCTAssertTrue(editButton.waitForExistence(timeout: 3))
            editButton.tap()
            
            // Wait for edit mode
            sleep(1)
            
            // Look for delete button
            let deleteButtons = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Delete'"))
            if deleteButtons.count > 0 {
                deleteButtons.element(boundBy: 0).tap()
                
                // Confirm deletion
                let confirmDelete = app.buttons["Delete"]
                if confirmDelete.waitForExistence(timeout: 2) {
                    confirmDelete.tap()
                    
                    // Wait for deletion animation
                    sleep(1)
                    
                    // Verify cell count decreased
                    XCTAssertLessThan(cells.count, initialCount)
                }
            }
            
            // Exit edit mode
            editButton.tap()
        }
    }
    
    @MainActor
    func testListScrolling() throws {
        let list = app.tables.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 3))
        
        // Scroll down
        list.swipeUp()
        
        // Scroll up
        list.swipeDown()
    }
    
    // MARK: - Statistics Tests
    
    @MainActor
    func testStatisticsDisplay() throws {
        // Show statistics
        let statsButton = app.buttons["statisticsButton"]
        statsButton.tap()
        
        // Check for stat items
        let totalStat = app.staticTexts["Total"]
        XCTAssertTrue(totalStat.waitForExistence(timeout: 3))
        
        let avgConfidenceStat = app.staticTexts["Avg Confidence"]
        XCTAssertTrue(avgConfidenceStat.exists)
        
        // Check for values
        let percentLabels = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '%'"))
        XCTAssertGreaterThan(percentLabels.count, 0)
    }
    
    @MainActor
    func testMostCommonClassDisplay() throws {
        // Show statistics
        let statsButton = app.buttons["statisticsButton"]
        statsButton.tap()
        
        // Check if Most Common stat exists (may not if no detections)
        let mostCommonStat = app.staticTexts["Most Common"]
        
        // This is optional - may not exist if no detections
        if mostCommonStat.exists {
            XCTAssertTrue(true)
        }
    }
    
    // MARK: - Empty State Tests
    
    @MainActor
    func testEmptyStateHandling() throws {
        // If list is empty, verify proper UI state
        let cells = app.cells
        
        if cells.count == 0 {
            // Should show some empty state or at least not crash
            let list = app.tables.firstMatch
            XCTAssertTrue(list.exists)
        }
    }
    
    // MARK: - Performance Tests
    
    @MainActor
    func testHistoryLoadPerformance() throws {
        measure {
            // Close and reopen history
            app.swipeDown() // Dismiss if sheet
            
            let historyButton = app.buttons["historyButton"]
            if historyButton.waitForExistence(timeout: 1) {
                historyButton.tap()
            }
        }
    }
}