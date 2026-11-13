// IconAssetTests.swift -- the icon files and the Info.plist agree (cleanup): every
// CFBundleTypeIconFile has its .icns in Mac/Resources/Icons, every .icns there is used, and the
// Windows-era assets (the .ico frames, the toolbar bitmaps, the old logo) stay gone; the app icon
// is an Icon Composer icon with a Dark-mode fill.

import XCTest

final class IconAssetTests: XCTestCase {

    private var macDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func iconFileNames() throws -> Set<String> {
        let data = try Data(contentsOf: macDir.appendingPathComponent("App/Info.plist"))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let types = try XCTUnwrap(plist["CFBundleDocumentTypes"] as? [[String: Any]])
        return Set(types.compactMap { $0["CFBundleTypeIconFile"] as? String })
    }

    func testEveryDocumentTypeIconExists() throws {
        let names = try iconFileNames()
        XCTAssertFalse(names.isEmpty)
        let icons = macDir.appendingPathComponent("Resources/Icons")
        for name in names.sorted() {
            XCTAssertTrue(FileManager.default.fileExists(atPath: icons.appendingPathComponent(name + ".icns").path),
                          "Info.plist names \(name), but Resources/Icons has no \(name).icns")
        }
    }

    func testEveryBundledIconIsUsedAndNoWindowsAssetIsLeft() throws {
        let names = try iconFileNames()
        let icons = macDir.appendingPathComponent("Resources/Icons")
        for file in try FileManager.default.contentsOfDirectory(atPath: icons.path) where !file.hasPrefix(".") {
            XCTAssertTrue(file.hasSuffix(".icns"), "\(file): only .icns files belong in Resources/Icons")
            XCTAssertTrue(names.contains(String(file.dropLast(5))), "\(file) is bundled but no document type uses it")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: macDir.appendingPathComponent("Resources/Assets.xcassets").path),
                       "no asset catalog: the app icon is AppIcon.icon")
    }

    func testTheAppIconHasADarkVariant() throws {
        let icon = macDir.appendingPathComponent("Resources/AppIcon.icon")
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: icon.appendingPathComponent("icon.json")))
                                 as? [String: Any])
        let specializations = try XCTUnwrap(json["fill-specializations"] as? [[String: Any]])
        XCTAssertTrue(specializations.contains { $0["appearance"] as? String == "dark" }, "a fill for Dark mode")
        let groups = try XCTUnwrap(json["groups"] as? [[String: Any]])
        let images = groups.flatMap { ($0["layers"] as? [[String: Any]]) ?? [] }.compactMap { $0["image-name"] as? String }
        XCTAssertFalse(images.isEmpty)
        for image in images {
            XCTAssertTrue(FileManager.default.fileExists(atPath: icon.appendingPathComponent("Assets/\(image)").path), image)
        }
    }
}
