//
//  iWatchUITests.swift
//  iWatchUITests
//
//  Created by Tyler Keegan on 8/15/25.
//

import XCTest

final class iWatchUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testLaunchTabsAndMovieDetail() throws {
        let app = XCUIApplication()
        app.launchArguments.append("UITEST_MODE")
        app.launch()

        let moviesTab = app.tabBars.buttons["Movies"]
        let showsTab = app.tabBars.buttons["Shows"]
        let searchTab = app.tabBars.buttons["Search"]

        XCTAssertTrue(moviesTab.waitForExistence(timeout: 5))
        XCTAssertTrue(showsTab.exists)
        XCTAssertTrue(searchTab.exists)

        let movieTitle = app.staticTexts["UI Test Movie"]
        XCTAssertTrue(movieTitle.waitForExistence(timeout: 5))
        movieTitle.tap()

        XCTAssertTrue(app.buttons["Following"].waitForExistence(timeout: 5))
        if app.buttons["Close"].exists {
            app.buttons["Close"].tap()
        }

        showsTab.tap()
        XCTAssertTrue(app.staticTexts["UI Test Show"].waitForExistence(timeout: 5))

        searchTab.tap()
        XCTAssertTrue(app.navigationBars["Search"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSettingsNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments.append("UITEST_MODE")
        app.launch()

        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Preferences"].exists)
        XCTAssertTrue(app.staticTexts["Sync"].exists)

        app.buttons["Trakt, Not Connected"].tap()
        XCTAssertTrue(app.navigationBars["Trakt"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Connect Trakt"].exists)

        app.navigationBars["Trakt"].buttons.firstMatch.tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'App Appearance,'")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["App Appearance"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["System"].exists)
        XCTAssertTrue(app.staticTexts["Light"].exists)
        XCTAssertTrue(app.staticTexts["Dark"].exists)
    }

}
