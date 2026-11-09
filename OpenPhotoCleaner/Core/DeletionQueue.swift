import Photos
import Observation

/// Deletion queue. Photos are not deleted right away; only their identifiers are collected, and they persist across launches.
/// The actual deletion shows a system confirmation; confirming moves the photos to "Recently Deleted" in the Photos app.
@Observable
final class DeletionQueue {
    private let key = "deletionQueue.ids"
    private let defaults: UserDefaults
    private(set) var ids: [String]

    /// `defaults` is injectable so tests never touch the app's real queue.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        ids = defaults.stringArray(forKey: key) ?? []
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

    /// Removes from the queue (restore). The photos stay untouched.
    func remove(_ assets: [PHAsset]) {
        remove(ids: assets.map(\.localIdentifier))
    }

    /// Prunes identifiers of photos that are no longer in the library.
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

    /// The queued photos, in the order they were added.
    func assets() -> [PHAsset] {
        guard !ids.isEmpty else { return [] }
        var byID: [String: PHAsset] = [:]
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
            .enumerateObjects { asset, _, _ in byID[asset.localIdentifier] = asset }
        return ids.compactMap { byID[$0] }
    }

    /// Actually deletes the photos. A system confirmation appears; if the user cancels it throws (`userCancelled`).
    /// On success they are also removed from the queue.
    func delete(_ assets: [PHAsset]) async throws {
        guard !assets.isEmpty else { return }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }
        remove(ids: assets.map(\.localIdentifier))
    }

    /// Size of one photo in bytes. Reads the undocumented `fileSize` key, so a missing value counts as 0.
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
        defaults.set(ids, forKey: key)
    }
}
