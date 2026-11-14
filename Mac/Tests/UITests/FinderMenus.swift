// FinderMenus.swift -- reading Finder's open menus through accessibility, shared by
// `FinderContextMenuTests` (choosing 7-Zip commands) and `ShowcaseUITests` (the README image).

import XCTest

enum FinderMenus {

    /// The selectable rows of a menu, top to bottom: visible, titled, enabled items, one per row
    /// (an alternate such as "Always Open With" shares its row with "Open With"). These are the rows
    /// the arrow keys step through.
    static func rows(of menu: XCUIElementSnapshot) -> [XCUIElementSnapshot] {
        var seen = Set<Int>()
        return menu.children
            .filter { $0.elementType == .menuItem && $0.frame.width > 0 && !$0.title.isEmpty }
            .sorted { $0.frame.minY < $1.frame.minY }
            .filter { seen.insert(Int($0.frame.minY)).inserted && $0.isEnabled }
    }

    /// Finder's menus that are on screen right now (context menu and open submenus).
    static func visible(in finder: XCUIApplication) -> [XCUIElementSnapshot] {
        finder.menus.allElementsBoundByIndex
            .compactMap { try? $0.snapshot() }
            .filter { $0.frame.width > 0 }
    }
}
