import SwiftUI
import Photos

/// Chips for the albums this photo is already in, overlaid at the photo's top left.
/// Tapping a chip removes the photo from that album. The card stays, so you can then keep, delete or pick another album.
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

    /// Never shows albums of a previous photo.
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
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Remove from \(album.title)"))
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
