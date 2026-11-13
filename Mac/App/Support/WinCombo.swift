// WinCombo.swift -- the dialogs' combo box (CBS_DROPDOWN, AppKit's own) and `CellCopy`, which keeps
// a cell's stored references alive across AppKit's bitwise cell copies.

import AppKit

/// The Swift half of an `NSCell` copy (reports/okcancel.md §4).
///
/// `-[NSCell copyWithZone:]` duplicates the instance bitwise (NSCopyObject), Swift stored
/// properties included, but does not retain what they point to. AppKit copies cells all the time
/// (a header while it draws or tracks, the accessibility snapshot XCUITest and VoiceOver read, a
/// pop-up's menu), so every copy that is freed released an object its original still used: a
/// header's `titleFont` (the shared list font -- the next `PanelMetrics.listFont` crashed), the
/// address combo's icon, a drop-down's hover owner. A cell subclass with a stored reference calls
/// `adopt` for it in `copy(with:)`, which gives the copy the reference it already holds.
enum CellCopy {
    static func adopt(_ object: AnyObject?) {
        if let object { _ = Unmanaged.passUnretained(object).retain() }
    }
}

/// CBS_DROPDOWN: the edit-with-list of every dialog combo that has an edit (Copy / Move, Extract,
/// Add to Archive's name and volume, Split, Link, Create Folder / File). AppKit's own combo box.
final class WinComboBox: NSComboBox {}
