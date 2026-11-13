// MacTerms.swift -- native-look: the macOS names of menu commands (HIG "The menu bar": Settings…,
// New Folder, Get Info, Move to Trash, Close Window, Go, Sort By ...).
//
// The 7-Zip lang files only have the Windows names, so the Mac names come from this table, in
// the languages it has; any other language keeps its own translation of the Windows name rather
// than fall back to English in the middle of a translated menu bar.

import Foundation
import SevenZipKit

enum MacTerm: String {
    case settings, newTab, newFolder, newFile, getInfo, moveToTrash, deleteImmediately, closeWindow
    case go, enclosingFolder, sortBy, customizeToolbar, showToolbar, help

    private var table: [String: String] {
        switch self {
        case .settings: return ["en": "Settings…", "de": "Einstellungen …"]
        case .newTab: return ["en": "New Tab", "de": "Neuer Tab"]
        case .newFolder: return ["en": "New Folder", "de": "Neuer Ordner"]
        case .newFile: return ["en": "New File", "de": "Neue Datei"]
        case .getInfo: return ["en": "Get Info", "de": "Informationen"]
        case .moveToTrash: return ["en": "Move to Trash", "de": "In den Papierkorb legen"]
        case .deleteImmediately: return ["en": "Delete Immediately…", "de": "Sofort löschen …"]
        case .closeWindow: return ["en": "Close Window", "de": "Fenster schließen"]
        case .go: return ["en": "Go", "de": "Gehe zu"]
        case .enclosingFolder: return ["en": "Enclosing Folder", "de": "Übergeordneter Ordner"]
        case .sortBy: return ["en": "Sort By", "de": "Sortieren nach"]
        case .customizeToolbar: return ["en": "Customize Toolbar…", "de": "Symbolleiste anpassen …"]
        case .showToolbar: return ["en": "Show Toolbar", "de": "Symbolleiste einblenden"]
        case .help: return ["en": "7-Zip Help", "de": "7-Zip-Hilfe"]
        }
    }

    /// The language the menus are in: the loaded lang file's code, "en" when none is loaded.
    static var languageCode: String {
        let code = SZLang.shared.currentLanguageCode.lowercased()
        return code.isEmpty || code == "-" ? "en" : code
    }

    /// The Mac name in the current language; `windows` (the lang text of the Windows command)
    /// when this table has no entry for the language.
    func title(windows: @autoclosure () -> String) -> String {
        let code = Self.languageCode
        if let text = table[code] ?? table[String(code.prefix(2))] { return text }
        return windows()
    }

    /// The Mac name, English when the language has none (for items with no Windows counterpart).
    var title: String { title(windows: table["en"] ?? rawValue) }
}
