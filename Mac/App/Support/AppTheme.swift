// AppTheme.swift -- the app-wide appearance (theme), a macOS addition: 7zFM has no theme setting
// (reports/theme.md).
//
// Options > macOS > "Theme:" chooses System (follow the Mac's Light / Dark setting, the default),
// Light or Dark. The choice is `NSApp.appearance` -- nil, `.aqua` or `.darkAqua` -- so it reaches
// every window of the process at once: the file-manager windows, every dialog, the message boxes,
// the progress windows and the 7zG-mode dialogs. Every custom-drawn component already picks its
// colours per appearance (`PanelSelectionStyle`, `WinProgressBar`, `DialogMetrics.groupLine`,
// ...), and AppKit redraws a view whose effective appearance changed, so switching needs no window
// rebuild.
//
// Stored as `FM.Theme` = "system" | "light" | "dark" in the settings domain; every choice is
// stored, System included. Absent (a fresh install, after Reset All Settings) or unknown = System.
// 1.1.2-1.2.x made Light the default while the window copied Windows' (fix112); a user who kept
// that default has no key and follows the system again from 1.3.0, one who picked Light keeps it.
// Applied at launch (`applyAtLaunch`, before the first window) and whenever the key is written --
// Apply / OK of the Options page, or a test reset that replaced the whole domain.

import AppKit

enum AppTheme: String, CaseIterable {
    case system
    case light
    case dark

    /// The `NSApp.appearance` the theme sets: nil follows the system.
    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    // MARK: - the drop-down's texts (macOS addition: lang IDs of its own, see `langID`)

    /// Lang IDs outside every 7-Zip block (the official files stop at 7830s), so a translator can
    /// add them to a Lang/*.txt (a line "9900" then the four texts) and the built-in English is the
    /// fallback. "System" falls back to IDD_SYSTEM's caption (2200, "System"), which every official
    /// translation already carries.
    static let labelLangID: UInt32 = 9900
    var langID: UInt32 {
        switch self {
        case .system: return 9901
        case .light: return 9902
        case .dark: return 9903
        }
    }

    var fallbackTitle: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var title: String {
        if self == .system, Lang.translated(langID) == nil { return Lang.text(2200, fallbackTitle) }
        return Lang.text(langID, fallbackTitle)
    }

    static var labelText: String { Lang.text(labelLangID, "Theme:") }

    // MARK: - applying

    /// Sets `NSApp.appearance` from the stored theme.
    static func applyStored() {
        apply(Settings.theme)
    }

    static func apply(_ theme: AppTheme) {
        let wanted = theme.appearance
        guard NSApp.appearance?.name != wanted?.name else { return }
        NSApp.appearance = wanted
    }

    private static var observer: NSObjectProtocol?

    /// Called from `applicationWillFinishLaunching`, before any window exists. Also follows later
    /// writes of the key (the Options page's Apply) and a test reset (a keyless notification).
    static func applyAtLaunch() {
        applyStored()
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: Settings.Group.view.notificationName, object: nil, queue: nil) { note in
            let key = note.userInfo?[Settings.keyUserInfoKey] as? String
            guard key == nil || key == Settings.Key.theme else { return }
            if Thread.isMainThread { applyStored() } else { DispatchQueue.main.async { applyStored() } }
        }
    }
}

extension Settings.Key {
    /// macOS only: the app's appearance (`AppTheme`).
    static let theme = "FM.Theme"
}

extension Settings {
    /// The theme of a fresh install: System, as every Mac app (fix112 made it Light while the
    /// window copied Windows').
    static let defaultTheme = AppTheme.system

    /// `FM.Theme` (macOS only): System (absent, the default), Light or Dark. Every choice is
    /// stored, System as "system", so it survives a later change of the default.
    static var theme: AppTheme {
        // Follows the system's Light / Dark unless a theme was chosen.
        get { string(Key.theme).flatMap(AppTheme.init(rawValue:)) ?? defaultTheme }
        set { setString(newValue.rawValue, Key.theme) }
    }
}
