import Photos
import Observation

/// Sorting state. Holds the newest-first list without queued photos and the current position,
/// and saves the position whenever it changes.
@Observable
final class SwipeSession {
    private let library: PhotoLibrary
    private let store = ProgressStore()
    let queue = DeletionQueue()
    let albums = AlbumLibrary()
    /// Newest-first list without photos in the deletion queue. Shared by the grid and the one-photo view.
    private(set) var items: [PHAsset] = []
    private(set) var index = 0
    /// Album that swiping up adds to right away.
    private(set) var target: Album?
    /// Increments whenever album membership changes (refreshes the photo's album chips).
    private(set) var albumsVersion = 0
    /// Last error to show in an alert.
    var lastError: String?

    init(library: PhotoLibrary) {
        self.library = library
        queue.prune()
        items = buildItems()
        index = store.resumeIndex(in: items)
        target = albums.targetID.flatMap { albums.album(id: $0) }
    }

    var count: Int { items.count }
    /// Nil once everything has been reviewed.
    var current: PHAsset? { index < count ? items[index] : nil }
    var canGoBack: Bool { index > 0 }

    /// Adds to the deletion queue (hidden from the list) and moves to the next photo.
    func trash() {
        guard let current else { return }
        record(.trashed(current))
        queue.add(current)
        items.remove(at: index)
        saveProgress()
    }

    /// Keeps the photo and moves to the next one.
    func keep() {
        guard let current else { return }
        record(.kept(current))
        advance()
    }

    // MARK: Undo

    private enum Undoable {
        case kept(PHAsset)
        case trashed(PHAsset)
        case addedToAlbum(PHAsset, Album, wasMember: Bool)
        case removedFromAlbum(PHAsset, Album)
    }

    private var undoStack: [Undoable] = []
    private let maxUndo = 100
    /// Album adds run in the background; undo waits for them so it never races an add.
    private var pendingAdd: Task<Void, Never>?

    private func record(_ action: Undoable) {
        undoStack.append(action)
        if undoStack.count > maxUndo { undoStack.removeFirst() }
    }

    /// Undoes the most recent action and returns a short message for a toast, or nil if there is nothing to undo.
    /// Deleting from the library is a system action and cannot be undone here; undoing a queue add of a deleted photo is skipped.
    func undo() async -> String? {
        await pendingAdd?.value
        while let action = undoStack.popLast() {
            switch action {
            case .kept(let asset):
                guard show(asset) else { continue }
                return String(localized: "Undid keep")
            case .trashed(let asset):
                guard queue.contains(asset) else { continue }
                queue.remove([asset])
                items = buildItems()
                show(asset)
                return String(localized: "Restored from the delete queue")
            case .addedToAlbum(let asset, let album, let wasMember):
                show(asset)
                if wasMember { return String(localized: "Undid add") }
                do {
                    try await albums.remove(asset, from: try await albums.resolve(album))
                    albumsVersion += 1
                } catch {
                    lastError = String(localized: "Couldn't remove from \(album.title). \(error.localizedDescription)")
                }
                return String(localized: "Removed from \(album.title)")
            case .removedFromAlbum(let asset, let album):
                show(asset)
                await add(asset, to: album)
                return String(localized: "Added back to \(album.title)")
            }
        }
        return nil
    }

    /// Moves to `asset` if it is in the list. Returns false when it is gone (e.g. deleted).
    @discardableResult
    private func show(_ asset: PHAsset) -> Bool {
        guard let newIndex = items.firstIndex(where: { $0.localIdentifier == asset.localIdentifier }) else { return false }
        index = newIndex
        saveProgress()
        return true
    }

    /// Takes photos out of the queue so they show in the list again. The current position is kept.
    func restore(_ assets: [PHAsset]) {
        guard !assets.isEmpty else { return }
        let currentID = current?.localIdentifier
        queue.remove(assets)
        items = buildItems()
        if let currentID, let newIndex = items.firstIndex(where: { $0.localIdentifier == currentID }) {
            index = newIndex
        } else {
            index = min(index, count)
        }
    }

    enum DeleteResult {
        case deleted
        /// Not allowed in the system confirmation. The queue is unchanged.
        case cancelled
        case failed
    }

    /// Deletes queued photos. A system confirmation appears.
    @discardableResult
    func deleteQueued(_ assets: [PHAsset]) async -> DeleteResult {
        do {
            try await queue.delete(assets)
            return .deleted
        } catch {
            if (error as? PHPhotosError)?.code == .userCancelled { return .cancelled }
            lastError = String(localized: "Couldn't delete. \(error.localizedDescription)")
            return .failed
        }
    }

    @discardableResult
    func deleteAllQueued() async -> DeleteResult {
        await deleteQueued(queue.assets())
    }

    /// Adds the current photo to the album and moves on right away. The add runs in the background.
    func addCurrent(to album: Album) {
        guard let asset = current else { return }
        record(.addedToAlbum(asset, album, wasMember: albums.albums(containing: asset).contains(album)))
        advance()
        let previous = pendingAdd
        pendingAdd = Task {
            await previous?.value
            await add(asset, to: album)
        }
    }

    enum SlotResult {
        case added(Album)
        case removed(Album)
        case none
    }

    /// If the current photo is not in the numbered album, adds it and moves on.
    /// If it is already in the album, removes it and stays on that photo (to correct a mistake).
    func toggleCurrent(toSlot digit: String) -> SlotResult {
        guard let asset = current, let album = albums.album(forSlot: digit) else { return .none }
        if albums.albums(containing: asset).contains(album) {
            remove(asset, from: album)
            return .removed(album)
        }
        addCurrent(to: album)
        return .added(album)
    }

    /// Removes the photo from the album. The screen stays as it is.
    func remove(_ asset: PHAsset, from album: Album) {
        record(.removedFromAlbum(asset, album))
        Task {
            do {
                try await albums.remove(asset, from: album)
                albumsVersion += 1
            } catch {
                lastError = String(localized: "Couldn't remove from \(album.title). \(error.localizedDescription)")
            }
        }
    }

    /// Clears the target album.
    func clearTarget() {
        target = nil
        albums.targetID = nil
    }

    /// Deletes the album; its photos stay. Clears the target if it was the target.
    func deleteAlbum(_ album: Album) async {
        do {
            try await albums.deleteAlbum(album)
            if target?.id == album.id { target = nil }
        } catch {
            lastError = String(localized: "Couldn't delete the album. \(error.localizedDescription)")
        }
    }

    /// Sets the target album. A "Pending Share" that does not exist yet is created here. With `addCurrent` the current photo is added too.
    func select(_ album: Album, addCurrent: Bool) async {
        do {
            let resolved = try await albums.resolve(album)
            target = resolved
            albums.targetID = resolved.id
            albums.recordUse(resolved)
            if addCurrent { self.addCurrent(to: resolved) }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Only creates the album. It is not chosen as target and no photo is added.
    /// The new album is recorded as used so it comes first in recently-used order.
    @discardableResult
    func createAlbum(title: String) async -> Album? {
        do {
            let album = try await albums.create(title: title)
            albums.recordUse(album)
            return album
        } catch {
            lastError = String(localized: "Couldn't create the album. \(error.localizedDescription)")
            return nil
        }
    }

    /// Moves to the photo chosen in the grid.
    func go(to newIndex: Int) {
        guard newIndex >= 0, newIndex < count else { return }
        index = newIndex
        saveProgress()
    }

    /// Plain back navigation (not undo).
    func previous() {
        guard index > 0 else { return }
        index -= 1
        saveProgress()
    }

    private func advance() {
        guard index < count else { return }
        index += 1
        saveProgress()
    }

    private func saveProgress() {
        if let current { store.save(current) }
    }

    private func buildItems() -> [PHAsset] {
        let hidden = queue.idSet
        var result: [PHAsset] = []
        result.reserveCapacity(library.assets.count)
        library.assets.enumerateObjects { asset, _, _ in
            if !hidden.contains(asset.localIdentifier) { result.append(asset) }
        }
        return result
    }

    private func add(_ asset: PHAsset, to album: Album) async {
        do {
            try await albums.add(asset, to: album)
            albumsVersion += 1
        } catch {
            lastError = String(localized: "Couldn't add to \(album.title). \(error.localizedDescription)")
        }
    }
}
