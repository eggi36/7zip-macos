// PanelArchivePreview.swift -- Quick Look on files inside an archive (Space, a macOS addition, as
// Finder shows a file): the selected files are extracted to a `7zO` temp folder the way Open
// Outside does it (ItemOpenCommands, 01 §3.8), and Quick Look shows those copies. Folders are
// not extracted. The copies are kept while the panel shows the same archive folder, so moving
// through the list with the arrows extracts each file once, and are removed when the panel shows
// another folder and when the app quits.

import AppKit
import SevenZipKit

/// The temp copies Quick Look shows, per panel.
final class ArchivePreviewStore {
    static let shared = ArchivePreviewStore()

    /// The most files one Space extracts (a large selection previews its first ones).
    static let maxFiles = 50

    private struct Entry {
        var folderKey: String
        var files: [String: SZTempFile]       // "engineIndex:name" -> copy
    }
    private var entries: [ObjectIdentifier: Entry] = [:]

    func files(for panel: PanelViewController, folderKey: String) -> [String: SZTempFile] {
        guard let entry = entries[ObjectIdentifier(panel)], entry.folderKey == folderKey else { return [:] }
        return entry.files
    }

    func add(_ file: SZTempFile, key: String, for panel: PanelViewController, folderKey: String) {
        let id = ObjectIdentifier(panel)
        if entries[id]?.folderKey != folderKey { remove(for: panel) }
        entries[id, default: Entry(folderKey: folderKey, files: [:])].files[key] = file
    }

    /// Deletes the panel's copies (another folder, or the panel closed).
    func remove(for panel: PanelViewController) {
        guard let entry = entries.removeValue(forKey: ObjectIdentifier(panel)) else { return }
        for file in entry.files.values { SZTempOpen.removeTemporaryDirectory(atPath: file.directoryPath) }
    }

    func removeAll() {
        for entry in entries.values {
            for file in entry.files.values { SZTempOpen.removeTemporaryDirectory(atPath: file.directoryPath) }
        }
        entries = [:]
    }
}

extension PanelViewController {

    private var previewFolderKey: String { snapshot?.fullPath ?? "" }

    private static func previewKey(_ row: PanelRow) -> String { "\(row.engineIndex):\(row.name)" }

    /// The copies of the selected archive files that are extracted, in list order.
    func archivePreviewPaths(_ indices: [Int]) -> [String] {
        let files = ArchivePreviewStore.shared.files(for: self, folderKey: previewFolderKey)
        return indices.compactMap { files[Self.previewKey(rows[$0])]?.filePath }
    }

    /// Extracts the selected files of an archive folder that have no copy yet. A cancel or an
    /// error (the runner has shown it) stops at that file.
    func prepareArchivePreviews() {
        guard let snap = snapshot, snap.isArchive else {
            ArchivePreviewStore.shared.remove(for: self)
            return
        }
        let key = previewFolderKey
        let store = ArchivePreviewStore.shared
        if store.files(for: self, folderKey: key).isEmpty { store.remove(for: self) }   // another folder
        let wanted = operatedRowIndices().filter { !rows[$0].isDirectory && !rows[$0].isParentRow }
            .prefix(ArchivePreviewStore.maxFiles)
        for index in wanted {
            let row = rows[index]
            guard store.files(for: self, folderKey: key)[Self.previewKey(row)] == nil else { continue }
            guard let context = operationContext(rowIndices: [index]), let engineIndex = context.indices.first,
                  let file = ItemOpenCommands.extractForPreview(context: context, index: engineIndex) else { return }
            store.add(file, key: Self.previewKey(row), for: self, folderKey: key)
        }
    }
}
