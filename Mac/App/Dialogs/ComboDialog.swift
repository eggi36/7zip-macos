// ComboDialog.swift -- CComboDialog / IDD_COMBO 98 (ComboDialog.cpp/.rc), built in code.
// Parity: 01b-fm-dialogs-settings.md 4.4. 240 x 64 du, MY_MODAL_RESIZE_DIALOG_STYLE: the
// caption is `Title`, static IDT_COMBO 100 shows `Static`, the edit combo IDC_COMBO 101 is
// pre-filled with `Value` and lists `Strings`; OnOK (:60-64) reads the edit text back.
//
// Callers (01b 4.4): Select/Deselect by mask (PanelSelect.cpp), Create Folder / Create File /
// Comment (PanelOperations.cpp) and the Browse dialog's "+" button (Dlg_CreateFolder).

import AppKit

/// The single-value input dialog. Main thread only.
enum ComboDialog {

    /// Returns the edit-field text, or nil when the user cancelled.
    static func run(title: String, label: String, value: String = "",
                    strings: [String] = [], parent: NSWindow?) -> String? {
        let dialog = ComboDialogController(title: title, label: label, value: value,
                                           strings: strings, parent: parent)
        return dialog.run()
    }
}

private final class ComboDialogController: NSObject {

    private let window: NSWindow
    private let combo = WinComboBox()                  // IDC_COMBO 101 (MY_COMBO_WITH_EDIT)
    private var result: String?

    init(title: String, label: String, value: String, strings: [String], parent: NSWindow?) {
        // IDD_COMBO 98: caption "Combo" in the .rc, replaced by Title at OnInit.
        window = DialogKit.window(title: title, resizable: true)
        super.init()

        // ComboDialog.cpp:35-37: SetText(Value) + AddString(Strings[i]).
        combo.isEditable = true
        combo.completes = true
        combo.usesDataSource = false
        combo.numberOfVisibleItems = 12
        if !strings.isEmpty { combo.addItems(withObjectValues: strings) }
        combo.stringValue = value

        // IDD_COMBO 98 (ComboDialog.rc): 256 x 80 DLU = 384 x 130 px, resizable (WS_THICKFRAME);
        // OnSize keeps OK / Cancel at the bottom right and stretches the combo (dlgfeel).
        let rc = RcDialog(98)
        let form = RcFormView()
        form.add(DialogKit.label(label), rc, 100)                                // IDT_COMBO 100 (LTEXT)
        form.add(combo, rc, 101)
        // OK_CANCEL: OK is the default button, Cancel answers Escape.
        let ok = form.add(DialogKit.button(Lang.text(401, "OK"), target: self, action: #selector(okClicked), key: "\r"), rc, 1)
        let cancel = form.add(DialogKit.button(Lang.text(402, "Cancel"), target: self,
                                               action: #selector(cancelClicked), key: "\u{1b}"), rc, 2)
        let comboRect = rc.rect(101)
        form.onResize = { [combo] size in
            RcResize.bottomRightButtons([(cancel, rc.rect(2).size), (ok, rc.rect(1).size)], in: size)
            RcResize.setWidth(combo, size.width - 2 * RcResize.mx, rect: comboRect)
        }
        RcPlace.install(form, in: window, size: rc.size, parent: parent)
        window.initialFirstResponder = combo
    }

    /// Runs modally on the main thread; the whole value is selected first so typing replaces it.
    func run() -> String? {
        // native-look: a sheet of the main window (DialogKit.sheetParent), else a window.
        if DialogKit.sheetParent(for: window) == nil {
            window.makeKeyAndOrderFront(nil)
        } else {
            addSheetHeading()
        }
        combo.selectText(nil)
        DialogKit.runModal(for: window, asSheet: true)
        window.orderOut(nil)
        return result
    }

    /// native-look: a sheet has no title bar, and this one dialog serves Rename, Create Folder,
    /// Create File, Comment and Select -- so the caption becomes a bold heading above the field,
    /// as an NSAlert's message text names what a sheet asks.
    private func addSheetHeading() {
        guard let form = window.contentView else { return }
        let heading = NSTextField(labelWithString: window.title)
        heading.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
        heading.lineBreakMode = .byTruncatingMiddle
        let height: CGFloat = 26
        let size = form.frame.size
        let container = NSView(frame: NSRect(x: 0, y: 0, width: size.width, height: size.height + height))
        let x = RcDialog(98).rect(100).minX
        heading.frame = NSRect(x: x, y: size.height + 2, width: size.width - 2 * x, height: 18)
        heading.autoresizingMask = [.width, .minYMargin]
        form.frame = NSRect(origin: .zero, size: size)
        form.autoresizingMask = [.width, .height]
        window.contentView = container
        container.addSubview(form)
        container.addSubview(heading)
        // The new content view takes the window's old size, so the target is computed up front.
        window.contentMinSize = NSSize(width: window.contentMinSize.width, height: window.contentMinSize.height + height)
        window.setContentSize(NSSize(width: size.width, height: size.height + height))
        form.frame = NSRect(origin: .zero, size: size)                         // then the final frames
        heading.frame = NSRect(x: x, y: size.height + 2, width: size.width - 2 * x, height: 18)
        window.initialFirstResponder = combo
        window.makeFirstResponder(combo)
    }

    @objc private func okClicked() {
        result = combo.stringValue                       // OnOK: _comboBox.GetText(Value)
        NSApp.stopModal()
    }

    @objc private func cancelClicked() {
        result = nil
        NSApp.stopModal()
    }
}
