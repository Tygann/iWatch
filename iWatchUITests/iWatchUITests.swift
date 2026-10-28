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

        let status = app.buttons["Viewing status: Watchlist"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        status.tap()
        XCTAssertTrue(app.buttons["Remove from Watchlist"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Mark as Watched"].exists)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
        app.navigationBars.buttons["Movies"].tap()
        XCTAssertTrue(movieTile.waitForExistence(timeout: 5))

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
        let app = launchSyncSettings(contentSize: contentSize, state: "confirmation")
        XCTAssertFalse(app.buttons["settings-trakt-sync"].exists)
        XCTAssertFalse(app.buttons["Manage Data"].exists)
        capture(app, "Simplified settings - " + contentSize)
        app.buttons["settings-library"].tap()
        XCTAssertTrue(app.navigationBars["Your Library"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Details"].exists)
        capture(app, "Library sync overview - " + contentSize)
        let counts = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Show Progress'")).firstMatch
        reveal(counts, in: app)
        capture(app, "Library counts - " + contentSize)
        let manage = app.buttons["Manage Data"]
        reveal(manage, in: app)
        manage.tap()
        XCTAssertTrue(app.navigationBars["Manage Data"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["iCloud Diagnostics"].exists)
        capture(app, "Manage data - " + contentSize)
        app.navigationBars["Manage Data"].buttons.firstMatch.tap()
        openTrakt(in: app)
        XCTAssertFalse(app.buttons["Advanced"].exists)
        reveal(app.staticTexts["Waiting for Confirmation"], in: app)
        reveal(app.buttons["Check Again"], in: app)
        capture(app, "Contextual Trakt issue - " + contentSize)
        let pending = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Pending Changes'")).firstMatch
        reveal(pending, in: app)
        pending.tap()
        XCTAssertTrue(app.navigationBars["Pending Changes"].waitForExistence(timeout: 5))
        let episode = app.staticTexts["Example Show · S1 E1"]
        reveal(episode, in: app)
        capture(app, "Pending changes - " + contentSize)
        let help = app.buttons["Help with These Changes"]
        reveal(help, in: app)
        help.tap()
        XCTAssertTrue(app.navigationBars["Help with Changes"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Diagnostics"].exists)
        let check = app.buttons["Check Library Data"]
        reveal(check, in: app)
        check.tap()
        XCTAssertTrue(app.navigationBars["Check Library Data"].waitForExistence(timeout: 5))
        app.navigationBars["Check Library Data"].buttons.firstMatch.tap()
        let rebuild = app.buttons["Rebuild from Trakt"]
        reveal(rebuild, in: app)
        rebuild.tap()
        XCTAssertTrue(app.navigationBars["Rebuild from Trakt"].waitForExistence(timeout: 5))
        let discard = app.buttons["Rebuild from Trakt"]
        reveal(discard, in: app)
        discard.tap()
        XCTAssertTrue(app.buttons["Discard Changes and Rebuild"].waitForExistence(timeout: 5))
        capture(app, "Protected rebuild - " + contentSize)
        app.buttons["Cancel"].tap()
    }

    @MainActor
    func testSupportAtStandardTextSize() throws { verifySupport(contentSize: "UICTContentSizeCategoryL") }

    @MainActor
    func testSupportAtAccessibilityTextSize() throws { verifySupport(contentSize: "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge") }

    @MainActor
    private func verifySupport(contentSize: String) {
        let app = launchSyncSettings(contentSize: contentSize, state: "normal")
        let help = app.buttons["settings-help"]
        reveal(help, in: app)
        help.tap()
        XCTAssertTrue(app.navigationBars["Help & About"].waitForExistence(timeout: 5))
        let support = app.buttons["Contact Support"]
        reveal(support, in: app)
        capture(app, "Help and about - " + contentSize)
        support.tap()
        XCTAssertTrue(app.navigationBars["Contact Support"].waitForExistence(timeout: 5))
        let share = app.buttons["Share Diagnostic Report"]
        reveal(share, in: app)
        XCTAssertTrue(share.exists)
        capture(app, "Support report - " + contentSize)
        app.navigationBars["Contact Support"].buttons.firstMatch.tap()
        let credits = app.buttons["Acknowledgments"]
        reveal(credits, in: app)
        credits.tap()
        XCTAssertTrue(app.navigationBars["Acknowledgments"].waitForExistence(timeout: 5))
        let attribution = app.staticTexts["This product uses the TMDB API but is not endorsed or certified by TMDB."]
        reveal(attribution, in: app)
        capture(app, "Acknowledgments - " + contentSize)
    }

    @MainActor
    private func openTrakt(in app: XCUIApplication) {
        if app.navigationBars["Trakt"].exists { return }
        if !app.navigationBars["Your Library"].exists {
            let library = app.buttons["settings-library"]
            reveal(library, in: app)
            library.tap()
        }
        let trakt = app.buttons["settings-trakt"]
        reveal(trakt, in: app)
        trakt.tap()
        XCTAssertTrue(app.navigationBars["Trakt"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testTraktSetupCanStillDisconnect() throws {
        let app = launchSyncSettings(contentSize: "UICTContentSizeCategoryL", state: "setup")
        openTrakt(in: app)
        let disconnect = app.buttons["Disconnect Trakt"]
        reveal(disconnect, in: app)
        XCTAssertTrue(disconnect.waitForExistence(timeout: 5))
        XCTAssertTrue(disconnect.isEnabled)
        disconnect.tap()
        XCTAssertTrue(app.staticTexts["Disconnect Trakt?"].waitForExistence(timeout: 5))
        capture(app, "Trakt setup disconnect confirmation")
        if app.buttons["Cancel"].exists {
            app.buttons["Cancel"].tap()
        } else {
            app.navigationBars["Trakt"].tap()
        }
        XCTAssertTrue(app.navigationBars["Trakt"].exists)
    }

    @MainActor
    func testTraktConnectedAtAccessibilityTextSize() throws {
        let app = launchSyncSettings(contentSize: "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge", state: "normal")
        openTrakt(in: app)
        XCTAssertTrue(app.descendants(matching: .any)["trakt-connection"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["trakt-connection"].label.contains("Connected"))
        let sync = app.buttons["Sync Now"]
        reveal(sync, in: app)
        XCTAssertTrue(sync.isEnabled)
        XCTAssertGreaterThanOrEqual(sync.frame.height, 44)
        capture(app, "Connected Trakt - accessibility")
    }

    @MainActor
    func testSyncNormalOfflineAndSetupStates() throws {
        for state in ["normal", "offline", "syncing", "setup"] {
            let app = launchSyncSettings(contentSize: "UICTContentSizeCategoryL", state: state)
            openTrakt(in: app)
            XCTAssertTrue(app.navigationBars["Trakt"].waitForExistence(timeout: 5))
            let expected = ["normal": "Trakt", "offline": "Connection Interrupted",
                            "syncing": "Syncing…", "setup": "Finish Setup"][state]!
            if state == "normal" {
                XCTAssertTrue(app.descendants(matching: .any)["trakt-connection"].waitForExistence(timeout: 5))
                XCTAssertTrue(app.descendants(matching: .any)["trakt-connection"].label.contains("Connected"))
                XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Last Sync'")).firstMatch.exists)
                XCTAssertTrue(app.buttons["Sync Now"].waitForExistence(timeout: 5))
                XCTAssertFalse(app.staticTexts["Signed In to Trakt"].exists)
                XCTAssertFalse(app.staticTexts["Last Successful Sync"].exists)
            } else {
                XCTAssertTrue(app.staticTexts[expected].waitForExistence(timeout: 5))
            }
            if state == "setup" {
                XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Replace iWatch Library from Trakt'")).firstMatch.exists)
                XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Upload Pending Changes'")).firstMatch.exists)
            }
            capture(app, "Trakt - " + state)
            app.terminate()
        }
    }

    @MainActor
    private func launchSyncSettings(contentSize: String, state: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["UITEST_MODE", "UITEST_SYNC_STATE", state,
            "-appTheme", contentSize.contains("Accessibility") ? "2" : "1",
            "-UIPreferredContentSizeCategoryName", contentSize]
        if contentSize.contains("Accessibility") { app.launchArguments.append("UITEST_ACCESSIBILITY_TEXT") }
        app.launch()
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        return app
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<15 {
            if element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable, "Expected reachable element: " + element.description)
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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
        XCTAssertFalse(app.staticTexts["Sync"].exists)
        XCTAssertTrue(app.buttons["settings-library"].exists)

        openTrakt(in: app)
        XCTAssertTrue(app.navigationBars["Trakt"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Connect Trakt"].exists)
        capture(app, "Disconnected Trakt")

        app.navigationBars["Trakt"].buttons.firstMatch.tap()
        app.navigationBars["Your Library"].buttons.firstMatch.tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Appearance,'")).firstMatch.tap()
        XCTAssertTrue(app.buttons["System"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Light"].exists)
        XCTAssertTrue(app.buttons["Dark"].exists)
    }

    @MainActor
    func testStartPageDoesNotFollowOrSwitchTheActiveTab() throws {
        let app = launchSyncSettings(contentSize: "UICTContentSizeCategoryL", state: "normal")
        let startPage = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Start Page,'")).firstMatch
        startPage.tap()
        app.collectionViews.buttons["Search"].tap()
        app.buttons["Close Settings"].tap()
        XCTAssertTrue(app.navigationBars["Movies"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Shows"].tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Start Page,' AND label CONTAINS 'Search'")).firstMatch.exists)
    }

    @MainActor
    func testNotificationSettingsAtStandardTextSize() throws {
        verifyNotificationSettings(contentSize: "UICTContentSizeCategoryL")
    }

    @MainActor
    func testNotificationSettingsAtAccessibilityTextSize() throws {
        verifyNotificationSettings(contentSize: "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge")
    }

    @MainActor
    private func verifyNotificationSettings(contentSize: String) {
        let app = launchSyncSettings(contentSize: contentSize, state: "normal")
        let notifications = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Notifications'")).firstMatch
        reveal(notifications, in: app)
        notifications.tap()
        XCTAssertTrue(app.navigationBars["Notifications"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["Release Notifications"].exists)
        XCTAssertFalse(app.buttons["Allow Notifications"].exists)
        capture(app, "Notification preferences - " + contentSize)
        let timing = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Notify Me'")).firstMatch
        reveal(timing, in: app)
        capture(app, "Notification timing - " + contentSize)
    }

    @MainActor
    func testTraktConnectAtAccessibilityTextSize() throws {
        let app = XCUIApplication()
        app.launchArguments += ["UITEST_MODE", "UITEST_ACCESSIBILITY_TEXT", "-appTheme", "2",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"]
        app.launch()
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        openTrakt(in: app)
        let connect = app.buttons["Connect Trakt"]
        XCTAssertTrue(connect.waitForExistence(timeout: 5))
        reveal(connect, in: app)
        XCTAssertTrue(connect.isHittable)
        XCTAssertGreaterThanOrEqual(connect.frame.height, 44)
        capture(app, "Disconnected Trakt - accessibility")
    }

    @MainActor
    func testRetainedLibraryErrorStandard() throws { verifyRetainedLibraryError(accessibility: false) }

    @MainActor
    func testRetainedLibraryErrorAccessibility() throws { verifyRetainedLibraryError(accessibility: true) }

    @MainActor
    private func verifyRetainedLibraryError(accessibility: Bool) {
        let app = XCUIApplication()
        app.launchArguments += ["UITEST_MODE", "UITEST_RETAINED_LIBRARY_ERROR", "-appTheme", accessibility ? "2" : "1"]
        if accessibility {
            app.launchArguments += ["UITEST_ACCESSIBILITY_TEXT", "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"]
        }
        app.launch()
        let retry = app.buttons["Try Again"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        capture(app, "Retained library - \(accessibility ? "accessibility" : "standard")")
        retry.tap()
        let movie = app.buttons["UI Test Movie"]
        reveal(movie, in: app)
        XCTAssertTrue(movie.exists)
        XCTAssertFalse(app.staticTexts["Unable to Load Movies"].exists)
    }

    @MainActor
    func testReferenceGalleryStandard() throws { verifyReferenceGallery(accessibility: false) }

    @MainActor
    func testReferenceGalleryAccessibility() throws { verifyReferenceGallery(accessibility: true) }

    @MainActor
    private func verifyReferenceGallery(accessibility: Bool) {
        let app = XCUIApplication()
        app.launchArguments += ["UITEST_MODE", "-appTheme", accessibility ? "2" : "1"]
        if accessibility {
            app.launchArguments += ["UITEST_ACCESSIBILITY_TEXT", "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"]
        }
        app.launch()
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        let gallery = app.buttons["Reference Gallery"]
        reveal(gallery, in: app)
        gallery.tap()
        XCTAssertTrue(app.navigationBars["Reference Gallery"].waitForExistence(timeout: 5))
        let offline = app.buttons["Offline Library"]
        reveal(offline, in: app)
        offline.tap()
        XCTAssertTrue(app.buttons["Try Again"].waitForExistence(timeout: 5))
        capture(app, "Gallery offline library - \(accessibility)")
        app.navigationBars["Movies"].buttons.firstMatch.tap()
        let notifications = app.buttons["Notifications — Blocked"]
        reveal(notifications, in: app)
        notifications.tap()
        XCTAssertTrue(app.navigationBars["Notifications"].waitForExistence(timeout: 5))
        capture(app, "Notification access - \(accessibility)")
        XCTAssertFalse(app.buttons["Notification Settings"].isEnabled)
    }

    @MainActor
    func testLibraryStartupRecoveryStandard() throws { verifyStartupRecovery(accessibility: false) }

    @MainActor
    func testLibraryStartupRecoveryAccessibility() throws { verifyStartupRecovery(accessibility: true) }

    @MainActor
    private func verifyStartupRecovery(accessibility: Bool) {
        let app = XCUIApplication()
        app.launchArguments += ["UITEST_MODE", "UITEST_STORE_OPEN_FAILURE", "-appTheme", accessibility ? "2" : "1"]
        if accessibility {
            app.launchArguments += ["UITEST_ACCESSIBILITY_TEXT", "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"]
        }
        app.launch()
        let retry = app.buttons["Try Again"]
        XCTAssertTrue(retry.waitForExistence(timeout: 8))
        XCTAssertFalse(app.tabBars.buttons["Movies"].exists)
        XCTAssertFalse(app.buttons["Reset"].exists)
        capture(app, "Library startup recovery - \(accessibility)")
        reveal(retry, in: app)
        retry.tap()
        XCTAssertTrue(app.buttons["Try Again"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.tabBars.buttons["Movies"].exists)
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
