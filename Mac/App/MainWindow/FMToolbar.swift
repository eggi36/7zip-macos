// FMToolbar.swift -- one toolbar command (App.cpp CreateToolbar / AddButton, 01 §1.3): its label,
// image and the selector it sends down the responder chain. The window's NSToolbar
// (MacToolbar.swift) is built from these.

import Cocoa

/// One toolbar button: its bitmap, label and the selector it sends down the responder chain.
struct FMToolbarItemSpec {
    let identifier: String
    let label: String
    let image: NSImage?
    let action: Selector
}
