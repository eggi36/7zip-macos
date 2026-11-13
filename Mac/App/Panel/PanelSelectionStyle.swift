// PanelSelectionStyle.swift -- the few colours the panel's list draws itself. Selection, focus
// and grid lines are AppKit's own (the system accent colour, NSTableView's grid); what is left is
// 7zFM's own markup:
//
//   * AlternativeSelection rows (01 §3.6): OnCustomDraw fills them RGB(255,192,192)
//     (PanelListNotify.cpp:721); in dark mode a dark red, so the text stays readable;
//   * kpidIsDeleted items in red (OnCustomDraw), everything else in the normal label colour.

import Cocoa

enum PanelSelectionStyle {

    /// AlternativeSelection rows (OnCustomDraw, RGB(255,192,192), PanelListNotify.cpp:721).
    static let mySelected = dynamic(light: NSColor(srgbRed: 1, green: 192 / 255, blue: 192 / 255, alpha: 1),
                                    dark: NSColor(srgbRed: 120 / 255, green: 48 / 255, blue: 48 / 255, alpha: 1))
    /// Text of a row: kpidIsDeleted items in red, everything else in the label colour.
    static func normalText(isDeleted: Bool) -> NSColor { isDeleted ? .systemRed : .labelColor }
    /// The name label's padding around its text inside the fill (the LVIR_LABEL rect).
    static let labelPadding: CGFloat = 2

    static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }
}

/// A Details cell. AppKit sets `backgroundStyle = .emphasized` on every cell of a selected row,
/// which turns `labelColor` text white whether or not anything blue is drawn behind it; with
/// "Full row select" off only the name has a fill, so Size, Modified and the rest were white on
/// white (the selcolors bug). The cell therefore stays `.normal` and takes its colours from the
/// panel's own rule, `PanelViewController.cellIsHighlighted(row:isName:)`.
final class PanelCellView: NSTableCellView {

    var isDeleted = false
    var isNameCell = false
    /// Name cells: makes the text field span the column while it is edited in place.
    var editingConstraint: NSLayoutConstraint?
    /// The unblended icon; `imageView.image` is this or its ILD_BLEND50 form.
    var baseImage: NSImage?
    private(set) var isHighlighted = false

    /// AppKit draws the selection and hands the cell its emphasized background style, which turns
    /// the label white by itself.
    func applyColors(highlighted: Bool) {
        isHighlighted = highlighted
        textField?.textColor = isDeleted ? .systemRed : .labelColor
        if isNameCell, let baseImage { imageView?.image = baseImage }
    }
}

// MARK: - The panel's side of the rule

extension PanelViewController {

    /// GetFocus() == the list: the window is key and its first responder is this panel's list
    /// (the Details table or the icon view). Only then is the selection drawn.
    var listHasKeyboardFocus: Bool {
        if let forced = listFocusOverride { return forced }
        guard isViewLoaded, let window = view.window, window.isKeyWindow else { return false }
        let responder = window.firstResponder
        return responder === tableView || (iconView != nil && responder === iconView.collectionView)
    }

    /// A Details cell is drawn white on the highlight: its row is selected, the list has the focus,
    /// and the fill covers it (the name always, the other columns with FullRow).
    func cellIsHighlighted(row: Int, isName: Bool) -> Bool {
        guard listHasKeyboardFocus, tableView.isRowSelected(row) else { return false }
        return isName || Settings.fullRow
    }

    /// Re-colour and redraw every visible row and icon after a selection, focus or setting change.
    func refreshSelectionAppearance() {
        guard isViewLoaded else { return }
        tableView.enumerateAvailableRowViews { view, _ in
            (view as? PanelRowView)?.updateCellColors()
            view.needsDisplay = true
        }
        iconView?.refreshItemAppearance()
    }
}
