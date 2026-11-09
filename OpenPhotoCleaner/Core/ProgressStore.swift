import Photos

/// Saves where you stopped and finds where to resume when the app is reopened.
struct ProgressStore {
    private let idKey = "progress.assetID"
    private let dateKey = "progress.creationDate"
    private var defaults: UserDefaults { .standard }

    func save(_ asset: PHAsset) {
        defaults.set(asset.localIdentifier, forKey: idKey)
        defaults.set(asset.creationDate, forKey: dateKey)
    }

    /// Index of the last viewed photo. If it is no longer in the list (e.g. hidden in the queue), the next photo from the same time; 0 if nothing is saved.
    /// `items` is newest first.
    func resumeIndex(in items: [PHAsset]) -> Int {
        guard !items.isEmpty else { return 0 }

        if let id = defaults.string(forKey: idKey),
           let index = items.firstIndex(where: { $0.localIdentifier == id }) {
            return index
        }

        if let date = defaults.object(forKey: dateKey) as? Date {
            return items.firstIndex { ($0.creationDate ?? .distantPast) <= date } ?? items.count - 1
        }

        return 0
    }
}
