// ListFeelTests.swift -- the main list's look and feel against fresh-default 7zFM 26.03 on
// Windows 11 at 96 dpi (ai/reports/listfeel.md; the Windows numbers come from
// listfeel-data/win1/*.geom.txt, dlg-prop-*.txt and pixel measurements of the captures):
// row pitch, header height, icon and text placement, the selection fill's padding, default column
// widths, tabular digits, no sort arrow, the column menu's order, the rubber-band hit zones, the
// address drop-down, Properties routing (Finder Get Info outside an archive) and its rows, the
// toolbar's pressed offset, and the fresh one-panel default.
//
// Also writes the Mac half of the paired captures `screenshots/wincompare-listfeel-*-mac.png`.

import AppKit
import SevenZipKit
import XCTest
@testable import SevenZipAppHost

final class ListFeelTests: AppHostTestCase {

    override var screenshotPrefix: String { "listfeel" }

    private var controllers: [MainWindowController] = []
    private var scratchDirectories: [String] = []
    private var savedNumPanels = 1
    private var savedPanelPaths: [String?] = []
    private var savedFullRow = false
    private var savedListModes: [Int] = []
    private var savedAppearance: NSAppearance?
    private var savedSender: (([URL], @escaping (FinderInfo.Outcome) -> Void) -> Void)?

    override func setUpWithError() throws {
        try super.setUpWithError()
        savedNumPanels = Settings.numPanels
        savedPanelPaths = [Settings.panelPath(0), Settings.panelPath(1)]
        savedFullRow = Settings.fullRow
        savedListModes = [Settings.listMode(0), Settings.listMode(1)]
        savedAppearance = NSApp.appearance
        savedSender = FinderInfo.sender
        NSApp.appearance = NSAppearance(named: .aqua)
        Settings.fullRow = false
    }

    override func tearDown() {
        while NSApp.modalWindow != nil { NSApp.abortModal() }
        for controller in controllers { controller.window?.close() }
        controllers = []
        for path in scratchDirectories { try? FileManager.default.removeItem(atPath: path) }
        scratchDirectories = []
        for (i, path) in savedPanelPaths.enumerated() { Settings.setPanelPath(path, i) }
        for (i, mode) in savedListModes.enumerated() { Settings.setListMode(mode, i) }
        Settings.numPanels = savedNumPanels
        Settings.fullRow = savedFullRow
        NSApp.appearance = savedAppearance
        if let savedSender { FinderInfo.sender = savedSender }
        super.tearDown()
    }

    // MARK: helpers

    /// The Windows fixture folder's plain files (wincompare's `cmp`, same names and sizes) plus the
    /// test archives.
    private func makeScratch() -> String {
        let path = (TestPaths.artifacts as NSString).appendingPathComponent("listfeel-\(UUID().uuidString)")
        let fm = FileManager.default
        try? fm.createDirectory(atPath: path + "/cmp/sub", withIntermediateDirectories: true)
        for (name, size) in [("a.txt", 1234), ("b.bin", 100_000), ("empty.txt", 0), ("notes.md", 20)] {
            fm.createFile(atPath: path + "/cmp/" + name, contents: Data(repeating: 0x61, count: size))
        }
        fm.createFile(atPath: path + "/cmp/sub/c.txt", contents: Data(repeating: 0x30, count: 10))
        for name in ["test.7z", "test.zip"] {
            try? fm.copyItem(atPath: TestPaths.fixture(name), toPath: path + "/cmp/" + name)
        }
        var c = DateComponents()
        (c.year, c.month, c.day, c.hour, c.minute) = (2024, 1, 15, 10, 30)
        if let date = Calendar.current.date(from: c) {
            for name in (try? fm.contentsOfDirectory(atPath: path + "/cmp")) ?? [] {
                try? fm.setAttributes([.modificationDate: date, .creationDate: date], ofItemAtPath: path + "/cmp/" + name)
            }
        }
        scratchDirectories.append(path)
        return path + "/cmp"
    }

    private func makeWindow(panels: Int = 1) -> MainWindowController {
        Settings.numPanels = panels
        Settings.setListMode(3, 0)
        Settings.setListMode(3, 1)
        let controller = MainWindowController()
        controllers.append(controller)
        controller.window?.setContentSize(NSSize(width: 1000, height: 600))
        controller.showWindow(nil)
        return controller
    }

    private func navigate(_ panel: PanelViewController, to path: String) {
        var done = false
        panel.navigate(to: path) { _ in done = true }
        XCTAssertTrue(wait(for: "panel bound to \(path)") { done })
        panel.view.window?.contentView?.layoutSubtreeIfNeeded()
    }

    private func row(_ panel: PanelViewController, _ name: String) -> Int {
        panel.rows.firstIndex { $0.displayName == name } ?? -1
    }

    private func select(_ panel: PanelViewController, _ names: [String], focus: String?) {
        panel.tableView.selectRowIndexes(IndexSet(names.map { row(panel, $0) }.filter { $0 >= 0 }), byExtendingSelection: false)
        if let focus { panel.focusedIndex = row(panel, focus) }
        panel.refreshSelectionAppearance()
        panel.view.window?.contentView?.layoutSubtreeIfNeeded()
    }

    /// `rect` (table coordinates) rendered at 2x into sRGB; pixel (x, y) in points from its top-left.
    private struct Render {
        let rep: NSBitmapImageRep
        let rect: NSRect
        /// Premultiplied sRGB bytes, composited over white (the list's background).
        func rgb(_ x: Int, _ y: Int) -> RGB {
            guard let data = rep.bitmapData, x >= 0, y >= 0, x < rep.pixelsWide, y < rep.pixelsHigh else { return .white }
            let p = data + y * rep.bytesPerRow + x * 4
            let a = Int(p[3])
            return RGB(r: Int(p[0]) + 255 - a, g: Int(p[1]) + 255 - a, b: Int(p[2]) + 255 - a)
        }
        /// Bounding box (points, relative to `rect`'s top-left) of the pixels matching `test`.
        func bbox(_ test: (RGB) -> Bool) -> NSRect? {
            var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
            for y in 0..<rep.pixelsHigh {
                for x in 0..<rep.pixelsWide where test(rgb(x, y)) {
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                }
            }
            guard maxX >= 0 else { return nil }
            return NSRect(x: CGFloat(minX) / 2, y: CGFloat(minY) / 2,
                          width: CGFloat(maxX - minX + 1) / 2, height: CGFloat(maxY - minY + 1) / 2)
        }
    }

    private func render(_ table: NSTableView, _ rect: NSRect) -> Render? {
        let area = rect.integral
        guard let raw = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(area.width) * 2,
                                         pixelsHigh: Int(area.height) * 2, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 32),
              let rep = raw.retagging(with: .sRGB) else { return nil }
        rep.size = area.size
        table.cacheDisplay(in: area, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: TestPaths.artifacts)
                .appendingPathComponent("listfeel-render-\(Int(area.minX))-\(Int(area.minY)).png"))
        }
        return Render(rep: rep, rect: area)
    }

    private static func isInk(_ p: RGB) -> Bool { (p.r + p.g + p.b) / 3 < 140 }

    // MARK: - 1. rows, header, cells

    // MARK: - 2. the selection fill

    // MARK: - 3. columns

    /// GetColumnWidth: Name 160, every other column 100, in a folder and inside archives.
    func testDefaultColumnWidthsAreTheWindowsOnes() {
        let scratch = makeScratch()
        let controller = makeWindow()
        let panel = controller.focusedPanel
        for (path, type) in [(scratch, "FSFolder"), (scratch + "/test.7z", "7-Zip.7z"), (scratch + "/test.zip", "7-Zip.zip")] {
            Settings.removeKey("FM.Columns." + type)
            navigate(panel, to: path)
            for column in panel.tableView.tableColumns {
                let pid = PanelViewController.propID(of: column)
                // sffont: a time column is as wide as SF Pro's full date + 12 (123), the rest Windows'.
                let isTime = panel.columnsModel.columns.first { $0.propID == pid }?.varType == .fileTime
                // datecols: a size column holds "9 999 999 999 999" (126).
                let isSize = pid.map { Formatting.sizePropIDs.contains($0) } ?? false
                XCTAssertEqual(column.width, pid == .name ? 160 : (isTime ? CGFloat(PanelMetrics.timeColumnWidth)
                                                                   : isSize ? CGFloat(PanelMetrics.sizeColumnWidth) : 100),
                               "\(type) \(column.title)")
            }
        }
    }

    /// ShowColumnsContextMenu lists `_columns`: the folder's property order, whatever the header
    /// shows -- 7zFM 26.03's file-system list, then the macOS-only columns (listfeel-data/win1/hdrmenu-fs.txt).
    func testColumnMenuOrder() {
        let scratch = makeScratch()
        let controller = makeWindow()
        let panel = controller.focusedPanel
        Settings.removeKey("FM.Columns.FSFolder")
        navigate(panel, to: scratch)
        let titles = panel.makeColumnsContextMenu().items.map { $0.title }
        let windows = ["Name", "Size", "Modified", "Created", "Accessed", "Metadata Changed", "Attributes",
                       "Packed Size", "iNode", "Links", "Comment", "Folders", "Files", "Link"]
        XCTAssertEqual(Array(titles.prefix(windows.count)), windows)
        XCTAssertEqual(Array(titles.dropFirst(windows.count)), ["Mode", "User", "Group"], "the macOS-only columns last")
        // A header drag does not reorder the menu.
        panel.tableView.moveColumn(3, toColumn: 1)
        panel.saveColumnLayout()
        XCTAssertEqual(Array(panel.makeColumnsContextMenu().items.map { $0.title }.prefix(windows.count)), windows)
        let archiveMenu = { () -> [String] in
            self.navigate(panel, to: scratch + "/test.7z")
            return panel.makeColumnsContextMenu().items.map { $0.title }
        }()
        XCTAssertEqual(archiveMenu.first, "Name")
        XCTAssertEqual(archiveMenu, panel.columnsModel.menuColumns.map { $0.title })
    }

    // MARK: - 4. rubber band

    // MARK: - 5. address bar

    /// CBN_DROPDOWN's list: the path's components by name, indented, then Documents, Computer and
    /// the volumes; a mouse pick binds at once (CBN_SELENDOK), the arrow keys do not.
    func testAddressDropdownEntriesAndCommit() throws {
        let entries = AddressDropdown.entries(currentPath: "/Users/me/arc.7z/sub/", documents: "/Users/me/Documents/",
                                              volumes: ["/", "/Volumes/Data"])
        XCTAssertEqual(entries.map { $0.title }, ["/", "   Users", "      me", "         arc.7z", "            sub",
                                                  "Documents", "Computer", "   /", "   /Volumes/Data"])
        XCTAssertEqual(entries.map { $0.path }, ["/", "/Users/", "/Users/me/", "/Users/me/arc.7z/", "/Users/me/arc.7z/sub/",
                                                 "/Users/me/Documents/", "", "/", "/Volumes/Data/"])
        let mouse = NSEvent.mouseEvent(with: .leftMouseUp, location: .zero, modifierFlags: [], timestamp: 0,
                                       windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)
        let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                   context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 125)
        XCTAssertTrue(AddressDropdown.isCommitEvent(mouse))
        XCTAssertFalse(AddressDropdown.isCommitEvent(key))
        XCTAssertFalse(AddressDropdown.isCommitEvent(nil))

        let scratch = makeScratch()
        let controller = makeWindow()
        let panel = controller.focusedPanel
        navigate(panel, to: scratch + "/sub")
        XCTAssertEqual(panel.pathCombo.focusRingType, .none, "no focus ring on the address bar")
        panel.rebuildAddressDropdown()
        let parent = try XCTUnwrap(panel.addressDropdownPaths.firstIndex(of: scratch + "/"), "\(panel.addressDropdownPaths)")
        panel.commitAddressDropdownEntry(at: parent)
        XCTAssertTrue(wait(for: "bound to the picked entry") { panel.currentPath == scratch + "/" })
        XCTAssertTrue(wait(for: "the list has the focus") { controller.window?.firstResponder === panel.tableView })
    }

    // MARK: - 6. Properties

    /// CPanel::Properties: an archive folder gets the list; the file system goes to the system
    /// (Finder Get Info) for the operated items, and nothing happens without one; the root too.
    func testPropertiesRouting() {
        XCTAssertEqual(FinderInfo.route(isArchive: true, isFileSystem: false, isVolumesFolder: false, itemPaths: []), .listDialog)
        XCTAssertEqual(FinderInfo.route(isArchive: false, isFileSystem: true, isVolumesFolder: false, itemPaths: ["/a", "/b"]),
                       .finder([URL(fileURLWithPath: "/a"), URL(fileURLWithPath: "/b")]))
        XCTAssertEqual(FinderInfo.route(isArchive: false, isFileSystem: true, isVolumesFolder: false, itemPaths: []), .nothing)
        XCTAssertEqual(FinderInfo.route(isArchive: false, isFileSystem: false, isVolumesFolder: true, itemPaths: ["/"]),
                       .finder([URL(fileURLWithPath: "/")]))
        XCTAssertEqual(FinderInfo.route(isArchive: false, isFileSystem: false, isVolumesFolder: false, itemPaths: ["/x"]), .nothing)
        let many = (0..<30).map { "/f\($0)" }
        if case .finder(let urls) = FinderInfo.route(isArchive: false, isFileSystem: true, isVolumesFolder: false, itemPaths: many) {
            XCTAssertEqual(urls.count, FinderInfo.maxWindows)
        } else { XCTFail("not routed to Finder") }
        XCTAssertFalse(FinderInfo.sendsRealEvents, "no Apple Event may be sent from a test")
        // The object specifier: information window ('iwnd') of the file.
        let spec = FinderInfo.informationWindow(of: URL(fileURLWithPath: "/tmp"))
        XCTAssertEqual(spec.descriptorType, DescType(typeObjectSpecifier))
        XCTAssertEqual(spec.forKeyword(AEKeyword(keyAEKeyData))?.typeCodeValue, FinderInfo.fourCharCode("iwnd"))
    }

    /// The file system: Finder is asked for the selected items; when it refuses (Automation denied)
    /// the 7-Zip list comes up instead, and when it shows the windows nothing else does.
    func testPropertiesOutsideAnArchiveAskFinderAndFallBack() {
        let scratch = makeScratch()
        let controller = makeWindow()
        let panel = controller.focusedPanel
        navigate(panel, to: scratch)
        select(panel, ["a.txt", "b.bin"], focus: "b.bin")
        var asked: [URL] = []
        FinderInfo.sender = { urls, done in asked = urls; done(.shown) }
        panel.showProperties()
        XCTAssertEqual(asked.map { $0.lastPathComponent }.sorted(), ["a.txt", "b.bin"])
        XCTAssertNil(NSApp.modalWindow, "Finder showed the windows: no 7-Zip dialog")

        FinderInfo.sender = { urls, done in asked = urls; done(.denied) }
        let appeared = ModalProbe.present({ panel.showProperties() }) { window in
            XCTAssertEqual(window.title, "Properties", "the fallback list")
        }
        XCTAssertTrue(appeared, "no fallback dialog after Finder refused")

        select(panel, [], focus: "b.bin")
        asked = []
        panel.showProperties()
        XCTAssertEqual(panel.lastPropertiesRoute, .nothing, "nothing operated: InvokeSystemCommand returns")
        XCTAssertTrue(asked.isEmpty)
    }

    /// The rows of the list for a file, two files, a folder and nothing inside test.7z, in 7zFM's
    /// structure (listfeel-data/win1/dlg-prop-7z-*.txt): no title rows, "------------------------"
    /// separators, the summary block for several items, the folder's own block, the archive level,
    /// and the two closing separators.
    func testPropertiesRowsFollowPanelMenuCpp() throws {
        let scratch = makeScratch()
        let controller = makeWindow()
        let panel = controller.focusedPanel
        navigate(panel, to: scratch + "/test.7z")
        let snapshot = try XCTUnwrap(panel.snapshot)
        func lines(_ names: [String]) -> PanelPropertyLines {
            let indices = names.map { n in panel.rows.first { $0.name == n }!.engineIndex }
            return panel.queue.sync { PanelProperties.build(folder: panel.folder!, itemIndices: indices, snapshot: snapshot, level: .min) }
        }
        let sep = PanelPropertyLines.separator
        let file = lines(["notes.md"])
        XCTAssertEqual(file.names.first, "Name")
        XCTAssertEqual(file.values.first, "notes.md")
        XCTAssertTrue(file.names.contains("Encrypted"), "VT_BOOL false is '-', not dropped: \(file.names)")
        XCTAssertEqual(file.values[file.names.firstIndex(of: "Encrypted")!], "-")
        XCTAssertFalse(file.names.contains { $0.hasPrefix("----Path") }, "no level title rows")
        XCTAssertFalse(file.names.contains("ArcFileName"))
        XCTAssertEqual(Array(file.names.suffix(2)), [sep, sep], "the NonOpen level's two separators")
        let firstSep = try XCTUnwrap(file.names.firstIndex(of: sep))
        XCTAssertEqual(Array(file.names[(firstSep + 1)...].prefix(5)), ["Size", "Packed Size", "Folders", "Files", "CRC"],
                       "IFolderProperties of the archive folder")
        XCTAssertTrue(file.names.contains("Physical Size") && file.names.contains("Headers Size") && file.names.contains("Solid"))

        let two = lines(["notes.md", "readme.txt"])
        XCTAssertEqual(two.names.first, "")
        XCTAssertEqual(two.values.first, "2 object(s) selected")
        XCTAssertEqual(Array(two.names.prefix(5)), ["", "Files", "Size", "Packed Size", sep])

        let mixed = lines(["notes.md", "sub"])
        XCTAssertEqual(Array(mixed.names.prefix(6)), ["", "Folders", "Files", "Size", "Packed Size", sep])
        XCTAssertEqual(mixed.values[1], "2", "sub and sub/deep")
        XCTAssertEqual(mixed.values[2], "3", "notes.md, big.txt, inner.txt")

        let none = lines([])
        XCTAssertEqual(Array(none.names.prefix(5)), ["Size", "Packed Size", "Folders", "Files", "CRC"])

        navigate(panel, to: scratch + "/test.7z/sub")
        let inSub = panel.queue.sync { PanelProperties.build(folder: panel.folder!, itemIndices: [], snapshot: panel.snapshot!, level: .min) }
        XCTAssertEqual(inSub.names.first, "Name")
        XCTAssertEqual(inSub.values.first, "sub/", "GetFolderProperty(kpidPath) under the name of kpidName")

        // The dialog: autosized columns, 80 / text + 12 as on Windows, 17 pt rows.
        let widths = ListViewMetrics.autosizedWidths(strings: file.names, values: file.values)
        XCTAssertEqual(widths.strings, 84, accuracy: 0.5, "the separator (72 px in Segoe UI, 76 pt in SF Pro 12.2) + 8")
        let appeared = ModalProbe.present({ PropertiesDialog.show(lines: file, parent: controller.window) }) { window in
            guard let table = Self.firstTable(in: window.contentView) else { return XCTFail("no list") }
            XCTAssertEqual(table.tableColumns[0].width, widths.strings, accuracy: 0.5)
            XCTAssertEqual(table.tableColumns[1].width, widths.values, accuracy: 0.5)
            XCTAssertEqual(table.rect(ofRow: 1).minY - table.rect(ofRow: 0).minY, 17)
            XCTAssertFalse(table.usesAlternatingRowBackgroundColors)
            XCTAssertEqual(table.headerView?.frame.height, 24)
            _ = self.attach(window, "listfeel-02-properties")
        }
        XCTAssertTrue(appeared)
    }

    private static func firstTable(in view: NSView?) -> NSTableView? {
        guard let view else { return nil }
        if let table = view as? NSTableView { return table }
        for sub in view.subviews { if let t = firstTable(in: sub) { return t } }
        return nil
    }

    private static func find<T: NSView>(_ type: T.Type, in view: NSView?) -> T? {
        guard let view else { return nil }
        if let match = view as? T { return match }
        for sub in view.subviews { if let found = find(type, in: sub) { return found } }
        return nil
    }

    // MARK: - 8. fresh defaults

    /// kNumDefaultPanels = 1 (FM.cpp:127): with no stored value the window starts with one panel,
    /// as 7zFM does with HKCU\Software\7-Zip deleted (listfeel-data/win1/log.txt "fresh lists=1").
    func testFreshDefaultIsOnePanel() {
        Settings.removeKey(Settings.Key.numPanels)
        XCTAssertEqual(Settings.numPanels, 1)
        let controller = MainWindowController()
        controllers.append(controller)
        XCTAssertEqual(controller.numPanels, 1)
    }

    // MARK: - paired captures

    /// The Mac half of `wincompare-listfeel-<state>-*.png`: the list's top-left 760 x 200 pt at 1x.
    func testPairedCaptures() {
        let scratch = makeScratch()
        let controller = makeWindow()
        let panel = controller.focusedPanel
        Settings.removeKey("FM.Columns.FSFolder")
        navigate(panel, to: scratch)
        controller.window?.makeFirstResponder(panel.tableView)
        panel.listFocusOverride = true
        defer { panel.listFocusOverride = nil }
        select(panel, ["a.txt"], focus: "a.txt")
        capture(panel, "wincompare-listfeel-list-mac.png")
        Settings.removeKey("FM.Columns.7-Zip.7z")
        navigate(panel, to: scratch + "/test.7z")
        select(panel, [], focus: nil)
        capture(panel, "wincompare-listfeel-archive-mac.png")
    }

    private func capture(_ panel: PanelViewController, _ file: String) {
        guard let window = panel.view.window, let content = window.contentView else { return }
        content.layoutSubtreeIfNeeded()
        let list: NSView = panel.tableView.enclosingScrollView ?? panel.tableView
        var rect = list.convert(list.bounds, to: content)
        rect = NSRect(x: rect.minX, y: rect.maxY - 200, width: min(760, rect.width), height: 200)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(rect.width), pixelsHigh: Int(rect.height),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = rect.size
        content.cacheDisplay(in: rect, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = file
        attachment.lifetime = .keepAlways
        add(attachment)
        try? png.write(to: URL(fileURLWithPath: TestPaths.screenshots).appendingPathComponent(file), options: .atomic)
    }
}
