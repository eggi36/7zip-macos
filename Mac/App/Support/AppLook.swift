// AppLook.swift -- the main window's look, a macOS addition (native-look): 7zFM has one look, the
// Windows one, which the port reproduces pixel for pixel ("Classic"). "Mac" draws the same window
// -- the same panels, columns, menus, keys, toolbar commands and status-bar parts -- with AppKit's
// own controls and metrics: an NSToolbar with SF Symbols, the system list style, font, selection
// and file icons, a rounded address field and a quiet status bar. No command or setting is dropped.
//
// Options > macOS > "Appearance:" chooses it. Stored as `FM.Look` = "mac" | "classic". Absent (a
// fresh install, after Reset All Settings) = Mac, except under a test (the XCUITest harness or an
// XCTest bundle in the process), whose parity tests describe the Windows window and therefore start
// in Classic unless a test asks for Mac.
//
// The look is read when a window is built (`AppLook.current` is fixed per window): changing it
// rebuilds every main window in place (`MainWindows.rebuildForLookChange`), keeping each window's
// frame, panels and folders. The dialogs keep their Windows layout in both looks for now.

import AppKit

enum AppLook: String, CaseIterable {
    case mac
    case classic

    /// The look of the windows being built now.
    static var current: AppLook { Settings.look }
    static var isMac: Bool { current == .mac }

    /// An XCTest bundle is loaded in this process (the app-hosted unit tests).
    static let isUnderXCTest = NSClassFromString("XCTestCase") != nil

    // MARK: - the drop-down's texts (macOS addition: lang IDs next to the theme's 9900-9903)

    static let labelLangID: UInt32 = 9904
    var langID: UInt32 {
        switch self {
        case .mac: return 9905
        case .classic: return 9906
        }
    }

    var fallbackTitle: String {
        switch self {
        case .mac: return "Mac"
        case .classic: return "Classic (Windows)"
        }
    }

    var title: String { Lang.text(langID, fallbackTitle) }

    static var labelText: String { Lang.text(labelLangID, "Appearance:") }

    // MARK: - applying

    private static var observer: NSObjectProtocol?
    private static var applied: AppLook?

    /// Called at launch, before the first window: remembers the look the windows are built with,
    /// and rebuilds them when a later write (Options > Apply) changes it.
    static func observeChanges() {
        applied = current
        // In an app-hosted test the tests set the look per window and rebuild on purpose.
        guard observer == nil, !isUnderXCTest else { return }
        observer = NotificationCenter.default.addObserver(
            forName: Settings.Group.view.notificationName, object: nil, queue: .main) { note in
            let key = note.userInfo?[Settings.keyUserInfoKey] as? String
            guard key == nil || key == Settings.Key.look else { return }
            MainActor.assumeIsolated {
                let now = current
                guard now != applied else { return }
                applied = now
                MainWindows.rebuildForLookChange()
                NSApp.mainMenu = MainMenu.build()       // native-look: the menus follow the look
            }
        }
    }
}

extension Settings.Key {
    /// macOS only: the main window's look (`AppLook`).
    static let look = "FM.Look"
}

extension Settings {
    /// The look of a fresh install: Mac; Classic under the test harness (see the header).
    static var defaultLook: AppLook { TestSupport.isEnabled || AppLook.isUnderXCTest ? .classic : .mac }

    /// `FM.Look` (macOS only): Mac or Classic. Every choice is stored.
    static var look: AppLook {
        get { string(Key.look).flatMap(AppLook.init(rawValue:)) ?? defaultLook }
        set { setString(newValue.rawValue, Key.look) }
    }
}

/// The address band and the status bar, per look (native-look). Kept out of WinChrome.swift, which the
/// Quick Look extension compiles without AppLook.
extension WinChrome {
    // native-look: the Mac look's address bar is a 32 pt strip with a 24 pt rounded field inset by
    // 4 pt top and bottom and 8 pt on the right, the Up button a 24 pt square 8 pt in.

    /// The address band (ReBarWindow32): 24 px high.
    static var bandHeight: CGFloat { AppLook.isMac ? 32 : 24 }
    /// The Up button's toolbar (ToolbarWindow32 1002): @2,1 23 x 22 in the band.
    static var upButtonRect: NSRect {
        AppLook.isMac ? NSRect(x: 8, y: 4, width: 24, height: 24) : NSRect(x: 2, y: 1, width: 23, height: 22)
    }
    /// ComboBoxEx32 1003 starts at x 33 and runs to the band's right edge.
    static var comboX: CGFloat { AppLook.isMac ? 38 : 33 }
    /// The field's inset from the band's top/bottom and right edge (0 on Windows).
    static var comboInset: NSSize { AppLook.isMac ? NSSize(width: 8, height: 4) : .zero }

    /// The status bar: 23 px including its top line (Windows); 24 pt in the Mac look.
    static var statusHeight: CGFloat { AppLook.isMac ? 24 : 23 }
}
