import SwiftUI
import Photos

/// Main screen: the photo grid. Tapping a photo (Mac: arrow keys then Enter) opens its one-photo window.
/// "Delete Queue (N)" at the top right opens the queue screen. Queued photos are hidden from this list.
struct PhotoGridView: View {
    let session: SwipeSession
    /// True when the one-photo window is closed and this screen is frontmost. Key input is only handled then.
    let isActive: Bool
    let onOpen: (Int) -> Void
    @State private var selected: Int
    @State private var showQueue = false
    @State private var showInfo = false
    @FocusState private var focused: Bool

    private let cellSize: CGFloat = 100
    private let spacing: CGFloat = 2

    init(session: SwipeSession, isActive: Bool, onOpen: @escaping (Int) -> Void) {
        self.session = session
        self.isActive = isActive
        self.onOpen = onOpen
        _selected = State(initialValue: session.index)
    }

    var body: some View {
        NavigationStack {
            Group {
                if session.items.isEmpty {
                    ContentUnavailableView("No Photos", systemImage: "photo")
                } else {
                    grid
                }
            }
            .navigationTitle("Photos")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Delete Queue (\(session.queue.count))") { showQueue = true }
                        .disabled(session.queue.count == 0)
                }
                ToolbarItem(placement: infoPlacement) {
                    #if os(macOS)
                    // While the photo window is open the toolbar's button explains the controls instead.
                    if isActive {
                        Button { showInfo = true } label: { Image(systemName: "info.circle") }
                            .accessibilityLabel("About")
                    } else {
                        Button { NotificationCenter.default.post(name: .showTutorial, object: nil) } label: { Image(systemName: "questionmark.circle") }
                            .accessibilityLabel("How to Sort Photos")
                    }
                    #else
                    Button { showInfo = true } label: { Image(systemName: "info.circle") }
                        .accessibilityLabel("About")
                    #endif
                }
            }
        }
        .sheet(isPresented: $showQueue) { QueueSheet(session: session) }
        .sheet(isPresented: $showInfo) { InfoSheet() }
        .onAppear { focused = isActive }
        .onChange(of: isActive) {
            guard isActive else { return }
            selected = clamped(session.index)
            focused = true
        }
        .onChange(of: showQueue) { if !showQueue { focused = isActive } }
        .onChange(of: session.items.count) { selected = clamped(selected) }
        // Also save the cell chosen in the grid as the last position, so the app resumes there.
        .onChange(of: selected) {
            if isActive { session.go(to: selected) }
        }
    }

    private var grid: some View {
        GeometryReader { proxy in
            let columns = max(1, Int(proxy.size.width / (cellSize + spacing)))
            ScrollViewReader { reader in
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns), spacing: spacing) {
                        ForEach(0..<session.items.count, id: \.self) { index in
                            cell(index).id(index)
                        }
                    }
                }
                .refreshable { session.reload() }
                .onAppear { reader.scrollTo(selected, anchor: .center) }
                .onChange(of: selected) { reader.scrollTo(selected) }
                .onChange(of: isActive) {
                    if isActive { reader.scrollTo(clamped(session.index), anchor: .center) }
                }
            }
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onKeyPress(.leftArrow) { move(-1); return .handled }
            .onKeyPress(.rightArrow) { move(1); return .handled }
            .onKeyPress(.upArrow) { move(-columns); return .handled }
            .onKeyPress(.downArrow) { move(columns); return .handled }
            .onKeyPress(.return) { open(selected); return .handled }
        }
    }

    private func cell(_ index: Int) -> some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                AssetImageView(asset: session.items[index], targetSize: CGSize(width: 300, height: 300), fill: true)
            }
            .clipped()
            .overlay(alignment: .topTrailing) {
                if session.isChecked(session.items[index]) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.white, .green)
                        .padding(4)
                        .accessibilityLabel("Reviewed")
                }
            }
            .overlay {
                if index == selected {
                    Rectangle().strokeBorder(Color.accentColor, lineWidth: 3)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { open(index) }
    }

    private var infoPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .navigation
        #endif
    }

    private func clamped(_ index: Int) -> Int {
        max(0, min(index, session.items.count - 1))
    }

    private func move(_ delta: Int) {
        guard isActive else { return }
        let next = selected + delta
        guard next >= 0, next < session.items.count else { return }
        selected = next
    }

    private func open(_ index: Int) {
        guard isActive, session.items.indices.contains(index) else { return }
        onOpen(index)
    }
}
