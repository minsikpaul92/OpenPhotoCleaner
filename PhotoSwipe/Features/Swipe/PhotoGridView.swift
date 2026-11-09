import SwiftUI
import Photos

/// 메인 화면인 사진 그리드. 사진을 누르면(Mac은 방향키로 옮기고 Enter) 그 사진의 한 장 보기 창이 열린다.
/// 오른쪽 위 "삭제 대기(N개)"로 대기열 화면을 연다. 대기열 사진은 이 목록에서 숨겨져 있다.
struct PhotoGridView: View {
    let session: SwipeSession
    /// 한 장 보기 창이 닫혀 있고 이 화면이 맨 앞일 때 true. 키 입력은 이때만 받는다.
    let isActive: Bool
    let onOpen: (Int) -> Void
    @State private var selected: Int
    @State private var showQueue = false
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
            }
        }
        .sheet(isPresented: $showQueue) { QueueSheet(session: session) }
        .onAppear { focused = isActive }
        .onChange(of: isActive) {
            guard isActive else { return }
            selected = clamped(session.index)
            focused = true
        }
        .onChange(of: showQueue) { if !showQueue { focused = isActive } }
        .onChange(of: session.items.count) { selected = clamped(selected) }
        // 그리드에서 고른 칸도 마지막 위치로 저장해, 다시 열면 거기서 시작한다.
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
            .overlay {
                if index == selected {
                    Rectangle().strokeBorder(Color.accentColor, lineWidth: 3)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { open(index) }
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
