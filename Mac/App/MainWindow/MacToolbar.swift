// MacToolbar.swift -- native-look: the main window's toolbar in the Mac look. The same seven
// commands as the Windows strip (FMToolbar.swift, App.cpp g_ArchiveButtons / g_StandardButtons:
// Add, Extract, Test | Copy, Move, Delete, Info), sent down the same responder chain, as an
// NSToolbar in the window's unified title bar with SF Symbols, plus the panel's Back / Forward
// (the macOS addition already in View > Back / Forward) as navigational items next to the title.
//
// View > Toolbars still decides what is shown: "Archive Toolbar" and "Standard Toolbar" add their
// groups, "Show Buttons Text" switches between icon and label and icon only. "Large Buttons" has no
// Mac counterpart (macOS sizes toolbar icons itself) and only affects the Classic look.

import AppKit

extension NSToolbarItem.Identifier {
    static let szBack = NSToolbarItem.Identifier("sz.back")
    static let szForward = NSToolbarItem.Identifier("sz.forward")
}

extension MainWindowController: NSToolbarDelegate {

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
        default: return nil
        }
        for name in names {
            if let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) { return image }
        }
        return nil
    }

    /// The items for the current View > Toolbars mask.
    var macToolbarItems: [NSToolbarItem.Identifier] {
        var ids: [NSToolbarItem.Identifier] = [.szBack, .szForward, .flexibleSpace]
        let archive = (toolbarsMaskForMac & 8) != 0
        let standard = (toolbarsMaskForMac & 4) != 0
        if archive { ids += [.szAdd, .szExtract, .szTest] }
        if archive && standard { ids.append(.space) }
        if standard { ids += [.szCopy, .szMove, .szDelete, .szInfo] }
        return ids
    }

    /// (Re)builds the window's NSToolbar from the mask. A new toolbar each time: its item set and
    /// display mode follow View > Toolbars, and nothing is customised or autosaved.
    func installMacToolbar() {
        guard let window else { return }
        let toolbar = NSToolbar(identifier: "sz.main.\(toolbarsMaskForMac)")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.displayMode = (toolbarsMaskForMac & 1) != 0 ? .iconAndLabel : .iconOnly
        window.toolbar = toolbar
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        macToolbarItems
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.szBack, .szForward, .szAdd, .szExtract, .szTest, .szCopy, .szMove, .szDelete, .szInfo,
         .flexibleSpace, .space]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        let label: String
        let action: Selector
        switch itemIdentifier {
        case .szBack:
            (label, action) = ("Back", #selector(MenuActions.viewGoBack(_:)))
            item.isNavigational = true
        case .szForward:
            (label, action) = ("Forward", #selector(MenuActions.viewGoForward(_:)))
            item.isNavigational = true
        default:
            guard let spec = Self.toolbarSpec(itemIdentifier, large: false) else { return nil }
            (label, action) = (spec.label, spec.action)
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
