import SwiftUI
import Photos

/// PHAsset 한 장을 불러와 보여준다. 저화질이 먼저 보이고 고화질로 교체된다.
/// `fill`이 true면 칸을 가득 채우는 썸네일용(넘치는 부분은 호출한 쪽에서 잘라낸다).
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
        .onChange(of: asset.localIdentifier) { load() }
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
            #if canImport(UIKit)
            image = Image(uiImage: platformImage)
            #else
            image = Image(nsImage: platformImage)
            #endif
        }
    }

    private func cancel() {
        if let requestID { PHImageManager.default().cancelImageRequest(requestID) }
        requestID = nil
    }
}
