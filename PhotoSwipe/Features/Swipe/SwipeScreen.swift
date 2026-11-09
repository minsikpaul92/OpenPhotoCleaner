import SwiftUI
import Photos

/// One-photo window shown above the grid.
/// Controlled by four-way swipes on iPhone and the four arrow keys on Mac. Down closes the window and returns to the grid.
/// Mac only: number key = save straight to the numbered album, ↑ twice = album picker, Esc = back to the grid.
struct SwipeScreen: View {
    let session: SwipeSession
    /// True while the tutorial is shown on top. Key input resumes when it closes.
    let isBlocked: Bool
    let onClose: () -> Void
    @State private var drag: CGSize = .zero
    @State private var isAnimating = false
    @State private var fading = false
    @State private var albumPicker: AlbumPickerMode?
    @State private var isClosing = false
    @State private var pendingUp: Task<Void, Never>?
    @State private var toast: String?
    @FocusState private var focused: Bool

    private let threshold: CGFloat = 100
    /// How long a single ↑ waits to tell whether a second ↑ follows.
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
        .onReceive(NotificationCenter.default.publisher(for: .undoRequested)) { _ in performUndo() }
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
        // Delete = same as ← (delete queue), Return = same as → (keep).
        .onDeleteKey { perform(.left) }
        .onKeyPress(.return) { perform(.right); return .handled }
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
                    // Receive swipes over the whole area, whatever the photo's shape.
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(dragGesture(size: proxy.size))
                    // The photo lets touches through (the swipe area below receives them); only the album chips are tappable.
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
                        .opacity(fading ? 0 : 1)
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

    /// Target album chip. Tap it to pick another album. Hidden while swiping.
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
    /// List of numbered albums. Pressing the number key saves straight to that album.
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

    // Temporary previous button. To be replaced by undo.
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
        // Use global coordinates: measuring in the moving view's own space compounds the translation.
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

    /// For arrow keys. Uses a rough screen size to know how far the card flies off.
    private func perform(_ direction: SwipeDirection) {
        guard !isAnimating else { return }
        commit(direction, size: CGSize(width: 600, height: 800))
    }

    /// ↑ key. Without a target album, open the picker right away. With one, wait briefly: a second ↑ opens the picker, otherwise add to the target.
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

    /// Number key. Adds the current photo to that number's album right away and moves on.
    private func quickAdd(_ characters: String) {
        guard let digit = characters.first.map(String.init), session.current != nil else { return }
        switch session.toggleCurrent(toSlot: digit) {
        case .added(let album): showToast(String(localized: "\(digit) · Added to \(album.title)"))
        case .removed(let album): showToast(String(localized: "\(digit) · Removed from \(album.title)"))
        case .none: showToast(String(localized: "No album assigned to \(digit)"))
        }
    }

    /// Prefetches around the current photo (see PhotoLoader.ahead / behind).
    private func prefetch() {
        PhotoLoader.shared.prefetch(session.items, around: session.index)
    }

    /// Undo from ⌘Z (Mac menu) or a shake (iPhone). Ignored while a sheet or animation is up.
    private func performUndo() {
        guard albumPicker == nil, !isAnimating else { return }
        Task { showToast(await session.undo() ?? String(localized: "Nothing to undo")) }
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
            // Saving to an album (up) is the most frequent move: a shorter, fading flight feels quicker.
            let isUp = direction == .up
            withAnimation(.easeOut(duration: isUp ? 0.12 : 0.18)) {
                drag = direction.offscreenOffset(in: size)
                if isUp { fading = true }
            } completion: {
                apply(direction)
                var reset = Transaction()
                reset.disablesAnimations = true
                withTransaction(reset) {
                    drag = .zero
                    fading = false
                }
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

    /// If the queue is not empty, show the system delete confirmation right away. Deleting closes; "Don't Allow" keeps the queue and closes.
    /// Stays open only if deletion failed. Closes immediately when the queue is empty.
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

extension Notification.Name {
    /// Posted by the Mac Undo menu command (⌘Z) and by a shake on iPhone; the card view performs the undo.
    static let undoRequested = Notification.Name("undoRequested")
}
