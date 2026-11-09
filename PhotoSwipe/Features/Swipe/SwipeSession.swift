import Photos
import Observation

/// 사진 정리 상태. 삭제 대기열에 넣은 사진을 뺀 최신순 목록과 현재 위치를 들고 있고,
/// 위치가 바뀔 때마다 저장한다.
@Observable
final class SwipeSession {
    private let library: PhotoLibrary
    private let store = ProgressStore()
    let queue = DeletionQueue()
    let albums = AlbumLibrary()
    /// 삭제 대기열에 넣은 사진을 뺀 최신순 목록. 그리드와 한 장 보기가 함께 쓴다.
    private(set) var items: [PHAsset] = []
    private(set) var index = 0
    /// 위로 올리면 바로 사진을 넣는 앨범.
    private(set) var target: Album?
    /// 앨범 구성이 바뀔 때마다 오른다(사진의 앨범 칩 새로고침용).
    private(set) var albumsVersion = 0
    /// 화면에 알림으로 보여줄 마지막 오류.
    var lastError: String?

    init(library: PhotoLibrary) {
        self.library = library
        queue.prune()
        items = buildItems()
        index = store.resumeIndex(in: items)
        target = albums.targetID.flatMap { albums.album(id: $0) }
    }

    var count: Int { items.count }
    /// 모두 넘겼으면 nil.
    var current: PHAsset? { index < count ? items[index] : nil }
    var canGoBack: Bool { index > 0 }

    /// 삭제 대기열에 추가하고(목록에서 숨김) 다음 사진으로.
    func trash() {
        guard let current else { return }
        queue.add(current)
        items.remove(at: index)
        saveProgress()
    }

    /// 유지하고 다음 사진으로.
    func keep() {
        advance()
    }

    /// 대기열에서 빼서 다시 목록에 보이게 한다. 보던 위치는 유지한다.
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
        /// 시스템 확인창에서 허용하지 않음. 대기열은 그대로다.
        case cancelled
        case failed
    }

    /// 대기열 사진을 삭제한다. 시스템 확인창이 뜬다.
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

    /// 현재 사진을 앨범에 추가하고 곧바로 다음 사진으로 넘어간다. 추가는 뒤에서 진행한다.
    func addCurrent(to album: Album) {
        guard let asset = current else { return }
        advance()
        Task { await add(asset, to: album) }
    }

    enum SlotResult {
        case added(Album)
        case removed(Album)
        case none
    }

    /// 번호 앨범에 현재 사진이 없으면 넣고 다음 사진으로 넘어간다.
    /// 이미 들어 있으면 앨범에서 빼고 그 사진 화면에 머문다(잘못 넣은 것을 바로잡을 때).
    func toggleCurrent(toSlot digit: String) -> SlotResult {
        guard let asset = current, let album = albums.album(forSlot: digit) else { return .none }
        if albums.albums(containing: asset).contains(album) {
            remove(asset, from: album)
            return .removed(album)
        }
        addCurrent(to: album)
        return .added(album)
    }

    /// 앨범에서 사진을 뺀다. 화면은 그대로 둔다.
    func remove(_ asset: PHAsset, from album: Album) {
        Task {
            do {
                try await albums.remove(asset, from: album)
                albumsVersion += 1
            } catch {
                lastError = String(localized: "Couldn't remove from \(album.title). \(error.localizedDescription)")
            }
        }
    }

    /// 대상 앨범을 해제한다(비운다).
    func clearTarget() {
        target = nil
        albums.targetID = nil
    }

    /// 앨범을 삭제한다. 사진은 남는다. 대상 앨범이었으면 해제된다.
    func deleteAlbum(_ album: Album) async {
        do {
            try await albums.deleteAlbum(album)
            if target?.id == album.id { target = nil }
        } catch {
            lastError = String(localized: "Couldn't delete the album. \(error.localizedDescription)")
        }
    }

    /// 대상 앨범으로 고정한다. 아직 없는 "공유 대기"는 이때 만든다. `addCurrent`면 현재 사진도 추가한다.
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

    /// 새 앨범을 만들기만 한다. 대상 앨범으로 고르거나 사진을 넣지는 않는다.
    /// 만든 앨범은 최근 사용순에서 맨 앞에 오도록 사용한 것으로 기록한다.
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

    /// 그리드에서 고른 사진으로 이동한다.
    func go(to newIndex: Int) {
        guard newIndex >= 0, newIndex < count else { return }
        index = newIndex
        saveProgress()
    }

    // 임시 이전 버튼용. 6단계에서 되돌리기로 대체한다.
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
