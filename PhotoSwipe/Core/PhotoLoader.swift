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

/// Large-image loader for the one-photo view. Prefetches photos around the current one and keeps them in memory,
/// so swiping to the next photo shows it immediately on the same frame.
final class PhotoLoader {
    static let shared = PhotoLoader()

    /// Number of photos to prefetch in the direction of travel (later in the list, older photos).
    /// iPhone was already smooth, so keep it small to save memory.
    static let ahead: Int = {
        #if os(macOS)
        20
        #else
        10
        #endif
    }()

    /// Number of photos to keep prefetched in the opposite direction (already passed).
    static let behind: Int = {
        #if os(macOS)
        10
        #else
        3
        #endif
    }()

    /// Large image size in pixels.
    static let largeSize: CGSize = {
        #if os(macOS)
        CGSize(width: 1800, height: 1800)
        #else
        CGSize(width: 1200, height: 1200)
        #endif
    }()

    /// Request high quality once, without a low-quality stage first.
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

    /// Returns the image right away if it was prefetched (nil otherwise).
    func cachedImage(for asset: PHAsset) -> Image? {
        images[asset.localIdentifier].map { Image(platform: $0) }
    }

    /// Prefetches around `index`, nearest photos first, and drops anything outside the window.
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

    /// Drops everything prefetched (when the one-photo window closes).
    func stop() {
        for requestID in inFlight.values { manager.cancelImageRequest(requestID) }
        inFlight = [:]
        images = [:]
    }
}

/// Large photo for the one-photo view. Prefetched photos appear on the same frame.
/// No skeleton, blurred preview or fade animation. A photo that was not prefetched appears as soon as it arrives.
struct LargeAssetImage: View {
    let asset: PHAsset
    @State private var loaded: Loaded?
    @State private var currentID = ""
    @State private var requestID: PHImageRequestID?

    private struct Loaded {
        let id: String
        let image: Image
    }

    /// Image of the current photo. Never shows the previous photo's image.
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
