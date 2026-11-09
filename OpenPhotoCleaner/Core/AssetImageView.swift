import SwiftUI
import Photos

/// Loads and shows one PHAsset. A low-quality image appears first and is replaced by the high-quality one.
/// When `fill` is true it fills its cell, for thumbnails (the caller clips the overflow).
struct AssetImageView: View {
    let asset: PHAsset
    var targetSize = CGSize(width: 1600, height: 1600)
    var fill = false
    @State private var image: Image?
    @State private var requestID: PHImageRequestID?

    var body: some View {
        ZStack {
            if let image {
                image.resizable().aspectRatio(contentMode: fill ? .fill : .fit)
            }
        }
        .onAppear(perform: load)
        .onChange(of: asset.cacheKey) { load() }
        .onDisappear(perform: cancel)
    }

    private func load() {
        cancel()
        image = nil
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        requestID = PHImageManager.default().requestImage(for: asset, targetSize: targetSize, contentMode: fill ? .aspectFill : .aspectFit, options: options) { platformImage, _ in
            guard let platformImage else { return }
            image = Image(platform: platformImage)
        }
    }

    private func cancel() {
        if let requestID { PHImageManager.default().cancelImageRequest(requestID) }
        requestID = nil
    }
}
