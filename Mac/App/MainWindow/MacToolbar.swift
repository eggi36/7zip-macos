// MacToolbar.swift -- native-look: the main window's toolbar in the Mac look. The same seven
// commands as the Windows strip (FMToolbar.swift, App.cpp g_ArchiveButtons / g_StandardButtons:
// Add, Extract, Test | Copy, Move, Delete, Info), sent down the same responder chain, as an
// NSToolbar in the window's unified title bar with SF Symbols, plus the panel's Back / Forward
// (the macOS addition already in View > Back / Forward) as navigational items next to the title.
//
// The toolbar is customizable (right-click on it > Customize Toolbar...):
// besides the seven buttons it offers a few more 7zFM commands (Up, Refresh, Create Folder, Rename,
// Split, Combine, Flat View, 2 Panels, Folders History, Benchmark, and a Finder-style view
// switcher for Large Icons / Small Icons / List / Details), and AppKit saves the arrangement
// and the icon / label mode for every window (`sz.main.mac`).
//
// 7zFM's View > Toolbars is not in the menu: Customize Toolbar... adds and removes buttons, the
// toolbar's right-click menu switches the labels (Icon and Text / Icon Only), and macOS sizes
// toolbar icons itself. The Toolbars setting still records what a toolbar holds (the groups and
// the labels, `syncMaskFromMacToolbar`), and a fresh one starts with them.
//
// Back, Forward and Up One Level are navigational items: they sit next to the title, and
// Customize Toolbar... can put Up One Level there (01 §1.3: Up is the address bar's button on
// Windows).

import AppKit

extension NSToolbarItem.Identifier {
    static let szBack = NSToolbarItem.Identifier("sz.back")
    static let szForward = NSToolbarItem.Identifier("sz.forward")
    static let szUp = NSToolbarItem.Identifier("sz.up")
    static let szRefresh = NSToolbarItem.Identifier("sz.refresh")
    static let szCreateFolder = NSToolbarItem.Identifier("sz.createFolder")
    static let szRename = NSToolbarItem.Identifier("sz.rename")
    static let szSplit = NSToolbarItem.Identifier("sz.split")
    static let szCombine = NSToolbarItem.Identifier("sz.combine")
    static let szFlatView = NSToolbarItem.Identifier("sz.flatView")
    static let szTwoPanels = NSToolbarItem.Identifier("sz.twoPanels")
    static let szHistory = NSToolbarItem.Identifier("sz.history")
    static let szBenchmark = NSToolbarItem.Identifier("sz.benchmark")
    static let szViewMode = NSToolbarItem.Identifier("sz.viewMode")
}

/// The view switcher (View > Large Icons / Small Icons / List / Details, IDM_VIEW_LARGE_ICONS
/// 700 - IDM_VIEW_DETAILS 703; 01 §3.1), as Finder's toolbar has one: four segments, the focused
/// panel's mode selected. It is NSToolbarItemGroup's own selection group (only the factory
/// initializer gives one that keeps a selection, and it cannot make a subclass), so the window
/// controller syncs the selection in `windowDidUpdate` -- after every event, which covers the
/// menu, Cmd-1 ... Cmd-4 and a focus change between the panels.
enum ViewModeToolbarItem {
    /// Index = 7zFM's _listViewMode: 0 large icons, 1 small icons, 2 list, 3 details.
    /// Details is Finder's list view (rows with columns), so it gets Finder's list symbol.
    static let symbols: [[String]] = [["square.grid.2x2"], ["square.grid.3x3"],
                                      ["tablecells", "list.bullet.rectangle"], ["list.bullet"]]
    static var titles: [String] {
        [Lang.text(700, "Large Icons"), Lang.text(701, "Small Icons"), Lang.text(702, "List"),
         Lang.text(703, "Details")].map { Lang.stripMnemonic($0).components(separatedBy: "\t")[0] }
    }
}

extension MainWindowController: NSToolbarDelegate {

    static let macArchiveGroup: [NSToolbarItem.Identifier] = [.szAdd, .szExtract, .szTest]
    static let macStandardGroup: [NSToolbarItem.Identifier] = [.szCopy, .szMove, .szDelete, .szInfo]
    static let macExtraItems: [NSToolbarItem.Identifier] = [.szUp, .szRefresh, .szCreateFolder, .szRename,
                                                            .szSplit, .szCombine, .szFlatView, .szTwoPanels,
                                                            .szHistory, .szBenchmark, .szViewMode]
    /// One autosaved configuration shared by every main window.
    static let macToolbarIdentifier = "sz.main.mac"

    /// The SF Symbol for each command, with fallbacks for older symbol sets.
    static func macToolbarSymbol(_ id: NSToolbarItem.Identifier) -> NSImage? {
        let names: [String]
        switch id {
        case .szAdd: names = ["plus"]
        case .szExtract: names = ["shippingbox.and.arrow.backward", "arrow.up.bin", "tray.and.arrow.up"]
        case .szTest: names = ["checkmark.seal", "checkmark.circle"]
        case .szCopy: names = ["doc.on.doc"]
        case .szMove: names = ["arrow.right.doc.on.clipboard", "folder"]
        case .szDelete: names = ["trash"]
        case .szInfo: names = ["info.circle"]
        case .szBack: names = ["chevron.left"]
        case .szForward: names = ["chevron.right"]
        case .szUp: names = ["arrow.up"]
        case .szRefresh: names = ["arrow.clockwise"]
        case .szCreateFolder: names = ["folder.badge.plus"]
        case .szRename: names = ["pencil"]
        case .szSplit: names = ["square.split.2x1", "scissors"]
        case .szCombine: names = ["square.on.square", "link"]
        case .szFlatView: names = ["list.bullet.indent", "list.bullet"]
        case .szTwoPanels: names = ["rectangle.split.2x1"]
        case .szHistory: names = ["clock.arrow.circlepath", "clock"]
        case .szBenchmark: names = ["speedometer", "gauge"]
        case .szViewMode: names = ["square.grid.2x2"]
        default: return nil
        }
        for name in names {
            if let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) { return image }
        }
        return nil
    }

    /// A menu title without its trailing "..." / "…" (a toolbar label opens no dialog cue).
    static func noEllipsis(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        while t.hasSuffix(".") || t.hasSuffix("\u{2026}") { t.removeLast() }
        return t
    }

    /// The label and command of a Mac-only or extra item (the seven buttons use `toolbarSpec`).
    static func macExtraSpec(_ id: NSToolbarItem.Identifier) -> (label: String, action: Selector)? {
        switch id {
        case .szBack: return ("Back", #selector(MenuActions.viewGoBack(_:)))
        case .szForward: return ("Forward", #selector(MenuActions.viewGoForward(_:)))
        case .szUp: return (Lang.text(735, "Up One Level"), #selector(MenuActions.viewOpenParentFolder(_:)))
        case .szRefresh: return (Lang.text(737, "Refresh"), #selector(MenuActions.viewRefresh(_:)))
        case .szCreateFolder: return (Lang.text(555, "Create Folder"), #selector(MenuActions.fileCreateFolder(_:)))
        case .szRename: return (Lang.text(545, "Rename"), #selector(MenuActions.fileRename(_:)))
        case .szSplit: return (Self.noEllipsis(Lang.text(549, "Split file...")), #selector(MenuActions.fileSplit(_:)))
        case .szCombine: return (Self.noEllipsis(Lang.text(550, "Combine files...")), #selector(MenuActions.fileCombine(_:)))
        case .szFlatView: return (Lang.text(731, "Flat View"), #selector(MenuActions.viewFlatView(_:)))
        case .szTwoPanels: return (Lang.text(732, "2 Panels"), #selector(MenuActions.viewTwoPanels(_:)))
        case .szHistory: return (Self.noEllipsis(Lang.text(736, "Folders History...")), #selector(MenuActions.viewFoldersHistory(_:)))
        case .szBenchmark: return (Lang.text(901, "Benchmark"), #selector(MenuActions.toolsBenchmark(_:)))
        default: return nil
        }
    }

    /// The items a fresh toolbar starts with: Back, Forward, Up, then the groups of the mask.
    var macToolbarItems: [NSToolbarItem.Identifier] {
        var ids: [NSToolbarItem.Identifier] = [.szBack, .szForward, .szUp, .flexibleSpace]
        let archive = (toolbarsMaskForMac & 8) != 0
        let standard = (toolbarsMaskForMac & 4) != 0
        if archive { ids += Self.macArchiveGroup }
        if archive && standard { ids.append(.space) }
        if standard { ids += Self.macStandardGroup }
        return ids
    }

    /// Puts the window's NSToolbar up once; later changes edit it in place, so a customised
    /// arrangement is never thrown away.
    func installMacToolbar() {
        guard let window, window.toolbar == nil else { return }
        let toolbar = NSToolbar(identifier: Self.macToolbarIdentifier)
        toolbar.delegate = self
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        // Only a toolbar without a saved configuration takes the mask's text setting; a saved one
        // brings its own display mode.
        if UserDefaults.standard.object(forKey: "NSToolbar Configuration \(Self.macToolbarIdentifier)") == nil {
            toolbar.displayMode = (toolbarsMaskForMac & 1) != 0 ? .iconAndLabel : .iconOnly
        }
        window.toolbar = toolbar
    }

    /// The Toolbars mask bits that the Mac toolbar currently shows: archive group, standard group,
    /// labels. The Large Buttons bit (no Mac counterpart) is kept as it is.
    func macToolbarMask(keeping mask: UInt32) -> UInt32 {
        guard let toolbar = window?.toolbar else { return mask }
        let ids = Set(toolbar.items.map(\.itemIdentifier))
        var result = mask & 2
        if Self.macArchiveGroup.contains(where: ids.contains) { result |= 8 }
        if Self.macStandardGroup.contains(where: ids.contains) { result |= 4 }
        if toolbar.displayMode != .iconOnly { result |= 1 }
        return result
    }

    /// The view switcher (`ViewModeToolbarItem`).
    func makeViewModeItem() -> NSToolbarItem {
        let titles = ViewModeToolbarItem.titles
        let images = ViewModeToolbarItem.symbols.enumerated().map { i, names in
            names.lazy.compactMap { NSImage(systemSymbolName: $0, accessibilityDescription: titles[i]) }.first
                ?? NSImage()
        }
        let group = NSToolbarItemGroup(itemIdentifier: .szViewMode, images: images, selectionMode: .selectOne,
                                       labels: titles, target: self, action: #selector(viewModeChosen(_:)))
        let label = Lang.stripMnemonic(Lang.menuTitle(MainMenu.idmView, "&View"))
        group.label = label
        group.paletteLabel = label
        group.toolTip = label
        for (i, sub) in group.subitems.enumerated() { sub.toolTip = titles[i] }
        group.selectedIndex = focusedPanel.listViewMode
        return group
    }

    /// Selects the focused panel's mode in every view switcher of the window's toolbar.
    func syncViewModeItems() {
        guard let items = window?.toolbar?.items else { return }
        Self.selectViewMode(focusedPanel.listViewMode, in: items)
    }

    static func selectViewMode(_ mode: Int, in items: [NSToolbarItem]) {
        for case let group as NSToolbarItemGroup in items where group.itemIdentifier == .szViewMode
            && group.selectedIndex != mode && (0..<group.subitems.count).contains(mode) {
            group.selectedIndex = mode
        }
    }

    /// A segment of the view switcher: the focused panel takes that mode (SetListViewMode).
    @objc func viewModeChosen(_ sender: Any?) {
        guard let mode = (sender as? NSToolbarItemGroup)?.selectedIndex else { return }
        guard (0...3).contains(mode), mode != focusedPanel.listViewMode else { return }
        focusedPanel.setListViewMode(mode)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        macToolbarItems
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.szBack, .szForward] + Self.macArchiveGroup + Self.macStandardGroup + Self.macExtraItems
            + [.flexibleSpace, .space]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if itemIdentifier == .szViewMode { return makeViewModeItem() }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        let label: String
        let action: Selector
        if let extra = Self.macExtraSpec(itemIdentifier) {
            (label, action) = extra
            item.isNavigational = [.szBack, .szForward, .szUp].contains(itemIdentifier)
        } else if let spec = Self.toolbarSpec(itemIdentifier) {
            (label, action) = (spec.label, spec.action)
        } else {
            return nil
        }
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.image = Self.macToolbarSymbol(itemIdentifier)
        item.isBordered = true
        item.target = nil                       // the responder chain, as the menu items do
        item.action = action
        item.autovalidates = true
        return item
    }
}
