import XCTest

/// Every launch uses MyDock's disposable DEBUG store and disables system changes.
/// Run with the MyDock Visual QA scheme on an unlocked Mac with full Xcode,
/// after quitting the canonical app cleanly (the Xcode target shares its bundle ID).
final class MyDockVisualPreviewUITests: XCTestCase {
    func testRenameAutosavesAcrossSettingsNavigation() {
        let app = launchEditablePreview()
        defer { quitPreview(app) }
        let originalField = renameField(in: app)
        originalField.click()
        app.typeKey("a", modifierFlags: .command)
        app.typeText("Renamed ")
        XCTAssertTrue(app.windows["MyDock"].staticTexts["Saved"].waitForExistence(timeout: 5))
        XCTAssertEqual(originalField.value as? String, "Renamed ")
        originalField.typeText("Dock")
        XCTAssertTrue(app.windows["MyDock"].staticTexts["Saved"].waitForExistence(timeout: 5))
        app.typeKey(.return, modifierFlags: [])
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Settings"].firstMatch.waitForExistence(timeout: 5))
        let profile = app.buttons.containing(.staticText, identifier: "Renamed Dock").firstMatch
        XCTAssertTrue(profile.waitForExistence(timeout: 5))
        profile.click()
        let field = renameField(in: app)
        XCTAssertEqual(field.value as? String, "Renamed Dock")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertFalse(app.buttons["manager.save"].exists)
        XCTAssertFalse(app.buttons["manager.discard"].exists)
    }

    func testAddedStatePreventsDuplicatesAndNewItemSupportsUndo() {
        let app = launchEditablePreview()
        defer { quitPreview(app) }
        app.buttons["manager.add-item"].click()
        let search = librarySearch(in: app)
        search.click()
        search.typeText("Clock")
        XCTAssertTrue(app.buttons["Clock, Added"].waitForExistence(timeout: 5))
        app.typeKey(.return, modifierFlags: [])
        app.buttons["Done"].click()
        XCTAssertEqual(itemButtons("Clock", in: app).count, 1)
        app.buttons["manager.add-item"].click()
        librarySearch(in: app).typeText("AI Activity")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.buttons["AI Activity, Added"].waitForExistence(timeout: 5))
        app.buttons["Done"].click()
        waitUntil { self.itemButtons("AI Activity", in: app).count == 1 }
        app.typeKey(.delete, modifierFlags: [])
        waitUntil { self.itemButtons("AI Activity", in: app).count == 0 }
        app.typeKey("z", modifierFlags: .command)
        waitUntil { self.itemButtons("AI Activity", in: app).count == 1 }
    }

    func testCommandPaletteReturnsFromSettingsToWorkspace() {
        let app = launchEditablePreview()
        defer { quitPreview(app) }
        app.typeKey("k", modifierFlags: .command)
        librarySearch(in: app).typeText("Open Settings")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["Settings"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["manager.add-item"].exists)
        app.typeKey("k", modifierFlags: .command)
        librarySearch(in: app).typeText("Switch to Everyday")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.buttons["manager.add-item"].waitForExistence(timeout: 5))
        XCTAssertEqual(itemButtons("Clock", in: app).count, 1)
    }

    func testCreationAndDuplicationOpenTheNewProfile() {
        let app = launchEditablePreview()
        defer { quitPreview(app) }
        app.typeKey("n", modifierFlags: .command)
        let name = app.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.click()
        app.typeKey("a", modifierFlags: .command)
        name.typeText("Test Dock")
        app.buttons["Create"].click()
        XCTAssertTrue(app.staticTexts["Your Dock is empty"].waitForExistence(timeout: 5))
        app.typeKey("d", modifierFlags: .command)
        let duplicatedName = app.textFields["manager.profile.name"]
        XCTAssertTrue(duplicatedName.waitForExistence(timeout: 5))
        XCTAssertNotEqual(duplicatedName.value as? String, "Test Dock")
        XCTAssertTrue((duplicatedName.value as? String)?.contains("Test Dock") == true)
        app.typeKey(.return, modifierFlags: [])
    }

    func testPointerDropAtEndAndUndoRestoreComposition() {
        let app = launchEditablePreview()
        defer { quitPreview(app) }
        let clock = itemButtons("Clock", in: app).firstMatch
        let last = itemButtons("Sticky Note", in: app).firstMatch
        XCTAssertTrue(clock.waitForExistence(timeout: 5))
        XCTAssertTrue(last.exists)
        XCTAssertLessThan(clock.frame.midX, last.frame.midX)
        let start = clock.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        // Drop in the material's trailing region, beyond the final tile.
        let end = last.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
            .withOffset(CGVector(dx: 12, dy: 0))
        start.press(forDuration: 0.15, thenDragTo: end)
        waitUntil { clock.frame.midX > last.frame.midX }
        app.typeKey(.leftArrow, modifierFlags: [])
        waitUntil { last.isSelected }
        app.typeKey(.leftArrow, modifierFlags: .shift)
        waitUntil { last.isSelected && self.itemButtons("Focus Timer", in: app).firstMatch.isSelected }
        app.typeKey("z", modifierFlags: .command)
        waitUntil { clock.frame.midX < last.frame.midX }
    }

    private func launchEditablePreview() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["MYDOCK_VISUAL_PREVIEW"] = "1"
        app.launchEnvironment["MYDOCK_UNIT_TEST_HOST"] = "0"
        app.launch()
        XCTAssertTrue(app.windows["MyDock"].waitForExistence(timeout: 15))
        app.windows["MyDock"].click()
        XCTAssertTrue(app.buttons["manager.add-item"].waitForExistence(timeout: 5))
        return app
    }

    private func renameField(in app: XCUIApplication) -> XCUIElement {
        let more = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Profile actions")).firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.click()
        let rename = app.menuItems["Rename…"]
        XCTAssertTrue(rename.waitForExistence(timeout: 5))
        rename.click()
        let field = app.textFields["manager.profile.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        return field
    }

    private func librarySearch(in app: XCUIApplication) -> XCUIElement {
        let search = app.searchFields.firstMatch
        if search.waitForExistence(timeout: 2) { return search }
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        return field
    }

    private func itemButtons(_ title: String, in app: XCUIApplication) -> XCUIElementQuery {
        app.windows["MyDock"].buttons.matching(NSPredicate(format: "label == %@", title))
    }

    private func waitUntil(_ condition: @escaping () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, file: file, line: line)
    }

    private func quitPreview(_ app: XCUIApplication) {
        guard app.state != .notRunning else { return }
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10), "Preview should flush drafts and quit cleanly")
    }

    func testLightPreviewSurfaces() {
        capturePreview(name: "light-bottom", dark: false,
                       windows: ["MyDock", "Custom Dock Preview"])
    }

    func testDarkPreviewSurfaces() {
        capturePreview(name: "dark-bottom", dark: true,
                       windows: ["MyDock", "Custom Dock Preview"])
    }

    func testSideDockPreviews() {
        for position in ["left", "right"] {
            capturePreview(name: "light-\(position)", dark: false, position: position,
                           windows: ["Custom Dock Preview"])
        }
    }

    func testCountdownLongContentPreview() {
        capturePreview(name: "light-countdown", dark: false, countdown: true,
                       windows: ["Custom Dock Preview"])
    }

    private func capturePreview(name: String, dark: Bool, position: String = "bottom",
                                countdown: Bool = false, windows: [String]) {
        let app = XCUIApplication()
        app.launchEnvironment["MYDOCK_VISUAL_PREVIEW"] = "1"
        app.launchEnvironment["MYDOCK_UNIT_TEST_HOST"] = "0"
        app.launchEnvironment["MYDOCK_VISUAL_DARK"] = dark ? "1" : "0"
        app.launchEnvironment["MYDOCK_VISUAL_POSITION"] = position
        app.launchEnvironment["MYDOCK_COUNTDOWN_VISUAL_PREVIEW"] = countdown ? "1" : "0"
        app.launch()
        defer { quitPreview(app) }
        for title in windows {
            let window = app.windows[title]
            XCTAssertTrue(window.waitForExistence(timeout: 15), "Missing \(title) preview window")
            guard window.exists else { continue }
            let attachment = XCTAttachment(screenshot: window.screenshot())
            attachment.name = "mydock-\(name)-\(title.replacingOccurrences(of: " ", with: "-").lowercased())"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
