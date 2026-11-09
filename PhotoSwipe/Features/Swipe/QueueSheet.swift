import SwiftUI
import Photos

/// 삭제 대기열 화면. 사진을 그리드로 보여주고, 전체삭제/전체복원을 한다.
/// 사진을 고르면 선택삭제/선택복원으로 바뀐다. 삭제는 시스템 확인창이 한 번 뜬다.
/// - iPhone: "선택"을 눌러 선택 모드로 들어가 사진을 누른다.
/// - Mac: 사진을 클릭하거나 방향키로 점선 칸을 옮겨 Enter로 선택/해제한다(여러 장 가능).
///   Delete = 선택삭제, Esc = 선택 해제(선택이 없으면 닫기).
struct QueueSheet: View {
    let session: SwipeSession
    @Environment(\.dismiss) private var dismiss
    @State private var assets: [PHAsset] = []
    @State private var totalBytes: Int64 = 0
    @State private var selecting = false
    @State private var selected: Set<String> = []
    @State private var focusedID: String?
    @FocusState private var focused: Bool

    private let tileSize: CGFloat = 100

    /// 선택 모드인가. Mac은 사진을 하나라도 고르면 자동으로 선택 모드다.
    private var isSelecting: Bool {
        #if os(macOS)
        selecting || !selected.isEmpty
        #else
        selecting
        #endif
    }

    /// 삭제/복원 대상. 선택 모드면 고른 사진, 아니면 전부.
    private var targets: [PHAsset] {
        isSelecting ? assets.filter { selected.contains($0.localIdentifier) } : assets
    }

    var body: some View {
        NavigationStack {
            Group {
                if assets.isEmpty {
                    ContentUnavailableView("The delete queue is empty", systemImage: "trash")
                } else {
                    VStack(spacing: 0) {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                        grid
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !assets.isEmpty { actionBar }
            }
            .navigationTitle("Delete Queue")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(selecting ? String(localized: "Done") : String(localized: "Select")) { toggleSelecting() }
                        .disabled(assets.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 520)
        #endif
        .onAppear {
            refresh()
            focused = true
        }
    }

    private var grid: some View {
        GeometryReader { proxy in
            let columns = max(1, Int(proxy.size.width / (tileSize + 2)))
            ScrollViewReader { reader in
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: tileSize), spacing: 2)], spacing: 2) {
                        ForEach(assets, id: \.localIdentifier) { cell($0).id($0.localIdentifier) }
                    }
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
                if let focusedID { toggle(focusedID) }
                return .handled
            }
            .onKeyPress(.delete) { deleteSelected(); return .handled }
            .onKeyPress(.deleteForward) { deleteSelected(); return .handled }
            .onKeyPress(.escape) { escape(); return .handled }
        }
    }

    private var summary: String {
        isSelecting
            ? String(localized: "\(selected.count) selected")
            : String(localized: "\(assets.count) photos · \(totalBytes.formatted(.byteCount(style: .file)))")
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button(isSelecting ? String(localized: "Restore Selected") : String(localized: "Restore All")) { restore(targets) }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            Button(isSelecting ? String(localized: "Delete Selected") : String(localized: "Delete All"), role: .destructive) { delete(targets) }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .disabled(targets.isEmpty)
        .padding()
        .background(.bar)
    }

    private func cell(_ asset: PHAsset) -> some View {
        let id = asset.localIdentifier
        let isSelected = selected.contains(id)
        return Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { AssetImageView(asset: asset, targetSize: CGSize(width: 300, height: 300), fill: true) }
            .clipped()
            .overlay {
                if isSelected { Color.accentColor.opacity(0.3) }
            }
            .overlay(alignment: .bottomTrailing) {
                if isSelecting {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .padding(6)
                }
            }
            .overlay {
                if id == focusedID {
                    Rectangle().strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [6, 4]))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                focusedID = id
                focused = true
                #if os(macOS)
                toggle(id)
                #else
                if selecting { toggle(id) }
                #endif
            }
    }

    private func toggle(_ id: String) {
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
    }

    private func move(_ delta: Int) {
        guard let index = assets.firstIndex(where: { $0.localIdentifier == focusedID }) else {
            focusedID = assets.first?.localIdentifier
            return
        }
        let next = index + delta
        guard assets.indices.contains(next) else { return }
        focusedID = assets[next].localIdentifier
    }

    /// Esc: 선택이 있으면 모두 해제, 없으면 창을 닫는다.
    private func escape() {
        if !selected.isEmpty {
            selected = []
            selecting = false
        } else {
            dismiss()
        }
    }

    /// Delete 키: 선택한 사진만 삭제한다(선택이 없으면 아무 일도 하지 않는다. 전체삭제는 버튼으로만).
    private func deleteSelected() {
        let chosen = assets.filter { selected.contains($0.localIdentifier) }
        guard !chosen.isEmpty else { return }
        delete(chosen)
    }

    private func toggleSelecting() {
        selecting.toggle()
        selected = []
    }

    private func delete(_ targets: [PHAsset]) {
        Task {
            await session.deleteQueued(targets)
            refresh()
            focused = true
        }
    }

    private func restore(_ targets: [PHAsset]) {
        session.restore(targets)
        refresh()
    }

    /// 목록과 총 용량을 다시 읽는다. 사라진 사진은 선택·점선에서 빼고, 비었으면 닫는다.
    private func refresh() {
        assets = session.queue.assets()
        totalBytes = assets.reduce(0) { $0 + DeletionQueue.byteSize(of: $1) }
        let remaining = Set(assets.map(\.localIdentifier))
        selected = selected.intersection(remaining)
        if let focusedID, !remaining.contains(focusedID) { self.focusedID = nil }
        if focusedID == nil { focusedID = assets.first?.localIdentifier }
        if assets.isEmpty { dismiss() }
    }
}
