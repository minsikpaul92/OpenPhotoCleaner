import Photos

/// 어디까지 봤는지 저장하고, 다시 열 때 이어서 시작할 위치를 찾는다.
struct ProgressStore {
    private let idKey = "progress.assetID"
    private let dateKey = "progress.creationDate"
    private var defaults: UserDefaults { .standard }

    func save(_ asset: PHAsset) {
        defaults.set(asset.localIdentifier, forKey: idKey)
        defaults.set(asset.creationDate, forKey: dateKey)
    }

    /// 마지막으로 본 사진의 위치. 그 사진이 목록에 없으면(대기열로 숨김 등) 같은 시점 다음 사진으로, 기록이 없으면 0.
    /// `items`는 최신순이다.
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
