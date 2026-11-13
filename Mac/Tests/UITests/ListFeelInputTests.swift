// ListFeelInputTests.swift -- the list's mouse behaviour with real input (ai/reports/
// listfeel.md §6, §8): the rubber band as 7zFM 26.03 draws it with "Full row select" off, and the
// address bar's drop-down navigating on a pick. The geometry is in the app-hosted ListFeelTests.
// Input shard: it clicks and drags.

import AppKit
import XCTest

final class ListFeelInputTests: SevenZipUITestCase {

    override var screenshotPrefix: String { "listfeel" }

    private func makeScratch() throws -> String {
        let fm = FileManager.default
        let base = (TestPaths.artifacts as NSString).appendingPathComponent("listfeel-\(UUID().uuidString.prefix(8))")
        try fm.createDirectory(atPath: base + "/sub", withIntermediateDirectories: true)
        for (name, size) in [("a.txt", 1234), ("b.bin", 100_000), ("c.txt", 20), ("d.txt", 300), ("notes.md", 20)] {
            try Data(repeating: 0x78, count: size).write(to: URL(fileURLWithPath: base + "/" + name))
        }
        addTeardownBlock { [weak sevenZip] in
            if let app = sevenZip, app.isRunning, app.testSupportIsImplemented {
                var options = SevenZipApp.ResetOptions()
                options.panels = 1
                options.path0 = TestPaths.fixtures
                app.reset(options)
            }
            try? fm.removeItem(atPath: base)
        }
        return base
    }

    /// The status bar's first part without its bidi isolation marks ("4 / 6 object(s) selected").
    private func selected(_ panel: SevenZipPanel) -> String {
        panel.status.filter { $0.isASCII }
    }

    private func cells(of row: XCUIElement) -> [XCUIElement] {
        row.cells.allElementsBoundByIndex.sorted { $0.frame.minX < $1.frame.minX }
    }

    /// As in Finder's list: the whole row is the item, so a click on any of its cells selects it,
    /// and the rubber band starts on the empty list below the rows and selects every row it
    /// crosses, whichever column it crosses them in.
    func testRubberBandFromTheEmptyList() throws {
        let scratch = try makeScratch()
        launch(seed: .values([SettingsDomain.Key.panelPath0: scratch]))
        let panel = sevenZip.panel(0)
        XCTAssertTrue(panel.waitForRow(named: "notes.md"))
        let b = cells(of: panel.row(named: "b.bin"))
        XCTAssertGreaterThan(b.count, 2)
        let mid = CGVector(dx: 0.5, dy: 0.5)

        // From the empty list under the rows up into b.bin's Size cell: b.bin, c.txt, d.txt and
        // notes.md (the folder "sub" and a.txt sit above it).
        let empty = panel.table.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.95))
        empty.click(forDuration: 0.2, thenDragTo: b[1].coordinate(withNormalizedOffset: mid))
        XCTAssertTrue(waitFor("four selected") { selected(panel).hasPrefix("4 / ") }, "status \(panel.status)")
        screenshot("input-rubber-band")

        // A click on the empty list clears the selection; a click on a Size cell selects its row.
        empty.click()
        XCTAssertTrue(waitFor("cleared") { selected(panel).hasPrefix("0 / ") }, "status \(panel.status)")
        b[1].click()
        XCTAssertTrue(waitFor("b.bin selected") { selected(panel).hasPrefix("1 / ") }, "status \(panel.status)")
    }

    /// CBN_SELENDOK: picking an entry in the address bar's drop-down with the mouse goes there at
    /// once, with no Return, and the entries are the path's components by name.
    func testAddressDropdownPickNavigates() throws {
        let scratch = try makeScratch()
        launch(seed: .values([SettingsDomain.Key.panelPath0: scratch + "/sub"]))
        let panel = sevenZip.panel(0)
        XCTAssertTrue(panel.waitForPath(scratch + "/sub"))
        let bar = panel.addressBar
        XCTAssertTrue(bar.waitForExistence(timeout: 10), "no address bar")
        // The arrow, 9 pt in from the combo's right edge, opens the Windows-style list
        // (AddressPopup, feel3): one row per entry, named after the entry, no indent spaces.
        bar.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: -9, dy: 0)).click()
        let name = (scratch as NSString).lastPathComponent
        let entry = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'address-dropdown-' AND label == %@", name))
            .firstMatch
        if !entry.waitForExistence(timeout: 10) { _ = sevenZip.dumpTree("listfeel-dropdown") }
        XCTAssertTrue(entry.exists, "no drop-down entry for \(name)")
        screenshot("input-address-dropdown")
        entry.click()
        XCTAssertTrue(panel.waitForPath(scratch), "the pick did not navigate: \(panel.path)")
        XCTAssertTrue(panel.waitForRow(named: "a.txt"))
    }
}
