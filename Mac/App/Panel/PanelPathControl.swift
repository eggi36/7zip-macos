// PanelPathControl.swift -- native-look: Finder's path bar (View > Show Path Bar, Option+Cmd+P;
// HIG "Path controls") under the panel's list: the folder's chain from its volume down, each
// part with its icon, a click opens that folder -- archive folders included, since the parts
// are what the address field would take (SZFolder.folder(forPath:) binds through the archive).
//
// The editable address field above stays: 7zFM's address combo (01 §1.2) is how a path, an
// archive path or a mask is typed, and the path bar adds the Mac's way of reading and climbing
// the same path. Classic has no path bar.

import AppKit

/// Whether the path bars are shown: one setting for every panel and window, as in Finder.
enum MacPathBar {
    static let didChange = Notification.Name("SZMacPathBarDidChange")
    /// `FM.ShowPathBar` (macOS only), in the app's settings domain like every other setting.
    static let key = "FM.ShowPathBar"

    static var isShown: Bool {
        get { Settings.bool(key, default: true) }
        set {
            Settings.setBool(newValue, key)
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    /// The prefixes of `path` the bar shows, outermost first: "/" (the startup volume) or the
    /// mounted volume under /Volumes, then every folder down to `path` itself.
    static func parts(of path: String) -> [String] {
        guard path.hasPrefix("/") else { return [] }
        let names = path.split(separator: "/").map(String.init)
        var parts = ["/"]
        var current = ""
        for name in names {
            current += "/" + name
            parts.append(current)
        }
        // A volume under /Volumes starts the chain itself, as in Finder.
        if names.count >= 2, names[0] == "Volumes" { parts.removeFirst(2) }
        return parts
    }
}

/// The bar: a separator line on top and the path control. Height 0 while hidden.
final class PanelPathControlBar: NSView {
    static let height: CGFloat = 24

    let control = NSPathControl()
    /// Called with the path of the part that was clicked.
    var onOpen: ((String) -> Void)?
    private var paths: [String] = []
    private(set) var heightConstraint: NSLayoutConstraint!

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let line = PanelColorView(.separatorColor)
        addSubview(line)
        control.translatesAutoresizingMaskIntoConstraints = false
        control.pathStyle = .standard
        control.controlSize = .small
        control.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        control.focusRingType = .none
        control.isEditable = false
        control.unregisterDraggedTypes()
        control.target = self
        control.action = #selector(partClicked(_:))
        control.setAccessibilityIdentifier("sz.panel.pathControl")
        addSubview(control)
        heightConstraint = heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            heightConstraint,
            line.topAnchor.constraint(equalTo: topAnchor),
            line.leadingAnchor.constraint(equalTo: leadingAnchor),
            line.trailingAnchor.constraint(equalTo: trailingAnchor),
            line.heightAnchor.constraint(equalToConstant: 1),
            control.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            control.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            control.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 0.5),
        ])
        clipsToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var isShown: Bool = false {
        didSet {
            isHidden = !isShown
            heightConstraint.constant = isShown ? Self.height : 0
        }
    }

    /// The parts of the folder at `path`; the root list (no path) shows an empty bar.
    func show(path: String) {
        var trimmed = path
        while trimmed.count > 1, trimmed.hasSuffix("/") { trimmed.removeLast() }
        let parts = MacPathBar.parts(of: trimmed)
        guard parts != paths else { return }
        paths = parts
        control.pathItems = parts.map { part in
            let item = NSPathControlItem()
            item.title = part == "/" ? FileManager.default.displayName(atPath: "/")
                                     : (part as NSString).lastPathComponent
            // A part inside an archive is no file on disk: a plain folder icon.
            let icon = FileManager.default.fileExists(atPath: part)
                ? NSWorkspace.shared.icon(forFile: part) : Icons.folder
            let small = (icon.copy() as? NSImage) ?? icon
            small.size = NSSize(width: 16, height: 16)
            item.image = small
            return item
        }
    }

    /// The paths shown, outermost first (tests).
    var shownPaths: [String] { paths }

    @objc private func partClicked(_ sender: NSPathControl) {
        guard let clicked = sender.clickedPathItem,
              let index = sender.pathItems.firstIndex(where: { $0 === clicked }),
              index < paths.count, index != paths.count - 1 else { return }
        onOpen?(paths[index])
    }

    /// Opens the part at `index` as a click would (tests).
    func openPart(at index: Int) {
        guard index < paths.count else { return }
        onOpen?(paths[index])
    }
}
