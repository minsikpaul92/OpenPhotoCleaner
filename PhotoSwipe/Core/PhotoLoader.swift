import SwiftUI
import Photos
#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#else
import AppKit
typealias PlatformImage = NSImage
#endif

extension Image {
    init(platform image: PlatformImage) {
        #if canImport(UIKit)
        self.init(uiImage: image)
        #else
        self.init(nsImage: image)
        #endif
    }
}

/// 한 장 보기용 큰 이미지 로더. 지금 사진 앞뒤를 미리 읽어 메모리에 들고 있다가,
/// 사진을 넘기면 기다림 없이 같은 화면에서 바로 보여준다.
final class PhotoLoader {
    static let shared = PhotoLoader()

    /// 진행 방향(목록에서 뒤쪽, 더 오래된 사진)으로 미리 읽을 장 수.
    /// iPhone은 원래 부드러워서 메모리를 아끼려고 적게 잡는다.
    static let ahead: Int = {
        #if os(macOS)
        20
        #else
        10
        #endif
    }()

    /// 반대 방향(이미 지나온 쪽)으로 미리 읽어 둘 장 수.
    static let behind: Int = {
        #if os(macOS)
        10
        #else
        3
        #endif
    }()

    /// 큰 이미지 크기(픽셀).
    static let largeSize: CGSize = {
        #if os(macOS)
        CGSize(width: 1800, height: 1800)
        #else
        CGSize(width: 1200, height: 1200)
        #endif
    }()

    /// 저화질을 먼저 주지 않고 한 번에 고화질로 받는다.
    static let largeOptions: PHImageRequestOptions = {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        return options
    }()

    let manager = PHCachingImageManager()
    private var images: [String: PlatformImage] = [:]
    private var inFlight: [String: PHImageRequestID] = [:]

    /// 이미 읽어 둔 사진이면 바로 돌려준다(없으면 nil).
    func cachedImage(for asset: PHAsset) -> Image? {
        images[asset.localIdentifier].map { Image(platform: $0) }
    }

    /// `index` 주변을 미리 읽는다. 지금 사진에 가까운 것부터 읽고, 범위를 벗어난 것은 버린다.
    func prefetch(_ items: [PHAsset], around index: Int) {
        let lower = max(0, index - Self.behind)
        let upper = min(items.count - 1, index + Self.ahead)
        guard !items.isEmpty, lower <= upper else {
            stop()
            return
        }
        let window = Array(items[lower...upper])
        let windowIDs = Set(window.map(\.localIdentifier))

        for (id, requestID) in inFlight where !windowIDs.contains(id) {
            manager.cancelImageRequest(requestID)
            inFlight[id] = nil
        }
        images = images.filter { windowIDs.contains($0.key) }

        let center = index - lower
        let nearestFirst = window.enumerated().sorted { abs($0.offset - center) < abs($1.offset - center) }
        for (_, asset) in nearestFirst {
            let id = asset.localIdentifier
            guard images[id] == nil, inFlight[id] == nil else { continue }
            inFlight[id] = manager.requestImage(for: asset, targetSize: Self.largeSize, contentMode: .aspectFit, options: Self.largeOptions) { [weak self] platformImage, _ in
                guard let self else { return }
                self.inFlight[id] = nil
                if let platformImage { self.images[id] = platformImage }
            }
        }
    }

    /// 미리 읽은 것을 모두 버린다(한 장 보기 창이 닫힐 때).
    func stop() {
        for requestID in inFlight.values { manager.cancelImageRequest(requestID) }
        inFlight = [:]
        images = [:]
    }
}

/// 한 장 보기용 큰 사진. 미리 읽어 둔 사진은 같은 화면에서 바로 뜬다.
/// 스켈레톤이나 흐린 미리보기, 페이드 모션은 없다. 못 읽어 둔 사진은 오면 바로 나타난다.
struct LargeAssetImage: View {
    let asset: PHAsset
    @State private var loaded: Loaded?
    @State private var currentID = ""
    @State private var requestID: PHImageRequestID?

    private struct Loaded {
        let id: String
        let image: Image
    }

    /// 지금 사진의 이미지. 예전 사진의 것은 보여주지 않는다.
    private var shown: Image? {
        if let loaded, loaded.id == asset.localIdentifier { return loaded.image }
        return PhotoLoader.shared.cachedImage(for: asset)
    }

    var body: some View {
        ZStack {
            if let shown {
                shown.resizable().aspectRatio(contentMode: .fit)
            }
        }
        .onAppear(perform: load)
        .onChange(of: asset.localIdentifier) { load() }
        .onDisappear(perform: cancel)
    }

    private func load() {
        cancel()
        let id = asset.localIdentifier
        currentID = id
        guard loaded?.id != id, PhotoLoader.shared.cachedImage(for: asset) == nil else { return }
        requestID = PhotoLoader.shared.manager.requestImage(for: asset, targetSize: PhotoLoader.largeSize, contentMode: .aspectFit, options: PhotoLoader.largeOptions) { platformImage, _ in
            guard currentID == id, let platformImage else { return }
            loaded = Loaded(id: id, image: Image(platform: platformImage))
        }
    }

    private func cancel() {
        if let requestID { PhotoLoader.shared.manager.cancelImageRequest(requestID) }
        requestID = nil
    }
}
