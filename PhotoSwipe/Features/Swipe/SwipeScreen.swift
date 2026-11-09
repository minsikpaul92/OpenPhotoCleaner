import SwiftUI
import Photos

/// 그리드 위에 띄우는 사진 한 장 보기 창.
/// iPhone은 4방향 스와이프, Mac은 방향키 4방향으로 조작한다. 아래는 창을 닫고 그리드로 돌아간다.
/// Mac 전용: 숫자키 = 번호 앨범에 바로 저장, ↑ 두 번 = 앨범 선택창, Esc = 그리드로.
struct SwipeScreen: View {
    let session: SwipeSession
    /// 튜토리얼이 위에 떠 있는 동안 true. 닫히면 키 입력을 다시 받는다.
    let isBlocked: Bool
    let onClose: () -> Void
    @State private var drag: CGSize = .zero
    @State private var isAnimating = false
    @State private var albumPicker: AlbumPickerMode?
    @State private var isClosing = false
    @State private var pendingUp: Task<Void, Never>?
    @State private var toast: String?
    @FocusState private var focused: Bool

    private let threshold: CGFloat = 100
    /// ↑를 두 번 눌렀는지 가리려고 한 번 눌렀을 때 기다리는 시간.
    private let doubleUpWindow: Duration = .milliseconds(300)

    var body: some View {
        VStack(spacing: 0) {
            card
            #if os(macOS)
            favoritesLegend
            #endif
            controls
        }
        #if os(macOS)
        .environment(\.colorScheme, .dark)
        .background(Color.black)
        #else
        .background(.background)
        #endif
        .overlay(alignment: .top) { toastView }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear {
            focused = true
            prefetch()
        }
        .onDisappear { PhotoLoader.shared.stop() }
        .onChange(of: session.index) { prefetch() }
        .onChange(of: session.items.count) { prefetch() }
        .onKeyPress(.leftArrow) { perform(.left); return .handled }
        .onKeyPress(.rightArrow) { perform(.right); return .handled }
        .onKeyPress(.upArrow, phases: .down) { _ in handleUp(); return .handled }
        .onKeyPress(.downArrow) { perform(.down); return .handled }
        .onKeyPress(.escape) { requestClose(); return .handled }
        .onKeyPress(characters: .decimalDigits, phases: .down) { press in
            quickAdd(press.characters)
            return .handled
        }
        .sheet(item: $albumPicker) { mode in
            AlbumPickerSheet(session: session, mode: mode)
        }
        .onChange(of: albumPicker?.id) { focused = true }
        .onChange(of: isBlocked) { if !isBlocked { focused = true } }
    }

    @ViewBuilder
    private var card: some View {
        GeometryReader { proxy in
            if let asset = session.current {
                ZStack {
                    // 사진 모양과 상관없이 영역 전체에서 스와이프를 받는다.
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(dragGesture(size: proxy.size))
                    // 사진은 터치를 통과시키고(아래 스와이프 영역이 받음), 앨범 칩만 눌린다.
                    LargeAssetImage(asset: asset)
                        .allowsHitTesting(false)
                        .overlay(alignment: .topLeading) {
                            AlbumBadges(asset: asset, session: session) { album in
                                session.remove(asset, from: album)
                                showToast(String(localized: "Removed from \(album.title)"))
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .offset(drag)
                        .rotationEffect(.degrees(Double(drag.width) / 40))
                    #if os(macOS)
                    EdgeHints(
                        container: proxy.size,
                        imageAspect: CGFloat(asset.pixelWidth) / CGFloat(max(asset.pixelHeight, 1))
                    )
                    #endif
                    SwipeHintOverlay(drag: drag, threshold: threshold, target: session.target)
                    targetChip
                }
            } else {
                ContentUnavailableView {
                    Label("All Reviewed", systemImage: "checkmark.circle")
                } actions: {
                    if session.canGoBack {
                        Button("Previous Photo") { session.previous() }
                    }
                    Button("Back to Grid") { requestClose() }
                }
            }
        }
    }

    /// 대상 앨범 이름 칩. 누르면 다른 앨범을 고를 수 있다. 스와이프하는 동안에는 숨긴다.
    @ViewBuilder
    private var targetChip: some View {
        if let target = session.target {
            Button { albumPicker = .changeTarget } label: {
                Label(target.title, systemImage: "folder")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .opacity(drag == .zero ? 1 : 0)
            .allowsHitTesting(drag == .zero)
        }
    }

    #if os(macOS)
    /// 번호를 지정한 앨범 목록. 숫자키를 누르면 그 앨범에 바로 저장된다.
    private var favoritesLegend: some View {
        let entries = AlbumLibrary.slotKeys.compactMap { digit in
            session.albums.slotTitles[digit].map { (digit: digit, title: $0) }
        }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if entries.isEmpty {
                    Text("No numbered albums · press ↑↑ to open the album picker, then press a number key on a tile")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entries, id: \.digit) { entry in
                        HStack(spacing: 6) {
                            Text(entry.digit)
                                .font(.caption.weight(.bold).monospacedDigit())
                                .frame(width: 18, height: 18)
                                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 5))
                            Text(entry.title).lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.thinMaterial, in: Capsule())
                    }
                }
            }
            .font(.footnote)
            .padding(.horizontal, 16)
        }
        .frame(height: 34)
    }
    #endif

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            Text(toast)
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(.thinMaterial, in: Capsule())
                .padding(.top, 150)
                .transition(.opacity)
                .allowsHitTesting(false)
        }
    }

    // 임시 이전 버튼. 6단계에서 되돌리기로 대체한다.
    private var controls: some View {
        HStack {
            Button { session.previous() } label: { Image(systemName: "chevron.left") }
                .disabled(!session.canGoBack)
            Spacer()
            Text("\(min(session.index + 1, session.count)) / \(session.count)")
                .font(.footnote.monospacedDigit())
            Spacer()
            Label("\(session.queue.count)", systemImage: "trash")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private func dragGesture(size: CGSize) -> some Gesture {
        // 움직이는 뷰 자신의 좌표로 재면 이동량이 겹쳐 커지므로 화면 좌표를 쓴다.
        DragGesture(coordinateSpace: .global)
            .onChanged { value in
                guard !isAnimating else { return }
                drag = value.translation
            }
            .onEnded { value in
                guard !isAnimating else { return }
                let distance = hypot(value.translation.width, value.translation.height)
                if distance >= threshold, let direction = SwipeDirection(translation: value.translation) {
                    commit(direction, size: size)
                } else {
                    withAnimation(.spring) { drag = .zero }
                }
            }
    }

    /// 방향키용. 카드가 날아가는 거리를 알기 위해 대략적인 화면 크기를 쓴다.
    private func perform(_ direction: SwipeDirection) {
        guard !isAnimating else { return }
        commit(direction, size: CGSize(width: 600, height: 800))
    }

    /// ↑ 키. 대상 앨범이 없으면 바로 선택창. 있으면 잠깐 기다려서, 그 안에 한 번 더 누르면 선택창, 아니면 추가한다.
    private func handleUp() {
        guard !isAnimating else { return }
        if let waiting = pendingUp {
            waiting.cancel()
            pendingUp = nil
            albumPicker = .changeTarget
            return
        }
        guard session.target != nil else {
            perform(.up)
            return
        }
        pendingUp = Task {
            try? await Task.sleep(for: doubleUpWindow)
            guard !Task.isCancelled else { return }
            pendingUp = nil
            perform(.up)
        }
    }

    /// 숫자키. 그 번호의 앨범에 현재 사진을 바로 추가하고 다음 사진으로 넘어간다.
    private func quickAdd(_ characters: String) {
        guard let digit = characters.first.map(String.init), session.current != nil else { return }
        switch session.toggleCurrent(toSlot: digit) {
        case .added(let album): showToast(String(localized: "\(digit) · Added to \(album.title)"))
        case .removed(let album): showToast(String(localized: "\(digit) · Removed from \(album.title)"))
        case .none: showToast(String(localized: "No album assigned to \(digit)"))
        }
    }

    /// 지금 사진 앞뒤를 미리 읽어 둔다(진행 방향 20장, 반대쪽 10장).
    private func prefetch() {
        PhotoLoader.shared.prefetch(session.items, around: session.index)
    }

    private func showToast(_ text: String) {
        toast = text
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            if toast == text { toast = nil }
        }
    }

    private func commit(_ direction: SwipeDirection, size: CGSize) {
        if direction.advances(hasTarget: session.target != nil) {
            isAnimating = true
            withAnimation(.easeOut(duration: 0.18)) {
                drag = direction.offscreenOffset(in: size)
            } completion: {
                apply(direction)
                drag = .zero
                isAnimating = false
            }
        } else {
            apply(direction)
            withAnimation(.spring) { drag = .zero }
        }
    }

    private func apply(_ direction: SwipeDirection) {
        switch direction {
        case .left:
            session.trash()
        case .right:
            session.keep()
        case .up:
            if let target = session.target {
                session.addCurrent(to: target)
            } else {
                albumPicker = .addCurrent
            }
        case .down:
            requestClose()
        }
    }

    /// 대기열에 사진이 있으면 시스템 삭제 확인창을 바로 띄운다. 삭제하면 닫고, "허용 안 함"이면 대기열에 유지한 채 닫는다.
    /// 삭제에 실패했을 때만 창에 남는다. 대기열이 비어 있으면 바로 닫는다.
    private func requestClose() {
        guard !isClosing else { return }
        guard session.queue.count > 0 else {
            onClose()
            return
        }
        isClosing = true
        Task {
            let result = await session.deleteAllQueued()
            isClosing = false
            if result != .failed { onClose() }
        }
    }
}
