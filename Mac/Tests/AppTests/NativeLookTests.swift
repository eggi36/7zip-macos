// NativeLookTests.swift -- the main window and the dialogs drawn with AppKit's chrome (Mac look):
// the toolbar, menus, Settings window, alerts and sheets, the path bar, window tabs, Undo for
// Move to Trash and the right-aligned form labels.

import AppKit
import Quartz
import SevenZipKit
import XCTest
@testable import SevenZipAppHost

final class NativeLookTests: AppHostTestCase {

    override var screenshotPrefix: String { "nativelook" }

    private var controllers: [MainWindowController] = []
    private var savedTheme: String?
    private var savedNumPanels = 1
    private var savedPanelPath: String?
    private var savedAppearance: NSAppearance?

    override func setUpWithError() throws {
        try super.setUpWithError()
        savedTheme = Settings.string(Settings.Key.theme)
        savedNumPanels = Settings.numPanels
        savedPanelPath = Settings.panelPath(0)
        savedAppearance = NSApp.appearance
    }

    /// Quick Look closes with an animation: wait until it is really gone, so the next test starts
    /// without a preview on screen.
    private func closeQuickLook() {
        guard QLPreviewPanel.sharedPreviewPanelExists(), let ql = QLPreviewPanel.shared() else { return }
        if ql.isVisible { ql.orderOut(nil) }
        if !wait(for: "Quick Look closed", timeout: 3, until: { !ql.isVisible }) { ql.close() }
    }

    /// Quick Look attaches to the key window's responder chain: the test app must be frontmost
    /// with the panel's list as first responder. When macOS keeps it in the background (someone
    /// is using the Mac), the preview cannot find its controller and the test is skipped.
    private func makeListKey(_ controller: MainWindowController) throws {
        let window = try XCTUnwrap(controller.window)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(controller.focusedPanel.tableView)
        try XCTSkipUnless(wait(for: "key window", timeout: 3) { window.isKeyWindow && NSApp.isActive },
                          "the test app is not frontmost; Quick Look needs the key window")
    }

    override func tearDown() {
        closeQuickLook()
        for controller in controllers { controller.closeDiscardingState() }
        controllers = []
        Settings.setString(savedTheme, Settings.Key.theme)
        Settings.numPanels = savedNumPanels
        Settings.setPanelPath(savedPanelPath, 0)
        NSApp.appearance = savedAppearance
        super.tearDown()
    }

    private static let toolbarDefaultsKey = "NSToolbar Configuration \(MainWindowController.macToolbarIdentifier)"

    private func openWindow(panels: Int = 1) throws -> MainWindowController {
        UserDefaults.standard.removeObject(forKey: Self.toolbarDefaultsKey)   // a fresh arrangement
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

    func testMacLookKeepsEveryToolbarCommand() throws {
        let controller = try openWindow()
        let window = try XCTUnwrap(controller.window)
        let toolbar = try XCTUnwrap(window.toolbar, "the Mac look uses an NSToolbar")
        let ids = toolbar.items.map(\.itemIdentifier)
        for id in [NSToolbarItem.Identifier.szAdd, .szExtract, .szTest, .szCopy, .szMove, .szDelete, .szInfo,
                   .szBack, .szForward] {
            XCTAssertTrue(ids.contains(id), "missing \(id.rawValue)")
        }
        // the same selectors as the Classic buttons
        for item in toolbar.items {
            guard let spec = MainWindowController.toolbarSpec(item.itemIdentifier) else { continue }
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
        let controller = try openWindow()
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
        let controller = try openWindow()
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
        let controller = try openWindow()
        show(controller, "/Applications")
        let table = controller.focusedPanel.tableView
        table.layoutSubtreeIfNeeded()
        let rowRect = table.rect(ofRow: 0)
        // a point near the row's right edge, in the date columns, far from the name
        let point = NSPoint(x: rowRect.maxX - 20, y: rowRect.midY)
        XCTAssertTrue(table.isOnItem(point, row: 0), "the whole row is the item, as in Finder")
    }

    func testMacLookTitleNamesTheFolder() throws {
        let controller = try openWindow()
        show(controller, "/Applications")
        let window = try XCTUnwrap(controller.window)
        XCTAssertTrue(wait(for: "title") { window.title == "Applications" })
        XCTAssertEqual(window.subtitle, "/")
        XCTAssertEqual(window.representedURL?.path, "/Applications")
    }

    func testRenderMacLook() throws {
        try ShowcaseDemo.make()
        try SZCodecs.loadCodecs()
        for theme in [AppTheme.light, .dark] {
            Settings.theme = theme
            let controller = try openWindow()
            show(controller, ShowcaseDemo.folder)
            let panel = controller.focusedPanel
            if let row = panel.rows.firstIndex(where: { $0.name == "Project backup.7z" }) {
                panel.tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                panel.focusedIndex = row
            }
            controller.window?.makeFirstResponder(panel.tableView)
            try writeWholeWindow(try XCTUnwrap(controller.window), "main-\(theme.rawValue)")

            Settings.numPanels = 2
            let two = try openWindow(panels: 2)
            two.window?.setContentSize(NSSize(width: 1100, height: 460))
            show(two, ShowcaseDemo.folder)
            try writeWholeWindow(try XCTUnwrap(two.window), "two-panels-\(theme.rawValue)")
            for c in [controller, two] { c.closeDiscardingState() }
        }
    }

    func testRenderMacDialogs() throws {
        try ShowcaseDemo.make()
        try SZCodecs.loadCodecs()
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
            let tabView = try XCTUnwrap(optionsWindow.contentView?.subviews.compactMap { $0 as? NSTabView }.first)
            XCTAssertEqual(tabView.tabViewType, .noTabsNoBorder, "a Settings window: the toolbar switches the panes")
            XCTAssertEqual(tabView.selectedTabViewItem?.label, "macOS")
            let toolbar = try XCTUnwrap(optionsWindow.toolbar)
            XCTAssertEqual(optionsWindow.toolbarStyle, .preference)
            XCTAssertEqual(toolbar.items.count, options.pageCount)
            XCTAssertFalse(toolbar.items.contains { $0.label.isEmpty || $0.image == nil })
            XCTAssertEqual(toolbar.selectedItemIdentifier, toolbar.items.last?.itemIdentifier)
            XCTAssertEqual(optionsWindow.title, "macOS", "the title names the pane")
            XCTAssertEqual(optionsWindow.contentLayoutRect.height,
                           options.macContentHeight(for: try XCTUnwrap(tabView.selectedTabViewItem?.viewController as? OptionsPageBase)),
                           accuracy: 1, "the window fits the pane")
            let buttonTitles = (optionsWindow.contentView?.subviews ?? []).compactMap { ($0 as? NSButton)?.title }
            XCTAssertFalse(buttonTitles.contains("OK") || buttonTitles.contains("Cancel") || buttonTitles.contains("Apply"),
                           "changes apply at once")
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
        let mac = try XCTUnwrap(OptionsSystemPage.formatIcon(for: zip))
        XCTAssertTrue(mac.representations.contains { $0 is NSBitmapImageRep && $0.pixelsWide >= 512 },
                      "doc-zip.icns (\(bundled.lastPathComponent)), not the 16 px .ico frame")
    }

    private func spaceKey(_ window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                         windowNumber: window.windowNumber, context: nil, characters: " ",
                         charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49)!
    }

    func testSpaceOpensQuickLookInTheMacLook() throws {
        closeQuickLook()
        let controller = try openWindow()
        show(controller, "/Applications")
        let panel = controller.focusedPanel
        let window = try XCTUnwrap(controller.window)
        try makeListKey(controller)
        panel.tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        panel.focusedIndex = 0
        XCTAssertFalse(panel.quickLookPaths.isEmpty, "a file-system item can be previewed")
        XCTAssertTrue(panel.handleListKeyDown(spaceKey(window)))
        let ql = try XCTUnwrap(QLPreviewPanel.shared())
        XCTAssertTrue(wait(for: "Quick Look", timeout: 5) { ql.isVisible }, "Space opens Quick Look")
        XCTAssertTrue((ql.currentController as AnyObject?) === panel, "the panel controls the preview")
        _ = wait(for: "the opening animation", timeout: 1) { false }   // a close mid-animation is ignored
        XCTAssertTrue(panel.handleListKeyDown(spaceKey(window)))
        XCTAssertTrue(wait(for: "Quick Look closed", timeout: 5) { !ql.isVisible }, "Space again closes it")
    }

    func testArrowKeysInQuickLookMoveThroughTheList() throws {
        let controller = try openWindow()
        show(controller, "/Applications")
        let panel = controller.focusedPanel
        let window = try XCTUnwrap(controller.window)
        try makeListKey(controller)
        panel.tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        panel.focusedIndex = 0
        XCTAssertTrue(panel.handleListKeyDown(spaceKey(window)))
        let ql = try XCTUnwrap(QLPreviewPanel.shared())
        XCTAssertTrue(wait(for: "Quick Look", timeout: 5) { ql.isVisible })
        let first = panel.quickLookPaths
        let down = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.numericPad, .function], timestamp: 0,
                                    windowNumber: ql.windowNumber, context: nil,
                                    characters: String(UnicodeScalar(NSDownArrowFunctionKey)!),
                                    charactersIgnoringModifiers: String(UnicodeScalar(NSDownArrowFunctionKey)!),
                                    isARepeat: false, keyCode: 125)!
        // what Quick Look does with a key while it is key: it asks its delegate first
        XCTAssertTrue(panel.previewPanel(ql, handle: down), "the list takes the arrow")
        XCTAssertEqual(panel.tableView.selectedRow, 1, "Down moved the selection")
        XCTAssertNotEqual(panel.quickLookPaths, first, "the preview shows the next item")
        XCTAssertTrue(ql.isVisible, "Quick Look stays open")
        XCTAssertFalse(panel.previewPanel(ql, handle: spaceKey(ql)), "Space stays with Quick Look (it closes)")
    }

    func testRenderMacQuickLookPreview() throws {
        try SZCodecs.loadCodecs()
        let url = URL(fileURLWithPath: TestPaths.fixture("test.7z"))
        let preview = ArchivePreviewBuilder.build(path: url.path)
        let view = ArchivePreviewView(frame: NSRect(x: 0, y: 0, width: 640, height: 300))
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        view.show(preview, fileURL: url)
        XCTAssertEqual(view.outlineView.rowHeight, 22)
        XCTAssertTrue(view.outlineView.usesAlternatingRowBackgroundColors)
        window.orderFront(nil)
        try writeWholeWindow(window, "quicklook-mac")
        window.orderOut(nil)
    }

    // MARK: native-look: Mac menus

    /// Every command item (selector + tag) of a menu tree, hidden twins included.
    private func commands(_ menu: NSMenu) -> Set<String> {
        var out = Set<String>()
        for item in menu.items {
            if let action = item.action { out.insert("\(NSStringFromSelector(action))#\(item.tag)") }
            if let sub = item.submenu { out.formUnion(commands(sub)) }
        }
        return out
    }

    private func allItems(_ menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { [$0] + ($0.submenu.map(allItems) ?? []) }
    }

    private func find(_ menu: NSMenu, _ action: Selector, tag: Int? = nil) -> NSMenuItem? {
        allItems(menu).first { $0.action == action && !$0.isHidden && (tag == nil || $0.tag == tag) }
    }

    func testMacMenusUseMacNamesAndKeepEveryCommand() throws {
        let mac = MainMenu.build()

        let a = MenuActions.self
        let settings = try XCTUnwrap(find(mac.items[0].submenu!, #selector(a.toolsOptions(_:))))
        XCTAssertEqual(settings.title, "Settings…")
        XCTAssertEqual(settings.keyEquivalent, ",")
        XCTAssertEqual(allItems(mac).filter { $0.action == #selector(a.toolsOptions(_:)) }.count, 1, "only in the app menu")
        XCTAssertNotNil(find(mac.items[0].submenu!, #selector(AppDelegate.helpCheckForUpdates(_:))), "update check under About")

        let info = try XCTUnwrap(find(mac, #selector(a.fileProperties(_:))))
        XCTAssertEqual(info.title, "Get Info")
        XCTAssertEqual(info.keyEquivalent, "i")
        let folder = try XCTUnwrap(find(mac, #selector(a.fileCreateFolder(_:))))
        XCTAssertEqual(folder.title, "New Folder")
        XCTAssertEqual(folder.keyEquivalentModifierMask, [.command, .shift])
        let f7 = try XCTUnwrap(allItems(mac).first { $0.action == #selector(a.fileCreateFolder(_:)) && $0.isHidden },
                               "F7 still works through a hidden twin")
        XCTAssertTrue(f7.allowsKeyEquivalentWhenHidden)
        XCTAssertEqual(find(mac, #selector(a.fileDelete(_:)), tag: 548)?.title, "Move to Trash")
        XCTAssertEqual(find(mac, #selector(a.fileDelete(_:)), tag: MainMenu.deleteImmediatelyTag)?.isAlternate, true)
        XCTAssertEqual(find(mac, #selector(a.fileExit(_:)))?.title, "Close Window")
        XCTAssertEqual(find(mac, #selector(a.fileNewWindow(_:)))?.keyEquivalent, "n")
        XCTAssertEqual(find(mac, #selector(a.fileNewWindow(_:)))?.keyEquivalentModifierMask, [.command])

        let titles = mac.items.compactMap { $0.submenu?.title }
        XCTAssertTrue(titles.contains("Go"), "Finder's Go menu: \(titles)")
        let go = try XCTUnwrap(mac.items.first { $0.submenu?.title == "Go" }?.submenu)
        XCTAssertNotNil(find(go, #selector(a.viewGoBack(_:))))
        XCTAssertEqual(find(go, #selector(a.viewOpenParentFolder(_:)))?.title, "Enclosing Folder")
        XCTAssertNotNil(find(mac, #selector(NSWindow.runToolbarCustomizationPalette(_:))))
        XCTAssertEqual(find(mac, #selector(a.helpContents(_:)))?.keyEquivalent, "?")
        let edit = try XCTUnwrap(mac.items[2].submenu)
        XCTAssertEqual(edit.items.first?.action, Selector(("undo:")), "Undo, Redo first")
        XCTAssertEqual(edit.items[3].action, #selector(NSText.cut(_:)), "then Cut, Copy, Paste")

        // Cmd+Z is Undo on the Mac: nothing else takes it, and no two items share a shortcut.
        var seen: [String: String] = [:]
        for item in allItems(mac) where !item.keyEquivalent.isEmpty && !item.isAlternate {
            let key = "\(item.keyEquivalentModifierMask.rawValue)-\(item.keyEquivalent.lowercased())"
            if let other = seen[key] {
                XCTFail("'\(item.title)' and '\(other)' share a shortcut")
            }
            seen[key] = item.title
        }
        XCTAssertEqual(seen["\(NSEvent.ModifierFlags.command.rawValue)-z"], "Undo", "Cmd+Z is Undo")
    }

    // MARK: native-look: form labels

    func testMacFormLabelsAlignRightAgainstTheirControl() throws {
        func form() -> (RcFormView, named: NSTextField, above: NSTextField, value: NSTextField) {
            let form = RcFormView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
            func label(_ text: String, _ rect: NSRect) -> NSTextField {
                let field = NSTextField(labelWithString: text)
                field.frame = rect
                form.addSubview(field)
                return field
            }
            let named = label("Archive format:", NSRect(x: 10, y: 10, width: 120, height: 17))
            let popup = NSPopUpButton(frame: NSRect(x: 180, y: 6, width: 150, height: 24))
            form.addSubview(popup)
            let above = label("Parameters:", NSRect(x: 10, y: 50, width: 300, height: 17))
            form.addSubview(NSTextField(frame: NSRect(x: 10, y: 70, width: 300, height: 22)))
            let value = label("Memory usage:", NSRect(x: 10, y: 120, width: 150, height: 17))
            _ = label("2225 MB", NSRect(x: 10, y: 138, width: 150, height: 17))
            form.addSubview(NSPopUpButton(frame: NSRect(x: 180, y: 120, width: 150, height: 24)))
            form.growTextIntoFreeSpace()
            return (form, named, above, value)
        }
        let mac = form()
        XCTAssertEqual(mac.named.alignment, .right, "a label left of its control hugs it")
        XCTAssertEqual(mac.named.frame.maxX, 172, accuracy: 0.5)
        XCTAssertNotEqual(mac.above.alignment, .right, "a label above its field stays")
        XCTAssertNotEqual(mac.value.alignment, .right, "a label over its value stays")
        mac.0.growTextIntoFreeSpace()
        XCTAssertEqual(mac.named.frame.maxX, 172, accuracy: 0.5, "a second pass changes nothing")
    }

    // MARK: native-look: path bar

    func testMacPathBarClimbsThePath() throws {
        XCTAssertEqual(MacPathBar.parts(of: "/Users/me/b"), ["/", "/Users", "/Users/me", "/Users/me/b"])
        XCTAssertEqual(MacPathBar.parts(of: "/Volumes/Disk/x"), ["/Volumes/Disk", "/Volumes/Disk/x"])
        XCTAssertEqual(MacPathBar.parts(of: ""), [])
        defer { Settings.removeKey(MacPathBar.key) }
        MacPathBar.isShown = true

        let controller = try openWindow()
        show(controller, "/Applications/Utilities")
        let panel = controller.focusedPanel
        let bar = panel.pathControlBar
        XCTAssertFalse(bar.isHidden)
        XCTAssertEqual(bar.shownPaths.last, "/Applications/Utilities")
        XCTAssertEqual(bar.control.pathItems.last?.title, "Utilities")
        XCTAssertEqual(bar.control.pathItems.first?.title, FileManager.default.displayName(atPath: "/"))
        controller.window?.layoutIfNeeded()
        XCTAssertEqual(bar.frame.height, PanelPathControlBar.height)

        // A click on "Applications" opens it, with Utilities selected.
        let index = try XCTUnwrap(bar.shownPaths.firstIndex(of: "/Applications"))
        bar.openPart(at: index)
        XCTAssertTrue(wait(for: "Applications listed") { panel.snapshot?.fullPath.hasPrefix("/Applications/Utilities") == false
            && panel.rows.contains { $0.name == "Utilities" } })
        XCTAssertEqual(panel.focusedRow()?.name, "Utilities")

        // View > Hide Path Bar hides it in every panel; the menu item says what it will do.
        let item = try XCTUnwrap(allItems(MainMenu.build()).first { $0.action == #selector(AppDelegate.toggleMacPathBar(_:)) })
        XCTAssertEqual(item.keyEquivalent, "p")
        XCTAssertEqual(item.keyEquivalentModifierMask, [.command, .option])
        MacPathBar.isShown = false
        controller.window?.layoutIfNeeded()
        XCTAssertTrue(bar.isHidden)
        XCTAssertEqual(bar.frame.height, 0)

    }

    // MARK: native-look: window tabs

    func testMacWindowsOpenAsTabs() throws {
        let controller = try openWindow()
        let window = try XCTUnwrap(controller.window)
        XCTAssertEqual(window.tabbingIdentifier, MainWindowController.tabbingIdentifier)
        window.tabbingMode = .preferred        // TestAnimations turns tabbing off for every test window
        let menu = MainMenu.build()
        let newTab = try XCTUnwrap(allItems(menu).first { $0.action == #selector(NSResponder.newWindowForTab(_:)) })
        XCTAssertEqual(newTab.title, "New Tab")
        XCTAssertEqual(newTab.keyEquivalent, "t")
        XCTAssertEqual(newTab.keyEquivalentModifierMask, [.command])

        controller.newWindowForTab(nil)
        let tabs = window.tabbedWindows ?? []
        XCTAssertEqual(tabs.count, 2, "the new window is a tab of the first")
        let tab = try XCTUnwrap(tabs.first { $0 !== window })
        XCTAssertTrue(tab.windowController is MainWindowController)
        XCTAssertTrue(MainWindows.controllers.contains { $0.window === tab })
        tab.toolbar = nil
        tab.close()
    }

    // MARK: native-look: undo Move to Trash

    func testMacUndoPutsTrashedItemsBack() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sz-trash-undo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("put-back.txt")
        try Data("7-Zip".utf8).write(to: file)

        let controller = try openWindow()
        show(controller, dir.path)
        let window = try XCTUnwrap(controller.window)
        let panel = controller.focusedPanel
        let row = try XCTUnwrap(panel.rows.firstIndex { $0.name == "put-back.txt" })
        let undo = try XCTUnwrap(window.undoManager)
        undo.removeAllActions()

        panel.deleteItems(rowIndices: [row], toTrash: true, confirm: false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "moved to the Trash")
        XCTAssertTrue(undo.canUndo)
        XCTAssertEqual(undo.undoActionName, "Move to Trash")

        undo.undo()
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "Undo puts it back")
        XCTAssertTrue(wait(for: "listed again") { panel.rows.contains { $0.name == "put-back.txt" } })
        XCTAssertTrue(undo.canRedo)

        undo.redo()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "Redo trashes it again")
        undo.undo()
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "and Undo works again")
        undo.removeAllActions()
    }

    // MARK: native-look: sheets

    func testMacDialogsAreSheetsOfTheirWindow() throws {
        defer { while NSApp.modalWindow != nil { NSApp.abortModal() } }
        let controller = try openWindow()
        show(controller, "/Applications")
        let window = try XCTUnwrap(controller.window)
        window.makeKeyAndOrderFront(nil)
        var parent: NSWindow?
        var answered: WinMessageBox.Result?
        XCTAssertTrue(ModalProbe.present({
            answered = WinMessageBox.run("Are you sure you want to delete 'notes.md'?", caption: "Confirm File Delete",
                                         buttons: .yesNo, icon: .question, owner: window)
        }) { box in
            parent = box.sheetParent
            try? self.writeSheet(box, on: window, "sheet-alert")
            (box as? WinMessageBoxWindow)?.answer(.yes)
        })
        XCTAssertEqual(answered, .yes, "the caller still gets its answer")
        // A DialogKit dialog: Extract, cancelled through its close path (IDCANCEL).
        var extractParent: NSWindow?
        var extract = ExtractDialog.Options()
        extract.directoryPath = "/Users/Shared/"
        extract.archivePath = "/Users/Shared/demo.zip"
        extract.parentWindow = window          // as the panel passes it (the test app may be inactive)
        var returned = false, extractResult: ExtractDialog.Result?
        XCTAssertTrue(ModalProbe.present({ extractResult = ExtractDialog.run(extract); returned = true }) { dialog in
            extractParent = dialog.sheetParent
            try? self.writeSheet(dialog, on: window, "sheet-extract")
            dialog.performClose(nil)
        })
        XCTAssertTrue(returned, "run() returned")
        XCTAssertNil(extractResult, "cancelled")
        XCTAssertTrue(extractParent === window)
        XCTAssertNil(window.attachedSheet)
        // The one-field dialog (Create Folder, Rename, ...): as a sheet its caption is a heading.
        var labels: [String] = []
        XCTAssertTrue(ModalProbe.present({
            _ = ComboDialog.run(title: "Create Folder", label: "Folder name:", value: "New Folder", parent: window)
        }) { dialog in
            func texts(_ v: NSView) -> [String] {
                ((v as? NSTextField).map { [$0.stringValue] } ?? []) + v.subviews.flatMap(texts)
            }
            labels = dialog.contentView.map(texts) ?? []
            try? self.writeSheet(dialog, on: window, "sheet-create-folder")
            dialog.performClose(nil)
        })
        XCTAssertTrue(labels.contains("Create Folder"), "the heading names the command: \(labels)")
        XCTAssertTrue(parent === window, "the question is a sheet of its window")
        XCTAssertNil(window.attachedSheet, "and it is gone afterwards")
        controller.closeDiscardingState()
        // The test keeps the closed window alive; its toolbar would go on syncing with the
        // next test's (same identifier), so it is detached here.
        window.toolbar = nil
    }

    /// A box answered while it is a sheet leaves no sheet session behind: the window takes the
    /// next sheet and nothing stays modal (answering used to order the sheet out before endSheet).
    func testAnsweredAlertSheetEndsItsSession() throws {
        let controller = try openWindow()
        let window = try XCTUnwrap(controller.window)
        window.makeKeyAndOrderFront(nil)
        defer { window.toolbar = nil }
        for way in 0..<3 {
            var parent: NSWindow?
            XCTAssertTrue(ModalProbe.present({
                _ = WinMessageBox.run("Specify command", caption: "7-Zip", buttons: .okCancel, icon: .none, owner: window)
            }) { box in
                parent = box.sheetParent
                guard let box = box as? WinMessageBoxWindow else { return }
                switch way {
                case 0: box.performClose(nil)
                case 1: box.cancelOperation(nil)
                default: box.pushButtons[0].performClick(nil)
                }
            })
            XCTAssertTrue(parent === window, "the box is a sheet of its window")
            XCTAssertNil(NSApp.modalWindow, "way \(way): no modal session left")
            XCTAssertNil(window.attachedSheet, "way \(way): the sheet is gone")
        }
    }

    /// The window with its sheet drawn in place.
    private func writeSheet(_ sheet: NSWindow, on window: NSWindow, _ name: String) throws {
        func image(_ w: NSWindow) throws -> NSBitmapImageRep {
            let view = try XCTUnwrap(w.contentView?.superview)
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
            let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: rep)
            return rep
        }
        _ = wait(for: "draw", timeout: 0.5) { false }
        let base = try image(window), top = try image(sheet)
        let out = NSImage(size: window.frame.size, flipped: false) { _ in
            base.draw(in: NSRect(origin: .zero, size: window.frame.size))
            top.draw(in: NSRect(origin: NSPoint(x: sheet.frame.minX - window.frame.minX, y: sheet.frame.minY - window.frame.minY),
                                size: sheet.frame.size))
            return true
        }
        let tiff = try XCTUnwrap(out.tiffRepresentation)
        let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = "\(screenshotPrefix)-\(name).png"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testMacSettingsApplyAtOnce() throws {
        let wasGrid = Settings.showGrid
        defer {
            Settings.showGrid = wasGrid
            if let w = OptionsWindowController.shared.window, w.isVisible { ModalProbe.close(w) }
        }
        let options = OptionsWindowController.shared
        var page: OptionsMacPage?
        XCTAssertTrue(ModalProbe.present({ OptionsWindowController.showOptions() }) { window in
            options.selectPage(options.pageCount - 1)
            page = window.contentView?.subviews.compactMap { $0 as? NSTabView }.first?
                .selectedTabViewItem?.viewController as? OptionsMacPage
            page?.gridBox.performClick(nil)                       // while the window is up
        })
        let macPage = try XCTUnwrap(page)
        XCTAssertEqual(Settings.showGrid, !wasGrid, "the checkbox took effect without OK or Apply")
        XCTAssertFalse(macPage.pageIsChanged, "nothing left to apply")
    }

    func testMacMessageBoxKeepsTheAnswersInMacOrder() throws {
        let box = WinMessageBoxWindow(text: "Are you sure you want to delete 'notes.md'?", caption: "Confirm File Delete",
                                      buttons: .yesNoCancel, icon: .question, owner: nil)
        XCTAssertNotNil(box.macLayout)
        XCTAssertEqual(box.pushButtons.map(\.title), ["Yes", "No", "Cancel"], "same answers")
        XCTAssertTrue(box.defaultButtonCell === box.pushButtons.first?.cell, "Yes stays the default")
        let layout = box.macLayout
        XCTAssertEqual(layout.messageText, "Are you sure you want to delete 'notes.md'?", "one line: all of it is the bold message")
        XCTAssertTrue(layout.stacksButtons, "three answers stack, as NSAlert does")
        let ys = box.pushButtons.map(\.frame.minY)                    // flipped: the default on top
        XCTAssertLessThan(ys[0], ys[1])
        XCTAssertLessThan(ys[1], ys[2])
        XCTAssertTrue(box.styleMask.contains(.fullSizeContentView), "no visible title bar")
        XCTAssertEqual(box.titleVisibility, .hidden)
        let two = WinMessageBoxWindow(text: "Cannot open the file as archive\n/Users/me/Report.pdf", caption: "7-Zip",
                                      buttons: .okCancel, icon: .error, owner: nil)
        let twoLayout = two.macLayout
        XCTAssertEqual(twoLayout.messageText, "Cannot open the file as archive")
        XCTAssertEqual(twoLayout.informativeText, "/Users/me/Report.pdf")
        XCTAssertFalse(twoLayout.stacksButtons)
        XCTAssertGreaterThan(two.pushButtons[0].frame.minX, two.pushButtons[1].frame.minX, "the default sits rightmost")
        XCTAssertEqual(two.pushButtons[0].frame.width, two.pushButtons[1].frame.width, "equal widths")
    }

    func testRenderMacAlertsAndProgress() throws {
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
        let controller = try openWindow()
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
