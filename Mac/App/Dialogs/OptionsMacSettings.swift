// OptionsMacSettings.swift -- the macOS additions on Options > Settings (IDD_SETTINGS 2500). 7zFM
// has no theme, Quick Look or reset; until 1.3.0 they were a "macOS" tab after Language, and the
// user had them moved onto the Settings page, under its own controls (OptionsSettingsPage.swift).
// The rows, in dialog units on the 316 x 296 DLU page, below IDD_SETTINGS' last row (y 158):
//
//   Theme:  [System v]          label + CBS_DROPDOWNLIST row, as "Archive format:" in IDD_COMPRESS
//                               (LTEXT 2 DLU under the combo's top). `AppTheme`, FM.Theme.
//   [x] Quick Look preview for archives  quicklook: the preview extension's PlugInKit election
//                               (`QuickLookExtensionControl`, default on), lang 9970. Read from
//                               `pluginkit` when the page opens, written on Apply, exactly like
//                               Options > 7-Zip's "Integrate 7-Zip to shell context menu"
//                               (OptionsMenuPage). Disabled in a copy without the extension.
//   [Reset All Settings...]     fix112: PUSHBUTTON, lang 9960. Asks (WinMessageBox, Yes / No, lang
//                               9961), then empties the settings domain and restarts the app
//                               (`SettingsReset`). Acts at once, not on Apply: the sheet's pending
//                               changes are dropped with everything else.
//
// Apply / OK write what changed; the theme takes effect at once (`AppTheme` follows FM.Theme).

import Cocoa

extension RcDialog {
    /// A template that is not in the generated `RcTemplates` (a page with macOS rows).
    init(template: RcTemplate) { self.template = template }
}

/// The macOS rows' control IDs and template places (macOS only, outside every 7-Zip ID block).
enum OptionsMacSettings {
    static let themeLabel = 9900        // LTEXT "Theme:"
    static let themeCombo = 9910        // COMBOBOX, CBS_DROPDOWNLIST
    static let quickLook = 9935         // checkbox, lang 9970 "Quick Look preview for archives" (quicklook)
    static let resetAll = 9940          // PUSHBUTTON, lang 9960 "Reset All Settings..." (fix112)

    static let controls: [RcControl] = [
        RcControl(id: themeLabel, kind: .ltext, x: 8, y: 184, width: 76, height: 8, text: "Theme:"),
        RcControl(id: themeCombo, kind: .comboList, x: 88, y: 182, width: 120, height: 64, text: ""),
        RcControl(id: quickLook, kind: .check, x: 8, y: 202, width: 300, height: 10, text: "Quick Look preview for archives"),
        RcControl(id: resetAll, kind: .push, x: 8, y: 220, width: 100, height: 14, text: "Reset All Settings..."),
    ]
}

extension OptionsSettingsPage {

    func loadMacRows(_ rc: RcDialog) {
        themePopup.removeAllItems()
        for theme in AppTheme.allCases {
            themePopup.addItem(withTitle: theme.title)
            themePopup.lastItem?.representedObject = theme.rawValue
        }
        themePopup.target = self
        themePopup.action = #selector(themeChosen(_:))
        themePopup.setAccessibilityIdentifier("optionsTheme")
        themeLabel.setAccessibilityIdentifier("optionsThemeLabel")
        form.add(themeLabel, rc, OptionsMacSettings.themeLabel)
        form.add(themePopup, rc, OptionsMacSettings.themeCombo)
        quickLookBox = OptionsUI.checkbox(PreviewLangID.checkbox, "Quick Look preview for archives",
                                          self, #selector(quickLookClicked(_:)))
        quickLookBox.setAccessibilityIdentifier("optionsMacQuickLook")
        form.add(quickLookBox, rc, OptionsMacSettings.quickLook)
        resetButton = NSButton(title: SettingsReset.buttonTitle, target: self, action: #selector(resetAllClicked(_:)))
        resetButton.bezelStyle = .rounded
        resetButton.setAccessibilityIdentifier("optionsMacResetAll")
        form.add(resetButton, rc, OptionsMacSettings.resetAll)
    }

    func macPageDidLoad() {
        selectTheme(Settings.theme)
        themeChanged = false
        quickLookChanged = false
        refreshQuickLookState()
    }

    func relabelMacRows() {
        themeLabel.stringValue = AppTheme.labelText
        for (i, theme) in AppTheme.allCases.enumerated() { themePopup.item(at: i)?.title = theme.title }
        themePopup.needsDisplay = true
        quickLookBox.title = Lang.text(PreviewLangID.checkbox, "Quick Look preview for archives")
        resetButton.title = SettingsReset.buttonTitle
    }

    func applyMacRows() {
        if themeChanged {
            Settings.theme = selectedTheme             // AppTheme applies it at once
            themeChanged = false
        }
        applyQuickLook()
    }

    // MARK: Theme

    var selectedTheme: AppTheme {
        (themePopup.selectedItem?.representedObject as? String).flatMap(AppTheme.init(rawValue:)) ?? Settings.defaultTheme
    }

    func selectTheme(_ theme: AppTheme) {
        themePopup.selectItem(at: AppTheme.allCases.firstIndex(of: theme) ?? 0)
    }

    @objc func themeChosen(_ sender: Any?) {
        themeChanged = true
        changed()
    }

    // MARK: Quick Look (quicklook scope)

    /// The box shows PlugInKit's state for this copy's extension (on unless elected ignore);
    /// checked while unknown, which is the default.
    func refreshQuickLookState(completion: (() -> Void)? = nil) {
        let embedded = quickLookAppexPath
        quickLookBox.isEnabled = embedded != nil
        if !quickLookChanged { quickLookBox.state = embedded == nil ? .off : .on }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let state = QuickLookExtensionControl.currentState(embeddedPath: embedded)
            DispatchQueue.main.async {
                self?.showQuickLook(state)
                completion?()
            }
        }
    }

    private func showQuickLook(_ state: QuickLookExtensionControl.State) {
        quickLookState = state
        quickLookBox.isEnabled = state != .notEmbedded
        // A click that has not been applied yet wins over a late answer from pluginkit. A copy
        // that is not registered yet (never launched from where it is) counts as on: its first
        // launch registers it, and nothing has elected it off.
        if !quickLookChanged {
            let on: Bool
            switch state {
            case .enabled, .notRegistered: on = true
            case .otherCopy(_, let enabled): on = enabled
            case .disabled, .notEmbedded: on = false
            }
            quickLookBox.state = on ? .on : .off
        }
        quickLookBox.toolTip = QuickLookExtensionControl.describe(state)
    }

    @objc func quickLookClicked(_ sender: Any?) {
        guard quickLookAppexPath != nil else { return }
        quickLookChanged = true
        changed()
    }

    /// Apply's PlugInKit half: elect use (claiming the registration) or ignore, off the main thread.
    func applyQuickLook(completion: (() -> Void)? = nil) {
        guard quickLookChanged, let embedded = quickLookAppexPath else { completion?(); return }
        quickLookChanged = false
        let wanted = quickLookBox.state == .on
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let state = QuickLookExtensionControl.setEnabled(wanted, embeddedPath: embedded)
            DispatchQueue.main.async {
                self?.showQuickLook(state)
                completion?()
            }
        }
    }

    // MARK: Reset All Settings

    /// Reset All Settings... (fix112): Yes empties the domain and restarts; No leaves everything,
    /// the sheet's unapplied changes included.
    @objc func resetAllClicked(_ sender: Any?) {
        SettingsReset.confirmAndRun(owner: view.window)
    }
}

/// quicklook: the checkbox's lang ID (macOS addition, the preview's block 9970-9979; the preview's
/// own texts are `PreviewText.LangID` in Mac/QuickLook).
enum PreviewLangID {
    static let checkbox: UInt32 = 9970
}
