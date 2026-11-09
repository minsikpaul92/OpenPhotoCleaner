import SwiftUI

/// 앨범 선택 시트가 열린 이유.
enum AlbumPickerMode: Identifiable {
    /// 위로 올렸는데 대상 앨범이 없을 때. 고르면 현재 사진도 그 앨범에 추가한다.
    case addCurrent
    /// 떠 있는 칩을 눌렀거나 ↑를 두 번 눌렀을 때. 대상 앨범만 바꾼다.
    case changeTarget

    var id: Self { self }
}

/// 앨범을 그리드로 보여주고 대상 앨범을 고른다. 마우스 없이 키보드로 쓸 수 있다.
/// - 방향키: 칸 이동(점선 표시)  - Enter: 선택(이미 대상인 앨범이면 해제)
/// - 숫자키 1~9, 0: 점선 칸의 앨범에 번호 지정(덮어쓰기, 같은 번호를 다시 누르면 해제)
/// - +: 새 앨범  - Delete: 앨범 삭제(확인창)  - S: 최근 사용순/이름순 전환  - Esc: 닫기
/// 최근 사용순이면 마지막에 쓴 앨범(새로 만든 앨범 포함)이 맨 앞 칸이다.
struct AlbumPickerSheet: View {
    let session: SwipeSession
    let mode: AlbumPickerMode
    @Environment(\.dismiss) private var dismiss
    @State private var albums: [Album] = []
    @State private var focusedID: String?
    @State private var showNewAlbum = false
    @State private var newAlbumTitle = ""
    @State private var pendingDelete: Album?
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
                .onKeyPress(.delete) { requestDelete(); return .handled }
                .onKeyPress(.deleteForward) { requestDelete(); return .handled }
                // 키보드에 따라 Delete가 다른 문자로 올 수 있어 한 번 더 받는다.
                .onKeyPress(phases: .down) { press in
                    guard press.characters == "\u{7F}" || press.characters == "\u{8}" else { return .ignored }
                    requestDelete()
                    return .handled
                }
                .onKeyPress(characters: CharacterSet(charactersIn: "+="), phases: .down) { _ in
                    showNewAlbum = true
                    return .handled
                }
                .onKeyPress(characters: CharacterSet(charactersIn: "sS"), phases: .down) { _ in
                    toggleSort()
                    return .handled
                }
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
            // Mac 시트에서는 위쪽 도구줄이 보이지 않아, 아래에 직접 그린 버튼 줄을 둔다.
            .safeAreaInset(edge: .bottom) { macBar }
            #endif
            .alert("New Album", isPresented: $showNewAlbum) {
                TextField("Album name", text: $newAlbumTitle)
                Button("Create") { createAlbum() }
                Button("Cancel", role: .cancel) { newAlbumTitle = "" }
            } message: {
                Text("This only creates the album; it will not be set as the target.")
            }
            .alert(
                "Delete the album \"\(pendingDelete?.title ?? "")\"?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                presenting: pendingDelete
            ) { album in
                Button("Delete Album", role: .destructive) { deleteAlbum(album) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Only the album is deleted. Its photos stay in your library.")
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
        .onChange(of: pendingDelete?.id) { focused = true }
    }

    #if os(macOS)
    /// Mac용 아래쪽 버튼 줄. 키 안내와 정렬·앨범 삭제·새 앨범·닫기 버튼.
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
                Button("Delete Album", role: .destructive) { pendingDelete = album }
            }
        }
    }

    /// 목록을 다시 읽는다. `id`가 아직 있으면 거기에, 없으면 대상 앨범이나 첫 칸에 점선을 둔다.
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

    /// 정렬을 바꾸고, 점선 칸은 같은 앨범에 그대로 둔다.
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

    /// 선택한다. 이미 대상인 앨범을 다시 고르면 대상을 해제한다.
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

    private func requestDelete() {
        guard let album = focusedAlbum, !album.isPlaceholder else { return }
        pendingDelete = album
    }

    private func deleteAlbum(_ album: Album) {
        Task {
            await session.deleteAlbum(album)
            reload()
        }
    }

    /// 새 앨범을 만든다. 선택은 하지 않고 선택창도 닫지 않는다. 새 앨범 칸에 점선만 둔다.
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
