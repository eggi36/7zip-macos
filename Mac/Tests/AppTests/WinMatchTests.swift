// WinMatchTests.swift -- the `winmatch` changes, each pinned to what the real 7zFM 25.01 does
// (ai/reports/winmatch.md): the flat toolbar strip, a fresh folder with focus but no
// selection, the .rc English, the Extract dialog without a summary, the progress window without
// an extra status line, F1 in About. Also writes the Mac half of the paired toolbar screenshots,
// `screenshots/wincompare-toolbar-<state>-mac.png`.

import AppKit
import SevenZipKit
import XCTest
@testable import SevenZipAppHost

final class WinMatchTests: AppHostTestCase {

    override var screenshotPrefix: String { "winmatch" }

    private var controllers: [MainWindowController] = []
    private var scratchDirectories: [String] = []
    private var savedNumPanels = 1
    private var savedPanelPaths: [String?] = []
    private var savedMask: UInt32 = 0

    override func setUpWithError() throws {
        try super.setUpWithError()
        savedNumPanels = Settings.numPanels
        savedPanelPaths = [Settings.panelPath(0), Settings.panelPath(1)]
        savedMask = Settings.toolbarsMask
    }

    override func tearDown() {
        while NSApp.modalWindow != nil { NSApp.abortModal() }
        for controller in controllers { controller.window?.close() }
        controllers = []
        for path in scratchDirectories { try? FileManager.default.removeItem(atPath: path) }
        scratchDirectories = []
        for (i, path) in savedPanelPaths.enumerated() { Settings.setPanelPath(path, i) }
        Settings.numPanels = savedNumPanels
        Settings.toolbarsMask = savedMask
        Help.opener = nil
        super.tearDown()
    }

    // MARK: - helpers

    private func makeScratch() -> String {
        let path = (TestPaths.artifacts as NSString).appendingPathComponent("winmatch-t-\(UUID().uuidString)")
        let fm = FileManager.default
        try? fm.createDirectory(atPath: path + "/sub", withIntermediateDirectories: true)
        for name in ["test.7z", "test.zip"] {
            try? fm.copyItem(atPath: TestPaths.fixture(name), toPath: path + "/" + name)
        }
        fm.createFile(atPath: path + "/a.txt", contents: Data(repeating: 0x61, count: 1234))
        scratchDirectories.append(path)
        return path
    }

    private func makeWindow(mask: UInt32? = nil) -> MainWindowController {
        Settings.numPanels = 1
        if let mask { Settings.toolbarsMask = mask }
        // A fresh toolbar arrangement: AppKit keeps a customized one per identifier.
        UserDefaults.standard.removeObject(forKey: "NSToolbar Configuration \(MainWindowController.macToolbarIdentifier)")
        let controller = MainWindowController()
        controllers.append(controller)
        controller.window?.setContentSize(NSSize(width: 1000, height: 600))
        controller.showWindow(nil)
        ActiveContext.register(controller)
        return controller
    }

    private func navigate(_ panel: PanelViewController, to path: String) {
        var done = false
        panel.navigate(to: path) { _ in done = true }
        XCTAssertTrue(wait(for: "panel bound to \(path)") { done })
    }

    private func allViews(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(allViews) }

    private func texts(_ window: NSWindow) -> [String] {
        allViews(window.contentView!).compactMap { ($0 as? NSTextField)?.stringValue }
    }

    private func key(_ functionKey: Int, in window: NSWindow?) -> NSEvent {
        let s = String(Character(UnicodeScalar(UInt16(functionKey))!))
        return NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.function],
                                timestamp: ProcessInfo.processInfo.systemUptime,
                                windowNumber: window?.windowNumber ?? 0, context: nil,
                                characters: s, charactersIgnoringModifiers: s, isARepeat: false,
                                keyCode: 0)!
    }

    // MARK: - toolbar (App.cpp CreateToolbar / AddButton, 01 §1.3)

    /// A button sends its selector down the responder chain (kMenuCmdID_Toolbar_Add 1070 ...).
    func testToolbarButtonsSendTheirCommands() throws {
        let controller = makeWindow(mask: 0xD)
        let actions = controller.commandToolbarItems.map { $0.action.map(NSStringFromSelector) ?? "" }
        XCTAssertEqual(actions, ["toolbarAddToArchive:", "toolbarExtractArchives:", "toolbarTestArchives:",
                                 "fileCopyTo:", "fileMoveTo:", "fileDelete:", "fileProperties:"])
        XCTAssertTrue(controller.commandToolbarItems.allSatisfy { $0.target == nil })
    }

    // MARK: - a folder just opened (PanelItems.cpp:984-1001, RefreshListCtrl)

    /// 7zFM opens a folder with the first item focused and nothing selected: "0 / N object(s)
    /// selected", nothing operated, the File menu fully enabled, Down moves on from the focus.
    func testFreshFolderIsFocusedButNotSelected() throws {
        let scratch = makeScratch()
        let controller = makeWindow(mask: 0xD)
        let panel = controller.focusedPanel
        navigate(panel, to: scratch)
        controller.window?.makeFirstResponder(panel.tableView)
        let total = panel.rows.filter { !$0.isParentRow }.count
        XCTAssertTrue(panel.selectedIndexes.isEmpty, "nothing selected")
        XCTAssertEqual(panel.focusedIndex, panel.rows.firstIndex { !$0.isParentRow }, "the first item has the focus")
        XCTAssertEqual(panel.statusBarTexts.first, Bidi.isolate("0 / \(total) object(s) selected"))
        XCTAssertEqual(panel.statusBarTexts[1], "", "no operated size")
        XCTAssertTrue(panel.operatedRowIndices().isEmpty)
        XCTAssertEqual(panel.operatedSmartRowIndices().count, total, "OperSmart: the whole folder")
        for action in [#selector(PanelViewController.fileOpen(_:)), #selector(PanelViewController.fileRename(_:)),
                       #selector(PanelViewController.fileDelete(_:)), #selector(PanelViewController.fileProperties(_:))] {
            XCTAssertTrue(panel.isActionEnabled(action), "\(action) is enabled with nothing selected, as in 7zFM")
        }
        attach(try XCTUnwrap(controller.window), "fresh-folder")

        // Down from an unselected focus selects the *next* item, as the list control does.
        let first = panel.focusedIndex
        XCTAssertTrue(panel.handleListKeyDown(key(NSDownArrowFunctionKey, in: controller.window)))
        XCTAssertEqual(panel.focusedIndex, first + 1)
        XCTAssertEqual(panel.selectedIndexes, IndexSet(integer: first + 1))
        XCTAssertEqual(panel.statusBarTexts.first, Bidi.isolate("1 / \(total) object(s) selected"))

        // Deselect All: focused, not selected, nothing operated (requests.md wincompare -> panel).
        panel.editDeselectAll(nil)
        XCTAssertTrue(panel.operatedRowIndices().isEmpty)
        XCTAssertEqual(panel.statusBarTexts.first, Bidi.isolate("0 / \(total) object(s) selected"))
    }

    // MARK: - .rc English (requests.md wincompare -> orchestrator)

    /// With no language file the text is the .rc resource's, not en.ttt's.
    func testBuiltInEnglishIsTheRcText() {
        useLanguage("-")
        XCTAssertEqual(Lang.text(4000, "x"), "Add to Archive", "IDD_COMPRESS caption (en.ttt: Add to archive)")
        XCTAssertEqual(Lang.text(4008, "x"), "Solid Block size:", "IDT_COMPRESS_SOLID (en.ttt: Solid block size:)")
        XCTAssertEqual(Lang.text(3400, "x"), "Extract")
        XCTAssertEqual(Lang.text(2900, "x"), "About 7-Zip")
        XCTAssertEqual(Lang.text(1008, "x"), "Packed Size", "STRINGTABLE wins for LangString")
        // per dialog where the dialogs disagree
        XCTAssertEqual(Lang.dialogText(4000, 3803, "x"), "Show Password")
        XCTAssertEqual(Lang.dialogText(3400, 3803, "x"), "Show Password")
        XCTAssertEqual(Lang.dialogText(3800, 3803, "x"), "Show password")
        XCTAssertEqual(Lang.dialogTextColon(97, 1008, "x"), "Compressed size:")
        XCTAssertEqual(Lang.dialogTextColon(97, 1032, "x"), "Files:")
        XCTAssertEqual(Lang.dialogText(7300, 7302, "x"), "Split to volumes,  bytes:")
        // a language file still wins, with the colon added by LangSetDlgItems_Colon
        useLanguage("de")
        XCTAssertNotEqual(Lang.text(4000, "x"), "Add to Archive")
        XCTAssertEqual(Lang.dialogTextColon(97, 1032, "x"), (Lang.translated(1032) ?? "") + ":")
        useLanguage("-")
    }

    /// The Compress dialog's caption and password box read the .rc text.
    func testCompressDialogUsesRcCaptions() {
        var input = CompressDialogInput()
        input.directoryPrefix = TestPaths.fixtures + "/"
        input.archiveBaseName = "a"
        input.itemPaths = [TestPaths.fixture("test.7z")]
        let appeared = ModalProbe.present(timeout: 40, { _ = CompressDialogController.run(input) }) { window in
            XCTAssertEqual(window.title, "Add to Archive")
            let titles = self.allViews(window.contentView!).compactMap { ($0 as? NSButton)?.title }
            XCTAssertTrue(titles.contains("Show Password"), "\(titles)")
            XCTAssertTrue(self.texts(window).contains("Solid Block size:"), "\(self.texts(window))")
            self.attach(window, "compress-rc-english")
        }
        XCTAssertTrue(appeared)
    }

    // MARK: - Extract dialog (IDD_EXTRACT 3400, requests.md wincompare -> extract)

    /// The Extract dialog for archives on disk has IDD_EXTRACT's controls only: no summary.
    func testExtractDialogHasNoArchiveSummary() {
        let scratch = makeScratch()
        let controller = makeWindow(mask: 0xD)
        let panel = controller.focusedPanel
        navigate(panel, to: scratch)
        if let i = panel.rows.firstIndex(where: { $0.name == "test.7z" }) { panel.setFocus(i) }
        let appeared = ModalProbe.present({ ExtractCommands.extractWithDialog() }) { window in
            let all = self.texts(window)
            XCTAssertFalse(all.contains { $0.contains("Archives:") }, "\(all)")
            XCTAssertFalse(all.contains { $0.hasPrefix("test.7z") }, "\(all)")
            self.attach(window, "extract-no-summary")
        }
        XCTAssertTrue(appeared)
    }

    // MARK: - progress window (IDD_PROGRESS, requests.md wincompare -> opsinfra)

    /// Finished with messages: Close, and no "Errors: N" status line (IDT_PROGRESS_STATUS stays
    /// empty; the count is the Errors row's). The labels are the .rc's "Files:" / "Compressed size:".
    func testFinishedProgressHasNoErrorsStatusLine() {
        let progress = ProgressDialog(title: Lang.text(3302, "Testing"), showCompressionInfo: true)
        progress.operationDidFinish(hasMessages: true)
        let all = texts(progress.window)
        XCTAssertFalse(all.contains { $0.hasPrefix("Errors: ") }, "\(all)")
        XCTAssertTrue(all.contains("Files:"), "\(all)")
        XCTAssertTrue(all.contains("Compressed size:"), "\(all)")
        progress.window.orderOut(nil)
    }

    // MARK: - About (IDD_ABOUT 2900, requests.md wincompare -> tools)

    /// Two buttons as on Windows, and F1 opens start.htm (CAboutDialog::OnHelp).
    func testAboutF1OpensTheStartPage() {
        var opened: [URL] = []
        Help.opener = { opened.append($0) }
        XCTAssertTrue(AboutDialog.isHelpKey(key(NSF1FunctionKey, in: nil)))
        XCTAssertTrue(AboutDialog.isHelpKey(key(NSHelpFunctionKey, in: nil)))
        XCTAssertFalse(AboutDialog.isHelpKey(key(NSF2FunctionKey, in: nil)))
        let appeared = ModalProbe.present({ AboutDialog.show(parent: nil) }) { window in
            let buttons = self.allViews(window.contentView!).compactMap { ($0 as? NSButton)?.title }
            XCTAssertEqual(Set(buttons), ["OK", "www.7-zip.org"])
            NSApp.sendEvent(self.key(NSF1FunctionKey, in: window))
        }
        XCTAssertTrue(appeared)
        XCTAssertEqual(opened.map(\.lastPathComponent), ["start.htm"], "\(opened)")
    }
}
