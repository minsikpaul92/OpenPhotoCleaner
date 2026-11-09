import Photos
import Observation

/// 사진 앨범 하나. 앨범에 추가해도 사진이 복사되지 않고 같은 사진을 가리킨다.
struct Album: Identifiable, Hashable {
    let id: String
    let title: String
    /// "공유 대기" 앨범이 아직 없을 때의 자리. 처음 쓸 때 실제로 만든다.
    var isPlaceholder = false
}

enum AlbumError: LocalizedError {
    case notFound
    var errorDescription: String? { String(localized: "Album not found.") }
}

/// 앨범 목록, 앨범 만들기·삭제, 앨범에 사진 추가, 최근 사용·대상 앨범·번호 즐겨찾기 기억.
@Observable
final class AlbumLibrary {
    static let pendingShareTitle = String(localized: "Pending Share")
    /// Earlier builds created the album under this Korean name; keep using it instead of making a duplicate.
    private static let legacyPendingShareTitle = "공유 대기"
    /// 번호 즐겨찾기에 쓰는 키. 숫자키 1~9, 0.
    static let slotKeys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
    private static let placeholderID = "placeholder.pendingShare"
    private let targetKey = "albums.targetID"
    private let slotIDsKey = "albums.slotIDs"
    private let slotTitlesKey = "albums.slotTitles"
    private let lastUsedKey = "albums.lastUsed"
    private let sortKey = "albums.sortsByName"
    private var defaults: UserDefaults { .standard }

    /// 번호 → 앨범 id. 앨범 하나에는 번호 하나만 둔다.
    private(set) var slotIDs: [String: String]
    /// 번호 → 앨범 이름(화면에 바로 보여주려고 같이 저장).
    private(set) var slotTitles: [String: String]
    /// 앨범 id → 마지막으로 쓴(대상으로 고르거나 사진을 넣거나 새로 만든) 시각.
    private(set) var lastUsed: [String: Double]
    /// true면 이름순, false면 최근 사용순.
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

    /// 최근 사용순과 이름순을 바꾼다.
    func toggleSort() {
        sortsByName.toggle()
        defaults.set(sortsByName, forKey: sortKey)
    }

    func album(id: String) -> Album? {
        PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil)
            .firstObject.map(Self.makeAlbum)
    }

    /// 앨범 목록. 최근 사용순이면 마지막에 쓴 앨범이 맨 앞(새로 만든 앨범도 만든 즉시 쓴 것으로 쳐서 맨 앞),
    /// 한 번도 안 쓴 앨범은 그 뒤에 이름순. 이름순이면 전부 이름순.
    /// 아직 만들지 않은 "공유 대기"는 한 번도 안 쓴 앨범처럼 목록에 들어간다.
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

    // MARK: 번호 즐겨찾기

    /// 이 번호에 지정된 앨범.
    func album(forSlot digit: String) -> Album? {
        guard let id = slotIDs[digit], let title = slotTitles[digit] else { return nil }
        return Album(id: id, title: title)
    }

    /// 이 앨범에 지정된 번호.
    func slot(of album: Album) -> String? {
        slotIDs.first { $0.value == album.id }?.key
    }

    /// 번호를 지정한다. 다른 앨범이 쓰던 번호면 덮어쓰고, 이 앨범의 예전 번호는 없어진다.
    /// 이 앨범에 같은 번호를 다시 지정하면 해제한다.
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

    // MARK: 앨범 만들기·삭제·추가

    /// 자리만 있던 "공유 대기"를 실제 앨범으로 바꿔 돌려준다. 이미 실제 앨범이면 그대로.
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

    /// 앨범만 삭제한다. 앨범 안의 사진은 보관함에 그대로 남는다.
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

    /// 앨범에 사진을 추가한다(복사가 아니라 참조). 실제 앨범으로 확정된 결과를 돌려준다.
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

    /// 이 사진이 이미 들어 있는 앨범들.
    func albums(containing asset: PHAsset) -> [Album] {
        var result: [Album] = []
        PHAssetCollection.fetchAssetCollectionsContaining(asset, with: .album, options: nil)
            .enumerateObjects { collection, _, _ in result.append(Self.makeAlbum(collection)) }
        return result
    }

    /// 앨범에서 사진만 뺀다. 사진은 보관함에 그대로 남는다.
    func remove(_ asset: PHAsset, from album: Album) async throws {
        guard let collection = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [album.id], options: nil).firstObject else {
            throw AlbumError.notFound
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCollectionChangeRequest(for: collection)?.removeAssets([asset] as NSArray)
        }
    }

    /// 방금 쓴 앨범으로 기록한다. 목록에서 맨 앞으로 온다.
    func recordUse(_ album: Album) {
        guard !album.isPlaceholder else { return }
        lastUsed[album.id] = Date().timeIntervalSince1970
        defaults.set(lastUsed, forKey: lastUsedKey)
    }

    // MARK: 내부

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

    /// 사진 앱에서 지워졌거나 이름이 바뀐 앨범을 반영한다.
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
