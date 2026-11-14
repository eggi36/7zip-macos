// ShowcaseUITests.swift -- the showcase images that need the real app on screen, taken in the
// neutral demo folder `/Users/Shared/7-Zip Demo/` that `ShowcaseScreenshotTests` (app-hosted)
// creates: the panel's context menu with the 7-Zip submenu open, and the README's window images
// (`testReadmeImages`): real screenshots of the windows, title bar and toolbar included, with the
// file icons Finder shows -- what the in-process renders cannot give on macOS 27.
//
// Opt-in like the app-hosted half: runs only when `Mac/build/showcase/RUN` exists (or
// SEVENZIP_SHOWCASE=1 is in the runner's environment) and the demo folder exists. `Mac/scripts/showcase.sh` runs both.
// The screenshot is an XCTest attachment that test.sh exports to Mac/build/screenshots/.

import AppKit
import XCTest

final class ShowcaseUITests: SevenZipUITestCase {

    override var screenshotPrefix: String { "showcase" }

    private static let demo = "/Users/Shared/7-Zip Demo"

    private func requireShowcase() throws {
        let flag = (TestPaths.repoRoot ?? "/nonexistent") + "/Mac/build/showcase/RUN"
        guard ProcessInfo.processInfo.environment["SEVENZIP_SHOWCASE"] == "1"
                || FileManager.default.fileExists(atPath: flag) else {
            throw XCTSkip("showcase images are opt-in: Mac/scripts/showcase.sh")
        }
        guard FileManager.default.fileExists(atPath: Self.demo + "/Photos 2025.zip") else {
            throw XCTSkip("no demo folder; run ShowcaseScreenshotTests first (Mac/scripts/showcase.sh)")
        }
    }

    /// A window's screenshot as the attachment `showcase-readme-<name>.png` (test.sh exports it).
    private func shot(_ element: XCUIScreenshotProviding, _ name: String) {
        let attachment = XCTAttachment(screenshot: element.screenshot())
        attachment.name = "showcase-readme-\(name).png"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func labelled(_ label: String, in root: XCUIElement) -> XCUIElement {
        root.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ OR title == %@ OR identifier == %@", label, label, label)).firstMatch
    }

    /// A window or dialog (AX subrole dialog: the app's own dialogs) whose title is `title`.
    private func window(titled title: String) -> XCUIElement {
        let byTitle = NSPredicate(format: "title == %@", title)
        let dialog = sevenZip.app.dialogs.matching(byTitle).firstMatch
        return dialog.exists ? dialog : sevenZip.app.windows.matching(byTitle).firstMatch
    }

    /// Waits until a window or dialog titled `title` appears.
    private func waitForWindow(titled title: String, timeout: TimeInterval = 15) -> XCUIElement? {
        var found: XCUIElement?
        _ = waitFor(title, timeout: timeout) {
            let w = window(titled: title)
            if w.exists { found = w; return true }
            return false
        }
        return found
    }

    /// The README images: the main window (870 x 500 pt) in Light and Dark, then, in Light, Add to
    /// Archive, Extract, the Properties of an item inside an archive, Benchmark, and Options >
    /// Settings / System.
    func testReadmeImages() throws {
        try requireShowcase()
        for theme in ["light", "dark"] {
            launch(seed: .values([SettingsDomain.Key.panelPath0: Self.demo, "FM.Theme": theme,
                                  SettingsDomain.Key.position: "{{160, 240}, {870, 500}}"]))
            let panel = sevenZip.panel(0)
            XCTAssertTrue(panel.waitForRow(named: "Project backup.7z"))
            panel.select("Project backup.7z")
            sleep(1)
            shot(sevenZip.window, "main-\(theme)")
            sevenZip.terminate()
        }

        // The dialogs, in Light, from a window big enough for its sheets; each image is the dialog.
        launch(seed: .values([SettingsDomain.Key.panelPath0: Self.demo, "FM.Theme": "light",
                              SettingsDomain.Key.position: "{{80, 60}, {1180, 860}}"]))
        let app = sevenZip.app
        let panel = sevenZip.panel(0)
        XCTAssertTrue(panel.waitForRow(named: "Project backup.7z"))
        func closeSheet(_ sheet: XCUIElement) {
            let cancel = sheet.buttons["Cancel"]
            if cancel.exists { cancel.click() } else { app.typeKey(.escape, modifierFlags: []) }
            _ = waitFor("sheet closed") { !sheet.exists }
        }

        // Add to Archive on the Documents folder
        panel.select("Documents")
        labelled("Add", in: sevenZip.window.toolbars.firstMatch).click()
        let add = sevenZip.window.sheets.firstMatch
        if add.waitForExistence(timeout: 15) { sleep(1); shot(add, "add-to-archive"); closeSheet(add) }
        else { XCTFail("no Add to Archive sheet"); sevenZip.dumpTree("showcase-add") }

        // Extract Photos 2025.zip
        panel.select("Photos 2025.zip")
        labelled("Extract", in: sevenZip.window.toolbars.firstMatch).click()
        let extract = sevenZip.window.sheets.firstMatch
        if extract.waitForExistence(timeout: 15) { sleep(1); shot(extract, "extract"); closeSheet(extract) }
        else { XCTFail("no Extract sheet"); sevenZip.dumpTree("showcase-extract") }

        // Properties of an item inside an archive
        panel.open("Project backup.7z")
        XCTAssertTrue(waitFor("inside the archive") { sevenZip.windowTitle == "Project backup.7z" })
        sleep(1)
        sevenZip.window.tables.firstMatch.click()
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.downArrow, modifierFlags: [])                       // past ".." to the first item
        XCTAssertTrue(sevenZip.selectMenuItem("File", "Get Info"), "no File > Get Info")
        if let info = waitForWindow(titled: "Properties") {
            sleep(1); shot(info, "properties")
            info.buttons["OK"].click()
        } else { XCTFail("no Properties: \(app.windows.allElementsBoundByIndex.map(\.title))") }
        app.typeKey(.upArrow, modifierFlags: .command)                   // back to the folder
        sleep(1)

        // Benchmark
        XCTAssertTrue(sevenZip.selectMenuItem("Tools", "Benchmark"))
        if let bench = waitForWindow(titled: "Benchmark") {
            sleep(6); shot(bench, "benchmark")
            let close = bench.buttons["Cancel"]
            if close.exists { close.click() } else { bench.typeKey(.escape, modifierFlags: []) }
        } else { XCTFail("no Benchmark: \(app.windows.allElementsBoundByIndex.map(\.title))") }
        app.typeKey(.escape, modifierFlags: [])
        sleep(1)

        // Options > Settings and System
        app.typeKey(",", modifierFlags: .command)
        let settings = app.windows.containing(NSPredicate(format: "label == 'Language' OR title == 'Language'")).firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 15), "no Settings window")
        for (pane, name) in [("Settings", "options-settings"), ("System", "options-system")] {
            labelled(pane, in: settings.toolbars.firstMatch).click()
            XCTAssertTrue(waitFor(pane) { settings.title == pane }, "title: \(settings.title)")
            sleep(1)
            shot(settings, name)
        }
        settings.typeKey("w", modifierFlags: .command)
        sevenZip.terminate()
    }

    func testContextMenuImage() throws {
        let flag = (TestPaths.repoRoot ?? "/nonexistent") + "/Mac/build/showcase/RUN"
        guard ProcessInfo.processInfo.environment["SEVENZIP_SHOWCASE"] == "1"
                || FileManager.default.fileExists(atPath: flag) else {
            throw XCTSkip("showcase images are opt-in: Mac/scripts/showcase.sh")
        }
        guard FileManager.default.fileExists(atPath: Self.demo + "/Photos 2025.zip") else {
            throw XCTSkip("no demo folder; run ShowcaseScreenshotTests first (Mac/scripts/showcase.sh)")
        }
        launch(seed: .values([SettingsDomain.Key.panelPath0: Self.demo]))
        let panel = sevenZip.panel(0)
        XCTAssertTrue(panel.waitForRow(named: "Photos 2025.zip"))
        panel.select("Photos 2025.zip")
        guard let menu = panel.openContextMenu(onRow: "Photos 2025.zip") else {
            return XCTFail("no context menu on Photos 2025.zip")
        }
        let sevenZipItem = menu.menuItems["7-Zip"]
        sevenZipItem.hover()
        let sub = sevenZipItem.menus.firstMatch
        XCTAssertTrue(sub.waitForExistence(timeout: 5), "the 7-Zip submenu did not open")
        screenshot("context-menu")
        sevenZip.app.typeKey(.escape, modifierFlags: [])
        sevenZip.app.typeKey(.escape, modifierFlags: [])
    }


    /// The README's Finder image: Finder's own right-click menu on `Photos 2025.zip` in the demo
    /// folder with the 7-Zip submenu open (03 §1.4), cut out to exactly the Finder window.
    ///
    /// * Finder is relaunched in English (`-AppleLanguages (en)`) so the image matches the English
    ///   README, and relaunched as the user has it in teardown. Nothing below looks up a Finder title
    ///   except the "Get Info" check that the relaunch took effect.
    /// * The shot is taken in a window of its own (⌘N, then Go to Folder), never in one of the
    ///   user's windows; teardown blocks -- which run even after a failure -- show the sidebar again
    ///   and close that window.
    /// * The sidebar, which shows the user's name, is hidden with ⌃⌘S; whether the toggle hid or
    ///   showed it is read from where the file's row moved, not from a menu title.
    /// * Only the menu is opened: whichever copy's Finder extension Finder runs builds it, nothing is
    ///   chosen. Submenus are entered with the arrow keys, as in `FinderContextMenuTests`.
    /// * The image is the window only, with transparent rounded corners: the menus must fit inside it
    ///   (checked), so nothing behind the window -- desktop, other apps -- can end up in the image.
    func testFinderContextMenuImage() throws {
        try requireShowcase()
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        let size = CGSize(width: 1100, height: 840)

        // An English Finder; afterwards the user's own Finder again.
        addTeardownBlock {
            finder.terminate()
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"),
                                               configuration: NSWorkspace.OpenConfiguration())
        }
        finder.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        finder.launch()
        finder.activate()

        // A window of its own, in the demo folder.
        finder.typeKey("n", modifierFlags: .command)
        let window = finder.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10), "Finder opened no window")
        let sidebar = SidebarState()
        addTeardownBlock {
            finder.typeKey(.escape, modifierFlags: [])
            finder.typeKey(.escape, modifierFlags: [])
            if sidebar.hidden { finder.typeKey("s", modifierFlags: [.control, .command]) }
            finder.typeKey("w", modifierFlags: .command)
        }
        finder.typeKey("g", modifierFlags: [.shift, .command])
        sleep(1)
        finder.typeText(Self.demo + "\n")
        XCTAssertTrue(waitFor("the demo folder in Finder", timeout: 15) { window.title == "7-Zip Demo" },
                      "Finder did not go to the demo folder (window: \(window.title))")
        finder.typeKey("2", modifierFlags: .command)     // as List

        // Top left of the main display, then the size of the image.
        guard let display = NSScreen.screens.first else { return XCTFail("no display") }
        let titleBar = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: 12))
        let target = CGPoint(x: 60, y: display.frame.height - display.visibleFrame.maxY + 40)
        titleBar.press(forDuration: 0.3, thenDragTo: titleBar.withOffset(
            CGVector(dx: target.x - window.frame.minX, dy: target.y - window.frame.minY)))
        let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1)).withOffset(CGVector(dx: -3, dy: -3))
        corner.press(forDuration: 0.3, thenDragTo: window.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: size.width - 3, dy: size.height - 3)))
        sleep(1)
        XCTAssertEqual(window.frame.width, size.width, accuracy: 4, "the window was not resized: \(window.frame)")
        XCTAssertEqual(window.frame.height, size.height, accuracy: 4, "the window was not resized: \(window.frame)")

        let item = window.descendants(matching: .any).matching(NSPredicate(format: "value == %@", "Photos 2025.zip")).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 15), "Finder did not show Photos 2025.zip")

        // Hide the sidebar: the row moves left when it goes, right when it comes back.
        let before = item.frame.minX - window.frame.minX
        finder.typeKey("s", modifierFlags: [.control, .command])
        XCTAssertTrue(waitFor("the sidebar toggle", timeout: 5) { abs(item.frame.minX - window.frame.minX - before) > 20 },
                      "⌃⌘S did not toggle the sidebar")
        if item.frame.minX - window.frame.minX < before {
            sidebar.hidden = true
        } else {                                            // it was hidden already: undo
            finder.typeKey("s", modifierFlags: [.control, .command])
            sleep(1)
        }

        item.click()
        item.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).rightClick()

        // The context menu is the one with the 7-Zip row.
        var context: XCUIElementSnapshot?
        _ = waitFor("context menu", timeout: 10) {
            context = FinderMenus.visible(in: finder).first { FinderMenus.rows(of: $0).contains { $0.title == "7-Zip" } }
            return context != nil
        }
        guard let menu = context else {
            throw XCTSkip("Finder shows no 7-Zip submenu: the Finder extension is not enabled")
        }
        let top = FinderMenus.rows(of: menu)
        XCTAssertTrue(top.contains { $0.title == "Get Info" }, "Finder is not running in English: \(top.map(\.title))")
        guard let index = top.firstIndex(where: { $0.title == "7-Zip" }) else { return XCTFail("no 7-Zip row") }
        for _ in index..<top.count { finder.typeKey(.upArrow, modifierFlags: []) }
        finder.typeKey(.rightArrow, modifierFlags: [])
        var submenu: XCUIElementSnapshot?
        _ = waitFor("7-Zip submenu", timeout: 10) {
            submenu = FinderMenus.visible(in: finder).first { $0.frame != menu.frame && $0.frame.minX > menu.frame.minX }
            return submenu != nil
        }
        guard let sub = submenu else { return XCTFail("the 7-Zip submenu did not open") }
        sleep(1)

        // The window only: the menus have to lie inside it.
        let frame = window.frame
        XCTAssertTrue(frame.contains(menu.frame) && frame.contains(sub.frame),
                      "the menus stick out of the window \(frame): \(menu.frame), \(sub.frame)")
        let screen = XCUIScreen.main.screenshot().image
        guard let cg = screen.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return XCTFail("no screen image")
        }
        let scale = CGFloat(cg.width) / display.frame.width
        XCTAssertEqual(scale, display.backingScaleFactor, accuracy: 0.01,
                       "the screenshot is not of the main display (\(cg.width) px for \(display.frame.width) pt)")
        XCTAssertTrue(CGRect(origin: .zero, size: display.frame.size).contains(frame),
                      "the window is not on the main display: \(frame)")
        let pixels = CGRect(x: frame.minX * scale, y: frame.minY * scale,
                            width: frame.width * scale, height: frame.height * scale).integral
        guard let cropped = cg.cropping(to: pixels),
              let context2 = CGContext(data: nil, width: cropped.width, height: cropped.height, bitsPerComponent: 8,
                                       bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return XCTFail("crop failed: \(pixels)")
        }
        // Transparent corners: what is behind the window's rounded corners stays out.
        let bounds = CGRect(x: 0, y: 0, width: cropped.width, height: cropped.height)
        let radius = 26 * scale
        context2.addPath(CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context2.clip()
        context2.draw(cropped, in: bounds)
        guard let masked = context2.makeImage(),
              let png = NSBitmapImageRep(cgImage: masked).representation(using: .png, properties: [:]) else {
            return XCTFail("could not encode the image")
        }
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = "showcase-readme-finder-context-menu.png"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// Whether the Finder test hid the sidebar, for its teardown block.
private final class SidebarState: @unchecked Sendable {
    var hidden = false
}
