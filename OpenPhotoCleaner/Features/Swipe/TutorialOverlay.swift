import SwiftUI

/// Controls guide shown once on first launch.
struct TutorialOverlay: View {
    let onDismiss: () -> Void
    @FocusState private var focused: Bool
    @State private var page = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.65)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
            VStack(alignment: .leading, spacing: 14) {
                Text("How to Sort Photos")
                    .font(.title2.bold())
                if page == 0 { firstPage } else { secondPage }
                Button(page == 0 ? "Next" : "Get Started", action: next)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(24)
            .frame(maxWidth: 440)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(24)
        }
        // Swallow all keys so the photo behind does not react while the guide is shown.
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        .onKeyPress { press in
            if press.key == .escape { onDismiss() }
            if press.key == .return || press.key == .space { next() }
            return .handled
        }
    }

    private func next() {
        if page == 0 { page = 1 } else { onDismiss() }
    }

    @ViewBuilder private var firstPage: some View {
        row(.left, "Delete", "Moves it to the delete queue and hides it from the list")
        row(.right, "Keep", "Leave it as is and go to the next photo")
        row(.up, "Save to Album", "Saves to the chosen album right away (asks for one if none is chosen)")
        row(.down, "Show Grid", "Return to the photo grid")
        if Platform.desktopStyle {
            Divider()
            extra("1 ~ 0", "Save to the album with that number")
            extra("⌫ / ↩", "Delete / Keep, same as ← / →")
            extra("A", "Open the album picker")
            extra("R", "Rotate 90°")
            extra("Esc", "Back to the grid")
            extra("⌘ Z", "Undo the last action")
            #if os(iOS)
            extra("↔", "By touch: swipe right to Delete, left to Keep")
            #endif
        }
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom != .pad {
            Divider()
            extra("Shake", "Undo the last action")
        }
        #endif
    }

    @ViewBuilder private var secondPage: some View {
        row(.down, "Show Grid", "If photos are waiting in the delete queue, you can delete them all at once or leave them in the queue to decide later")
        HStack(spacing: 12) {
            Image(systemName: "folder")
                .font(.title3.weight(.bold))
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("Album Button").font(.headline)
                Text("Tap the album name above the photo to choose an album, sort (recent or by name) and add a new one. Press and hold an album to delete it.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ direction: SwipeDirection, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            Image(systemName: arrow(direction))
                .font(.title3.weight(.bold))
                .foregroundStyle(direction.color)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func extra(_ keys: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            Text(keys)
                .font(.callout.weight(.semibold).monospaced())
                .frame(width: 56, alignment: .leading)
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    /// Touch devices swipe the other way (drag right = Delete), so iPhone shows the swipe arrow, not the key arrow.
    private func arrow(_ direction: SwipeDirection) -> String {
        switch Platform.desktopStyle ? direction : direction.mirroredHorizontally {
        case .left: "arrow.left"
        case .right: "arrow.right"
        case .up: "arrow.up"
        case .down: "arrow.down"
        }
    }
}

/// On Mac an arrow key acts instantly so a drag hint never shows, so the left/right hints are always visible.
/// Placed in the middle of the empty margins beside the photo (just inside the edge when the photo nearly fills the width).
struct EdgeHints: View {
    /// Size of the area showing the photo.
    let container: CGSize
    /// The photo's width / height ratio.
    let imageAspect: CGFloat

    var body: some View {
        let imageWidth = min(container.width, container.height * imageAspect)
        let margin = max(0, (container.width - imageWidth) / 2)
        let centerX = max(margin / 2, 50)
        ZStack {
            HStack(spacing: 6) {
                Image(systemName: "arrow.left")
                Text("Delete")
            }
            .foregroundStyle(SwipeDirection.left.color)
            .position(x: centerX, y: container.height / 2)
            HStack(spacing: 6) {
                Text("Keep")
                Image(systemName: "arrow.right")
            }
            .foregroundStyle(SwipeDirection.right.color)
            .position(x: container.width - centerX, y: container.height / 2)
        }
        .font(.title3.weight(.semibold))
        .frame(width: container.width, height: container.height)
        .allowsHitTesting(false)
    }
}
