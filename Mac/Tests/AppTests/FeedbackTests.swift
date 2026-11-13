// FeedbackTests.swift -- the user's review of 1.3.0 (2026-11-13): the About box's build line, no
// update check left in the app.

import AppKit
import XCTest
@testable import SevenZipAppHost

final class FeedbackTests: AppHostTestCase {

    // MARK: - About: a build line unique to every compile

    func testBuildLine() {
        XCTAssertEqual(PortVersion.buildLine(build: "402", stamp: "2026-11-13 21:50:07 1faab4b0c2"),
                       "Build 402 (2026-11-13 21:50:07 1faab4b0c2)")
        XCTAssertEqual(PortVersion.buildLine(build: "402", stamp: ""), "Build 402", "a copy without the stamp phase")
    }

    // MARK: - no update check

    func testNoUpdateCheckInTheMenus() {
        func all(_ menu: NSMenu) -> [NSMenuItem] { menu.items + menu.items.compactMap(\.submenu).flatMap(all) }
        let titles = all(MainMenu.build()).map(\.title)
        XCTAssertFalse(titles.contains { $0.localizedCaseInsensitiveContains("update") }, "\(titles)")
        XCTAssertNil(NSClassFromString("SevenZipAppHost.UpdateCheck"))
    }
}
