// PanelAddressBar.swift -- the panel's address band (Panel.cpp:440-580, CreateToolbarEx +
// ComboBoxEx32 in a ReBar; 01 §1.2): the editable address field (ComboBoxEx32 1003) across the
// band, with the folder's icon inside and a chevron that opens the dropped list (feel3). 7zFM's Up
// button (ToolbarWindow32 1002) is the toolbar's Up One Level next to Back / Forward here.

import AppKit

/// The address combo's look: a ComboBoxEx32 border, the folder icon inside, the text 24 px in, a
/// flat chevron. The behaviour (editing, the drop-down list) stays NSComboBox's.
final class AddressComboCell: NSComboBoxCell {
    var icon: NSImage?

    /// NSCell copied `icon` without retaining it (`CellCopy`, reports/okcancel.md).
    override func copy(with zone: NSZone? = nil) -> Any {
        let copy = super.copy(with: zone)
        if let cell = copy as? AddressComboCell { CellCopy.adopt(cell.icon) }
        return copy
    }

    /// Where the text goes: 24 px from the left (the Edit 1003 at x 57 in a combo at x 33), the
    /// arrow's 18 px at the right kept clear.
    static let textInsetLeft: CGFloat = 28
    static let arrowWidth: CGFloat = 24

    private func textRect(_ frame: NSRect) -> NSRect {
        var r = frame
        r.origin.x += Self.textInsetLeft - 2          // the field editor's own 2 pt line padding
        r.size.width = max(0, frame.width - Self.textInsetLeft - Self.arrowWidth)
        let h: CGFloat = 16
        r.origin.y = frame.minY + floor((frame.height - h) / 2)
        r.size.height = h
        return r
    }

    /// NSComboBoxCell places the field editor inside drawingRect(forBounds:) with its own bezel
    /// inset on top, so the edited path sat 4 px right of the drawn one -- the user's finding 7
    /// ("clicking the address bar shifts the path to the right"). The editor's rect is moved back
    /// by that inset (measured, Feel3Tests.testAddressTextDoesNotMoveWhenEdited).
    static let editorShift = NSSize(width: -4, height: 0)

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        textRect(rect).offsetBy(dx: Self.editorShift.width, dy: Self.editorShift.height)
    }
    override func titleRect(forBounds rect: NSRect) -> NSRect { textRect(rect) }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        drawMac(withFrame: cellFrame, in: controlView)
    }

    /// native-look: a rounded field in the system's colours, the folder icon 6 pt in, an SF Symbol
    /// chevron for the history drop-down.
    private func drawMac(withFrame cellFrame: NSRect, in controlView: NSView) {
        let field = NSBezierPath(roundedRect: cellFrame.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        NSColor.textBackgroundColor.setFill()
        field.fill()
        NSColor.separatorColor.setStroke()
        field.lineWidth = 1
        field.stroke()
        if let icon {
            let top = floor((cellFrame.height - 16) / 2)
            let y = controlView.isFlipped ? cellFrame.minY + top : cellFrame.maxY - top - 16
            icon.draw(in: NSRect(x: cellFrame.minX + 6, y: y, width: 16, height: 16), from: .zero,
                      operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        if let symbol = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            let arrow = NSRect(x: cellFrame.maxX - Self.arrowWidth, y: cellFrame.minY,
                               width: Self.arrowWidth - 4, height: cellFrame.height)
            MacSymbol.draw(symbol, tint: .secondaryLabelColor, centeredIn: arrow)
        }
        drawInterior(withFrame: cellFrame, in: controlView)
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        // while editing, the field editor draws the text
        guard (controlView as? NSControl)?.currentEditor() == nil else { return }
        super.drawInterior(withFrame: textRect(cellFrame), in: controlView)
    }

    // edit / select: NSTextFieldCell takes the field editor's frame from drawingRect(forBounds:)
    // itself. Passing textRect here as well (as before feel3) applied the inset twice, so the
    // path jumped right when the combo was clicked (the user's finding 7).
}

/// The combo itself: draws through `AddressComboCell` and has the band's 24 px height. Its arrow
/// opens the Windows-style dropped list (`AddressPopup`, feel3) instead of NSComboBox's own.
final class AddressComboBox: NSComboBox {
    override class var cellClass: AnyClass? {
        get { AddressComboCell.self }
        set { _ = newValue }
    }

    var addressCell: AddressComboCell? { cell as? AddressComboCell }

    /// CBN_DROPDOWN: the panel builds the entries and opens the list.
    var onDropDown: (() -> Void)?

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: AppLook.bandHeight)
    }

    /// The arrow's 18 px at the right edge.
    func isOnArrow(_ point: NSPoint) -> Bool {
        bounds.contains(point) && point.x >= bounds.maxX - AddressComboCell.arrowWidth
    }

    override func mouseDown(with event: NSEvent) {
        if isOnArrow(convert(event.locationInWindow, from: nil)) {
            onDropDown?()
            return
        }
        super.mouseDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        cell?.draw(withFrame: bounds, in: self)
    }
}

/// native-look: draws an SF Symbol in a colour, centred in a rect (flipped or not).
enum MacSymbol {
    static func draw(_ symbol: NSImage, tint: NSColor, centeredIn rect: NSRect) {
        let size = symbol.size
        let tinted = NSImage(size: size, flipped: false) { r in
            symbol.draw(in: r)
            tint.set()
            r.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: NSRect(x: rect.minX + floor((rect.width - size.width) / 2),
                               y: rect.minY + floor((rect.height - size.height) / 2),
                               width: size.width, height: size.height),
                    from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}
