// MacToolbar.swift -- native-look: the main window's toolbar in the Mac look. The same seven
// commands as the Windows strip (FMToolbar.swift, App.cpp g_ArchiveButtons / g_StandardButtons:
// Add, Extract, Test | Copy, Move, Delete, Info), sent down the same responder chain, as an
// NSToolbar in the window's unified title bar with SF Symbols, plus the panel's Back / Forward
// (the macOS addition already in View > Back / Forward) as navigational items next to the title.
//
// The toolbar is customizable (right-click on it > Customize Toolbar...):
// besides the seven buttons it offers a few more 7zFM commands (Up, Refresh, Create Folder, Rename,
// Split, Combine, Flat View, 2 Panels, Folders History, Benchmark), and AppKit saves the arrangement
// and the icon / label mode for every window (`sz.main.mac`).
//
// View > Toolbars still works on it: "Archive Toolbar" and "Standard Toolbar" add or remove their
// group, "Show Buttons Text" switches between icon and label and icon only, and their check marks
// show what the toolbar holds (`syncMaskFromMacToolbar`). "Large Buttons" has no Mac counterpart
// (macOS sizes toolbar icons itself) and has no effect.

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
}

extension MainWindowController: NSToolbarDelegate {

    static let macArchiveGroup: [NSToolbarItem.Identifier] = [.szAdd, .szExtract, .szTest]
    static let macStandardGroup: [NSToolbarItem.Identifier] = [.szCopy, .szMove, .szDelete, .szInfo]
    static let macExtraItems: [NSToolbarItem.Identifier] = [.szUp, .szRefresh, .szCreateFolder, .szRename,
                                                            .szSplit, .szCombine, .szFlatView, .szTwoPanels,
                                                            .szHistory, .szBenchmark]
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

    /// The items a fresh toolbar starts with: the View > Toolbars groups of the mask.
    var macToolbarItems: [NSToolbarItem.Identifier] {
        var ids: [NSToolbarItem.Identifier] = [.szBack, .szForward, .flexibleSpace]
        let archive = (toolbarsMaskForMac & 8) != 0
        let standard = (toolbarsMaskForMac & 4) != 0
        if archive { ids += Self.macArchiveGroup }
        if archive && standard { ids.append(.space) }
        if standard { ids += Self.macStandardGroup }
        return ids
    }

    /// Puts the window's NSToolbar up once; later View > Toolbars changes edit it in place, so a
    /// customised arrangement is never thrown away.
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

    /// The View > Toolbars bits that the Mac toolbar currently shows: archive group, standard group,
    /// labels. The Large Buttons bit is kept as it is.
    func macToolbarMask(keeping mask: UInt32) -> UInt32 {
        guard let toolbar = window?.toolbar else { return mask }
        let ids = Set(toolbar.items.map(\.itemIdentifier))
        var result = mask & 2
        if Self.macArchiveGroup.contains(where: ids.contains) { result |= 8 }
        if Self.macStandardGroup.contains(where: ids.contains) { result |= 4 }
        if toolbar.displayMode != .iconOnly { result |= 1 }
        return result
    }

    /// View > Archive Toolbar / Standard Toolbar in the Mac look: remove the group when any of it
    /// is there, else add it at the end.
    func toggleMacToolbarGroup(_ group: [NSToolbarItem.Identifier]) {
        guard let toolbar = window?.toolbar else { return }
        let present = toolbar.items.enumerated().filter { group.contains($0.element.itemIdentifier) }
        if !present.isEmpty {
            for (index, _) in present.reversed() { toolbar.removeItem(at: index) }
            return
        }
        for id in group { toolbar.insertItem(withItemIdentifier: id, at: toolbar.items.count) }
    }

    /// View > Show Buttons Text in the Mac look.
    func toggleMacToolbarText() {
        guard let toolbar = window?.toolbar else { return }
        toolbar.displayMode = toolbar.displayMode == .iconOnly ? .iconAndLabel : .iconOnly
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
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        let label: String
        let action: Selector
        if let extra = Self.macExtraSpec(itemIdentifier) {
            (label, action) = extra
            item.isNavigational = itemIdentifier == .szBack || itemIdentifier == .szForward
        } else if let spec = Self.toolbarSpec(itemIdentifier, large: false) {
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
