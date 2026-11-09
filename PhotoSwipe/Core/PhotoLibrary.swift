import Photos
import Observation

/// 사진 보관함 접근 권한과 최신순 에셋 목록.
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
