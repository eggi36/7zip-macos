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
}
