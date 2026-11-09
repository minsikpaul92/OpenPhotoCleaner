import SwiftUI

/// Why the album picker sheet was opened.
enum AlbumPickerMode: Identifiable {
    /// Swiped up with no target album. Picking an album also adds the current photo to it.
    case addCurrent
    /// The floating chip was tapped or ↑ was pressed twice. Only changes the target album.
    case changeTarget

    var id: Self { self }
}

/// Shows albums as a grid and picks the target album. Fully usable from the keyboard.
/// - Arrow keys: move the dashed cell  - Enter: select (clears the target if it is already the target)
/// - Number keys 1-9, 0: assign that number to the dashed album (overwrites; the same key again clears it)
/// - +: new album  - Delete: delete album (confirmation)  - S: toggle recently-used / by-name  - Esc: close
/// In recently-used order the last used album (including a new one) is the first cell.
struct AlbumPickerSheet: View {
    let session: SwipeSession
    let mode: AlbumPickerMode
    @Environment(\.dismiss) private var dismiss
    @State private var albums: [Album] = []
    @State private var focusedID: String?
    @State private var showNewAlbum = false
    @State private var newAlbumTitle = ""
    @FocusState private var focused: Bool

    private let tileWidth: CGFloat = 120
    private let spacing: CGFloat = 12
    private var addCurrent: Bool { mode == .addCurrent }
    private var focusedAlbum: Album? { albums.first { $0.id == focusedID } }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let columns = max(1, Int((proxy.size.width - 32 + spacing) / (tileWidth + spacing)))
                ScrollViewReader { reader in
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns), spacing: spacing) {
                            ForEach(albums) { album in
                                tile(album).id(album.id)
                            }
                        }
                        .padding(16)
                    }
                    .onChange(of: focusedID) {
                        if let focusedID { reader.scrollTo(focusedID) }
                    }
                }
                .focusable()
                .focused($focused)
                .focusEffectDisabled()
                .onKeyPress(.leftArrow) { move(-1); return .handled }
                .onKeyPress(.rightArrow) { move(1); return .handled }
                .onKeyPress(.upArrow) { move(-columns); return .handled }
                .onKeyPress(.downArrow) { move(columns); return .handled }
                .onKeyPress(.return) {
                    if let album = focusedAlbum { pick(album) }
                    return .handled
                }
                .onDeleteKey { requestDelete() }
                .onKeyPress(characters: CharacterSet(charactersIn: "+="), phases: .down) { _ in
                    showNewAlbum = true
                    return .handled
                }
                .onKeyPress(characters: .sortKey, phases: .down) { _ in
                    toggleSort()
                    return .handled
                }
                #if os(macOS)
                .onPhysicalKey(PhysicalKeyCode.s, enabled: !showNewAlbum) { toggleSort() }
                #endif
                .onKeyPress(characters: .decimalDigits, phases: .down) { press in
                    if let digit = press.characters.first.map(String.init), let album = focusedAlbum {
                        Task { await assignSlot(digit, to: album) }
                    }
                    return .handled
                }
            }
            .navigationTitle(addCurrent ? String(localized: "Choose Album") : String(localized: "Target Album"))
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #if !os(macOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(session.albums.sortsByName ? String(localized: "By Name") : String(localized: "Recently Used"), systemImage: "arrow.up.arrow.down") {
                        toggleSort()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("New Album", systemImage: "plus") { showNewAlbum = true }
                }
            }
            #else
            // The toolbar is not visible in Mac sheets, so draw a bottom button bar ourselves.
            .safeAreaInset(edge: .bottom) { macBar }
            #endif
            .alert("New Album", isPresented: $showNewAlbum) {
                TextField("Album name", text: $newAlbumTitle)
                Button("Create") { createAlbum() }
                Button("Cancel", role: .cancel) { newAlbumTitle = "" }
            } message: {
                Text("This only creates the album; it will not be set as the target.")
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 480)
        #endif
        .onAppear {
            reload()
            focused = true
        }
        .onChange(of: showNewAlbum) { focused = true }
    }

    #if os(macOS)
    /// Bottom button bar for Mac: key legend plus sort, delete album, new album and close buttons.
    private var macBar: some View {
        VStack(spacing: 8) {
            Text("← → ↑ ↓ Move  ·  Enter Select  ·  1–0 Number  ·  + New Album  ·  ⌫ Delete  ·  S Sort  ·  Esc Close")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button(session.albums.sortsByName ? String(localized: "By Name") : String(localized: "Recently Used"), systemImage: "arrow.up.arrow.down") {
                    toggleSort()
                }
                Spacer()
                Button("Delete Album", systemImage: "trash", role: .destructive) { requestDelete() }
                    .disabled(focusedAlbum == nil || focusedAlbum?.isPlaceholder == true)
                Button("New Album", systemImage: "plus") { showNewAlbum = true }
                Button("Close") { dismiss() }
            }
        }
        .padding(12)
        .background(.bar)
    }
    #endif

    private func tile(_ album: Album) -> some View {
        let isTarget = album.id == session.target?.id
        let isFocused = album.id == focusedID
        let slot = session.albums.slot(of: album)
        return VStack(spacing: 8) {
            Image(systemName: "rectangle.stack")
                .font(.title)
                .foregroundStyle(.tint)
            Text(album.title)
                .font(.subheadline)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 96)
        .padding(8)
        .background(isTarget ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .topLeading) {
            if let slot {
                Text(slot)
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 6))
                    .padding(6)
            }
        }
        .overlay(alignment: .topTrailing) {
            if isTarget {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
                    .padding(6)
            }
        }
        .overlay {
            if isFocused {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, dash: [6, 4]))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            focusedID = album.id
            pick(album)
        }
        .contextMenu {
            if !album.isPlaceholder {
                Button("Delete Album", role: .destructive) { deleteAlbum(album) }
            }
        }
    }

    /// Reloads the list. Puts the dashed cell on `id` if it still exists, otherwise on the target album or the first cell.
    private func reload(keeping id: String? = nil) {
        albums = session.albums.albums()
        if let id, albums.contains(where: { $0.id == id }) {
            focusedID = id
        } else if let targetID = session.target?.id, albums.contains(where: { $0.id == targetID }) {
            focusedID = targetID
        } else {
            focusedID = albums.first?.id
        }
    }

    /// Changes the sort order and keeps the dashed cell on the same album.
    private func toggleSort() {
        session.albums.toggleSort()
        reload(keeping: focusedID)
    }

    private func move(_ delta: Int) {
        guard let index = albums.firstIndex(where: { $0.id == focusedID }) else {
            focusedID = albums.first?.id
            return
        }
        let next = index + delta
        guard albums.indices.contains(next) else { return }
        focusedID = albums[next].id
    }

    /// Selects. Choosing the album that is already the target clears the target.
    private func pick(_ album: Album) {
        dismiss()
        if mode == .changeTarget, session.target?.id == album.id {
            session.clearTarget()
        } else {
            Task { await session.select(album, addCurrent: addCurrent) }
        }
    }

    private func assignSlot(_ digit: String, to album: Album) async {
        do {
            let resolved = try await session.albums.resolve(album)
            session.albums.toggleSlot(digit, for: resolved)
            reload(keeping: resolved.id)
        } catch {
            session.lastError = error.localizedDescription
        }
    }

    /// Delete key / button: deletes the album under the dashed cell. The system asks for confirmation, so there is no extra prompt.
    private func requestDelete() {
        guard let album = focusedAlbum, !album.isPlaceholder else { return }
        deleteAlbum(album)
    }

    private func deleteAlbum(_ album: Album) {
        Task {
            await session.deleteAlbum(album)
            reload()
            focused = true
        }
    }

    /// Creates a new album. It does not select it or close the sheet; only the dashed cell moves to it.
    private func createAlbum() {
        let title = newAlbumTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        newAlbumTitle = ""
        guard !title.isEmpty else { return }
        Task {
            if let album = await session.createAlbum(title: title) {
                reload(keeping: album.id)
            }
        }
    }
}
