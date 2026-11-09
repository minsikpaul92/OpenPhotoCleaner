import Photos
import Observation

/// Photo library authorization and the newest-first asset list.
@Observable
final class PhotoLibrary {
    private(set) var status: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    private(set) var assets: PHFetchResult<PHAsset> = PHFetchResult<PHAsset>()

    var isAuthorized: Bool { status == .authorized }

    init() {
        reload()
    }

    func requestAccess() async {
        status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        reload()
    }

    func reload() {
        guard isAuthorized else { return }
        assets = PHAsset.fetchAssets(with: Self.newestFirst)
    }

    static var newestFirst: PHFetchOptions {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return options
    }
}
