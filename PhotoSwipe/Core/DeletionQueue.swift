import Photos
import Observation

/// 삭제 대기열. 사진을 바로 지우지 않고 식별자만 모아 두며, 앱을 다시 열어도 유지된다.
/// 실제 삭제는 시스템이 확인창을 띄우고, 확인하면 사진 앱의 "최근 삭제된 항목"으로 간다.
@Observable
final class DeletionQueue {
    private let key = "deletionQueue.ids"
    private(set) var ids: [String]

    init() {
        ids = UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    var count: Int { ids.count }
    var idSet: Set<String> { Set(ids) }

    func contains(_ asset: PHAsset) -> Bool {
        ids.contains(asset.localIdentifier)
    }

    func add(_ asset: PHAsset) {
        guard !contains(asset) else { return }
        ids.append(asset.localIdentifier)
        save()
    }

    /// 대기열에서 뺀다(복원). 사진은 그대로 남는다.
    func remove(_ assets: [PHAsset]) {
        remove(ids: assets.map(\.localIdentifier))
    }

    /// 보관함에 더는 없는 사진의 식별자를 정리한다.
    func prune() {
        guard !ids.isEmpty else { return }
        var existing = Set<String>()
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
            .enumerateObjects { asset, _, _ in existing.insert(asset.localIdentifier) }
        let kept = ids.filter { existing.contains($0) }
        if kept.count != ids.count {
            ids = kept
            save()
        }
    }

    /// 대기열 사진들. 넣은 순서대로.
    func assets() -> [PHAsset] {
        guard !ids.isEmpty else { return [] }
        var byID: [String: PHAsset] = [:]
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
            .enumerateObjects { asset, _, _ in byID[asset.localIdentifier] = asset }
        return ids.compactMap { byID[$0] }
    }

    /// 사진을 실제로 삭제한다. 시스템 확인창이 뜨고, 사용자가 취소하면 오류(`userCancelled`)가 난다.
    /// 성공하면 대기열에서도 뺀다.
    func delete(_ assets: [PHAsset]) async throws {
        guard !assets.isEmpty else { return }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }
        remove(ids: assets.map(\.localIdentifier))
    }

    /// 사진 하나가 차지하는 용량(바이트). 문서화되지 않은 `fileSize` 키를 읽으므로 없으면 0으로 본다.
    static func byteSize(of asset: PHAsset) -> Int64 {
        PHAssetResource.assetResources(for: asset).reduce(0) { total, resource in
            total + ((resource.value(forKey: "fileSize") as? NSNumber)?.int64Value ?? 0)
        }
    }

    private func remove(ids removed: [String]) {
        let removedSet = Set(removed)
        ids.removeAll { removedSet.contains($0) }
        save()
    }

    private func save() {
        UserDefaults.standard.set(ids, forKey: key)
    }
}
