// PanelArchivePreview.swift -- Quick Look on files inside an archive (Space, a macOS addition, as
// Finder shows a file): the selected files are extracted to a `7zO` temp folder the way Open
// Outside does it (ItemOpenCommands, 01 §3.8), and Quick Look shows those copies. Folders are
// not extracted.
//
// * Space extracts the selected files (at most `maxFiles`); while the preview stays open, a new
//   selection extracts only the focused file, so ⌘A or Shift-arrows in a large archive do not
//   start one big extraction per key press.
// * The copies are kept while the panel shows the same listing, so moving through the list with
//   the arrows extracts each file once. Every new listing of the panel (another folder, a reload
//   after the archive changed, e.g. an edited file written back) deletes them, and so do the
//   panel's deinit and the app's quit -- nothing stays behind in the temp folder.

import AppKit
import SevenZipKit

/// The temp copies Quick Look shows, per panel.
final class ArchivePreviewStore {
    static let shared = ArchivePreviewStore()

    /// The most files one Space extracts (a large selection previews its first ones).
    static let maxFiles = 50

    /// Per panel: "engineIndex:name" -> copy.
    private var entries: [ObjectIdentifier: [String: SZTempFile]] = [:]

    func files(for panel: PanelViewController) -> [String: SZTempFile] {
        entries[ObjectIdentifier(panel)] ?? [:]
    }

    func add(_ file: SZTempFile, key: String, for panel: PanelViewController) {
        entries[ObjectIdentifier(panel), default: [:]][key] = file
    }

    /// Deletes the panel's copies (a new listing, or the panel went away).
    func remove(for panel: PanelViewController) {
        remove(id: ObjectIdentifier(panel))
    }

    /// The same by identifier, for the panel's deinit.
    func remove(id: ObjectIdentifier) {
        guard let files = entries.removeValue(forKey: id) else { return }
        for file in files.values { SZTempOpen.removeTemporaryDirectory(atPath: file.directoryPath) }
    }

    func removeAll() {
        for id in Array(entries.keys) { remove(id: id) }
    }
}

extension PanelViewController {

    private static func previewKey(_ row: PanelRow) -> String { "\(row.engineIndex):\(row.name)" }

    /// The copies of the selected archive files that are extracted, in list order.
    func archivePreviewPaths(_ indices: [Int]) -> [String] {
        let files = ArchivePreviewStore.shared.files(for: self)
        return indices.compactMap { files[Self.previewKey(rows[$0])]?.filePath }
    }

    /// Extracts the selected files of an archive folder that have no copy yet -- all of them (up to
    /// `maxFiles`) for Space, only the focused one (`onlyFocused`) when the selection changes under
    /// an open preview. A cancel or an error (the runner has shown it) stops at that file.
    func prepareArchivePreviews(onlyFocused: Bool = false) {
        let store = ArchivePreviewStore.shared
        guard let snap = snapshot, snap.isArchive else {
            store.remove(for: self)
            return
        }
        let files = operatedRowIndices().filter { !rows[$0].isDirectory && !rows[$0].isParentRow }
        let wanted: [Int]
        if onlyFocused {
            wanted = files.contains(focusedIndex) ? [focusedIndex] : Array(files.prefix(1))
        } else {
            wanted = Array(files.prefix(ArchivePreviewStore.maxFiles))
        }
        for index in wanted {
            let row = rows[index]
            guard store.files(for: self)[Self.previewKey(row)] == nil else { continue }
            guard let context = operationContext(rowIndices: [index]), let engineIndex = context.indices.first,
                  let file = ItemOpenCommands.extractForPreview(context: context, index: engineIndex) else { return }
            store.add(file, key: Self.previewKey(row), for: self)
        }
    }
}
