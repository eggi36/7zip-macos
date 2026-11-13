// FMToolbar.swift -- one toolbar command (App.cpp CreateToolbar / AddButton, 01 §1.3): its label
// and the selector it sends down the responder chain. The window's NSToolbar (MacToolbar.swift) is
// built from these, with SF Symbols for the buttons.

import Cocoa

/// One toolbar button: its label and the selector it sends down the responder chain.
struct FMToolbarItemSpec {
    let identifier: String
    let label: String
    let action: Selector
}
