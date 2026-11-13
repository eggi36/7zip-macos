// WinMessageBox.swift -- Windows' MessageBoxW as 7zFM 26.03 shows it on Windows 11 at 96 dpi, the one
// message box of the app (ai/reports/recheck2.md section 2).
//
// 7zFM asks every question and reports every error with `::MessageBoxW(owner, text, caption, flags)`
// (01 §2.8, 01b §4.19): MB_OK / MB_OKCANCEL / MB_YESNO / MB_YESNOCANCEL, with MB_ICONSTOP,
// MB_ICONWARNING, MB_ICONINFORMATION, MB_ICONQUESTION or no icon. Measured on the reference PC
// (recheck2-data/win/mb-*.txt, -png; the same geometry for 7zFM's own delete confirmation,
// fm-delete.txt):
//
//   * a separate window with the caption 7zFM passes, **centred on the screen** of its owner -- not on
//     the owner: 7zFM's main window at (78,78) 1440 x 753 and the box's centre at the screen's centre
//     (963,540 on 1920 x 1080), the same as with no owner at all;
//   * a white message area and a (243,243,243) button band 42 px high under it;
//   * the 32 px icon at (21,23), the text at x 62 (11 without an icon), y 23, or centred on a 34 px
//     icon block when it is shorter; lines 13 px apart, wrapped at about 324 px (SS_EDITCONTROL: a
//     word longer than that is broken between characters);
//   * 75 x 23 buttons, right-aligned 15 px from the edge, 83 px apart, 9 px under the band's top
//     (10 when the icon is taller than the text); the client is wide enough for the text (+28), the
//     buttons (27 + buttons + 15) and the caption;
//   * the first button is the default (DM_GETDEFID); Esc and the close box answer IDCANCEL when there
//     is a Cancel button, IDOK for a lone OK, and nothing for MB_YESNO, whose close box is disabled
//     (SC_CLOSE absent from its system menu);
//   * "&Yes" / "&No" answer the Y / N keys; Ctrl+C copies the box as text.
//
// Modal to the app (`DialogKit.runModal(for:)`), always owned by a visible window when the app has one
// (`DialogKit.owner`), and safe without one: it is an ordinary titled window that its own buttons,
// Esc, the close box, Cmd+W and the test reset (`TestResetCoordinator.closeTransientUI`) all end --
// never an ownerless `NSAlert` (ai/reports/modalfix.md, infohang.md).
//
// The user's exceptions: the native title bar and native push buttons.

import AppKit

enum WinMessageBox {

    /// MB_OK 0, MB_OKCANCEL 1, MB_YESNOCANCEL 3, MB_YESNO 4 -- the four 7zFM uses.
    enum Buttons {
        case ok, okCancel, yesNo, yesNoCancel

        var results: [Result] {
            switch self {
            case .ok: return [.ok]
            case .okCancel: return [.ok, .cancel]
            case .yesNo: return [.yes, .no]
            case .yesNoCancel: return [.yes, .no, .cancel]
            }
        }

        /// The button's caption: the lang text of the answer.
        func title(of result: Result) -> String { result.title }

        /// What Esc, the close box and Cmd+W answer: IDCANCEL when there is a Cancel button, IDOK for
        /// a lone OK (measured: Esc ends an MB_OK box with 1), nothing for MB_YESNO.
        var escapeResult: Result? {
            switch self {
            case .ok: return .ok
            case .okCancel, .yesNoCancel: return .cancel
            case .yesNo: return nil
            }
        }
    }

    /// MB_ICONHAND / MB_ICONSTOP / MB_ICONERROR 0x10, MB_ICONQUESTION 0x20, MB_ICONWARNING 0x30,
    /// MB_ICONINFORMATION 0x40.
    enum Icon { case none, error, question, warning, information }

    /// IDOK 1, IDCANCEL 2, IDYES 6, IDNO 7.
    enum Result: Int {
        case ok = 1, cancel = 2, yes = 6, no = 7

        var title: String {
            switch self {
            case .ok: return Lang.text(401, "OK")
            case .cancel: return Lang.text(402, "Cancel")
            case .yes: return Lang.text(406, "Yes")
            case .no: return Lang.text(407, "No")
            }
        }

        /// The access key of "&Yes" / "&No" (lang 406 / 407), lower-cased; OK and Cancel have none.
        var accessKey: Character? {
            switch self {
            case .yes: return Self.mnemonic(Lang.get(406, "&Yes"))
            case .no: return Self.mnemonic(Lang.get(407, "&No"))
            case .ok, .cancel: return nil
            }
        }

        private static func mnemonic(_ s: String) -> Character? {
            var it = s.makeIterator()
            while let c = it.next() {
                if c == "&", let next = it.next(), next != "&" { return Character(next.lowercased()) }
            }
            return nil
        }
    }

    /// Every box as it comes up, before its modal session starts (tests answer boxes from here).
    static var observers: [(WinMessageBoxWindow) -> Void] = []

    /// MessageBoxW: shows the box and waits for the answer. `owner` is the window the box belongs
    /// to; when it is nil or gone, the key / main / a 7-Zip window is used, as `DialogKit.owner`
    /// resolves a dialog's owner. Main thread only.
    @discardableResult
    static func run(_ text: String, caption: String = "7-Zip", buttons: Buttons = .ok, icon: Icon = .none,
                    owner: NSWindow?) -> Result {
        run(text, caption: caption, buttons: buttons, icon: icon, owner: owner, asynchronous: false)
    }

    private static func run(_ text: String, caption: String, buttons: Buttons, icon: Icon, owner: NSWindow?,
                            asynchronous: Bool) -> Result {
        let box = WinMessageBoxWindow(text: text, caption: caption, buttons: buttons, icon: icon,
                                      owner: DialogKit.owner(for: nil, parent: owner))
        box.isAsynchronous = asynchronous
        #if DEBUG
        NSLog("7-Zip message box [%@]: %@", caption, text)
        #endif
        return box.runModal()
    }

    /// The same box, shown from the main run loop after the caller has returned (what used to be a
    /// sheet that did not block). The modal session starts in a run-loop block in the common modes,
    /// never inside the caller's main-queue block, so a worker's `DispatchQueue.main.sync` is still
    /// served while the box is up (requests.md, `navgaps`).
    static func show(_ text: String, caption: String = "7-Zip", buttons: Buttons = .ok, icon: Icon = .none,
                     owner: NSWindow?, completion: ((Result) -> Void)? = nil) {
        weak let weakOwner = owner
        let hadOwner = owner != nil
        CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
            // The window it was for closed in the meantime: nobody to tell (ErrorAlert.present).
            if hadOwner, weakOwner == nil || weakOwner?.isVisible == false && weakOwner?.isMiniaturized == false {
                NSLog("7-Zip: %@ (its window is gone)", text)
                return
            }
            let result = run(text, caption: caption, buttons: buttons, icon: icon, owner: weakOwner, asynchronous: true)
            completion?(result)
        }
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }

    /// The boxes on screen, innermost last.
    static var visibleBoxes: [WinMessageBoxWindow] {
        NSApp.windows.compactMap { $0 as? WinMessageBoxWindow }.filter(\.isVisible)
    }
}

// MARK: - the window

final class WinMessageBoxWindow: NSWindow {

    let message: String
    let caption: String
    let boxButtons: WinMessageBox.Buttons
    let icon: WinMessageBox.Icon
    /// The alert's layout (NSAlert's metrics).
    let macLayout: MacMessageBoxLayout
    /// The window the box belongs to (nil only when the app shows no window).
    private(set) weak var ownerWindow: NSWindow?
    /// The push buttons, in the Windows order (Yes, No, Cancel / OK, Cancel).
    private(set) var pushButtons: [NSButton] = []
    private(set) var result: WinMessageBox.Result?
    /// Shown with `WinMessageBox.show`: nobody waits for the answer (an error report).
    var isAsynchronous = false

    init(text: String, caption: String, buttons: WinMessageBox.Buttons, icon: WinMessageBox.Icon, owner: NSWindow?) {
        message = text
        self.caption = caption
        boxButtons = buttons
        self.icon = icon
        ownerWindow = owner
        macLayout = MacMessageBoxLayout(text: text, titles: buttons.results.map(buttons.title(of:)))
        // MB_YESNO has no Cancel: its close box is disabled (SC_CLOSE is not in its system menu).
        // native-look: an alert has no visible title bar (NSAlert: titled, full-size content, the
        // title hidden); the caption stays the window's accessibility title.
        super.init(contentRect: NSRect(origin: .zero, size: macLayout.clientSize),
                   styleMask: [.titled, .closable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        title = caption
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        standardWindowButton(.closeButton)?.isHidden = true
        isReleasedWhenClosed = false
        animationBehavior = .alertPanel
        hidesOnDeactivate = false
        build()
        standardWindowButton(.closeButton)?.isEnabled = buttons.escapeResult != nil
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    /// native-look: an alert as macOS draws one (NSAlert, macOS 11 and later): the app icon (for an
    /// error the caution sign badged with it) at the top left, the first line of the message as the
    /// bold message text, the rest as the informative text, and equal-width buttons at the bottom
    /// -- side by side with the default (Windows' first button) rightmost, or stacked with the
    /// default on top when there are more than two. The answers, keys, Esc rule and copy-as-text
    /// are the Windows box's.
    private func buildMac(_ mac: MacMessageBoxLayout) {
        let content = RcFormView(frame: NSRect(origin: .zero, size: mac.clientSize))
        let view = NSImageView(frame: mac.iconFrame)
        view.image = Self.macAlertIcon(icon)
        view.imageScaling = .scaleProportionallyUpOrDown
        view.setAccessibilityElement(false)
        content.addSubview(view)
        let headline = NSTextField(wrappingLabelWithString: mac.messageText)
        headline.font = MacMessageBoxLayout.boldFont
        headline.isSelectable = true
        headline.frame = mac.messageFrame
        content.addSubview(headline)
        if !mac.informativeText.isEmpty {
            let info = NSTextField(wrappingLabelWithString: mac.informativeText)
            info.font = MacMessageBoxLayout.font
            info.isSelectable = true
            info.frame = mac.informativeFrame
            content.addSubview(info)
        }
        for (i, answer) in boxButtons.results.enumerated() {
            let button = NSButton(title: boxButtons.title(of: answer), target: self, action: #selector(buttonClicked(_:)))
            button.bezelStyle = .rounded
            button.controlSize = .large
            button.tag = answer.rawValue
            if i == 0 {
                button.keyEquivalent = "\r"
            } else if answer == .cancel {
                button.keyEquivalent = "\u{1b}"
            }
            button.frame = mac.buttonFrames[i]
            content.addSubview(button)
            pushButtons.append(button)
        }
        contentView = content
        initialFirstResponder = pushButtons.first
    }

    /// NSAlert's icons: the app icon, and for a critical alert (MB_ICONSTOP, MB_ICONWARNING) the
    /// caution sign with the app icon as a badge at its lower right.
    static func macAlertIcon(_ icon: WinMessageBox.Icon) -> NSImage {
        let app = NSApp.applicationIconImage ?? NSImage(named: NSImage.applicationIconName) ?? NSImage()
        guard icon == .error || icon == .warning, let caution = NSImage(named: NSImage.cautionName) else { return app }
        return NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            caution.draw(in: rect)
            app.draw(in: NSRect(x: rect.maxX - 32, y: rect.minY, width: 32, height: 32))
            return true
        }
    }

    private func build() { buildMac(macLayout) }

    // MARK: answering

    @objc private func buttonClicked(_ sender: NSButton) {
        guard let answer = WinMessageBox.Result(rawValue: sender.tag) else { return }
        self.answer(answer)
    }

    /// Ends the box with `answer` (EndDialog).
    func answer(_ answer: WinMessageBox.Result) {
        guard result == nil else { return }
        result = answer
        if NSApp.modalWindow === self { NSApp.stopModal(withCode: NSApplication.ModalResponse(rawValue: answer.rawValue)) }
        // A sheet is taken down by its parent's endSheet (DialogKit.runModal(for:asSheet:));
        // ordering it out here would detach it and leave AppKit's sheet session behind.
        if sheetParent == nil { orderOut(nil) }
    }

    /// Shows the box modally and returns the answer. A session ended from outside (the test reset)
    /// answers what Esc would, or No for MB_YESNO.
    func runModal() -> WinMessageBox.Result {
        for observer in WinMessageBox.observers { observer(self) }
        placeOnOwnersScreen()
        if result == nil { _ = DialogKit.runModal(for: self, asSheet: true) }   // native-look: a sheet
        if isVisible { orderOut(nil) }
        ownerWindow?.makeKeyAndOrderFront(nil)
        return result ?? boxButtons.escapeResult ?? .no
    }

    /// The centre of the owner's screen, the whole frame (MessageBox centres on the monitor, title
    /// bar included; the owner's own position does not matter).
    private func placeOnOwnersScreen() {
        // A Mac alert sits over the window it belongs to.
        DialogKit.center(self, over: ownerWindow)
    }

    /// `runModal(for:)` centres the window it orders in; the box keeps its own place.
    override func center() { placeOnOwnersScreen() }

    // MARK: keys and the close box

    /// The close box and Cmd+W: WM_CLOSE, which a message box turns into its Esc answer.
    override func performClose(_ sender: Any?) {
        if let answer = boxButtons.escapeResult { self.answer(answer) } else { NSSound.beep() }
    }

    override func cancelOperation(_ sender: Any?) {
        if let answer = boxButtons.escapeResult { self.answer(answer) }
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 53, flags.isEmpty { cancelOperation(nil); return }
        if flags.isEmpty || flags == .shift, let c = event.charactersIgnoringModifiers?.lowercased().first,
           let answer = boxButtons.results.first(where: { $0.accessKey == c }) {
            self.answer(answer)
            return
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.type == .keyDown, flags == .command {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "w": performClose(nil); return true
            case "c": copyAsText(); return true
            case ".": cancelOperation(nil); return true
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    /// Ctrl+C in a Windows message box: the caption, the text and the buttons between dashed lines.
    func copyAsText() {
        let rule = String(repeating: "-", count: 27)
        let buttons = boxButtons.results.map { boxButtons.title(of: $0) + "   " }.joined()
        let text = [rule, caption, rule, message, rule, buttons, rule, ""].joined(separator: "\r\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Whatever closed it, a box that is gone must not keep its modal session (DialogWindow.close).
    override func close() {
        let wasModal = NSApp.modalWindow === self
        super.close()
        guard wasModal else { return }
        RunLoop.main.perform(inModes: [.default, .modalPanel]) { [weak self] in
            guard let self, NSApp.modalWindow === self, !self.isVisible else { return }
            NSApp.stopModal(withCode: .abort)
        }
    }

    override var canBecomeKey: Bool { true }

    override func accessibilitySubrole() -> NSAccessibility.Subrole? { sheetParent != nil ? nil : .dialog }
    override func accessibilityRole() -> NSAccessibility.Role? { sheetParent != nil ? .sheet : super.accessibilityRole() }
    override func accessibilityTitle() -> String? { super.accessibilityTitle().flatMap { $0.isEmpty ? nil : $0 } ?? title }
}

/// native-look: the Mac look's alert geometry, measured from NSAlert on macOS 27: 260 pt wide, a
/// 64 pt icon 20 pt from the top left, the bold message text 16 pt below it, the informative text
/// 10 pt below that, and 28 pt buttons 16 pt from the edges, 8 pt apart side by side or 6 pt apart
/// stacked. A long message makes the alert wider (up to 460 pt) instead of very tall.
struct MacMessageBoxLayout {
    static let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    static let boldFont = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
    static let margin: CGFloat = 20
    static let iconSize: CGFloat = 64
    static let width: CGFloat = 260
    static let maxWidth: CGFloat = 460
    static let buttonHeight: CGFloat = 28

    let messageText: String
    let informativeText: String
    let clientSize: NSSize
    let iconFrame: NSRect
    let messageFrame: NSRect
    let informativeFrame: NSRect
    let buttonFrames: [NSRect]
    /// Whether the buttons are stacked (more than two, or too wide to sit side by side).
    let stacksButtons: Bool

    /// The first line is the message text, the rest the informative text.
    static func split(_ text: String) -> (String, String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let br = trimmed.firstIndex(where: \.isNewline) else { return (trimmed, "") }
        return (String(trimmed[..<br]), trimmed[br...].trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func height(_ text: String, _ font: NSFont, _ width: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = font
        field.preferredMaxLayoutWidth = width
        return ceil(field.fittingSize.height)
    }

    init(text: String, titles: [String]) {
        (messageText, informativeText) = Self.split(text)
        let m = Self.margin
        // Wider only when the text would run past about 12 lines at the standard width.
        var width = Self.width
        let lineHeight = ceil(Self.font.ascender - Self.font.descender + Self.font.leading)
        while width < Self.maxWidth,
              Self.height(messageText, Self.boldFont, width - 2 * m) + Self.height(informativeText, Self.font, width - 2 * m) > 12 * lineHeight {
            width += 50
        }
        let textWidth = width - 2 * m
        iconFrame = NSRect(x: m, y: m, width: Self.iconSize, height: Self.iconSize)
        var y = iconFrame.maxY + 16
        messageFrame = NSRect(x: m, y: y, width: textWidth, height: Self.height(messageText, Self.boldFont, textWidth))
        y = messageFrame.maxY
        if informativeText.isEmpty {
            informativeFrame = NSRect(x: m, y: y, width: textWidth, height: 0)
        } else {
            informativeFrame = NSRect(x: m, y: y + 10, width: textWidth,
                                      height: Self.height(informativeText, Self.font, textWidth))
            y = informativeFrame.maxY
        }
        y += 16
        let probe = NSButton(title: "", target: nil, action: nil)
        probe.bezelStyle = .rounded
        probe.controlSize = .large
        let natural: [CGFloat] = titles.map { probe.title = $0; return ceil(probe.intrinsicContentSize.width) }
        let rowWidth = width - 32
        let half = (rowWidth - 8) / 2
        stacksButtons = titles.count > 2 || natural.contains { $0 > half }
        var frames: [NSRect] = []
        if stacksButtons {
            for i in titles.indices {             // the default on top, the others below in order
                frames.append(NSRect(x: 16, y: y + CGFloat(i) * (Self.buttonHeight + 6), width: rowWidth, height: Self.buttonHeight))
            }
            y += CGFloat(titles.count) * (Self.buttonHeight + 6) - 6
        } else {
            let w = titles.count == 1 ? rowWidth : half
            for i in titles.indices {             // the default rightmost
                frames.append(NSRect(x: width - 16 - w - CGFloat(i) * (w + 8), y: y, width: w, height: Self.buttonHeight))
            }
            y += Self.buttonHeight
        }
        buttonFrames = frames
        clientSize = NSSize(width: width, height: y + 16)
    }
}
