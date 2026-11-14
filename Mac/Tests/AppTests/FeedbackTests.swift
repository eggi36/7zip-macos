// FeedbackTests.swift -- the user's review of 1.3.0 (2026-11-13): the About box's build line, no
// update check left in the app, a file 7-Zip can read opens inside the file manager.

import AppKit
import XCTest
@testable import SevenZipAppHost

final class FeedbackTests: AppHostTestCase {

    // MARK: - a file 7-Zip can read opens inside, whatever its extension

    /// An .epub (a zip) was one of 7zFM's kStartExtensions, started externally without trying;
    /// now Enter / a double-click opens it inside, as any archive.
    func testAnEpubOpensInsideTheFileManager() throws {
        let fm = FileManager.default
        let dir = (NSTemporaryDirectory() as NSString).appendingPathComponent("sz-open-\(UUID().uuidString)")
        let src = dir + "/src"
        try fm.createDirectory(atPath: src, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: dir) }
        try Data("chapter one\n".utf8).write(to: URL(fileURLWithPath: src + "/chapter.xhtml"))
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", src, dir + "/book.epub"]
        try ditto.run()
        ditto.waitUntilExit()
        XCTAssertEqual(ditto.terminationStatus, 0)

        let savedPanels = Settings.numPanels, savedPath = Settings.panelPath(0), savedMode = Settings.listMode(0)
        Settings.numPanels = 1
        Settings.setListMode(3, 0)
        let controller = MainWindowController()
        controller.showWindow(nil)
        defer {
            controller.window?.close()
            Settings.numPanels = savedPanels
            Settings.setPanelPath(savedPath, 0)
            Settings.setListMode(savedMode, 0)
        }
        let panel = controller.focusedPanel
        var bound = false
        panel.navigate(to: dir) { _ in bound = true }
        XCTAssertTrue(wait(for: "the folder") { bound })
        let row = try XCTUnwrap(panel.rows.first { $0.name == "book.epub" })
        panel.openRow(row, insideOnly: false, formatHint: nil)
        XCTAssertTrue(wait(for: "inside book.epub") { panel.currentPath.hasSuffix("book.epub/") },
                      "opened inside, not handed to Books: \(panel.currentPath)")
        XCTAssertTrue(panel.rows.contains { $0.name == "chapter.xhtml" })
    }

    // MARK: - Quick Look inside an archive

    /// Space on a file inside a zip previews a temp copy of it; the copy goes when the panel
    /// leaves the archive.
    func testQuickLookInsideAnArchiveShowsATempCopy() throws {
        let fm = FileManager.default
        let dir = (NSTemporaryDirectory() as NSString).appendingPathComponent("sz-ql-\(UUID().uuidString)")
        let src = dir + "/src"
        try fm.createDirectory(atPath: src + "/sub", withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: dir) }
        try Data("look at me\n".utf8).write(to: URL(fileURLWithPath: src + "/note.txt"))
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", src, dir + "/box.zip"]
        try ditto.run()
        ditto.waitUntilExit()

        let savedPanels = Settings.numPanels, savedPath = Settings.panelPath(0), savedMode = Settings.listMode(0)
        Settings.numPanels = 1
        Settings.setListMode(3, 0)
        let controller = MainWindowController()
        controller.showWindow(nil)
        defer {
            controller.window?.close()
            Settings.numPanels = savedPanels
            Settings.setPanelPath(savedPath, 0)
            Settings.setListMode(savedMode, 0)
        }
        let panel = controller.focusedPanel
        var bound = false
        panel.navigate(to: dir) { _ in bound = true }
        XCTAssertTrue(wait(for: "the folder") { bound })
        panel.openRow(try XCTUnwrap(panel.rows.first { $0.name == "box.zip" }), insideOnly: false, formatHint: nil)
        XCTAssertTrue(wait(for: "inside box.zip") { panel.currentPath.hasSuffix("box.zip/") })

        let index = try XCTUnwrap(panel.rows.firstIndex { $0.name == "note.txt" })
        panel.tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        panel.prepareArchivePreviews()
        let paths = panel.quickLookPaths
        XCTAssertEqual(paths.count, 1)
        let copy = try XCTUnwrap(paths.first)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: copy)), Data("look at me\n".utf8))
        // a folder is not extracted for a preview
        let sub = try XCTUnwrap(panel.rows.firstIndex { $0.name == "sub" })
        panel.tableView.selectRowIndexes(IndexSet(integer: sub), byExtendingSelection: false)
        panel.prepareArchivePreviews()
        XCTAssertTrue(panel.quickLookPaths.isEmpty)
        // back on disk: the copy is gone
        bound = false
        panel.navigate(to: dir) { _ in bound = true }
        XCTAssertTrue(wait(for: "back on disk") { bound })
        panel.prepareArchivePreviews()
        XCTAssertFalse(fm.fileExists(atPath: copy), "the temp copy is removed")
    }

    // MARK: - Options > Settings: the theme row starts at the margin

    func testThemePopupFollowsItsLabel() throws {
        let options = OptionsWindowController.shared
        defer { if let w = options.window, w.isVisible { ModalProbe.close(w) } }
        var page: OptionsSettingsPage?
        XCTAssertTrue(ModalProbe.present({ OptionsWindowController.showOptions() }) { window in
            options.selectPage(4)
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            page = window.contentView?.subviews.compactMap { $0 as? NSTabView }.first?
                .selectedTabViewItem?.viewController as? OptionsSettingsPage
        })
        let settings = try XCTUnwrap(page)
        let label = settings.themeLabel.frame, popup = settings.themePopup.frame
        let text = ceil(settings.themeLabel.intrinsicContentSize.width)
        XCTAssertEqual(label.minX, settings.quickLookBox.frame.minX, accuracy: 4, "the row starts at the checkboxes' edge")
        XCTAssertLessThanOrEqual(popup.minX - label.minX, text + 16, "the pop-up right after \"\(settings.themeLabel.stringValue)\"")
        XCTAssertGreaterThan(popup.minX, label.minX + text, "no overlap")
    }

    // MARK: - About: a build line unique to every compile

    func testBuildLine() {
        XCTAssertEqual(PortVersion.buildLine(build: "402", stamp: "2026-11-13 21:50:07 1faab4b0c2"),
                       "Build 402 (2026-11-13 21:50:07 1faab4b0c2)")
        XCTAssertEqual(PortVersion.buildLine(build: "402", stamp: ""), "Build 402", "a copy without the stamp phase")
    }

    // MARK: - no update check

    func testNoUpdateCheckInTheMenus() {
        func all(_ menu: NSMenu) -> [NSMenuItem] { menu.items + menu.items.compactMap(\.submenu).flatMap(all) }
        let titles = all(MainMenu.build()).map(\.title)
        XCTAssertFalse(titles.contains { $0.localizedCaseInsensitiveContains("update") }, "\(titles)")
        XCTAssertNil(NSClassFromString("SevenZipAppHost.UpdateCheck"))
    }

    /// "~" in a typed archive or destination path is the home folder (review finding).
    func testTildeMeansTheHomeFolder() {
        let home = NSHomeDirectory()
        XCTAssertEqual(CompressDialogController.expandingTilde("~/Desktop/a.7z"), home + "/Desktop/a.7z")
        XCTAssertEqual(CompressDialogController.expandingTilde("~"), home)
        XCTAssertEqual(CompressDialogController.expandingTilde("a~b.7z"), "a~b.7z")
        XCTAssertEqual(CompressDialogController.expandingTilde("~old.7z"), "~old.7z")
    }
}
