// Recheck2Tests.swift -- the `recheck2` fixes (ai/reports/recheck2.md), each against what
// 7zFM 26.03 does on Windows 11 at 96 dpi (recheck2-data/win/):
//
//   * WinMessageBox: geometry of the measured MessageBoxW cases, the keys and the close box, the
//     no-owner and test-reset paths, and that the app-modal session always ends;
//   * the Edit menu carries no AutoFill / Start Dictation / Emoji & Symbols items.

import AppKit
import XCTest
@testable import SevenZipAppHost

final class Recheck2Tests: AppHostTestCase {

    override var screenshotPrefix: String { "recheck2" }

    private var savedAppearance: NSAppearance?

    override func setUpWithError() throws {
        try super.setUpWithError()
        savedAppearance = NSApp.appearance
        NSApp.appearance = NSAppearance(named: .aqua)
    }

    override func tearDown() {
        WinMessageBox.observers = [recordAndDismissReports]
        for box in WinMessageBox.visibleBoxes { box.orderOut(nil) }
        NSApp.appearance = savedAppearance
        super.tearDown()
    }

    // MARK: - geometry (recheck2-data/win/mb-*.txt)

    private struct WinCase {
        let name: String
        let text: String
        let caption: String
        let buttons: WinMessageBox.Buttons
        let icon: WinMessageBox.Icon
        let client: NSSize          // measured client area
        let text0: NSPoint          // the static's top-left
        let lines: Int              // (static height - 2) / 13
        let buttonY: CGFloat
    }

    private let cases: [WinCase] = [
        WinCase(name: "delfile", text: "Are you sure you want to delete 'notes.md'?", caption: "Confirm File Delete",
                buttons: .yesNoCancel, icon: .question, client: NSSize(width: 318, height: 120),
                text0: NSPoint(x: 62, y: 33), lines: 1, buttonY: 88),
        WinCase(name: "upd3009", text: "File 'notes.md' was modified.\nDo you want to update it in the archive?",
                caption: "7-Zip", buttons: .yesNoCancel, icon: .question, client: NSSize(width: 299, height: 120),
                text0: NSPoint(x: 62, y: 26), lines: 2, buttonY: 88),
        WinCase(name: "askcancel", text: "Are you sure you want to cancel?", caption: "Checksum calculating...",
                buttons: .yesNoCancel, icon: .none, client: NSSize(width: 284, height: 101),
                text0: NSPoint(x: 11, y: 23), lines: 1, buttonY: 68),
        WinCase(name: "err", text: "Cannot open file 'C:\\Users\\yrambler2001\\AppData\\Local\\Temp\\szcmp\\cmp\\fake.zip' as archive",
                caption: "7-Zip", buttons: .ok, icon: .error, client: NSSize(width: 407, height: 127),
                text0: NSPoint(x: 62, y: 23), lines: 3, buttonY: 94),
        WinCase(name: "info", text: "There are no errors", caption: "7-Zip", buttons: .ok, icon: .information,
                client: NSSize(width: 189, height: 120), text0: NSPoint(x: 62, y: 33), lines: 1, buttonY: 88),
        WinCase(name: "okcancel", text: "Do you want to revert the file?", caption: "Version Control: File Revert",
                buttons: .okCancel, icon: .question, client: NSSize(width: 248, height: 120),
                text0: NSPoint(x: 62, y: 33), lines: 1, buttonY: 88),
        WinCase(name: "lines", text: "First line\nSecond line\n\nFourth line after an empty one", caption: "7-Zip",
                buttons: .ok, icon: .information, client: NSSize(width: 249, height: 140),
                text0: NSPoint(x: 62, y: 23), lines: 4, buttonY: 107),
        WinCase(name: "x", text: "x", caption: "7-Zip", buttons: .ok, icon: .none,
                client: NSSize(width: 117, height: 101), text0: NSPoint(x: 11, y: 23), lines: 1, buttonY: 68),
    ]


    // MARK: - behaviour

    /// Shows a box and lets `act` answer it from inside its modal session.
    private func runBox(_ text: String = "Are you sure you want to delete 'notes.md'?",
                        caption: String = "Confirm File Delete", buttons: WinMessageBox.Buttons = .yesNoCancel,
                        icon: WinMessageBox.Icon = .question, owner: NSWindow? = nil,
                        act: @escaping (WinMessageBoxWindow) -> Void) -> (WinMessageBox.Result, WinMessageBoxWindow?) {
        var seen: WinMessageBoxWindow?
        WinMessageBox.observers = [{ box in
            seen = box
            RunLoop.main.perform(inModes: [.modalPanel, .default]) {
                XCTAssertTrue(NSApp.modalWindow === box, "the box runs its own app-modal session")
                act(box)
            }
        }]
        let result = WinMessageBox.run(text, caption: caption, buttons: buttons, icon: icon, owner: owner)
        WinMessageBox.observers = [recordAndDismissReports]
        XCTAssertNil(NSApp.modalWindow, "the box must leave no modal session behind")
        XCTAssertFalse(seen?.isVisible ?? true, "the box must be gone")
        return (result, seen)
    }

    func testEscapeAndTheCloseBoxAnswerLikeWindows() {
        // MB_YESNOCANCEL: Esc and the close box are IDCANCEL.
        XCTAssertEqual(runBox { $0.cancelOperation(nil) }.0, .cancel)
        XCTAssertEqual(runBox { $0.performClose(nil) }.0, .cancel)
        // MB_OK: Esc is IDOK (measured: result 1).
        XCTAssertEqual(runBox("There are no errors", caption: "7-Zip", buttons: .ok, icon: .information) {
            $0.cancelOperation(nil)
        }.0, .ok)
        // MB_OKCANCEL: IDCANCEL.
        XCTAssertEqual(runBox(buttons: .okCancel) { $0.performClose(nil) }.0, .cancel)
        // MB_YESNO: the close box is disabled and neither Esc nor the close box ends the box.
        let (result, _) = runBox("Copy?", caption: "Confirm File Copy", buttons: .yesNo) { box in
            XCTAssertNotEqual(box.standardWindowButton(.closeButton)?.isEnabled, true)
            box.cancelOperation(nil)
            box.performClose(nil)
            XCTAssertTrue(box.isVisible, "MB_YESNO ignores Esc and WM_CLOSE")
            XCTAssertTrue(NSApp.modalWindow === box)
            box.pushButtons[1].performClick(nil)
        }
        XCTAssertEqual(result, .no)
    }

    func testAccessKeysAndCopy() {
        let y = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                 context: nil, characters: "y", charactersIgnoringModifiers: "y", isARepeat: false, keyCode: 16)!
        XCTAssertEqual(runBox { $0.keyDown(with: y) }.0, .yes)
        let (_, _) = runBox { box in
            box.copyAsText()
            box.answer(.cancel)
        }
        let copied = NSPasteboard.general.string(forType: .string) ?? ""
        XCTAssertEqual(copied, "---------------------------\r\nConfirm File Delete\r\n---------------------------\r\n"
                       + "Are you sure you want to delete 'notes.md'?\r\n---------------------------\r\n"
                       + "Yes   No   Cancel   \r\n---------------------------\r\n")
    }

    /// No owner at all (7zG with no window): an ordinary window on the main screen that its own
    /// close box still ends -- never an ownerless alert that nothing can dismiss.
    func testABoxWithNoOwnerIsStillSafe() {
        let box = WinMessageBoxWindow(text: "Specify command", caption: "7-Zip", buttons: .ok, icon: .none, owner: nil)
        RunLoop.main.perform(inModes: [.modalPanel, .default]) {
            XCTAssertTrue(NSApp.modalWindow === box)
            XCTAssertNil(box.ownerWindow)
            box.performClose(nil)
        }
        XCTAssertEqual(box.runModal(), .ok)
        XCTAssertNil(NSApp.modalWindow)
    }

    /// A box closed by `close()` from outside (what an `orderOut` + window close by the test reset
    /// amounts to) ends its own session and answers what Esc would.
    func testAClosedBoxEndsItsSession() {
        let (result, _) = runBox { $0.close() }
        XCTAssertEqual(result, .cancel)
    }

    /// `show` returns at once and puts the box up from the run loop, outside the caller's block.
    func testShowIsAsynchronous() {
        var answered: WinMessageBox.Result?
        WinMessageBox.observers = [{ box in
            RunLoop.main.perform(inModes: [.modalPanel, .default]) { box.answer(.ok) }
        }]
        defer { WinMessageBox.observers = [recordAndDismissReports] }
        WinMessageBox.show("There are no errors", owner: nil) { answered = $0 }
        XCTAssertNil(answered, "show must not block its caller")
        XCTAssertTrue(wait(for: "the box", timeout: 10) { answered != nil })
        XCTAssertEqual(answered, .ok)
    }

    // MARK: - captures (paired with recheck2-data/win/mb-*.png)

    /// The client area at 1x.
    private func render(_ box: WinMessageBoxWindow) -> NSBitmapImageRep? {
        guard let content = box.contentView else { return nil }
        let size = content.bounds.size
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        content.cacheDisplay(in: content.bounds, to: rep)
        return rep
    }

    // MARK: - the list: slow second click and Single-click hover (recheck2-data/win/log.txt)

    private var controllers: [MainWindowController] = []
    private var savedSingleClick = false

    private func boundPanel(files: Int = 8) throws -> (NSWindow, PanelViewController) {
        let dir = NSTemporaryDirectory() + "recheck2-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for i in 1...files { FileManager.default.createFile(atPath: dir + String(format: "/f%03d.txt", i), contents: Data("x".utf8)) }
        savedSingleClick = Settings.singleClick
        let savedPath = Settings.panelPath(0), savedPanels = Settings.numPanels, savedMode = Settings.listMode(0)
        addTeardownBlock { [weak self] in
            // the window first: a panel must not be left on a folder that is about to vanish
            for c in self?.controllers ?? [] { c.closeDiscardingState() }
            self?.controllers = []
            Settings.setPanelPath(savedPath, 0)
            Settings.numPanels = savedPanels
            Settings.setListMode(savedMode, 0)
            try? FileManager.default.removeItem(atPath: dir)
            Settings.singleClick = self?.savedSingleClick ?? false
        }
        Settings.numPanels = 1
        Settings.setListMode(3, 0)
        Settings.setPanelPath(dir, 0)
        let c = MainWindowController()
        controllers.append(c)
        c.window?.setContentSize(NSSize(width: 900, height: 500))
        c.showWindow(nil)
        let window = try XCTUnwrap(c.window)
        let p = c.focusedPanel
        var done = false
        p.navigate(to: dir) { _ in done = true }
        XCTAssertTrue(wait(for: "bound") { done })
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        window.contentView?.layoutSubtreeIfNeeded()
        window.makeFirstResponder(p.tableView)
        return (window, p)
    }

    /// A click on `point` (table coordinates): the mouse-up is queued first so NSTableView's
    /// tracking loop ends at once.
    private func click(_ window: NSWindow, _ table: NSTableView, _ point: NSPoint, count: Int = 1) {
        let at = table.convert(point, to: nil)
        let up = NSEvent.mouseEvent(with: .leftMouseUp, location: at, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: count, pressure: 0)!
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: at, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                      windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: count, pressure: 1)!
        NSApp.postEvent(up, atStart: true)
        window.sendEvent(down)
    }

    private func labelPoint(_ p: PanelViewController, _ row: Int) -> NSPoint {
        let r = p.tableView.labelHitRect(row: row)
        return NSPoint(x: r.minX + 4, y: r.midY)
    }

    /// LVS_EDITLABELS: a click on the label of the only selected, focused item starts the rename
    /// after the double-click time; a double-click, a click on the icon or on one of several
    /// selected items does not.
    func testSlowSecondClickRenamesAfterTheDoubleClickTime() throws {
        Settings.singleClick = false
        let (window, p) = try boundPanel()
        let table = p.tableView
        p.setFocus(2)
        click(window, table, labelPoint(p, 2))
        XCTAssertTrue(table.hasPendingSlowClickRename, "a click on the selected item's label waits")
        XCTAssertNil(p.renamingRow, "not at once: only after the double-click time")
        XCTAssertTrue(wait(for: "the rename", timeout: NSEvent.doubleClickInterval + 2) { p.renamingRow == 2 })
        window.makeFirstResponder(table)                       // end the edit unchanged
        XCTAssertTrue(wait(for: "the edit to end", timeout: 5) { p.renamingRow == nil })

        // a double-click opens instead
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))      // the unchanged rename reloads
        p.setFocus(3)
        XCTAssertEqual(p.selectedIndexes, IndexSet(integer: 3))
        click(window, table, labelPoint(p, 3))
        XCTAssertTrue(table.hasPendingSlowClickRename)
        table.cancelSlowClickRename()
        XCTAssertFalse(table.hasPendingSlowClickRename)

        // the first click on an unselected item only selects it
        p.setFocus(4)
        click(window, table, labelPoint(p, 5))
        XCTAssertFalse(table.hasPendingSlowClickRename, "the first click selects, it does not edit")
        p.setFocus(5)

        // the icon is not the label
        let icon = NSPoint(x: table.itemHitRect(row: 5).minX + 3, y: table.rect(ofRow: 5).midY)
        XCTAssertFalse(table.labelHitRect(row: 5).contains(icon))
        click(window, table, icon)
        XCTAssertFalse(table.hasPendingSlowClickRename, "a click on the icon starts nothing")

        // one of several selected items
        p.setSelectedIndexes(IndexSet([5, 6]))
        p.focusedIndex = 6
        click(window, table, labelPoint(p, 6))
        XCTAssertFalse(table.hasPendingSlowClickRename, "a click on one of several selected items starts nothing")
    }

    /// File > Delete while the slow click's rename is open deletes the item (7zFM: IDM_DELETE goes to
    /// the panel whatever the label edit is doing).
    func testDeleteWhileRenamingDeletesTheItem() throws {
        Settings.singleClick = false
        let (_, p) = try boundPanel()
        let name = p.rows[2].name
        p.setFocus(2)
        p.renameFocusedItem()
        XCTAssertEqual(p.renamingRow, 2)
        var chain: [String] = []
        var r: NSResponder? = p.view.window?.firstResponder
        while let x = r { chain.append(String(describing: type(of: x))); r = x.nextResponder }
        let handled = p.view.window?.firstResponder?.tryToPerform(#selector(MenuActions.fileDelete(_:)), with: nil) ?? false
        XCTAssertTrue(handled, "the panel takes File > Delete from the rename field: \(chain)")
        XCTAssertNil(p.renamingRow, "the delete cancelled the edit")
        XCTAssertTrue(wait(for: "the delete", timeout: 10) { !p.rows.contains { $0.name == name } },
                      "rows: \(p.rows.map(\.name))")
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        XCTAssertEqual(p.rows.count, 7, "nothing else was renamed or lost: \(p.rows.map(\.name))")
    }

    // MARK: - the Up button (recheck2.md section 3)

    // MARK: - Edit menu (recheck.md section 8 item 4)

    /// AppKit adds AutoFill, Start Dictation and Emoji & Symbols to a menu titled "Edit"; 7zFM's
    /// Edit menu has none of them (recheck-data/win/menu-main.txt).
    func testEditMenuHasNoSystemItems() throws {
        let edit = try XCTUnwrap(NSApp.mainMenu?.items.first { $0.submenu?.title == "Edit" }?.submenu)
        print("RECHECK2 | Edit menu as AppKit left it: \(edit.items.map { "\($0.title) [\($0.action.map(NSStringFromSelector) ?? "-")]" })")
        // What AppKit appends, the way it appends it: the cleanup takes each one out again.
        let before = edit.items.count
        edit.addItem(.separator())
        edit.addItem(NSMenuItem(title: "AutoFill", action: nil, keyEquivalent: ""))
        edit.addItem(NSMenuItem(title: "Start Dictation…", action: NSSelectorFromString("startDictation:"), keyEquivalent: ""))
        edit.addItem(NSMenuItem(title: "Emoji & Symbols", action: NSSelectorFromString("orderFrontCharacterPalette:"), keyEquivalent: " "))
        XCTAssertTrue(wait(for: "the cleanup", timeout: 5) { edit.items.count == before }, "\(edit.items.map(\.title))")
        edit.delegate?.menuNeedsUpdate?(edit)
        XCTAssertEqual(UserDefaults.standard.bool(forKey: "NSDisabledDictationMenuItem"), true)
        XCTAssertEqual(UserDefaults.standard.bool(forKey: "NSDisabledCharacterPaletteMenuItem"), true)
        let titles = edit.items.map(\.title)
        let actions = edit.items.compactMap { $0.action.map(NSStringFromSelector) }
        for banned in ["AutoFill", "Start Dictation", "Start Dictation…", "Emoji & Symbols"] {
            XCTAssertFalse(titles.contains { $0.hasPrefix(banned) }, "Edit menu has \(banned): \(titles)")
        }
        for banned in ["startDictation:", "orderFrontCharacterPalette:"] {
            XCTAssertFalse(actions.contains(banned), "Edit menu has \(banned): \(actions)")
        }
        XCTAssertFalse(titles.contains { $0.contains("AutoFill") || $0.contains("Autofill") }, "\(titles)")
    }
}
