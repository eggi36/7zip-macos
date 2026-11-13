// AppLook.swift -- the main window's metrics. The port draws 7zFM's window -- the same panels,
// columns, menus, keys, toolbar commands and status-bar parts -- with AppKit's own controls and
// metrics: an NSToolbar with SF Symbols, the system list style, font, selection and file icons, a
// rounded address field and a quiet status bar. No command or setting is dropped.
//
// Earlier versions drew the Windows window pixel for pixel ("Classic"); during 1.3 development it
// could be chosen in Options > macOS. It is gone, and a stored `FM.Look` is ignored.

import AppKit

/// The address band and the status bar. Kept out of WinChrome.swift, which the Quick Look
/// extension compiles too.
extension WinChrome {
    // The address bar is a 32 pt strip with a 24 pt rounded field inset by 4 pt top and bottom and
    // 8 pt on the right, the Up button a 24 pt square 8 pt in.

    /// The address band (ReBarWindow32).
    static let bandHeight: CGFloat = 32
    /// The Up button (ToolbarWindow32 1002 on Windows).
    static let upButtonRect = NSRect(x: 8, y: 4, width: 24, height: 24)
    /// Where the address field (ComboBoxEx32 1003) starts.
    static let comboX: CGFloat = 38
    /// The field's inset from the band's top/bottom and right edge.
    static let comboInset = NSSize(width: 8, height: 4)
    /// The status bar, including its top line.
    static let statusHeight: CGFloat = 24
}
