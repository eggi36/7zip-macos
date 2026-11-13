// TrashUndo.swift -- native-look: Edit > Undo Move to Trash (HIG "Undo and redo"; Finder's
// "Put Back"). 7zFM has no undo; Windows leaves it to the Recycle Bin, so the Classic look keeps
// that and only the Mac look registers the moves with the window's undo manager.
//
// The engine trashes on the operation thread (FSFolderMac.cpp DeleteItems -> NMacFileOps::
// TrashItem), which posts "SZFileSystemDidTrashItem" with the old and the new path; the recorder
// collects those for the paths this delete asked for.

import Cocoa

/// One item moved to the Trash: where it was and where it is now.
struct TrashedItem: Equatable {
    let source: String
    let result: String
}

/// Collects the items trashed while it is installed. Thread-safe: notifications arrive on the
/// operation thread.
final class TrashRecorder {
    static let notification = Notification.Name("SZFileSystemDidTrashItem")

    private let wanted: Set<String>
    private let lock = NSLock()
    private var collected: [TrashedItem] = []
    private var observer: NSObjectProtocol?

    /// `paths`: the items the delete was asked for (other windows may trash at the same time).
    init(paths: [String]) {
        wanted = Set(paths.map(Self.normalized))
        observer = NotificationCenter.default.addObserver(forName: Self.notification, object: nil,
                                                          queue: nil) { [weak self] note in
            self?.record(note)
        }
    }

    deinit { stop() }

    static func normalized(_ path: String) -> String {
        var p = (path as NSString).standardizingPath
        while p.count > 1, p.hasSuffix("/") { p.removeLast() }
        return p
    }

    private func record(_ note: Notification) {
        guard let source = note.userInfo?["source"] as? String,
              let result = note.userInfo?["result"] as? String else { return }
        let key = Self.normalized(source)
        lock.lock(); defer { lock.unlock() }
        if wanted.contains(key) { collected.append(TrashedItem(source: key, result: result)) }
    }

    /// Stops listening and returns what was trashed, in order.
    @discardableResult
    func stop() -> [TrashedItem] {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        lock.lock(); defer { lock.unlock() }
        return collected
    }
}

enum TrashUndo {

    /// Registers "Undo Move to Trash" for `items` on `undoManager`; undoing puts them back,
    /// redoing trashes them again. `refresh` gets the names to select in the folder.
    static func register(_ items: [TrashedItem], undoManager: UndoManager?,
                         refresh: @escaping ([String]) -> Void, report: @escaping (Error) -> Void) {
        guard let undoManager, !items.isEmpty else { return }
        undoManager.registerUndo(withTarget: Box.shared) { _ in
            let restored = putBack(items, report: report)
            refresh(restored.map { ($0.source as NSString).lastPathComponent })
            // Redo: the restored items go to the Trash again.
            undoManager.registerUndo(withTarget: Box.shared) { _ in
                let again = trash(restored.map(\.source), report: report)
                refresh([])
                register(again, undoManager: undoManager, refresh: refresh, report: report)
            }
            undoManager.setActionName(MacTerm.moveToTrash.title(windows: "Move to Trash"))
        }
        undoManager.setActionName(MacTerm.moveToTrash.title(windows: "Move to Trash"))
    }

    /// Moves each item back to where it was; returns the ones that made it.
    static func putBack(_ items: [TrashedItem], report: (Error) -> Void) -> [TrashedItem] {
        var done: [TrashedItem] = []
        var firstError: Error?
        for item in items {
            do {
                try FileManager.default.moveItem(atPath: item.result, toPath: item.source)
                done.append(item)
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        if let firstError { report(firstError) }
        return done
    }

    /// Moves the paths to the Trash; returns the new locations.
    static func trash(_ paths: [String], report: (Error) -> Void) -> [TrashedItem] {
        var done: [TrashedItem] = []
        var firstError: Error?
        for path in paths {
            do {
                var resulting: NSURL?
                try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: &resulting)
                if let url = resulting as URL? { done.append(TrashedItem(source: path, result: url.path)) }
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        if let firstError { report(firstError) }
        return done
    }

    /// The undo target: the actions capture everything they need.
    private final class Box { static let shared = Box() }
}
