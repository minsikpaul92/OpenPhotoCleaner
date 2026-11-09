import SwiftUI
import Photos

/// Deletion queue screen. Shows the photos as a grid with Delete All / Restore All.
/// Selecting photos switches it to Delete Selected / Restore Selected. Deleting shows one system confirmation.
/// - iPhone: tap "Select" to enter selection mode, then tap photos.
/// - Mac: click a photo, or move the dashed cell with the arrow keys and press Enter, to toggle it (several allowed).
///   Delete = delete selected, Esc = clear the selection (closes when nothing is selected).
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

    /// Whether selection mode is on. On Mac and iPad it turns on automatically as soon as one photo is selected.
    private var isSelecting: Bool {
        Platform.desktopStyle ? (selecting || !selected.isEmpty) : selecting
    }

    /// Target of delete/restore: the selected photos in selection mode, otherwise all.
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
            .onDeleteKey { deleteSelected() }
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
                if Platform.desktopStyle || selecting { toggle(id) }
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

    /// Esc: clears the selection if there is one, otherwise closes the sheet.
    private func escape() {
        if !selected.isEmpty {
            selected = []
            selecting = false
        } else {
            dismiss()
        }
    }

    /// Delete key: deletes only the selected photos (does nothing with no selection; Delete All is button-only).
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

    /// Reloads the list and total size. Drops vanished photos from the selection and focus, and closes when empty.
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
