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
        XCTAssertTrue(app.buttons["Watched"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["UI Test Watched Movie"].exists)

        let movieTile = app.buttons["UI Test Movie"]
        XCTAssertTrue(movieTile.waitForExistence(timeout: 5))
        movieTile.tap()

        XCTAssertTrue(app.buttons["Remove from watchlist"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Mark as watched"].exists)
        if app.buttons["Close"].exists {
            app.buttons["Close"].tap()
        }

        movieTile.press(forDuration: 1)
        XCTAssertTrue(app.buttons["Mark as Watched"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Remove from Watchlist"].exists)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()

        showsTab.tap()
        XCTAssertTrue(app.buttons["UI Test Show, Season 1 Episode 2, Continue Watching"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Coming Up"].exists)
        XCTAssertTrue(app.staticTexts["2 days"].exists)

        app.buttons["Continue Watching"].tap()
        XCTAssertTrue(app.staticTexts["UI Test Show"].waitForExistence(timeout: 5))

        searchTab.tap()
        XCTAssertTrue(app.navigationBars["Search"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testWatchlistMovieDoubleTapMarksWatched() throws {
        let app = XCUIApplication()
        app.launchArguments.append("UITEST_MODE")
        app.launch()

        let movieTile = app.buttons["UI Test Movie"]
        XCTAssertTrue(movieTile.waitForExistence(timeout: 5))
        movieTile.doubleTap()

        let feedback = app.descendants(matching: .any)["TransientFeedbackHUD"]
        XCTAssertTrue(feedback.waitForExistence(timeout: 5))
        XCTAssertEqual(feedback.label, "UI Test Movie marked watched")
        XCTAssertTrue(app.staticTexts["Nothing to watch"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testWatchFeedbackSupportsAccessibilityTextSize() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "UITEST_MODE",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        ]
        app.launch()

        let movieTile = app.buttons["UI Test Movie"]
        XCTAssertTrue(movieTile.waitForExistence(timeout: 5))
        movieTile.doubleTap()

        let feedback = app.descendants(matching: .any)["TransientFeedbackHUD"]
        XCTAssertTrue(feedback.waitForExistence(timeout: 5))
        XCTAssertEqual(feedback.label, "UI Test Movie marked watched")
    }

    @MainActor
    func testSyncDiagnosticsAtStandardTextSize() throws {
        try verifySyncDiagnostics(contentSize: "UICTContentSizeCategoryL")
    }

    @MainActor
    func testSyncDiagnosticsAtAccessibilityTextSize() throws {
        try verifySyncDiagnostics(contentSize: "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge")
    }

    @MainActor
    private func verifySyncDiagnostics(contentSize: String) throws {
        let app = XCUIApplication()
        app.launchArguments += ["UITEST_MODE", "-UIPreferredContentSizeCategoryName", contentSize]
        if contentSize.contains("Accessibility") { app.launchArguments.append("UITEST_ACCESSIBILITY_TEXT") }
        app.launch()
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        let cloud = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'iCloud Sync,'")).firstMatch
        for _ in 0..<6 {
            if cloud.exists { break }
            app.swipeUp()
        }
        XCTAssertTrue(cloud.waitForExistence(timeout: 5))
        cloud.tap()
        XCTAssertTrue(app.navigationBars["Sync Diagnostics"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["iCloud"].exists)
        let status = XCTAttachment(screenshot: app.screenshot())
        status.name = "Sync status - " + contentSize
        status.lifetime = .keepAlways
        add(status)
        let recovery = app.buttons["Recover Pending Uploads on This Device"]
        for _ in 0..<8 {
            if recovery.exists, recovery.frame.midY > app.frame.minY + 100,
               recovery.frame.midY < app.frame.maxY - 100 { break }
            app.swipeUp()
        }
        XCTAssertTrue(recovery.exists)
        XCTAssertFalse(recovery.isEnabled)
        let maintenance = XCTAttachment(screenshot: app.screenshot())
        maintenance.name = "Sync maintenance - " + contentSize
        maintenance.lifetime = .keepAlways
        add(maintenance)
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
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Appearance,'")).firstMatch.tap()
        XCTAssertTrue(app.buttons["System"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Light"].exists)
        XCTAssertTrue(app.buttons["Dark"].exists)
    }

    @MainActor
    func testAboutLightStandard() throws {
        try verifyAbout(theme: "light", accessibility: false)
    }

    @MainActor
    func testAboutDarkStandard() throws {
        try verifyAbout(theme: "dark", accessibility: false)
    }

    @MainActor
    func testAboutLightAccessibility() throws {
        try verifyAbout(theme: "light", accessibility: true)
    }

    @MainActor
    func testAboutDarkAccessibility() throws {
        try verifyAbout(theme: "dark", accessibility: true)
    }

    @MainActor
    private func verifyAbout(theme: String, accessibility: Bool) throws {
        let app = XCUIApplication()
        app.launchArguments += ["UITEST_MODE", "-appTheme", theme == "dark" ? "2" : "1"]
        if accessibility {
            app.launchArguments += ["UITEST_ACCESSIBILITY_TEXT",
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"]
        }
        app.launch()
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        let about = app.buttons["About"]
        for _ in 0..<6 {
            if about.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(about.isHittable)
        about.tap()
        XCTAssertTrue(app.navigationBars["About"].waitForExistence(timeout: 5))
        let identity = XCTAttachment(screenshot: app.screenshot())
        identity.name = "About identity - \(theme) - \(accessibility ? "accessibility" : "standard")"
        identity.lifetime = .keepAlways
        add(identity)

        for label in ["The Movie Database (TMDB)", "Trakt", "Privacy Policy", "Support"] {
            let link = app.buttons[label]
            for _ in 0..<8 {
                if link.isHittable { break }
                app.swipeUp()
            }
            XCTAssertTrue(link.isHittable, "About link must remain reachable: " + label)
        }
        let links = XCTAttachment(screenshot: app.screenshot())
        links.name = "About links - \(theme) - \(accessibility ? "accessibility" : "standard")"
        links.lifetime = .keepAlways
        add(links)
    }

}
