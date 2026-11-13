// MacLookUITests.swift -- the Mac look driven through the real event stream: the Settings window
// and its toolbar of panes, dialogs and alerts as sheets of the main window, the Mac menus and
// keys, window tabs, the Finder path bar and Undo for Move to Trash (CHANGELOG "Mac look").
//
// Input shard: every test types or clicks. Each test gets a process of its own.

import Foundation
import XCTest

final class MacLookUITests: SevenZipUITestCase {

    override var screenshotPrefix: String { "maclook" }
    override class var reusesTheApp: Bool { false }

    private func launchMac(_ values: [String: String] = [:]) {
        var seed = values
        if seed[SettingsDomain.Key.panelPath0] == nil { seed[SettingsDomain.Key.panelPath0] = TestPaths.fixtures }
        launch(seed: .values(seed))
        XCTAssertTrue(sevenZip.panel(0).waitForRow(named: "test.7z") || values[SettingsDomain.Key.panelPath0] != nil)
    }

    /// A scratch folder with `names` as small text files, removed after the test.
    private func makeScratch(_ name: String, files names: [String]) throws -> String {
        let fm = FileManager.default
        let base = (TestPaths.artifacts as NSString).appendingPathComponent("maclook-\(name)-\(UUID().uuidString.prefix(8))")
        try fm.createDirectory(atPath: base, withIntermediateDirectories: true)
        for file in names {
            try Data(file.utf8).write(to: URL(fileURLWithPath: (base as NSString).appendingPathComponent(file)))
        }
        addTeardownBlock { [weak sevenZip] in
            sevenZip?.terminate()
            try? fm.removeItem(atPath: base)
        }
        return base
    }

    private func element(labelled label: String, in root: XCUIElement) -> XCUIElement {
        root.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ OR title == %@", label, label)).firstMatch
    }

    // MARK: menus

    func testMenusUseMacNamesAndKeys() {
        launchMac()
        let titles = sevenZip.topLevelMenuTitles
        XCTAssertTrue(titles.contains("Go"), "Finder's Go menu: \(titles)")
        let app = sevenZip.itemTitles(in: SevenZipApp.appMenuTitle)
        XCTAssertTrue(app.contains("Settings…"), "app menu: \(app)")
        let file = sevenZip.itemTitles(in: "File")
        for title in ["New Window", "New Tab", "Move to Trash", "Get Info", "New Folder", "Close Window"] {
            XCTAssertTrue(file.contains(title), "File lacks \(title): \(file)")
        }
        let edit = sevenZip.itemTitles(in: "Edit")
        XCTAssertEqual(edit.first, "Undo", "Edit: \(edit)")
        let view = sevenZip.itemTitles(in: "View")
        XCTAssertTrue(view.contains("Hide Path Bar") || view.contains("Show Path Bar"), "View: \(view)")
        sevenZip.closeOpenMenus()
    }

    // MARK: Settings window

    func testSettingsWindowSwitchesPanesFromItsToolbar() {
        launchMac()
        app.typeKey(",", modifierFlags: .command)
        let settings = app.windows.containing(NSPredicate(format: "label == 'Language' OR title == 'Language'")).firstMatch
        let opened = settings.waitForExistence(timeout: 15)
        if !opened { sevenZip.dumpTree("maclook-settings") }
        XCTAssertTrue(opened, "Cmd+, opened no Settings window")
        let language = element(labelled: "Language", in: settings.toolbars.firstMatch)
        XCTAssertTrue(language.waitForExistence(timeout: 5), "no Language pane in the toolbar")
        language.click()
        XCTAssertTrue(waitFor("the Language pane") { settings.title == "Language" }, "title: \(settings.title)")
        XCTAssertFalse(settings.buttons["OK"].exists, "a Settings window has no OK / Cancel")
        screenshot("settings-language")
        settings.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(waitFor("Settings closed") { !settings.exists })
    }

    // MARK: sheets

    func testExtractDialogIsASheetOfTheWindow() {
        launchMac()
        let panel = sevenZip.panel(0)
        panel.select("test.7z")
        sevenZip.toolbarButton("Extract").click()
        let sheet = sevenZip.window.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 15), "Extract did not open as a sheet")
        XCTAssertTrue(sheet.buttons["Cancel"].exists)
        screenshot("extract-sheet")
        sheet.buttons["Cancel"].click()
        XCTAssertTrue(waitFor("sheet closed") { self.sevenZip.window.sheets.count == 0 })
    }

    func testDeleteImmediatelyAsksInASheetAndCancelKeepsTheFile() throws {
        let scratch = try makeScratch("delete", files: ["keep-me.txt"])
        launchMac([SettingsDomain.Key.panelPath0: scratch])
        let panel = sevenZip.panel(0)
        XCTAssertTrue(panel.waitForRow(named: "keep-me.txt"))
        panel.select("keep-me.txt")
        app.typeKey(.delete, modifierFlags: [.command, .option])       // File > Delete Immediately…
        // An NSAlert-style sheet attached to the main window (AX role Sheet).
        let sheet = sevenZip.window.sheets.firstMatch
        let asked = sheet.waitForExistence(timeout: 15)
        if !asked { sevenZip.dumpTree("maclook-delete") }
        XCTAssertTrue(asked, "the confirmation is not a sheet")
        screenshot("delete-sheet")
        let cancel = sheet.buttons["Cancel"]
        XCTAssertTrue(cancel.exists, "buttons: \(sheet.buttons.allElementsBoundByIndex.map(\.title))")
        cancel.click()
        XCTAssertTrue(waitFor("sheet closed") { !sheet.exists })
        XCTAssertTrue(FileManager.default.fileExists(atPath: scratch + "/keep-me.txt"))
    }

    // MARK: Quick Look follows the selection

    /// Something in the Quick Look window that names the file it shows: its title bar's name or
    /// the text preview (each scratch file holds its own name).
    private func quickLookWindow(showing name: String) -> XCUIElement {
        app.windows["Quick Look"].descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@ OR title CONTAINS %@ OR value CONTAINS %@", name, name, name))
            .firstMatch
    }

    /// Space opens Quick Look on the selection; the arrows move the list under it and the preview
    /// follows -- in Details, after switching to Large Icons (Cmd-1) and back (Cmd-4), where it
    /// used to keep the old file (the user's finding).
    func testQuickLookFollowsTheSelectionAcrossViewModes() throws {
        let scratch = try makeScratch("ql", files: ["a.txt", "b.txt", "c.txt", "d.txt"])
        launchMac([SettingsDomain.Key.panelPath0: scratch])
        let panel = sevenZip.panel(0)
        XCTAssertTrue(panel.waitForRow(named: "a.txt"))
        panel.select("a.txt")
        app.typeKey(" ", modifierFlags: [])
        let opened = quickLookWindow(showing: "a.txt").waitForExistence(timeout: 15)
        if !opened { sevenZip.dumpTree("maclook-ql-open"); print(app.windows["Quick Look"].debugDescription) }
        XCTAssertTrue(opened, "Space opened no preview of a.txt: \(app.windows.allElementsBoundByIndex.map(\.title))")
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(quickLookWindow(showing: "b.txt").waitForExistence(timeout: 10),
                      "Details, Down: \(app.windows.allElementsBoundByIndex.map(\.title))")
        sevenZip.window.click()                                     // the main window in front again
        app.typeKey("1", modifierFlags: .command)                   // View > Large Icons
        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(quickLookWindow(showing: "c.txt").waitForExistence(timeout: 10),
                      "Large Icons, Right: \(app.windows.allElementsBoundByIndex.map(\.title))")
        app.typeKey("4", modifierFlags: .command)                   // View > Details
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(quickLookWindow(showing: "d.txt").waitForExistence(timeout: 10),
                      "Details again, Down: \(app.windows.allElementsBoundByIndex.map(\.title))")
        screenshot("quicklook-follows")
        app.typeKey(.escape, modifierFlags: [])
    }

    // MARK: Undo Move to Trash

    func testMoveToTrashAndUndoPutsTheFileBack() throws {
        let scratch = try makeScratch("trash", files: ["trash-me.txt", "stay.txt"])
        let file = scratch + "/trash-me.txt"
        launchMac([SettingsDomain.Key.panelPath0: scratch])
        let panel = sevenZip.panel(0)
        XCTAssertTrue(panel.waitForRow(named: "trash-me.txt"))
        panel.select("trash-me.txt")
        app.typeKey(.delete, modifierFlags: .command)                   // File > Move to Trash
        XCTAssertTrue(waitFor("file trashed") { !FileManager.default.fileExists(atPath: file) })
        XCTAssertTrue(waitFor("row gone") { !panel.hasRow(named: "trash-me.txt") })
        app.typeKey("z", modifierFlags: .command)                       // Edit > Undo Move to Trash
        XCTAssertTrue(waitFor("file put back") { FileManager.default.fileExists(atPath: file) })
        XCTAssertTrue(panel.waitForRow(named: "trash-me.txt"), "rows: \(panel.names)")
    }

    // MARK: window tabs

    func testNewTabOpensASecondTabInTheWindow() {
        launchMac()
        app.typeKey("t", modifierFlags: .command)                       // File > New Tab
        let tabs = sevenZip.window.tabGroups.firstMatch
        let two = waitFor("two tabs") { tabs.exists && tabs.tabs.count == 2 }
        if !two { sevenZip.dumpTree("maclook-tabs") }
        XCTAssertTrue(two, "tab bar: \(tabs.exists ? "\(tabs.tabs.count) tabs" : "none")")
        screenshot("tabs")
        XCTAssertEqual(app.windows.count, 1, "a tab, not a second window")
        app.typeKey("w", modifierFlags: .command)                       // closes the new tab
        XCTAssertTrue(waitFor("one tab left") { !tabs.exists || tabs.tabs.count < 2 })
    }

    // MARK: path bar

    func testPathBarOpensAnEnclosingFolder() {
        launchMac()
        let panel = sevenZip.panel(0)
        let bar = sevenZip.window.descendants(matching: .any)["sz.panel.pathControl"]
        XCTAssertTrue(bar.waitForExistence(timeout: 10), "no path bar")
        let parent = (TestPaths.fixtures as NSString).deletingLastPathComponent
        let parentName = (parent as NSString).lastPathComponent
        // NSPathControl's parts are static texts whose value is the part's title.
        let part = bar.staticTexts.matching(NSPredicate(format: "value == %@", parentName)).firstMatch
        XCTAssertTrue(part.waitForExistence(timeout: 5), "no \(parentName) part in the path bar")
        part.click()
        XCTAssertTrue(panel.waitForPath(parent + "/") || panel.waitForPath(parent), "panel shows \(panel.path)")
        XCTAssertTrue(panel.waitForRow(named: "Fixtures"))
        screenshot("path-bar")
    }
}
