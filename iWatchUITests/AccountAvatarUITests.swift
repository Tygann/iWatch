import XCTest

final class AccountAvatarUITests: XCTestCase {
    @MainActor
    func testAdjustApplyAndRemovePhotoAtStandardAndAccessibilityTextSizes() {
        for contentSize in ["UICTContentSizeCategoryL", "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"] {
            let app = XCUIApplication()
            app.launchArguments += ["UITEST_MODE", "UITEST_ACCOUNT_PROFILE", "UITEST_ACCOUNT_AVATAR",
                                    "-appTheme", "2", "-UIPreferredContentSizeCategoryName", contentSize]
            if contentSize.contains("Accessibility") { app.launchArguments.append("UITEST_ACCESSIBILITY_TEXT") }
            app.launch()

            let settings = app.buttons["Settings"]
            XCTAssertTrue(settings.waitForExistence(timeout: 5))
            settings.tap()
            app.buttons["settings-account"].tap()
            app.navigationBars["Account"].buttons["Edit"].tap()
            let edit = app.navigationBars["Edit Account"]
            let save = edit.buttons["Save"]
            let cancel = edit.buttons["Cancel"]
            let addPhoto = app.buttons["Add Photo"]
            XCTAssertFalse(save.isEnabled)
            XCTAssertTrue(addPhoto.waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["Remove Photo"].exists)
            addPhoto.tap()

            let adjust = app.navigationBars["Adjust Photo"]
            XCTAssertTrue(adjust.waitForExistence(timeout: 5))
            XCTAssertTrue(app.descendants(matching: .any)["avatar.crop-preview"].exists)
            let zoomIn = app.buttons["Zoom in"]
            for _ in 0..<4 where !zoomIn.isHittable { app.swipeUp() }
            zoomIn.tap()
            XCTAssertTrue(app.staticTexts["110%"].exists)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Adjust photo - " + contentSize
            screenshot.lifetime = .keepAlways
            add(screenshot)
            adjust.buttons["Use Photo"].tap()

            let changePhoto = app.buttons["Change Photo"]
            XCTAssertTrue(changePhoto.waitForExistence(timeout: 5))
            XCTAssertTrue(save.isEnabled)
            let editScreenshot = XCTAttachment(screenshot: app.screenshot())
            editScreenshot.name = "Draft photo - " + contentSize
            editScreenshot.lifetime = .keepAlways
            add(editScreenshot)
            save.tap()

            let account = app.navigationBars["Account"]
            XCTAssertTrue(account.waitForExistence(timeout: 5))
            account.buttons["Edit"].tap()
            let remove = app.buttons["Remove Photo"]
            XCTAssertTrue(remove.waitForExistence(timeout: 5))
            XCTAssertFalse(save.isEnabled)
            remove.tap()
            XCTAssertTrue(addPhoto.waitForExistence(timeout: 5))
            XCTAssertTrue(save.isEnabled)
            cancel.tap()
            XCTAssertTrue(account.waitForExistence(timeout: 5))

            account.buttons["Edit"].tap()
            XCTAssertTrue(changePhoto.waitForExistence(timeout: 5))
            remove.tap()
            save.tap()
            XCTAssertTrue(account.waitForExistence(timeout: 5))
            account.buttons["Edit"].tap()
            XCTAssertTrue(addPhoto.waitForExistence(timeout: 5))
            XCTAssertFalse(save.isEnabled)
            app.terminate()
        }
    }
}
