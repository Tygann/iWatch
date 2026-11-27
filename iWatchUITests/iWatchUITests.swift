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
    func testQuickWatchStandard() throws { verifyQuickWatch(accessibility: false) }

    @MainActor
    func testQuickWatchAccessibility() throws { verifyQuickWatch(accessibility: true) }

    @MainActor
    private func verifyQuickWatch(accessibility: Bool) {
        let app = XCUIApplication()
        app.launchArguments += ["UITEST_MODE", "UITEST_START_ON_SHOWS", "UITEST_QUICK_WATCH"]
        if accessibility { app.launchArguments.append("UITEST_ACCESSIBILITY_TEXT") }
        app.launch()
        let markSecond = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "episode-preview-watch-")).firstMatch
        XCTAssertTrue(markSecond.waitForExistence(timeout: 10))
        capture(app, "Quick watch cards - \(accessibility)")
        XCTAssertEqual(markSecond.label, "Mark UI Test Show, Season 1 Episode 2 watched")
        XCTAssertTrue(app.staticTexts["Second Look"].exists)
        markSecond.tap()
        let markThird = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier BEGINSWITH %@",
            "Mark UI Test Show, Season 1 Episode 3 watched", "episode-preview-watch-")).firstMatch
        XCTAssertTrue(markThird.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Mark Watched"].exists)
        capture(app, "Quick watch confirmation - \(accessibility)")
        app.buttons["Undo marking episode watched"].tap()
        XCTAssertTrue(markSecond.waitForExistence(timeout: 5))

        // Detail navigation stays on the marked episode until explicitly advanced.
        app.buttons["UI Test Show, Season 1 Episode 2, Continue Watching"].tap()
        let mark = app.buttons["Mark Watched"]
        XCTAssertTrue(mark.waitForExistence(timeout: 5))
        let next = app.buttons["Next Episode"]
        for _ in 0..<5 {
            if next.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(next.isEnabled)
        XCTAssertGreaterThanOrEqual(next.frame.height, 44)
        XCTAssertEqual(next.value as? String, "S1 E3 Third Time")
        XCTAssertTrue(app.buttons["Previous Episode"].isEnabled)
        mark.tap()
        XCTAssertTrue(app.buttons["Watched"].waitForExistence(timeout: 5))
        capture(app, "Explicit next episode - \(accessibility)")
        next.tap()
        XCTAssertTrue(app.staticTexts["S1 E3 • Third Time"].waitForExistence(timeout: 5))
        XCTAssertTrue(mark.waitForExistence(timeout: 5))
        mark.tap()
        XCTAssertTrue(app.buttons["Watched"].waitForExistence(timeout: 5))
        XCTAssertFalse(next.isEnabled)
        app.buttons["Previous Episode"].tap()
        XCTAssertTrue(app.staticTexts["S1 E2 • Second Look"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Shows"].tap()
        XCTAssertFalse(markThird.exists)
        app.terminate()
    }

    @MainActor
    func testContinueWatchingGridQuickWatchAndUndo() throws {
        let app = XCUIApplication()
        app.launchArguments += ["UITEST_MODE", "UITEST_START_ON_SHOWS", "UITEST_QUICK_WATCH"]
        app.launch()
        app.buttons["Continue Watching"].tap()
        let second = app.buttons["Mark UI Test Show, Season 1 Episode 2 watched"]
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        second.tap()
        XCTAssertTrue(app.buttons["Mark UI Test Show, Season 1 Episode 3 watched"].waitForExistence(timeout: 5))
        app.buttons["Undo marking episode watched"].tap()
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        app.terminate()
    }

    @MainActor
    func testCachedSeasonDuringRefreshStandard() throws { verifyCachedSeasonDuringRefresh(accessibility: false) }

    @MainActor
    func testCachedSeasonDuringRefreshAccessibility() throws { verifyCachedSeasonDuringRefresh(accessibility: true) }

    @MainActor
    private func verifyCachedSeasonDuringRefresh(accessibility: Bool) {
        let app = XCUIApplication()
        app.launchArguments += ["UITEST_MODE", "UITEST_START_ON_SHOWS", "UITEST_DELAY_SEASON_REFRESH"]
        if accessibility { app.launchArguments.append("UITEST_ACCESSIBILITY_TEXT") }
        app.launch()
        let show = app.buttons["UI Test Show, Season 1 Episode 2, Continue Watching"]
        XCTAssertTrue(show.waitForExistence(timeout: 10))
        show.press(forDuration: 1)
        let goToShow = app.buttons["Go to Show"]
        XCTAssertTrue(goToShow.waitForExistence(timeout: 3))
        goToShow.tap()
        let episode = app.staticTexts["E1 • Pilot"]
        XCTAssertTrue(episode.waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Loading episodes…"].exists)
        for _ in 0..<8 {
            if episode.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(episode.isHittable)
        capture(app, "Cached episodes while refreshing - \(accessibility)")
        app.terminate()
    }

    @MainActor
    func testSeasonRetryStandard() { verifySeasonRetry(accessibility: false) }

    @MainActor
    func testSeasonRetryAccessibility() { verifySeasonRetry(accessibility: true) }

    @MainActor
    private func verifySeasonRetry(accessibility: Bool) {
        let app = XCUIApplication()
        app.launchArguments += ["UITEST_MODE", "UITEST_START_ON_SHOWS", "UITEST_FAIL_FIRST_SEASON_LOAD"]
        if accessibility { app.launchArguments.append("UITEST_ACCESSIBILITY_TEXT") }
        app.launch()
        let show = app.buttons["UI Test Show, Season 1 Episode 2, Continue Watching"]
        XCTAssertTrue(show.waitForExistence(timeout: 10))
        show.press(forDuration: 1)
        let goToShow = app.buttons["Go to Show"]
        XCTAssertTrue(goToShow.waitForExistence(timeout: 3))
        goToShow.tap()

        let retry = app.buttons["Try Again"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Loading episodes…"].exists)
        for _ in 0..<8 {
            if retry.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(retry.isHittable)
        retry.tap()
        XCTAssertTrue(retry.waitForNonExistence(timeout: 5))
        let episode = app.staticTexts["E1 • Pilot"]
        for _ in 0..<4 {
            if episode.exists { break }
            app.swipeDown()
        }
        XCTAssertTrue(episode.waitForExistence(timeout: 5))
        app.terminate()
    }

    @MainActor
    func testSavedShowsAppearBeforeRefreshStandard() throws {
        verifySavedShowsAppearBeforeRefresh(accessibility: false)
    }

    @MainActor
    func testSavedShowsAppearBeforeRefreshAccessibility() throws {
        verifySavedShowsAppearBeforeRefresh(accessibility: true)
    }

    @MainActor
    private func verifySavedShowsAppearBeforeRefresh(accessibility: Bool) {
        let app = XCUIApplication()
        app.launchArguments += ["UITEST_MODE", "UITEST_START_ON_SHOWS", "UITEST_LIBRARY_PREVIEW",
                                "UITEST_CLEAR_LIBRARY_PREVIEW"]
        if accessibility { app.launchArguments.append("UITEST_ACCESSIBILITY_TEXT") }
        app.launch()
        let title = app.buttons["UI Test Show, Season 1 Episode 2, Continue Watching"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        app.terminate()
        app.launchArguments.removeAll { $0 == "UITEST_CLEAR_LIBRARY_PREVIEW" }
        app.launchArguments.append("UITEST_DELAY_LIBRARY_REFRESH")
        app.launch()
        XCTAssertTrue(title.waitForExistence(timeout: 2))
        XCTAssertTrue(title.isEnabled)
        XCTAssertFalse(app.staticTexts["Updating Library…"].exists)
        capture(app, "Interactive saved Shows before local refresh - \(accessibility)")
        title.tap()
        XCTAssertTrue(app.navigationBars.buttons["Shows"].waitForExistence(timeout: 3))
        capture(app, "Opened saved episode during refresh - \(accessibility)")
        app.terminate()
    }

    @MainActor
    func testColdLaunchShowsStandard() throws {
        verifyColdLaunchShows(accessibility: false)
    }

    @MainActor
    func testColdLaunchShowsAccessibility() throws {
        verifyColdLaunchShows(accessibility: true)
    }

    @MainActor
    private func verifyColdLaunchShows(accessibility: Bool) {
        let app = XCUIApplication()
        app.launchArguments += ["UITEST_MODE", "UITEST_START_ON_SHOWS"]
        if accessibility { app.launchArguments.append("UITEST_ACCESSIBILITY_TEXT") }
        for attempt in 1...2 {
            app.launch()
            XCTAssertTrue(app.buttons["UI Test Show, Season 1 Episode 2, Continue Watching"]
                .waitForExistence(timeout: 10), "Shows must load after cold launch \(attempt)")
            XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "Continue Watching")).count, 1)
            XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@",
                "continue-watching-episode-")).count, 1)
            capture(app, "Cold launch Shows - \(accessibility) - \(attempt)")
            let moviesTab = app.tabBars.buttons["Movies"]
            moviesTab.tap()
            // The system tab bar can resize during the initial selection animation.
            if !app.navigationBars["Movies"].waitForExistence(timeout: 2) { moviesTab.tap() }
            XCTAssertTrue(app.buttons["UI Test Movie"].waitForExistence(timeout: 5))
            let showsTab = app.tabBars.buttons["Shows"]
            showsTab.tap()
            if !app.navigationBars["Shows"].waitForExistence(timeout: 2) { showsTab.tap() }
            XCTAssertTrue(app.buttons["UI Test Show, Season 1 Episode 2, Continue Watching"]
                .waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    @MainActor
    func testShowCollectionUpdatesStandard() throws { try verifyShowCollectionUpdates(accessibility: false) }

    @MainActor
    func testShowCollectionUpdatesAccessibility() throws { try verifyShowCollectionUpdates(accessibility: true) }

    @MainActor
    private func verifyShowCollectionUpdates(accessibility: Bool) throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_MODE", "UITEST_SHOW_COLLECTION", "UITEST_START_ON_SHOWS"]
        if accessibility { app.launchArguments.append("UITEST_ACCESSIBILITY_TEXT") }
        app.launch()
        let section = app.buttons["Not Started"]
        XCTAssertTrue(section.waitForExistence(timeout: 10))
        if !section.isHittable { app.swipeUp() }
        section.tap()
        XCTAssertTrue(app.navigationBars["Not Started"].waitForExistence(timeout: 5))
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<4 { scroll.swipeUp() }
        let tiles = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Collection Show "))
        let visible = tiles.allElementsBoundByIndex.filter { $0.isHittable && $0.frame.midY > app.frame.minY + 180 && $0.frame.midY < app.frame.maxY - 155 }
        XCTAssertGreaterThanOrEqual(visible.count, 2)
        let target = try XCTUnwrap(visible.first)
        let neighbor = try XCTUnwrap(visible.last)
        let targetLabel = target.label
        let anchor = neighbor.label
        let previousY = neighbor.frame.midY
        XCTAssertNotEqual(targetLabel, anchor)
        target.tap()
        let status = app.buttons["Viewing status: Watchlist"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        status.tap()
        app.buttons["Remove from Watchlist"].tap()
        XCTAssertTrue(app.buttons["Add to Watchlist"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Not Started"].tap()
        let after = app.buttons[anchor]
        XCTAssertTrue(after.waitForExistence(timeout: 4))
        let removed = app.buttons[targetLabel]
        XCTAssertTrue(removed.waitForNonExistence(timeout: 5))
        XCTAssertTrue(after.isHittable)
        XCTAssertLessThan(abs(after.frame.midY - previousY), 230)
        app.tabBars.buttons["Movies"].tap()
        XCTAssertTrue(app.navigationBars["Movies"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Shows"].tap()
        XCTAssertTrue(app.navigationBars["Not Started"].waitForExistence(timeout: 5))
        XCTAssertTrue(after.isHittable)
        XCTAssertFalse(removed.exists)
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
    func testWatchlistMovieMenuMarksWatched() {
        verifyWatchlistMovieMenu(accessibility: false)
    }

    @MainActor
    func testWatchlistMovieMenuAtAccessibilityTextSize() {
        verifyWatchlistMovieMenu(accessibility: true)
    }

    @MainActor
    private func verifyWatchlistMovieMenu(accessibility: Bool) {
        let app = XCUIApplication()
        app.launchArguments.append("UITEST_MODE")
        if accessibility { app.launchArguments.append("UITEST_ACCESSIBILITY_TEXT") }
        app.launch()

        let movieTile = app.buttons["UI Test Movie"]
        XCTAssertTrue(movieTile.waitForExistence(timeout: 5))
        reveal(movieTile, in: app)
        movieTile.press(forDuration: 1)
        let markWatched = app.buttons["Mark as Watched"]
        XCTAssertTrue(markWatched.waitForExistence(timeout: 5))
        markWatched.tap()

        let emptyWatchlist = app.staticTexts["Nothing to watch"]
        XCTAssertTrue(emptyWatchlist.waitForExistence(timeout: 5))
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
        XCTAssertFalse(app.buttons["Show Maintenance Tools"].exists)
        capture(app, "Simplified settings - " + contentSize)
        app.buttons["settings-sync"].tap()
        XCTAssertTrue(app.navigationBars["Library Sync"].waitForExistence(timeout: 5))
        let cloud = app.descendants(matching: .any)["icloud-sync-status"].firstMatch
        XCTAssertTrue(cloud.waitForExistence(timeout: 5))
        XCTAssertTrue(cloud.label.contains("Syncs Automatically"))
        capture(app, "Library sync overview - " + contentSize)
        revealTraktSection(in: app)
        XCTAssertFalse(app.buttons["Advanced"].exists)
        let traktStatus = app.descendants(matching: .any)["trakt-connection"]
        XCTAssertTrue(traktStatus.label.contains("4 of 10 pending changes need confirmation."))
        let pending = app.buttons["Review Pending Changes"]
        reveal(pending, in: app)
        let syncNow = app.buttons["Sync Now"]
        if !contentSize.contains("Accessibility") {
            XCTAssertGreaterThanOrEqual(syncNow.frame.height, 44)
            XCTAssertGreaterThanOrEqual(pending.frame.height, 44)
            XCTAssertLessThan(pending.frame.minY, syncNow.frame.minY)
        }
        capture(app, "Contextual Trakt issue - " + contentSize)
        pending.tap()
        XCTAssertTrue(app.navigationBars["Library Sync"].exists)
        let failed = app.buttons["Needs Attention (6)"]
        reveal(failed, in: app)
        let confirmation = app.buttons["Waiting for Confirmation (4)"]
        reveal(confirmation, in: app)
        capture(app, "Pending changes overview - " + contentSize)
        confirmation.tap()
        let episode = app.staticTexts["Example Show · S1 E1"]
        reveal(episode, in: app)
        capture(app, "Pending changes - " + contentSize)
        confirmation.tap()
        let move = app.buttons["Move Uploads to This Device"]
        reveal(move, in: app)
        move.tap()
        XCTAssertTrue(app.buttons["Move Pending Uploads"].waitForExistence(timeout: 5))
        if app.buttons["Cancel"].exists {
            app.buttons["Cancel"].tap()
        } else {
            app.navigationBars["Library Sync"].tap()
        }
        let status = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == 'Trakt Service Status'")
        ).firstMatch
        reveal(status, in: app)
        let support = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == 'Contact Support'")
        ).firstMatch
        reveal(support, in: app)

        let erase = app.buttons["Erase All App Data"]
        XCTAssertFalse(erase.exists)
        let manage = app.buttons["Show Maintenance Tools"]
        reveal(manage, in: app)
        manage.tap()
        XCTAssertTrue(app.navigationBars["Library Sync"].exists)
        capture(app, "Library maintenance - " + contentSize)
        reveal(app.buttons["Check Library Data"], in: app)
        let rebuild = app.buttons["Rebuild from Trakt"]
        reveal(rebuild, in: app)
        rebuild.tap()
        XCTAssertTrue(app.buttons["Discard Changes and Rebuild"].waitForExistence(timeout: 5))
        capture(app, "Protected rebuild - " + contentSize)
        app.buttons["Cancel"].tap()
        reveal(erase, in: app)
        erase.tap()
        XCTAssertTrue(app.buttons["Erase All Data"].waitForExistence(timeout: 5))
        if app.buttons["Cancel"].exists {
            app.buttons["Cancel"].tap()
        } else {
            app.navigationBars["Library Sync"].tap()
        }
        XCTAssertTrue(app.navigationBars["Library Sync"].exists)
    }

    @MainActor
    func testSupportAtStandardTextSize() throws { verifySupport(contentSize: "UICTContentSizeCategoryL") }

    @MainActor
    func testSupportAtAccessibilityTextSize() throws { verifySupport(contentSize: "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge") }

    @MainActor
    private func verifySupport(contentSize: String) {
        let app = launchSyncSettings(contentSize: contentSize, state: "normal")
        XCTAssertFalse(app.buttons["Contact Support"].exists)
        let about = app.buttons["settings-about"]
        reveal(about, in: app)
        XCTAssertTrue(app.buttons["Share iWatch"].exists)
        XCTAssertTrue(app.buttons["Rate iWatch"].exists)
        capture(app, "Settings app section - " + contentSize)
        about.tap()
        XCTAssertTrue(app.navigationBars["About"].waitForExistence(timeout: 5))
        let support = app.buttons["about-support"]
        reveal(support, in: app)
        capture(app, "About support - " + contentSize)
        support.tap()
        XCTAssertTrue(app.navigationBars["Contact Support"].waitForExistence(timeout: 5))
        let share = app.buttons["Share Diagnostic Report"]
        reveal(share, in: app)
        capture(app, "Support report - " + contentSize)
        app.navigationBars["Contact Support"].buttons.firstMatch.tap()
        XCTAssertFalse(app.buttons["Share iWatch"].exists)
        XCTAssertFalse(app.buttons["Rate iWatch"].exists)
        XCTAssertFalse(app.buttons["Acknowledgments"].exists)
        XCTAssertTrue(app.navigationBars["About"].waitForExistence(timeout: 5))
        reveal(app.descendants(matching: .any)["about-tmdb"].firstMatch, in: app)
        reveal(app.descendants(matching: .any)["about-trakt"].firstMatch, in: app)
        let attribution = app.staticTexts["iWatch is not endorsed or certified by TMDB or Trakt."]
        reveal(attribution, in: app)
        capture(app, "Inline provider credits - " + contentSize)
    }

    @MainActor
    private func revealTraktSection(in app: XCUIApplication) {
        let connection = app.descendants(matching: .any)["trakt-connection"]
        let connect = app.buttons["Connect Trakt"]
        let progress = app.descendants(matching: .any)["trakt-sync-progress"]
        if !app.navigationBars["Library Sync"].exists {
            let sync = app.buttons["settings-sync"]
            reveal(sync, in: app)
            sync.tap()
        }
        XCTAssertTrue(app.navigationBars["Library Sync"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["settings-trakt"].exists)
        for _ in 0..<15 {
            if [connection, connect, progress].contains(where: { $0.exists && $0.isHittable }) { return }
            app.swipeUp()
        }
        XCTFail("Expected inline Trakt connection or Connect control in Sync")
    }

    @MainActor
    func testTraktSetupCanStillDisconnect() throws {
        let app = launchSyncSettings(contentSize: "UICTContentSizeCategoryL", state: "setup")
        revealTraktSection(in: app)
        let setup = app.buttons["Finish Setup"]
        reveal(setup, in: app)
        setup.tap()
        XCTAssertTrue(app.navigationBars["Library Sync"].exists)
        let replace = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Replace iWatch Library from Trakt'")).firstMatch
        reveal(replace, in: app)
        replace.tap()
        XCTAssertTrue(app.buttons["Replace and Import"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        setup.tap()
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
            app.navigationBars["Library Sync"].tap()
        }
        XCTAssertTrue(app.navigationBars["Library Sync"].exists)
    }

    @MainActor
    func testTraktSetupAtAccessibilityTextSize() throws {
        let app = launchSyncSettings(contentSize: "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge", state: "setup")
        revealTraktSection(in: app)
        let setup = app.buttons["Finish Setup"]
        reveal(setup, in: app)
        setup.tap()
        XCTAssertTrue(app.navigationBars["Library Sync"].exists)
        capture(app, "Trakt setup choices - accessibility")
        let upload = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Upload Pending Changes'")).firstMatch
        reveal(upload, in: app)
        XCTAssertTrue(upload.isEnabled)
        capture(app, "Trakt setup upload choice - accessibility")
    }

    @MainActor
    func testTraktConnectedAtAccessibilityTextSize() throws {
        let app = launchSyncSettings(contentSize: "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge", state: "normal")
        revealTraktSection(in: app)
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
            let app = launchSyncSettings(contentSize: "UICTContentSizeCategoryL", state: state, theme: "2")
            revealTraktSection(in: app)
            XCTAssertTrue(app.navigationBars["Library Sync"].waitForExistence(timeout: 5))
            let cloud = app.descendants(matching: .any)["icloud-sync-status"].firstMatch
            let cloudTitle = ["normal": "Syncs Automatically", "offline": "iCloud Needs Attention",
                              "syncing": "Uploading Changes…", "setup": "Syncs Automatically"][state]!
            XCTAssertTrue(cloud.label.contains(cloudTitle))
            let expected = ["normal": "Trakt", "offline": "Connection Interrupted",
                            "syncing": "Syncing…", "setup": "Finish Setup"][state]!
            if state == "normal" {
                XCTAssertTrue(app.descendants(matching: .any)["trakt-connection"].waitForExistence(timeout: 5))
                XCTAssertTrue(app.descendants(matching: .any)["trakt-connection"].label.contains("Connected"))
                XCTAssertTrue(app.buttons["Sync Now"].waitForExistence(timeout: 5))
                XCTAssertFalse(app.staticTexts["Signed In to Trakt"].exists)
                XCTAssertFalse(app.staticTexts["Last Successful Sync"].exists)
            } else if state == "syncing" {
                reveal(app.descendants(matching: .any)["trakt-sync-progress"], in: app)
            } else if state != "setup" {
                let status = app.descendants(matching: .any)["trakt-connection"]
                reveal(status, in: app)
                XCTAssertTrue(status.label.contains(expected))
            }
            if state == "setup" {
                let setup = app.buttons["Finish Setup"]
                reveal(setup, in: app)
                setup.tap()
                XCTAssertTrue(app.navigationBars["Library Sync"].exists)
                reveal(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Replace iWatch Library from Trakt'")).firstMatch, in: app)
                XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Upload Pending Changes'")).firstMatch.exists)
            }
            capture(app, "Trakt - " + state)
            app.terminate()
        }
    }

    @MainActor
    private func launchSyncSettings(
        contentSize: String, state: String, theme: String? = nil, additionalArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["UITEST_MODE", "UITEST_SYNC_STATE", state,
            "-appTheme", theme ?? (contentSize.contains("Accessibility") ? "2" : "1"),
            "-UIPreferredContentSizeCategoryName", contentSize] + additionalArguments
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
    func testGuestAccountAtStandardAndAccessibilityTextSizes() {
        for contentSize in ["UICTContentSizeCategoryL", "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"] {
            let app = launchSyncSettings(contentSize: contentSize, state: "normal",
                                         additionalArguments: ["UITEST_ACCOUNT_SIGN_IN"])
            let account = app.buttons["settings-account"]
            XCTAssertTrue(account.waitForExistence(timeout: 5))
            XCTAssertTrue(account.isHittable)
            XCTAssertTrue(account.label.contains("Guest"))
            XCTAssertTrue(account.label.contains("Account"))
            let sync = app.buttons["settings-sync"]
            XCTAssertTrue(sync.isHittable)
            XCTAssertLessThan(account.frame.minY, sync.frame.minY)
            capture(app, "Settings account row - " + contentSize)
            account.tap()

            let accountBar = app.navigationBars["Account"]
            XCTAssertTrue(accountBar.waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["Guest"].isHittable)
            XCTAssertTrue(app.staticTexts["You can use iWatch without an account."].isHittable)

            let signIn = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Sign in with Apple")).firstMatch
            XCTAssertTrue(signIn.isHittable)
            XCTAssertFalse(accountBar.buttons["Edit"].exists)
            capture(app, "Guest account - " + contentSize)
            accountBar.buttons.firstMatch.tap()
            XCTAssertTrue(account.isHittable)
            app.terminate()
        }
    }

    @MainActor
    func testSignedInAccountEditingAtStandardAndAccessibilityTextSizes() {
        for contentSize in ["UICTContentSizeCategoryL", "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"] {
            let app = XCUIApplication()
            app.launchArguments += ["UITEST_MODE", "UITEST_ACCOUNT_PROFILE", "-appTheme", "2",
                                    "-UIPreferredContentSizeCategoryName", contentSize]
            if contentSize.contains("Accessibility") { app.launchArguments.append("UITEST_ACCESSIBILITY_TEXT") }
            app.launch()
            let settings = app.buttons["Settings"]
            XCTAssertTrue(settings.waitForExistence(timeout: 5))
            settings.tap()
            app.buttons["settings-account"].tap()

            let accountBar = app.navigationBars["Account"]
            XCTAssertTrue(accountBar.waitForExistence(timeout: 5))
            let username = app.textFields["Username"]
            XCTAssertFalse(username.exists)
            XCTAssertTrue(app.buttons["Sign Out"].exists)
            XCTAssertTrue(app.buttons["Delete Account"].exists)
            capture(app, "Signed-in account - " + contentSize)
            accountBar.buttons["Edit"].tap()

            let editBar = app.navigationBars["Edit Account"]
            XCTAssertTrue(editBar.waitForExistence(timeout: 5))
            XCTAssertEqual(username.value as? String, "Sample Viewer")
            XCTAssertFalse(app.buttons["Save"].isEnabled)
            XCTAssertFalse(app.buttons["Sign Out"].exists)
            XCTAssertFalse(app.buttons["Delete Account"].exists)
            capture(app, "Edit account - " + contentSize)

            username.tap()
            username.typeText(" Updated")
            XCTAssertTrue(app.buttons["Save"].isEnabled)
            editBar.buttons["Cancel"].tap()
            XCTAssertTrue(accountBar.waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["Sample Viewer"].exists)

            accountBar.buttons["Edit"].tap()
            XCTAssertEqual(username.value as? String, "Sample Viewer")
            app.terminate()
        }
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
        XCTAssertTrue(app.buttons["settings-sync"].exists)

        revealTraktSection(in: app)
        XCTAssertTrue(app.navigationBars["Library Sync"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Connect Trakt"].exists)
        capture(app, "Disconnected Trakt")

        app.navigationBars["Library Sync"].buttons.firstMatch.tap()
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
        let app = launchSyncSettings(contentSize: contentSize, state: "normal",
            additionalArguments: ["-releaseNotifications.episodesEnabled", "YES"])
        let notifications = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Notifications'")).firstMatch
        reveal(notifications, in: app)
        notifications.tap()
        XCTAssertTrue(app.navigationBars["Notifications"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["Release Notifications"].exists)
        for title in ["TV Episodes", "Movies"] {
            let toggle = app.switches[title]
            reveal(toggle, in: app)
            XCTAssertTrue(toggle.exists)
            XCTAssertTrue(toggle.isEnabled)
        }
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
        revealTraktSection(in: app)
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
    func testAboutLandscapeStandard() throws {
        try verifyAbout(theme: "dark", accessibility: false, landscape: true)
    }

    @MainActor
    private func verifyAbout(theme: String, accessibility: Bool, landscape: Bool = false) throws {
        let app = XCUIApplication()
        app.launchArguments += ["UITEST_MODE", "-appTheme", theme == "dark" ? "2" : "1"]
        if accessibility {
            app.launchArguments += ["UITEST_ACCESSIBILITY_TEXT",
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"]
        }
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        app.launch()
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        let about = app.buttons["About"]
        for _ in 0..<6 {
            if about.isHittable { break }
            app.collectionViews.firstMatch.swipeUp()
        }
        if landscape { capture(app, "Landscape settings") }
        XCTAssertTrue(about.isHittable)
        about.tap()
        XCTAssertTrue(app.navigationBars["About"].waitForExistence(timeout: 5))
        if !accessibility && !landscape {
            app.descendants(matching: .any)["about-app-identity"].firstMatch.press(forDuration: 1)
            let copyVersion = app.buttons["Copy Version"]
            XCTAssertTrue(copyVersion.waitForExistence(timeout: 3))
            copyVersion.tap()
        }

        let identity = XCTAttachment(screenshot: app.screenshot())
        identity.name = "About identity - \(theme) - \(accessibility ? "accessibility" : "standard")"
        identity.lifetime = .keepAlways
        add(identity)

        func revealAbout(_ element: XCUIElement) {
            for _ in 0..<15 {
                if element.isHittable { return }
                app.collectionViews.firstMatch.swipeUp()
            }
            XCTAssertTrue(element.isHittable, "Expected reachable About element: " + element.description)
        }

        revealAbout(app.buttons["about-support"])
        XCTAssertLessThanOrEqual(app.buttons["about-support"].frame.width, 600)
        XCTAssertFalse(app.buttons["Share iWatch"].exists)
        XCTAssertFalse(app.buttons["Rate iWatch"].exists)
        revealAbout(app.descendants(matching: .any)["about-privacy"].firstMatch)
        XCTAssertFalse(app.buttons["Acknowledgments"].exists)
        for identifier in ["about-tmdb", "about-trakt"] {
            let link = app.descendants(matching: .any)[identifier].firstMatch
            revealAbout(link)
            if !landscape {
                let frame = link.frame
                XCTAssertGreaterThanOrEqual(frame.width, 44)
                XCTAssertGreaterThanOrEqual(frame.height, 44)
            }
        }
        let links = XCTAttachment(screenshot: app.screenshot())
        links.name = "About links - \(theme) - \(accessibility ? "accessibility" : "standard")"
        links.lifetime = .keepAlways
        add(links)
    }

}
