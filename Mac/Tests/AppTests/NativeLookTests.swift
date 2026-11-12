// NativeLookTests.swift -- native-look: the main window in the Mac look (AppLook.swift) keeps every
// command of the Classic window and draws it with AppKit's chrome; the Classic look is unchanged.
// Writes Mac/build/screenshots/nativelook-<name>.png: the whole window (title bar and toolbar
// included) in Light and Dark, in the demo folder of the showcase images.

import AppKit
import SevenZipKit
import XCTest
@testable import SevenZipAppHost

final class NativeLookTests: AppHostTestCase {

    override var screenshotPrefix: String { "nativelook" }

    private var controllers: [MainWindowController] = []
    private var savedLook: String?
    private var savedTheme: String?
    private var savedNumPanels = 1
    private var savedPanelPath: String?
    private var savedAppearance: NSAppearance?

    override func setUpWithError() throws {
        try super.setUpWithError()
        savedLook = Settings.string(Settings.Key.look)
        savedTheme = Settings.string(Settings.Key.theme)
        savedNumPanels = Settings.numPanels
        savedPanelPath = Settings.panelPath(0)
        savedAppearance = NSApp.appearance
    }

    override func tearDown() {
        for controller in controllers { controller.closeDiscardingState() }
        controllers = []
        Settings.setString(savedLook, Settings.Key.look)
        Settings.setString(savedTheme, Settings.Key.theme)
        Settings.numPanels = savedNumPanels
        Settings.setPanelPath(savedPanelPath, 0)
        NSApp.appearance = savedAppearance
        super.tearDown()
    }

    private static let toolbarDefaultsKey = "NSToolbar Configuration \(MainWindowController.macToolbarIdentifier)"

    private func openWindow(look: AppLook, panels: Int = 1) throws -> MainWindowController {
        UserDefaults.standard.removeObject(forKey: Self.toolbarDefaultsKey)   // a fresh arrangement
        Settings.look = look
        Settings.numPanels = panels
        let controller = MainWindowController()
        controllers.append(controller)
        let window = try XCTUnwrap(controller.window)
        window.setContentSize(NSSize(width: 900, height: 460))
        controller.showWindow(nil)
        return controller
    }

    private func show(_ controller: MainWindowController, _ folder: String) {
        let panel = controller.focusedPanel
        var done = false
        panel.navigate(to: folder) { _ in done = true }
        XCTAssertTrue(wait(for: "folder listed") { done && !panel.rows.isEmpty })
    }

    func testTestHarnessStartsInClassic() {
        Settings.removeKey(Settings.Key.look)
        XCTAssertEqual(Settings.look, .classic, "the parity tests describe the Windows window")
    }

    func testClassicLookIsUnchanged() throws {
        let controller = try openWindow(look: .classic)
        let window = try XCTUnwrap(controller.window)
        XCTAssertNil(window.toolbar, "Classic draws the Windows strip, not an NSToolbar")
        XCTAssertFalse(controller.toolbarView.isHidden)
        XCTAssertEqual(controller.toolbarView.buttons.count, 7)
        XCTAssertEqual(controller.focusedPanel.tableView.rowHeight, 19)
        XCTAssertEqual(controller.focusedPanel.tableView.style, .plain)
    }

    func testMacLookKeepsEveryToolbarCommand() throws {
        let controller = try openWindow(look: .mac)
        let window = try XCTUnwrap(controller.window)
        let toolbar = try XCTUnwrap(window.toolbar, "the Mac look uses an NSToolbar")
        XCTAssertTrue(controller.toolbarView.isHidden, "the Windows strip takes no room")
        let ids = toolbar.items.map(\.itemIdentifier)
        for id in [NSToolbarItem.Identifier.szAdd, .szExtract, .szTest, .szCopy, .szMove, .szDelete, .szInfo,
                   .szBack, .szForward] {
            XCTAssertTrue(ids.contains(id), "missing \(id.rawValue)")
        }
        // the same selectors as the Classic buttons
        for item in toolbar.items {
            guard let spec = MainWindowController.toolbarSpec(item.itemIdentifier, large: false) else { continue }
            XCTAssertEqual(item.action, spec.action, item.itemIdentifier.rawValue)
            XCTAssertNotNil(item.image, "\(item.itemIdentifier.rawValue) has an SF Symbol")
        }
        let table = controller.focusedPanel.tableView
        XCTAssertEqual(table.rowHeight, 24)
        XCTAssertEqual(table.style, .inset)
        XCTAssertTrue(table.usesAlternatingRowBackgroundColors)
    }

    func testMacLookFollowsToolbarMenus() throws {
        let saved = Settings.toolbarsMask
        defer { Settings.toolbarsMask = saved }
        Settings.toolbarsMask = 8 | 4 | 1
        let controller = try openWindow(look: .mac)
        let window = try XCTUnwrap(controller.window)
        XCTAssertEqual(window.toolbar?.displayMode, .iconAndLabel)
        controller.viewToolbarsShowButtonsText(nil)              // text off
        XCTAssertEqual(window.toolbar?.displayMode, .iconOnly)
        controller.viewArchiveToolbar(nil)                       // archive group off
        var ids = window.toolbar?.items.map(\.itemIdentifier) ?? []
        XCTAssertFalse(ids.contains(.szAdd))
        XCTAssertTrue(ids.contains(.szCopy))
        XCTAssertEqual(Settings.toolbarsMask & (8 | 4 | 1), 4, "the mask follows the toolbar")
        controller.viewArchiveToolbar(nil)                       // and back on, at the end
        ids = window.toolbar?.items.map(\.itemIdentifier) ?? []
        XCTAssertEqual(Array(ids.suffix(3)), MainWindowController.macArchiveGroup)
        UserDefaults.standard.removeObject(forKey: Self.toolbarDefaultsKey)
    }

    func testMacToolbarIsCustomizable() throws {
        let controller = try openWindow(look: .mac)
        let toolbar = try XCTUnwrap(controller.window?.toolbar)
        XCTAssertTrue(toolbar.allowsUserCustomization, "right-click > Customize Toolbar...")
        XCTAssertTrue(toolbar.autosavesConfiguration)
        let allowed = controller.toolbarAllowedItemIdentifiers(toolbar)
        for id in MainWindowController.macExtraItems {
            XCTAssertTrue(allowed.contains(id))
            let item = controller.toolbar(toolbar, itemForItemIdentifier: id, willBeInsertedIntoToolbar: false)
            XCTAssertNotNil(item?.image, "\(id.rawValue) has an SF Symbol")
            XCTAssertNotNil(item?.action)
            XCTAssertFalse(item?.label.hasSuffix("...") ?? true)
        }
        // a customised item survives a View > Toolbars change: groups are edited in place
        toolbar.insertItem(withItemIdentifier: .szRefresh, at: 2)
        controller.viewStandardToolbar(nil)
        XCTAssertTrue(toolbar.items.contains { $0.itemIdentifier == .szRefresh })
        UserDefaults.standard.removeObject(forKey: Self.toolbarDefaultsKey)
    }

    func testMacLookClickAnywhereInTheRowSelects() throws {
        // one look at a time: the look is app-wide (a change rebuilds every window)
        for (look, expected) in [(AppLook.classic, false), (.mac, true)] {
            let controller = try openWindow(look: look)
            show(controller, "/Applications")
            let table = controller.focusedPanel.tableView
            table.layoutSubtreeIfNeeded()
            let rowRect = table.rect(ofRow: 0)
            // a point near the row's right edge, in the date columns, far from the name
            let point = NSPoint(x: rowRect.maxX - 20, y: rowRect.midY)
            XCTAssertEqual(table.isOnItem(point, row: 0), expected,
                           look == .mac ? "Mac: the whole row is the item" : "Classic: only the name (LVHT_ONITEM)")
            controller.closeDiscardingState()
        }
    }

    func testMacLookTitleNamesTheFolder() throws {
        let controller = try openWindow(look: .mac)
        show(controller, "/Applications")
        let window = try XCTUnwrap(controller.window)
        XCTAssertTrue(wait(for: "title") { window.title == "Applications" })
        XCTAssertEqual(window.subtitle, "/")
        XCTAssertEqual(window.representedURL?.path, "/Applications")
    }

    func testLookChangeRebuildsTheWindow() throws {
        let controller = try openWindow(look: .classic)
        show(controller, "/Applications")
        MainWindows.register(controller)
        Settings.look = .mac
        MainWindows.rebuildForLookChange()
        // every registered window is rebuilt (the host app's own one too); ours is the one that
        // took over /Applications
        XCTAssertTrue(controller.isClosed, "the old window closes")
        controllers += MainWindows.controllers
        XCTAssertTrue(MainWindows.controllers.allSatisfy { $0.isMacLook && $0.window?.toolbar != nil })
        XCTAssertTrue(wait(for: "same folder") {
            MainWindows.controllers.contains { $0.isMacLook && $0.focusedPanel.currentPath.hasPrefix("/Applications") }
        })
        // put the host app's windows back into the Classic look the other tests expect
        Settings.look = .classic
        MainWindows.rebuildForLookChange()
    }

    func testRenderMacLook() throws {
        try ShowcaseDemo.make()
        try SZCodecs.loadCodecs()
        for theme in [AppTheme.light, .dark] {
            Settings.theme = theme
            let controller = try openWindow(look: .mac)
            show(controller, ShowcaseDemo.folder)
            let panel = controller.focusedPanel
            if let row = panel.rows.firstIndex(where: { $0.name == "Project backup.7z" }) {
                panel.tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                panel.focusedIndex = row
            }
            controller.window?.makeFirstResponder(panel.tableView)
            try writeWholeWindow(try XCTUnwrap(controller.window), "main-\(theme.rawValue)")

            Settings.numPanels = 2
            let two = try openWindow(look: .mac, panels: 2)
            two.window?.setContentSize(NSSize(width: 1100, height: 460))
            show(two, ShowcaseDemo.folder)
            try writeWholeWindow(try XCTUnwrap(two.window), "two-panels-\(theme.rawValue)")
            for c in [controller, two] { c.closeDiscardingState() }
        }
    }

    func testRenderMacDialogs() throws {
        try ShowcaseDemo.make()
        try SZCodecs.loadCodecs()
        Settings.look = .mac
        let demo = ShowcaseDemo.folder
        defer {
            while NSApp.modalWindow != nil { NSApp.abortModal() }
            if let w = OptionsWindowController.shared.window, w.isVisible { ModalProbe.close(w) }
        }
        for theme in [AppTheme.light, .dark] {
            Settings.theme = theme
            var input = CompressDialogInput()
            input.directoryPrefix = demo + "/"
            input.archiveBaseName = "Documents"
            input.itemPaths = [demo + "/Documents"]
            XCTAssertTrue(ModalProbe.present(timeout: 60, { _ = CompressDialogController.run(input) }) { w in
                try? self.writeWholeWindow(w, "add-\(theme.rawValue)")
            })
            var extract = ExtractDialog.Options()
            extract.directoryPath = demo + "/Photos 2025/"
            extract.archivePath = demo + "/Photos 2025.zip"
            XCTAssertTrue(ModalProbe.present({ _ = ExtractDialog.run(extract) }) { w in
                try? self.writeWholeWindow(w, "extract-\(theme.rawValue)")
            })
            let options = OptionsWindowController.shared
            let optionsWindow = try XCTUnwrap(options.window)
            XCTAssertTrue(ModalProbe.present({ OptionsWindowController.showOptions() }) { _ in })
            options.selectPage(options.pageCount - 1)
            let tabView = try XCTUnwrap(optionsWindow.contentView?.subviews.compactMap { $0 as? NSTabView }.first,
                                        "the Mac look uses AppKit's tab view")
            XCTAssertEqual(tabView.tabViewType, .topTabsBezelBorder)
            XCTAssertEqual(tabView.selectedTabViewItem?.label, "macOS")
            XCTAssertFalse(tabView.tabViewItems.contains { $0.label.isEmpty })
            try writeWholeWindow(optionsWindow, "options-macos-\(theme.rawValue)")
            options.selectPage(4)
            try writeWholeWindow(optionsWindow, "options-settings-\(theme.rawValue)")
            options.selectPage(0)                                   // System: the format icons
            try writeWholeWindow(optionsWindow, "options-system-\(theme.rawValue)")
            ModalProbe.close(optionsWindow)
        }
    }

    func testSystemPageShowsTheBundledIconsInTheMacLook() throws {
        guard let zip = FileTypes.all.first(where: { $0.ext == "zip" }) else { return XCTFail("no zip type") }
        let bundled = try XCTUnwrap(Bundle.main.url(forResource: "doc-zip", withExtension: "icns"))
        Settings.look = .mac
        let mac = try XCTUnwrap(OptionsSystemPage.formatIcon(for: zip))
        XCTAssertTrue(mac.representations.contains { $0 is NSBitmapImageRep && $0.pixelsWide >= 512 },
                      "the Mac look uses doc-zip.icns (\(bundled.lastPathComponent)), not the 16 px .ico frame")
        Settings.look = .classic
        let classic = try XCTUnwrap(OptionsSystemPage.formatIcon(for: zip))
        XCTAssertFalse(classic === mac, "Classic keeps the 7z.dll frame")
    }

    func testMacMessageBoxKeepsTheAnswersInMacOrder() throws {
        Settings.look = .mac
        let box = WinMessageBoxWindow(text: "Are you sure you want to delete 'notes.md'?", caption: "Confirm File Delete",
                                      buttons: .yesNoCancel, icon: .question, owner: nil)
        XCTAssertNotNil(box.macLayout)
        XCTAssertEqual(box.pushButtons.map(\.title), ["Yes", "No", "Cancel"], "same answers")
        XCTAssertTrue(box.defaultButtonCell === box.pushButtons.first?.cell, "Yes stays the default")
        let xs = box.pushButtons.map(\.frame.minX)
        XCTAssertGreaterThan(xs[0], xs[1], "the default sits rightmost")
        XCTAssertGreaterThan(xs[1], xs[2])
        Settings.look = .classic
        let classic = WinMessageBoxWindow(text: "x", caption: "c", buttons: .ok, icon: .none, owner: nil)
        XCTAssertNil(classic.macLayout)
    }

    func testRenderMacAlertsAndProgress() throws {
        Settings.look = .mac
        for theme in [AppTheme.light, .dark] {
            Settings.theme = theme
            let question = WinMessageBoxWindow(text: "Are you sure you want to delete 'notes.md'?",
                                               caption: "Confirm File Delete", buttons: .yesNoCancel,
                                               icon: .question, owner: nil)
            question.orderFront(nil)
            try writeWholeWindow(question, "alert-question-\(theme.rawValue)")
            question.orderOut(nil)
            let error = WinMessageBoxWindow(text: "Cannot open the file as archive:\n/Users/Shared/7-Zip Demo/presentation.key",
                                            caption: "7-Zip", buttons: .ok, icon: .error, owner: nil)
            error.orderFront(nil)
            try writeWholeWindow(error, "alert-error-\(theme.rawValue)")
            error.orderOut(nil)
            let progress = ProgressDialog(title: Lang.text(3300, "Extracting"), showCompressionInfo: true)
            progress.window.setContentSize(progress.window.contentMinSize)
            progress.window.orderFront(nil)
            try writeWholeWindow(progress.window, "progress-\(theme.rawValue)")
            progress.window.orderOut(nil)
        }
    }

    func testRenderMacRemainingViews() throws {
        try ShowcaseDemo.make()
        try SZCodecs.loadCodecs()
        Settings.theme = .light
        let controller = try openWindow(look: .mac)
        show(controller, ShowcaseDemo.folder)
        let panel = controller.focusedPanel
        let window = try XCTUnwrap(controller.window)
        for (mode, name) in [(0, "large-icons"), (1, "small-icons"), (2, "list")] {
            panel.setListViewMode(mode)
            _ = wait(for: "relayout", timeout: 0.5) { false }
            try writeWholeWindow(window, "view-\(name)")
        }
        panel.setListViewMode(3)
        panel.showAddressPopup()
        _ = wait(for: "popup", timeout: 0.5) { false }
        if let popup = AddressPopup.current?.panel {
            try writeWholeWindow(popup, "address-popup")
        }
        AddressPopup.current?.close()
        XCTAssertTrue(ModalProbe.present({ AboutDialog.show(parent: window) }) { w in
            try? self.writeWholeWindow(w, "about")
        })
        XCTAssertTrue(ModalProbe.present(timeout: 60, { BenchmarkDialog.run(parent: window) }) { w in
            try? self.writeWholeWindow(w, "benchmark")
        })
    }

    /// The window's frame view -- title bar, toolbar and content -- at 2x.
    private func writeWholeWindow(_ window: NSWindow, _ name: String) throws {
        let frameView = try XCTUnwrap(window.contentView?.superview)
        frameView.layoutSubtreeIfNeeded()
        frameView.displayIfNeeded()
        _ = wait(for: "draw", timeout: 0.5) { false }
        let bounds = frameView.bounds
        let rep = try XCTUnwrap(frameView.bitmapImageRepForCachingDisplay(in: bounds))
        frameView.cacheDisplay(in: bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let file = "\(screenshotPrefix)-\(name).png"
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = file
        attachment.lifetime = .keepAlways
        add(attachment)
        try FileManager.default.createDirectory(atPath: TestPaths.screenshots, withIntermediateDirectories: true)
        try png.write(to: URL(fileURLWithPath: TestPaths.screenshots).appendingPathComponent(file), options: .atomic)
    }
}
