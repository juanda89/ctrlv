import XCTest

/// End-to-end checks of the setup flow against the real Settings app and the
/// real keyboard switcher in the simulator. Each step is its own test so the
/// App Group and the global preferences can be inspected from the Mac between
/// steps:
///
///     xcodebuild test -scheme Control-V -destination 'platform=iOS Simulator,id=<udid>' \
///       -only-testing:'Control-V UITests/SetupFlowUITests/test_settings_addKeyboard' \
///       TEST_RUNNER_SNAPSHOT_DIR=/abs/dir
///
/// Screenshots land in SNAPSHOT_DIR (or the runner's tmp directory).
final class SetupFlowUITests: XCTestCase {
    private let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
    private let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
    }

    /// Always leaves a picture of where the flow ended, pass or fail.
    override func tearDown() {
        save("end-\(name.split(separator: " ").last?.replacingOccurrences(of: "]", with: "") ?? "test")", of: app)
    }

    // MARK: - Settings

    /// General → Keyboard → Keyboards → Add New Keyboard… → Control-V.
    func test_settings_addKeyboard() {
        openKeyboardsList()
        tapRow(prefix: "Add New Keyboard")
        tapRow("Control-V")
        let listed = settings.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Control-V'")).firstMatch
        XCTAssertTrue(listed.waitForExistence(timeout: 5), "Control-V should be listed after adding it")
        save("settings-keyboards-after-add", of: settings)
    }

    /// Keyboards → Control-V → Allow Full Access → Allow.
    func test_settings_allowFullAccess() {
        openKeyboardsList()
        tapRow(prefix: "Control-V")
        let toggle = settings.switches["Allow Full Access"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        save("settings-fullaccess-before", of: settings)
        if (toggle.value as? String) != "1" {
            // The element spans the whole row; the control itself sits at
            // the trailing edge, so tap there.
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            sleep(1)
            save("settings-fullaccess-alert", of: settings)
            // iOS confirms Full Access with an alert; its buttons are not
            // always inside an `alerts` element, so search app-wide.
            let allow = settings.descendants(matching: .button).matching(NSPredicate(format: "label == 'Allow'")).firstMatch
            if allow.waitForExistence(timeout: 5) { allow.tap() } else { NSLog("[uitest] no Allow button: %@", settings.debugDescription.prefix(4000).description) }
        }
        sleep(1)
        save("settings-fullaccess-after", of: settings)
        XCTAssertEqual(toggle.value as? String, "1")
    }

    /// Apps → Default Apps → Translation → Control-V (iOS 18.4+).
    func test_settings_setDefaultTranslation() {
        settings.launch()
        tapRow("Apps")
        tapRow(prefix: "Default Apps")
        tapRow("Translation")
        save("settings-default-translation", of: settings)
        tapRow(prefix: "Control-V")
        sleep(1)
        save("settings-default-translation-after", of: settings)
    }

    /// Keyboards → Edit → delete Control-V (used to reset between runs).
    func test_settings_removeKeyboard() {
        openKeyboardsList()
        let row = settings.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Control-V'")).firstMatch
        guard row.waitForExistence(timeout: 3) else { return }
        row.swipeLeft()
        let delete = settings.buttons["Delete"]
        if delete.waitForExistence(timeout: 3) { delete.tap() }
        sleep(1)
        save("settings-keyboards-after-remove", of: settings)
    }

    // MARK: - App

    /// Opens the setup sheet's test field, then switches to the Control-V
    /// keyboard through the globe key. The keyboard records itself in the App
    /// Group when it appears; the sheet should react.
    func test_app_switchToControlVKeyboard() {
        app.launchArguments = ["-ui.tab", "translate", "-ui.setupState", "both"]
        app.launch()
        let field = app.textViews["translate.editor"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "translate editor")
        field.tap()
        ensureSystemKeyboard()
        save("app-system-keyboard", of: app)

        switchToControlVKeyboard()
        let ours = app.descendants(matching: .any)["Translate and replace"]
        XCTAssertTrue(ours.waitForExistence(timeout: 5), "Control-V keyboard should be showing")
        sleep(2)
        save("app-controlv-keyboard", of: app)
        sleep(2)
        save("app-after-keyboard", of: app)
    }

    /// Selects the sample text and taps Translate in the edit menu, which
    /// opens Control-V's translation sheet when it is the default app.
    func test_app_useTranslateMenu() {
        // The Translate tab's editor: the sheet's field only shows while the
        // keyboard is added but unverified.
        app.launchArguments = ["-ui.tab", "translate", "-ui.setupState", "keyboard"]
        app.launch()
        let field = app.textViews["translate.editor"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("Hola, cómo va todo por allá")
        sleep(1)
        // Long press → Select All → the edit menu for the selection.
        field.press(forDuration: 1.0)
        let selectAll = app.menuItems["Select All"]
        if selectAll.waitForExistence(timeout: 3) { selectAll.tap() } else { field.doubleTap() }
        sleep(1)
        save("app-edit-menu", of: app)
        NSLog("[uitest] menu items: %@", app.menuItems.allElementsBoundByIndex.map(\.label).joined(separator: " | "))
        let translate = app.menuItems["Translate"]
        var pages = 0
        while !translate.exists, pages < 4 {
            // The edit menu pages its items behind a chevron drawn right
            // after the last item; tap there by position.
            guard let last = app.menuItems.allElementsBoundByIndex.last, last.exists else { break }
            let frame = last.frame
            let menu = app.menus.firstMatch
            let container = menu.exists ? menu.frame : frame
            NSLog("[uitest] last item %@ menu %@", NSCoder.string(for: frame), NSCoder.string(for: container))
            let x = menu.exists ? container.maxX - 14 : frame.maxX + 22
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: frame.midY)).tap()
            pages += 1; sleep(1)
            save("app-edit-menu-page\(pages)", of: app)
            NSLog("[uitest] menu items page %d: %@", pages, app.menuItems.allElementsBoundByIndex.map(\.label).joined(separator: " | "))
        }
        // The expanded menu lists its items as plain elements, not menuItems.
        let translateAny = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Translate'")).firstMatch
        XCTAssertTrue(translate.exists || translateAny.waitForExistence(timeout: 3), "Translate item in the edit menu")
        (translate.exists ? translate : translateAny).tap()
        sleep(4)
        save("app-translate-sheet", of: app)
    }

    /// Holds Control-V's own keys: the character preview, then the accent
    /// strip (e), with a slide to the second accent. The Mac side records.
    func test_app_holdControlVKeys() {
        app.launchArguments = ["-ui.tab", "translate", "-ui.setupState", "both"]
        app.launch()
        let field = app.textViews["translate.editor"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        switchToControlVKeyboard()
        let x = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'X' OR label == 'x'")).firstMatch
        XCTAssertTrue(x.waitForExistence(timeout: 5))
        x.press(forDuration: 1.5)
        sleep(1)
        // Top row: the preview must rise above the keyboard's edge.
        app.descendants(matching: .any).matching(NSPredicate(format: "label == 'W' OR label == 'w'")).firstMatch.press(forDuration: 1.5)
        sleep(1)
        let e = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'E' OR label == 'e'")).firstMatch
        e.press(forDuration: 1.5)
        sleep(1)
        let n = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'N' OR label == 'n'")).firstMatch
        let target = n.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        target.press(forDuration: 1.2, thenDragTo: target.withOffset(CGVector(dx: 8, dy: 0)))
        sleep(1)
        app.descendants(matching: .any)["Backspace"].firstMatch.press(forDuration: 1.5)
        sleep(1)
        save("app-controlv-typed", of: app)
    }

    /// Taps in the gaps between keys and between rows: each must type the
    /// nearest key (no dead spots), and two quick taps must both register.
    func test_app_typeInGaps() {
        app.launchArguments = ["-ui.tab", "translate", "-ui.setupState", "both"]
        app.launch()
        let field = app.textViews["translate.editor"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        switchToControlVKeyboard()
        // Select all and delete so the field starts empty.
        field.press(forDuration: 1.0)
        let selectAll = app.menuItems["Select All"]
        if selectAll.waitForExistence(timeout: 3) { selectAll.tap() }
        app.descendants(matching: .any)["Backspace"].firstMatch.tap()
        sleep(1)
        let q = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Q' OR label == 'q'")).firstMatch
        let w = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'W' OR label == 'w'")).firstMatch
        let a = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'A' OR label == 'a'")).firstMatch
        XCTAssertTrue(q.waitForExistence(timeout: 5))
        NSLog("[uitest] frames q=%@ w=%@ a=%@", NSCoder.string(for: q.frame), NSCoder.string(for: w.frame), NSCoder.string(for: a.frame))
        let gapBetweenQAndW = CGPoint(x: (q.frame.maxX + w.frame.minX) / 2, y: q.frame.midY)
        let gapBelowQ = CGPoint(x: q.frame.midX, y: (q.frame.maxY + a.frame.minY) / 2)
        // Cells tile the keyboard with no gap, so the only way to miss is a
        // touch exactly on a shared edge (a zero-width line no finger hits).
        // Probe 1 pt to either side of the edges between q, w and a.
        let probes: [(String, CGPoint)] = [
            ("1pt left of q|w edge", CGPoint(x: gapBetweenQAndW.x - 1, y: gapBetweenQAndW.y)),
            ("1pt right of q|w edge", CGPoint(x: gapBetweenQAndW.x + 1, y: gapBetweenQAndW.y)),
            ("1pt above the row edge", CGPoint(x: q.frame.midX + 6, y: gapBelowQ.y - 1)),
            ("1pt below the row edge", CGPoint(x: q.frame.midX + 6, y: gapBelowQ.y + 1)),
        ]
        var previous = (field.value as? String) ?? ""
        for (label, point) in probes {
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x, dy: point.y)).tap()
            usleep(250_000)
            let now = (field.value as? String) ?? ""
            NSLog("[uitest] tap %@ at %@ -> '%@'", label, NSCoder.string(for: point), String(now.dropFirst(previous.count)))
            previous = now
        }
        sleep(1)
        save("app-gap-typing", of: app)
        let typed = (field.value as? String) ?? ""
        NSLog("[uitest] typed in gaps: '%@'", typed)
        XCTAssertEqual(typed.count, 4, "four gap taps should type four letters, got '\(typed)'")
    }

    /// The acceptance test for detection: with the keyboard added but never
    /// opened, opening it in the sheet's field must turn the card green and
    /// close the sheet without any button.
    func test_app_detectKeyboardInSheet() {
        app.launchArguments = ["-ui.showSetup", "1", "-ui.setupState", "keyboardAdded"]
        app.launch()
        let field = app.textViews["setup.testField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "setup sheet with its test field")
        XCTAssertTrue(app.staticTexts["Added"].waitForExistence(timeout: 3), "keyboard card says Added")
        save("detect-before", of: app)
        field.tap()
        switchToControlVKeyboard()
        // The keyboard reported itself the moment it appeared; the sheet turns
        // green, dismisses the keyboard and goes away on its own.
        let sheetGone = NSPredicate(format: "exists == false")
        let done = XCTNSPredicateExpectation(predicate: sheetGone, object: field)
        XCTAssertEqual(XCTWaiter().wait(for: [done], timeout: 8), .completed, "sheet closes after detection")
        sleep(1)
        save("detect-after", of: app)
        XCTAssertFalse(app.staticTexts["Finish setup"].exists, "account screen no longer asks for setup")
    }

    /// Screenshot of the setup sheet as launched (no keyboard).
    func test_app_setupSheet() {
        app.launchArguments = ["-ui.showSetup", "1", "-ui.setupState", "keyboardAdded"]
        app.launch()
        XCTAssertTrue(app.textViews["setup.testField"].waitForExistence(timeout: 10))
        sleep(1)
        save("app-setup-sheet", of: app)
    }

    /// The system keyboard with a letter held down, for the character-preview
    /// popup and the accent popup; the Mac side records video meanwhile.
    func test_app_holdSystemKeys() {
        app.launchArguments = ["-ui.tab", "translate", "-ui.setupState", "both"]
        app.launch()
        let field = app.textViews["translate.editor"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        ensureSystemKeyboard()
        sleep(1)
        for key in ["x", "e", "n"] {
            let k = app.keyboards.keys[key]
            guard k.waitForExistence(timeout: 3) else { continue }
            k.press(forDuration: 1.2)
            sleep(1)
        }
        app.keyboards.buttons["shift"].firstMatch.tap()
        sleep(1)
        app.keyboards.keys["delete"].press(forDuration: 1.0)
        sleep(1)
    }

    // MARK: - Helpers

    /// Holds the globe key and picks Control-V from the input-mode list. On
    /// iOS 26 the globe sits in the system chrome under the keys, outside the
    /// `keyboards` element, so it is looked up app-wide and, failing that, by
    /// its position at the bottom-left of the screen.
    /// A custom keyboard is not a `keyboards` element, so when Control-V (or
    /// any third-party keyboard) is current, switch back to the system one.
    private func ensureSystemKeyboard() {
        if app.keyboards.firstMatch.waitForExistence(timeout: 3) { return }
        pressGlobe()
        let english = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'English'")).firstMatch
        if english.waitForExistence(timeout: 3) { english.tap() }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "software keyboard")
    }

    private func pressGlobe() {
        let byLabel = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] 'next keyboard' OR label CONTAINS[c] 'keyboard switcher' OR identifier == 'Next keyboard'"))
            .firstMatch
        if byLabel.waitForExistence(timeout: 3) {
            byLabel.press(forDuration: 1.2)
        } else {
            let frame = app.frame
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: 46, dy: frame.height - 45))
                .press(forDuration: 1.2)
        }
    }

    private func switchToControlVKeyboard() {
        if app.descendants(matching: .any)["Translate and replace"].exists { return }
        let byLabel = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] 'next keyboard' OR label CONTAINS[c] 'keyboard switcher' OR identifier == 'Next keyboard'"))
            .firstMatch
        if byLabel.waitForExistence(timeout: 3) {
            NSLog("[uitest] globe found: %@", byLabel.debugDescription)
            byLabel.press(forDuration: 1.2)
        } else {
            NSLog("[uitest] globe not found by label; keyboard tree: %@", app.keyboards.firstMatch.debugDescription)
            let frame = app.frame
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: 46, dy: frame.height - 45))
                .press(forDuration: 1.2)
        }
        let item = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Control-V'")).firstMatch
        if item.waitForExistence(timeout: 3) {
            item.tap()
        } else {
            NSLog("[uitest] Control-V not in the input mode list; tree: %@", app.debugDescription.prefix(6000).description)
        }
        sleep(2)
    }

    private func openKeyboardsList() {
        settings.launch()
        tapRow("General")
        tapRow("Keyboard")
        tapRow("Keyboards")
        XCTAssertTrue(settings.navigationBars["Keyboards"].waitForExistence(timeout: 5))
    }

    private func tapRow(_ label: String) { tapRow(label, prefix: false) }
    private func tapRow(prefix: String) { tapRow(prefix, prefix: true) }

    /// Settings repeats labels (row, section header, navigation title) and
    /// draws some rows as buttons, so prefer the text inside a cell, then a
    /// button, then any text.
    private func tapRow(_ label: String, prefix: Bool) {
        let predicate = NSPredicate(format: prefix ? "label BEGINSWITH %@" : "label == %@", label)
        let candidates = [settings.cells.staticTexts.matching(predicate).firstMatch,
                          settings.buttons.matching(predicate).firstMatch,
                          settings.staticTexts.matching(predicate).firstMatch]
        // Rows that are off screen do not exist yet (lazy lists), so search
        // and scroll alternately.
        for pass in 0..<12 {
            for row in candidates where row.exists {
                scrollUntilHittable(row, in: settings)
                row.tap()
                return
            }
            if pass == 0 { sleep(1) } else { settings.swipeUp() }
        }
        XCTFail("row not found: \(label)")
    }

    private func scrollUntilHittable(_ element: XCUIElement, in host: XCUIApplication) {
        var swipes = 0
        _ = element.waitForExistence(timeout: 5)
        while !(element.exists && element.isHittable), swipes < 8 {
            host.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(element.exists, "row not found: \(element)")
    }

    private func save(_ name: String, of host: XCUIApplication) {
        let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] ?? "/tmp/controlv-uitests"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
        do {
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
            NSLog("[uitest] saved %@", url.path)
        } catch {
            NSLog("[uitest] could not save %@: %@", url.path, String(describing: error))
        }
    }
}
