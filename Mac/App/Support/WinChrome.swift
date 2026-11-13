// WinChrome.swift -- the colours 7zFM 26.03's window chrome is drawn with on Windows 11 at 96 dpi,
// read from raw pixels of fresh-default captures (ai/reports/recheck.md §2,
// recheck-data/win/fresh-screen.png, two-screen.png) and from GetSysColor (syscolors.txt).
//
// 7zFM has no dark theme; in the dark appearance every colour falls back to the AppKit colour that
// plays the same role, so the dark look stays the one the port already had.

import AppKit

enum WinChrome {

    static func dynamic(_ light: NSColor, _ dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    static func gray(_ v: CGFloat) -> NSColor { rgb(v, v, v) }

    static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
        NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
    }

    /// COLOR_BTNFACE (240,240,240): the main window's client background (around the toolbar, the
    /// splitter's 4 px, the status bar) and every dialog's background. AppKit's windowBackgroundColor
    /// is white on macOS 26.
    static let face = dynamic(gray(240), .windowBackgroundColor)

    /// COLOR_WINDOW: the list, the address band and the combo's field.
    static let window = dynamic(gray(255), .textBackgroundColor)

    /// COLOR_WINDOWTEXT / COLOR_BTNTEXT (0,0,0): list, toolbar and status-bar text. AppKit's
    /// labelColor is 85 % black.
    static let text = dynamic(gray(0), .labelColor)

    /// msctls_statusbar32: a 1 px (215,215,215) line on top and the part dividers.
    static let statusLine = dynamic(gray(215), .separatorColor)

    // MARK: geometry (px = pt)

    // The address band's and the status bar's geometry (bandHeight, upButtonRect, comboX,
    // comboInset, statusHeight) lives in AppLook.swift (app only).
    // The status bar: 23 px including its top line; dividers 1 px at a part's right edge - 1,
    // rows 2..21; text ink 2 px into a part.
}
