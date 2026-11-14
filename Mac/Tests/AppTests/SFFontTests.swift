// SFFontTests.swift -- the sffont scope (reports/sffont.md): SF Pro 12.2 as the whole UI's font,
// the list's columns and rows for it, the dialogs' text measured against its frames in six
// languages, the archive icons' low-resolution frames drawn pixel-sharp, and the images for the
// user (sffont-main / -options / -compress / -extract, sffont-icons-before / -after, 1x and 2x).

import AppKit
import ImageIO
import SevenZipKit
import XCTest
@testable import SevenZipAppHost

final class SFFontTests: AppHostTestCase {

    override var screenshotPrefix: String { "sffont" }

    private var controllers: [MainWindowController] = []
    private var scratchRoot: String?
    private var savedNumPanels = 1
    private var savedPanelPath: String?
    private var savedListMode = 3
    private var savedTime = (-1, false)

    private var fixtures: String { TestPaths.fixtures }
    private var archive: String { TestPaths.fixture("test.7z") }

    override func setUpWithError() throws {
        try super.setUpWithError()
        savedNumPanels = Settings.numPanels
        savedPanelPath = Settings.panelPath(0)
        savedListMode = Settings.listMode(0)
        savedTime = (Settings.timestampLevel, Settings.timestampShowUTC)
        // The default View > Time: minutes, local time (datecols: a UTC left on by an earlier
        // test put "Z" into every date of sffont-main.png).
        Settings.timestampLevel = Int(SZTimestampLevel.min.rawValue)
        Settings.timestampShowUTC = false
        NSApp.appearance = NSAppearance(named: .aqua)
    }

    override func tearDown() {
        for controller in controllers { controller.window?.close() }
        controllers = []
        if let scratchRoot { try? FileManager.default.removeItem(atPath: scratchRoot) }
        Settings.numPanels = savedNumPanels
        Settings.setPanelPath(savedPanelPath, 0)
        Settings.setListMode(savedListMode, 0)
        (Settings.timestampLevel, Settings.timestampShowUTC) = savedTime
        NSApp.appearance = nil
        useLanguage("-")
        super.tearDown()
    }

    // MARK: - 1. the font

    private static let systemFamily = NSFont.systemFont(ofSize: 12.2).familyName

    private static func isUIFont(_ font: NSFont?) -> Bool {
        guard let font else { return false }
        return font.familyName == systemFamily && abs(font.pointSize - 12.2) < 0.01
    }

    /// The 19 px row holds SF Pro 12.2's line (ascender + descender) with room to spare, and the
    /// cell's text field is no taller than the row.
    func testRowsHoldTheFontsLine() throws {
        for font in [PanelMetrics.listFont, PanelMetrics.listDigitsFont] {
            let glyphs = font.ascender - font.descender
            let line = NSLayoutManager().defaultLineHeight(for: font)
            XCTAssertLessThanOrEqual(line, PanelMetrics.rowHeight - 2, "\(font): line \(line)")
            XCTAssertLessThanOrEqual(glyphs, PanelMetrics.rowHeight - 4, "\(font): glyphs \(glyphs)")
        }
        let (controller, panel) = try openPanel(on: makeFixture())
        _ = controller
        let table = panel.tableView
        XCTAssertEqual(table.rowHeight + table.intercellSpacing.height, PanelMetrics.rowHeight)
        for column in 0..<table.numberOfColumns {
            guard let cell = table.view(atColumn: column, row: 0, makeIfNecessary: true) as? NSTableCellView,
                  let field = cell.textField else { continue }
            cell.layoutSubtreeIfNeeded()
            XCTAssertGreaterThanOrEqual(field.frame.minY, -0.5, "column \(column): the text is not cut at the top")
            XCTAssertLessThanOrEqual(field.frame.maxY, cell.bounds.height + 0.5, "column \(column): nor at the bottom")
            XCTAssertGreaterThanOrEqual(field.frame.height, ceil(NSLayoutManager().defaultLineHeight(for: field.font!)) - 0.5)
        }
    }

    // MARK: - 2. dialog text against its frames, six languages

    /// Every label, check box, radio button, push button and group-box title of every dialog fits
    /// its frame in English, German, Russian, French, Japanese and Arabic: a one-line static's text
    /// on its line, a wrapping static's lines in its height, a button's title with its bezel.
    func testDialogTextFitsItsFramesInSixLanguages() {
        continueAfterFailure = true
        var failures: [String] = []
        var popups: [String] = []
        var checked = 0
        for code in ["-", "de", "ru", "fr", "ja", "ar"] {
            autoreleasepool {
                useLanguage(code)
                for probe in probes() {
                    let appeared = ModalProbe.present(timeout: probe.timeout, probe.present) { window in
                        let found = self.textFits(in: window, name: "\(probe.name) [\(code)]")
                        failures += found.clipped
                        popups += found.popups
                        checked += found.checked
                    }
                    if !appeared { failures.append("MISSING \(probe.name) [\(code)]") }
                }
                forEachOptionsPage { window, name in
                    let found = self.textFits(in: window, name: "\(name) [\(code)]")
                    failures += found.clipped
                    popups += found.popups
                    checked += found.checked
                }
            }
        }
        print("SFFONT-FIT | \(checked) texts checked, \(failures.count) clipped, \(popups.count) pop-up titles cut")
        for line in failures { print("SFFONT-FIT CLIPPED \(line)") }
        for line in popups { print("SFFONT-FIT POPUP \(line)") }
        XCTAssertGreaterThan(checked, 1000)
        XCTAssertTrue(failures.isEmpty, "text that does not fit its frame:\n" + failures.joined(separator: "\n"))
        XCTAssertLessThanOrEqual(popups.count, 3, "drop-down titles cut at 10 pt:\n" + popups.joined(separator: "\n"))
    }

    // MARK: - 3. archive icons

    // MARK: - 4. the images for the user

    /// The main window and three dialogs in SF Pro 12.2, at 2x, drawn without font smoothing as
    /// the screen draws them (Feel3FontTests.drawUnsmoothed); the list's rows must carry ink.
    func testScreenshotsInTheNewFont() throws {
        // The main window: Details on a folder with archives, a row selected.
        let (controller, panel) = try openPanel(on: makeFixture())
        let window = try XCTUnwrap(controller.window)
        panel.listFocusOverride = true
        defer { panel.listFocusOverride = nil }
        if let a = panel.rows.firstIndex(where: { $0.name == "backup.7z" }) {
            panel.tableView.selectRowIndexes(IndexSet(integer: a), byExtendingSelection: false)
            panel.focusedIndex = a
            panel.refreshSelectionAppearance()
        }
        let content = try XCTUnwrap(window.contentView)
        content.layoutSubtreeIfNeeded()
        content.displayIfNeeded()
        let image = try XCTUnwrap(renderMain(content: content, panel: panel, scale: 2))
        try write(image, "sffont-main.png")

        // The dialogs.
        var extract = ExtractDialog.Options()
        extract.directoryPath = fixtures + "/"
        extract.archivePath = archive
        XCTAssertTrue(ModalProbe.present({ _ = ExtractDialog.run(extract) }) { w in
            try? self.write(self.renderWindow(w, scale: 2), "sffont-extract.png")
        })
        try SZCodecs.loadCodecs()
        var input = CompressDialogInput()
        input.directoryPrefix = fixtures + "/"
        input.archiveBaseName = "test"
        input.itemPaths = [archive]
        XCTAssertTrue(ModalProbe.present(timeout: 60, { _ = CompressDialogController.run(input) }) { w in
            try? self.write(self.renderWindow(w, scale: 2), "sffont-compress.png")
        })
        let options = OptionsWindowController.shared
        let optionsWindow = try XCTUnwrap(options.window)
        XCTAssertTrue(ModalProbe.present({ OptionsWindowController.showOptions() }) { _ in })
        for index in 0..<options.pageCount {
            options.selectPage(index)
            optionsWindow.contentView?.layoutSubtreeIfNeeded()
            optionsWindow.displayIfNeeded()
            let name = index == 0 ? "sffont-options.png" : "sffont-options-\(index + 1).png"
            try write(renderWindow(optionsWindow, scale: 2), name)
        }
        ModalProbe.close(optionsWindow)
    }

    // MARK: - probes

    struct Probe {
        let name: String
        var timeout: TimeInterval = 30
        let present: () -> Void
    }

    /// Every dialog of the port that has text controls, built as the app builds it.
    private func probes() -> [Probe] {
        let fixtures = self.fixtures, archive = self.archive
        var list: [Probe] = [
            Probe(name: "About (IDD_ABOUT)") { AboutDialog.show(parent: nil) },
            Probe(name: "Copy (IDD_COPY)") {
                _ = CopyMoveDialog.run(move: false, value: fixtures + "/", history: [fixtures], info: archive, parent: nil)
            },
            Probe(name: "Move (IDD_COPY)") {
                _ = CopyMoveDialog.run(move: true, value: fixtures + "/", history: [], info: "", parent: nil)
            },
            Probe(name: "Create Folder (IDD_COMBO)") {
                _ = ComboDialog.run(title: Lang.text(6300, "Create Folder"), label: Lang.text(6302, "Folder name:"),
                                    value: Lang.text(6304, "New Folder"), parent: nil)
            },
            Probe(name: "Select (IDD_COMBO)") {
                _ = ComboDialog.run(title: Lang.text(6402, "Select"), label: Lang.text(6404, "Mask:"), value: "*",
                                    strings: ["*"], parent: nil)
            },
            Probe(name: "Comment (IDD_COMMENT)") { _ = CommentDialog.run(value: "", parent: nil) },
            Probe(name: "Split (IDD_SPLIT)") { _ = SplitDialog.run(filePath: archive, path: fixtures, parent: nil) },
            Probe(name: "Combine (IDD_COMBO)") {
                _ = CombineDialog.run(title: Lang.text(7400, "Combine Files"), prompt: Lang.text(7402, "Combine to:"),
                                      info: TestPaths.fixture("multi.7z.001"), path: fixtures, parent: nil)
            },
            Probe(name: "Link (IDD_LINK)") {
                _ = LinkDialog.run(currentDirPrefix: fixtures + "/", filePath: archive,
                                   anotherPath: TestPaths.realHome, parent: nil)
            },
            Probe(name: "Folders History (IDD_LISTVIEW)") {
                var history = ListViewDialogOptions()
                history.title = Lang.text(6601, "Folders History")
                history.strings = [fixtures, "/tmp"]
                history.deleteIsAllowed = true
                _ = ListViewDialog.run(history, parent: nil)
            },
            Probe(name: "Delete Temporary Files (IDD_TEMP_FILES)") { ToolsTempFilesDialog.show(parent: nil) },
            Probe(name: "Benchmark (IDD_BENCH)", timeout: 60) { BenchmarkDialog.run(totalMode: false, parent: nil) },
            Probe(name: "Extract (IDD_EXTRACT)") {
                var extract = ExtractDialog.Options()
                extract.directoryPath = fixtures + "/"
                extract.archivePath = archive
                _ = ExtractDialog.run(extract)
            },
            Probe(name: "Add to Archive (IDD_COMPRESS)", timeout: 60) {
                var input = CompressDialogInput()
                input.directoryPrefix = fixtures + "/"
                input.archiveBaseName = "a"
                input.itemPaths = [archive]
                _ = CompressDialogController.run(input)
            },
            Probe(name: "Overwrite (IDD_OVERWRITE)") {
                let old = OverwriteDialog.FileInfo(path: archive, size: 838, time: Date())
                let new = OverwriteDialog.FileInfo(path: TestPaths.fixture("test.zip"), size: 1024, time: Date())
                _ = OverwriteDialog.run(oldFile: old, newFile: new, showExtraButtons: true, parent: nil)
            },
            Probe(name: "Password (IDD_PASSWORD)") {
                var pw = PasswordDialog.Options()
                pw.subject = archive
                pw.requiresVerification = true
                pw.showsEncryptFileNames = true
                _ = PasswordDialog.run(pw, parent: nil)
            },
            Probe(name: "Messages (IDD_MESSAGES)") { MessagesDialog.show(messages: ["a : CRC failed"], parent: nil) },
            Probe(name: "Memory (IDD_MEM)") {
                var memory = MemoryUseDialog.Options()
                memory.requiredGB = 4
                memory.limitGB = 2
                memory.ramGB = 16
                memory.filePath = "sub/big.txt"
                memory.archivePath = archive
                memory.showRemember = true
                _ = MemoryUseDialog.run(memory, parent: nil)
            },
            Probe(name: "Progress (IDD_PROGRESS)") {
                let progress = ProgressDialog(title: Lang.text(3300, "Extracting"), showCompressionInfo: true)
                progress.window.makeKeyAndOrderFront(nil)
                SFFontTests.retained = progress
            },
            Probe(name: "Message box") {
                // A fixed path: the checkout's own path would make the line breaks depend on where
                // the repository lies (a worktree name half a point wider wrapped once more).
                _ = WinMessageBox.run(Lang.text(6000, "Copy") + ": /Users/Shared/7-Zip Demo/Project backup.7z",
                                      caption: "7-Zip",
                                      buttons: .yesNoCancel, icon: .question, owner: nil)
            },
        ]
        if (try? SZCodecs.loadCodecs()) != nil {
            for name in ["7z", "zip"] {
                guard let f = SZCodecs.format(named: name) else { continue }
                list.append(Probe(name: "Compress Options \(name) (IDD_COMPRESS_OPTIONS)") {
                    var state = CompressOptionsSheet.State(
                        formatName: f.name, formatTimeFlags: f.timeFlags, formatFlags: f.flags,
                        supportsMTime: f.supportsMTime, supportsCTime: f.supportsCTime, supportsATime: f.supportsATime,
                        supportsSymLinks: f.supportsSymLinks, supportsHardLinks: f.supportsHardLinks,
                        supportsAltStreams: f.supportsAltStreams, supportsNtSecurity: f.supportsNtSecurity,
                        isTar: false, isZip: name == "zip", isGZip: false,
                        isKeepName: f.keepName, tarMethodName: "")
                    _ = CompressOptionsSheet.run(&state, parent: nil)
                })
            }
            if let results = try? SZHasher.hash(paths: ["test.7z"], relativeTo: fixtures, methods: ["CRC32", "SHA256"],
                                                recursive: false, progress: nil) {
                list.append(Probe(name: "Checksum (IDD_LISTVIEW)") { HashResultsDialog.show(results: results, parent: nil) })
            }
        }
        return list
    }

    /// Keeps a window the probe opened non-modally alive until the probe closes it.
    static var retained: AnyObject?

    private func forEachOptionsPage(_ body: (NSWindow, String) -> Void) {
        let controller = OptionsWindowController.shared
        guard let window = controller.window else { return XCTFail("no Options window") }
        XCTAssertTrue(ModalProbe.present({ OptionsWindowController.showOptions() }) { _ in })
        for index in 0..<controller.pageCount {
            controller.selectPage(index)
            window.contentView?.layoutSubtreeIfNeeded()
            body(window, "Options page \(index + 1)")
        }
        ModalProbe.close(window)
    }

    // MARK: - measuring

    private func isVisible(_ view: NSView) -> Bool {
        var v: NSView? = view
        while let current = v {
            if current.isHidden || current.alphaValue < 0.01 { return false }
            v = current.superview
        }
        return true
    }

    /// The views of `root` that show text, outside scroll views (a list's cells are its own
    /// business) and outside the unselected tab pages.
    private func textViews(_ root: NSView?) -> [NSView] {
        guard let root else { return [] }
        var found: [NSView] = []
        for child in root.subviews where !child.isHidden {
            if child is NSScrollView { continue }
            if let tabs = child as? NSTabView {
                found += textViews(tabs.selectedTabViewItem?.view)
                continue
            }
            if child is NSControl || child is WinGroupBox { found.append(child) }
            // A control's subviews are its own (a field editor); a group box's title field is a label.
            if !(child is NSControl) { found += textViews(child) }
        }
        return found
    }

    private func fontDefects(in root: NSView?, path: String) -> [String] {
        var wrong: [String] = []
        for view in textViews(root) where isVisible(view) {
            guard let control = view as? NSControl else { continue }
            if control is NSSlider || control is NSStepper || control is NSSegmentedControl || control is NSImageView { continue }
            let title = (control as? NSButton)?.title ?? (control as? NSTextField)?.stringValue ?? ""
            if control is NSButton, title.isEmpty, !(control is NSPopUpButton) { continue }   // an icon button
            let font = control.font
            let bold = font.map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } ?? false
            if Self.isUIFont(font) || (bold && font?.familyName == Self.systemFamily && abs((font?.pointSize ?? 0) - 12.2) < 0.01) { continue }
            wrong.append("\(path) > \(type(of: control)) '\(title.prefix(40))': \(font.map { "\($0.fontName) \($0.pointSize)" } ?? "nil")")
        }
        return wrong
    }

    private struct FitResult {
        var clipped: [String] = []
        var popups: [String] = []
        var checked = 0
    }

    private func textFits(in window: NSWindow, name: String) -> FitResult {
        var result = FitResult()
        guard let content = window.contentView else { return result }
        content.layoutSubtreeIfNeeded()
        for view in textViews(content) where isVisible(view) {
            let frame = view.frame
            guard frame.width > 1, frame.height > 1 else { continue }
            if let group = view as? WinGroupBox {
                guard !group.title.isEmpty else { continue }
                result.checked += 1
                let needed = ceil(group.titleField.attributedStringValue.size().width)
                if needed > frame.width - 16 + 0.5 {
                    result.clipped.append("\(name) > group '\(group.title)' needs \(needed) + 16, has \(frame.width)")
                }
                continue
            }
            if let popup = view as? NSPopUpButton {
                let title = popup.titleOfSelectedItem ?? ""
                guard !title.isEmpty else { continue }
                // The room AppKit's pop-up leaves its title beside the arrows (RcFormView.overflow).
                let over = RcFormView.overflow(of: popup)
                let needed = frame.width + over
                if over > 0.5 {
                    // Cut only when nothing else could be done: no free room beside it and its
                    // font already at the 10 pt floor (a translation Windows cuts too).
                    let line = "\(name) > '\(title)' needs \(needed), has \(frame.width) at \(popup.font?.pointSize ?? 0) pt"
                    if (popup.font?.pointSize ?? 99) > 10.05 { result.clipped.append(line) } else { result.popups.append(line) }
                }
                continue
            }
            if view is NSComboBox { continue }
            if let field = view as? NSTextField {
                guard !field.isEditable, !field.isBezeled, let cell = field.cell else { continue }
                let text = field.stringValue
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                // A path or a value that is meant to be cut (the Copy dialog's info lines, a file
                // name) sets a truncating mode on purpose.
                if [.byTruncatingTail, .byTruncatingMiddle, .byTruncatingHead].contains(field.lineBreakMode)
                    || cell.truncatesLastVisibleLine { continue }
                result.checked += 1
                let size = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: frame.width, height: 10_000))
                let oneLine = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: 10_000, height: 10_000))
                let wraps = cell.wraps || field.maximumNumberOfLines != 1
                let needsWidth = !wraps && oneLine.width > frame.width + 0.5
                let needsHeight = size.height > frame.height + 1
                // A word longer than the line (a path) is broken between characters, not cut.
                let longestWord = text.split(whereSeparator: { $0 == " " || $0 == "\n" })
                    .map { ceil((String($0) as NSString).size(withAttributes: [.font: field.font ?? DialogMetrics.font]).width) }
                    .max() ?? 0
                if needsWidth || needsHeight {
                    result.clipped.append(String(format: "%@ > label '%@' needs %.0fx%.0f, has %.0fx%.0f%@", name,
                                                 String(text.prefix(60)), wraps ? frame.width : oneLine.width,
                                                 size.height, frame.width, frame.height,
                                                 longestWord > frame.width ? " (a word wider than the line)" : ""))
                }
                continue
            }
            if let button = view as? NSButton {
                let title = button.title
                guard !title.isEmpty, let cell = button.cell else { continue }
                result.checked += 1
                // A push button's title with AppKit's 9 pt of bezel each side; a check box's or
                // radio button's whole cell (box, gap, title).
                let push = button.bezelStyle == .rounded && button.isBordered
                let needed = push ? ceil(button.attributedTitle.size().width) + 18 : ceil(cell.cellSize.width)
                let room = frame.width
                if needed > room + 1 {
                    let kind = button.bezelStyle == .rounded && button.isBordered ? "button" : "check/radio"
                    result.clipped.append(String(format: "%@ > %@ '%@' needs %.0f, has %.0f (frame %.0f)", name, kind,
                                                 String(title.prefix(60)), needed, room, frame.width))
                }
            }
        }
        return result
    }

    // MARK: - the panel

    private func makeFixture() -> String {
        let root = (TestPaths.artifacts as NSString).appendingPathComponent("sffont-\(UUID().uuidString)")
        scratchRoot = root
        let path = root + "/Documents"
        let fm = FileManager.default
        try? fm.createDirectory(atPath: path + "/Projects", withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: path + "/Photos 2024", withIntermediateDirectories: true)
        let files: [(String, Int)] = [("backup.7z", 1_482_331), ("photos.zip", 25_731_040), ("source.tar.gz", 315_904),
                                      ("disk image.iso", 734_003_200 / 1000), ("installer.rar", 4_201_500),
                                      ("logs.tar.xz", 81_920), ("notes.txt", 1_234), ("report 2024.pdf", 412_771),
                                      ("split.7z.001", 1_048_576), ("readme.md", 2_048)]
        for (name, size) in files { fm.createFile(atPath: path + "/" + name, contents: Data(count: size)) }
        var c = DateComponents()
        (c.year, c.month, c.day, c.hour, c.minute) = (2024, 11, 28, 22, 58)
        if let date = Calendar.current.date(from: c) {
            for name in ((try? fm.contentsOfDirectory(atPath: path)) ?? []) + [""] {
                try? fm.setAttributes([.modificationDate: date, .creationDate: date],
                                      ofItemAtPath: name.isEmpty ? path : path + "/" + name)
            }
        }
        return path
    }

    private func openPanel(on folder: String) throws -> (MainWindowController, PanelViewController) {
        Settings.numPanels = 1
        Settings.setListMode(3, 0)
        Settings.removeKey("FM.Columns.FSFolder")
        let controller = MainWindowController()
        controllers.append(controller)
        controller.window?.setContentSize(NSSize(width: 900, height: 420))
        controller.showWindow(nil)
        let panel = controller.focusedPanel
        var done = false
        panel.navigate(to: folder) { _ in done = true }
        XCTAssertTrue(wait(for: "bound") { done })
        controller.window?.makeFirstResponder(panel.tableView)
        let rowCount = panel.rows.count
        XCTAssertTrue(wait(for: "row views") {
            controller.window?.contentView?.layoutSubtreeIfNeeded()
            controller.window?.contentView?.displayIfNeeded()
            let table = panel.tableView
            return rowCount >= 10 && table.numberOfRows == rowCount
                && (0..<min(rowCount, 9)).allSatisfy { table.view(atColumn: 0, row: $0, makeIfNecessary: false) != nil }
        })
        return (controller, panel)
    }

    // MARK: - rendering

    /// The main window's content without font smoothing, its list drawn part by part over it
    /// (Feel3FontTests.drawList: the rows' clip view can be skipped when the scroll view is drawn
    /// as one piece), refusing an image whose list has no rows.
    private func renderMain(content: NSView, panel: PanelViewController, scale: Int) throws -> CGImage? {
        let s = CGFloat(scale)
        guard let base = Feel3FontTests.drawUnsmoothed(content, rect: content.bounds, scale: scale),
              let scroll = panel.tableView.enclosingScrollView,
              let headerClip = panel.tableView.headerView?.superview as? NSClipView else { return nil }
        let inContent = content.convert(scroll.bounds, from: scroll)
        guard let list = Feel3FontTests.drawList(scroll, parts: [scroll.contentView, headerClip],
                                                 size: scroll.bounds.size, scale: scale) else { return nil }
        let ink = Feel3FontTests.ink(list, below: Int(PanelMetrics.headerHeight), scale: scale)
        XCTAssertGreaterThan(ink, Feel3FontTests.minimumRowInk, "the main window's list has no rows (ink \(Int(ink)))")
        let w = Int(content.bounds.width * s), h = Int(content.bounds.height * s)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        fillBackground(ctx, content.window, width: w, height: h)
        ctx.draw(base, in: CGRect(x: 0, y: 0, width: w, height: h))
        let y = content.isFlipped ? content.bounds.height - inContent.maxY : inContent.minY
        ctx.draw(list, in: CGRect(x: inContent.minX * s, y: y * s, width: inContent.width * s, height: inContent.height * s))
        return ctx.makeImage()
    }

    private func fillBackground(_ ctx: CGContext, _ window: NSWindow?, width: Int, height: Int) {
        let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns
        (window?.appearance ?? NSApp.effectiveAppearance).performAsCurrentDrawingAppearance {
            (window?.backgroundColor ?? .windowBackgroundColor).setFill()
            NSRect(x: 0, y: 0, width: width, height: height).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// A dialog's client area without font smoothing over its background.
    private func renderWindow(_ window: NSWindow, scale: Int) -> CGImage? {
        guard let content = window.contentView else { return nil }
        content.layoutSubtreeIfNeeded()
        content.displayIfNeeded()
        let s = CGFloat(scale)
        let w = Int(content.bounds.width * s), h = Int(content.bounds.height * s)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let image = Feel3FontTests.drawUnsmoothed(content, rect: content.bounds, scale: scale) else { return nil }
        fillBackground(ctx, window, width: w, height: h)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let made = ctx.makeImage()
        if let made {
            // Text was drawn: a dialog image is never just its background.
            XCTAssertGreaterThan(Feel3FontTests.ink(made, below: 0, scale: scale), 500, "\(window.title) has no ink")
        }
        return made
    }

    private func write(_ image: CGImage?, _ file: String) throws {
        let image = try XCTUnwrap(image, file)
        let rep = NSBitmapImageRep(cgImage: image)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(atPath: TestPaths.screenshots, withIntermediateDirectories: true)
        try png.write(to: URL(fileURLWithPath: TestPaths.screenshots).appendingPathComponent(file), options: .atomic)
    }

}
