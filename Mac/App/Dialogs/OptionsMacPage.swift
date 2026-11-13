// OptionsMacPage.swift -- Options > macOS: a macOS addition, no Windows counterpart (7zFM's
// property sheet has six pages, OptionsDialog.cpp:13-20). The last tab, after Language, so the
// six Windows pages keep their order and their layout untouched (reports/theme.md).
//
// The page is laid out like the others: a template in dialog units on the 316 x 296 DLU page
// (IDD_* MY_PAGE size), placed with the same `RcPlace` rules, in the dialog font. Its controls:
//
//   Theme:  [Light v]           label + CBS_DROPDOWNLIST row, as "Archive format:" in IDD_COMPRESS
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
// "Show grid lines" is only on the Settings page (IDX_SETTINGS_SHOW_GRID 2505), where Windows has it.

import Cocoa

extension RcDialog {
    /// A template that is not in the generated `RcTemplates` (a macOS-only page).
    init(template: RcTemplate) { self.template = template }
}

final class OptionsMacPage: OptionsPageBase {

    // No IDD_* resource: pageID 0 makes the tab title the fallback (OptionsWindowController.pageTitle).
    override var pageID: UInt32 { 0 }
    override var fallbackTitle: String { "macOS" }
    override var helpTopic: String { "fm/options.htm" }

    /// Control IDs of this page's own template (macOS only).
    enum ID {
        static let themeLabel = 9900        // LTEXT "Theme:"
        static let themeCombo = 9910        // COMBOBOX, CBS_DROPDOWNLIST
        static let resetAll = 9940          // PUSHBUTTON, lang 9960 "Reset All Settings..." (fix112)
        static let quickLook = 9935         // checkbox, lang 9970 "Quick Look preview for archives" (quicklook)
    }

    /// The page template in DLUs, in the IDD_SETTINGS style (m = 8, rows from y 8).
    static let template = RcTemplate(id: -9900, caption: "macOS", width: 316, height: 296, resizable: false, controls: [
        RcControl(id: ID.themeLabel, kind: .ltext, x: 8, y: 10, width: 76, height: 8, text: "Theme:"),
        RcControl(id: ID.themeCombo, kind: .comboList, x: 88, y: 8, width: 120, height: 64, text: ""),
        RcControl(id: ID.quickLook, kind: .check, x: 8, y: 30, width: 300, height: 10, text: "Quick Look preview for archives"),
        RcControl(id: ID.resetAll, kind: .push, x: 8, y: 50, width: 100, height: 14, text: "Reset All Settings..."),
    ])

    override var rc: RcDialog { RcDialog(template: Self.template) }

    let themeLabel = RcPlace.makeLabel(AppTheme.labelText)
    let themePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private(set) var resetButton: NSButton!
    private(set) var quickLookBox: NSButton!
    /// The preview extension's state as `pluginkit` last reported it (nil while checking).
    private(set) var quickLookState: QuickLookExtensionControl.State?
    /// The appex this copy carries; nil disables the box. Tests inject a path.
    var quickLookAppexPath: String? = QuickLookExtensionControl.embeddedAppexPath
    private var quickLookChanged = false
    private var themeChanged = false

    override func loadView() {
        super.loadView()
        let rc = self.rc
        themePopup.removeAllItems()
        for theme in AppTheme.allCases {
            themePopup.addItem(withTitle: theme.title)
            themePopup.lastItem?.representedObject = theme.rawValue
        }
        themePopup.target = self
        themePopup.action = #selector(themeChosen(_:))
        themePopup.setAccessibilityIdentifier("optionsTheme")
        themeLabel.setAccessibilityIdentifier("optionsThemeLabel")
        form.add(themeLabel, rc, ID.themeLabel)
        form.add(themePopup, rc, ID.themeCombo)
        quickLookBox = OptionsUI.checkbox(PreviewLangID.checkbox, "Quick Look preview for archives",
                                          self, #selector(quickLookClicked(_:)))
        quickLookBox.setAccessibilityIdentifier("optionsMacQuickLook")
        form.add(quickLookBox, rc, ID.quickLook)
        resetButton = NSButton(title: SettingsReset.buttonTitle, target: self, action: #selector(resetAllClicked(_:)))
        resetButton.bezelStyle = .rounded
        resetButton.setAccessibilityIdentifier("optionsMacResetAll")
        form.add(resetButton, rc, ID.resetAll)
    }

    // MARK: OnInit

    override func pageDidLoad() {
        selectTheme(Settings.theme)
        themeChanged = false
        quickLookChanged = false
        refreshQuickLookState()
        relabelPage()
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

    override func relabelPage() {
        themeLabel.stringValue = AppTheme.labelText
        for (i, theme) in AppTheme.allCases.enumerated() { themePopup.item(at: i)?.title = theme.title }
        themePopup.needsDisplay = true
        quickLookBox.title = Lang.text(PreviewLangID.checkbox, "Quick Look preview for archives")
        resetButton.title = SettingsReset.buttonTitle
    }

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

    /// Reset All Settings... (fix112): Yes empties the domain and restarts; No leaves everything,
    /// the sheet's unapplied changes included.
    @objc func resetAllClicked(_ sender: Any?) {
        SettingsReset.confirmAndRun(owner: view.window)
    }

    // MARK: OnApply

    override func applyPage() -> Bool {
        if themeChanged {
            Settings.theme = selectedTheme             // AppTheme applies it at once
            themeChanged = false
        }
        applyQuickLook()
        return true
    }
}

/// quicklook: the checkbox's lang ID (macOS addition, the preview's block 9970-9979; the preview's
/// own texts are `PreviewText.LangID` in Mac/QuickLook).
enum PreviewLangID {
    static let checkbox: UInt32 = 9970
}
