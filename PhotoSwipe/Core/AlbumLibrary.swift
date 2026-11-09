import Photos
import Observation

/// One photo album. Adding a photo to an album does not copy it; the album points at the same photo.
struct Album: Identifiable, Hashable {
    let id: String
    let title: String
    /// Stand-in for the "Pending Share" album when it does not exist yet. It is created for real on first use.
    var isPlaceholder = false
}

enum AlbumError: LocalizedError {
    case notFound
    var errorDescription: String? { String(localized: "Album not found.") }
}

/// Album list, creating and deleting albums, adding photos to albums, and remembering last use, the target album and number favorites.
@Observable
final class AlbumLibrary {
    static let pendingShareTitle = String(localized: "Pending Share")
    /// Earlier builds created the album under this Korean name; keep using it instead of making a duplicate.
    private static let legacyPendingShareTitle = "공유 대기"
    /// Keys used for number favorites: number keys 1-9, 0.
    static let slotKeys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
    private static let placeholderID = "placeholder.pendingShare"
    private let targetKey = "albums.targetID"
    private let slotIDsKey = "albums.slotIDs"
    private let slotTitlesKey = "albums.slotTitles"
    private let lastUsedKey = "albums.lastUsed"
    private let sortKey = "albums.sortsByName"
    private var defaults: UserDefaults { .standard }

    /// Number to album id. An album has at most one number.
    private(set) var slotIDs: [String: String]
    /// Number to album title (stored too so it can be shown without a lookup).
    private(set) var slotTitles: [String: String]
    /// Album id to the time it was last used (chosen as target, a photo added, or created).
    private(set) var lastUsed: [String: Double]
    /// True for by-name order, false for recently-used order.
    private(set) var sortsByName: Bool

    init() {
        let defaults = UserDefaults.standard
        slotIDs = defaults.dictionary(forKey: "albums.slotIDs") as? [String: String] ?? [:]
        slotTitles = defaults.dictionary(forKey: "albums.slotTitles") as? [String: String] ?? [:]
        lastUsed = defaults.dictionary(forKey: "albums.lastUsed") as? [String: Double] ?? [:]
        sortsByName = defaults.bool(forKey: "albums.sortsByName")
        refreshSlots()
    }

    var targetID: String? {
        get { defaults.string(forKey: targetKey) }
        set { defaults.set(newValue, forKey: targetKey) }
    }

    /// Switches between recently-used and by-name order.
    func toggleSort() {
        sortsByName.toggle()
        defaults.set(sortsByName, forKey: sortKey)
    }

    func album(id: String) -> Album? {
        PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil)
            .firstObject.map(Self.makeAlbum)
    }

    /// Album list. In recently-used order the last used album comes first (a new album counts as used when created),
    /// then never-used albums by name. In by-name order everything is sorted by name.
    /// A "Pending Share" album that does not exist yet is listed like a never-used album.
    func albums() -> [Album] {
        let result = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
        var all: [Album] = []
        result.enumerateObjects { collection, _, _ in all.append(Self.makeAlbum(collection)) }
        if !all.contains(where: { $0.title == Self.pendingShareTitle || $0.title == Self.legacyPendingShareTitle }) {
            all.append(Album(id: Self.placeholderID, title: Self.pendingShareTitle, isPlaceholder: true))
        }

        let byName: (Album, Album) -> Bool = { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        if sortsByName { return all.sorted(by: byName) }

        let used = all
            .compactMap { album in lastUsed[album.id].map { (album, $0) } }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
        let unused = all.filter { lastUsed[$0.id] == nil }.sorted(by: byName)
        return used + unused
    }

    // MARK: Number favorites

    /// The album assigned to this number.
    func album(forSlot digit: String) -> Album? {
        guard let id = slotIDs[digit], let title = slotTitles[digit] else { return nil }
        return Album(id: id, title: title)
    }

    /// The number assigned to this album.
    func slot(of album: Album) -> String? {
        slotIDs.first { $0.value == album.id }?.key
    }

    /// Assigns a number. Overwrites another album's use of it; this album's previous number is dropped.
    /// Assigning the same number to this album again clears it.
    func toggleSlot(_ digit: String, for album: Album) {
        guard !album.isPlaceholder else { return }
        if slotIDs[digit] == album.id {
            slotIDs[digit] = nil
            slotTitles[digit] = nil
        } else {
            removeSlots(of: album.id)
            slotIDs[digit] = album.id
            slotTitles[digit] = album.title
        }
        saveSlots()
    }

    // MARK: Creating, deleting and adding to albums

    /// Turns the stand-in "Pending Share" into a real album and returns it. A real album is returned unchanged.
    func resolve(_ album: Album) async throws -> Album {
        guard album.isPlaceholder else { return album }
        if let existing = albums().first(where: { $0.title == album.title && !$0.isPlaceholder }) {
            return existing
        }
        return try await create(title: album.title)
    }

    func create(title: String) async throws -> Album {
        let box = IDBox()
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
            box.id = request.placeholderForCreatedAssetCollection.localIdentifier
        }
        guard let id = box.id, let album = album(id: id) else { throw AlbumError.notFound }
        return album
    }

    /// Deletes only the album. Its photos stay in the library.
    func deleteAlbum(_ album: Album) async throws {
        guard !album.isPlaceholder,
              let collection = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [album.id], options: nil).firstObject
        else { throw AlbumError.notFound }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCollectionChangeRequest.deleteAssetCollections([collection] as NSArray)
        }
        removeSlots(of: album.id)
        saveSlots()
        lastUsed[album.id] = nil
        defaults.set(lastUsed, forKey: lastUsedKey)
        if targetID == album.id { targetID = nil }
    }

    /// Adds a photo to an album (a reference, not a copy). Returns the resolved real album.
    @discardableResult
    func add(_ asset: PHAsset, to album: Album) async throws -> Album {
        let resolved = try await resolve(album)
        guard let collection = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [resolved.id], options: nil).firstObject else {
            throw AlbumError.notFound
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCollectionChangeRequest(for: collection)?.addAssets([asset] as NSArray)
        }
        recordUse(resolved)
        return resolved
    }

    /// The albums this photo is already in.
    func albums(containing asset: PHAsset) -> [Album] {
        var result: [Album] = []
        PHAssetCollection.fetchAssetCollectionsContaining(asset, with: .album, options: nil)
            .enumerateObjects { collection, _, _ in result.append(Self.makeAlbum(collection)) }
        return result
    }

    /// Removes only the photo from the album. The photo stays in the library.
    func remove(_ asset: PHAsset, from album: Album) async throws {
        guard let collection = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [album.id], options: nil).firstObject else {
            throw AlbumError.notFound
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCollectionChangeRequest(for: collection)?.removeAssets([asset] as NSArray)
        }
    }

    /// Records the album as just used. It moves to the front of the list.
    func recordUse(_ album: Album) {
        guard !album.isPlaceholder else { return }
        lastUsed[album.id] = Date().timeIntervalSince1970
        defaults.set(lastUsed, forKey: lastUsedKey)
    }

    // MARK: Internal

    private func removeSlots(of albumID: String) {
        for digit in slotIDs.filter({ $0.value == albumID }).keys {
            slotIDs[digit] = nil
            slotTitles[digit] = nil
        }
    }

    private func saveSlots() {
        defaults.set(slotIDs, forKey: slotIDsKey)
        defaults.set(slotTitles, forKey: slotTitlesKey)
    }

    /// Reflects albums that were deleted or renamed in the Photos app.
    private func refreshSlots() {
        guard !slotIDs.isEmpty else { return }
        var titles: [String: String] = [:]
        PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: Array(slotIDs.values), options: nil)
            .enumerateObjects { collection, _, _ in
                titles[collection.localIdentifier] = collection.localizedTitle ?? String(localized: "Untitled")
            }
        var ids: [String: String] = [:]
        var names: [String: String] = [:]
        for (digit, id) in slotIDs {
            guard let title = titles[id] else { continue }
            ids[digit] = id
            names[digit] = title
        }
        slotIDs = ids
        slotTitles = names
        saveSlots()
    }

    private static func makeAlbum(_ collection: PHAssetCollection) -> Album {
        Album(id: collection.localIdentifier, title: collection.localizedTitle ?? String(localized: "Untitled"))
    }
}

private final class IDBox: @unchecked Sendable {
    var id: String?
}
