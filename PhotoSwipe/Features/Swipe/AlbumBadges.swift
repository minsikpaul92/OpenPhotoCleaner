import SwiftUI
import Photos

/// 이 사진이 이미 들어 있는 앨범 칩. 사진 왼쪽 위에 겹쳐 놓는다.
/// 칩을 누르면 그 앨범에서 사진을 뺀다(화면은 그대로 두므로, 이어서 유지/삭제/다른 앨범을 고르면 된다).
struct AlbumBadges: View {
    let asset: PHAsset
    let session: SwipeSession
    let onRemove: (Album) -> Void
    @State private var loaded: Loaded?

    private struct Loaded {
        let id: String
        let albums: [Album]
    }

    private let maxShown = 3

    /// 예전 사진의 앨범은 보여주지 않는다.
    private var albums: [Album] {
        guard let loaded, loaded.id == asset.localIdentifier else { return [] }
        return loaded.albums
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(albums.prefix(maxShown)) { album in
                Button { onRemove(album) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.fill")
                        Text(album.title).lineLimit(1)
                        Image(systemName: "xmark").font(.caption2.weight(.bold))
                    }
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            if albums.count > maxShown {
                Text("+\(albums.count - maxShown)")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: Capsule())
            }
        }
        .padding(8)
        .task(id: "\(asset.localIdentifier)|\(session.albumsVersion)") {
            loaded = Loaded(id: asset.localIdentifier, albums: session.albums.albums(containing: asset))
        }
    }
}
