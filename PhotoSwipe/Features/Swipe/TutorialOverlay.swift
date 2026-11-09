import SwiftUI

/// Controls guide shown once on first launch.
struct TutorialOverlay: View {
    let onDismiss: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.65)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
            VStack(alignment: .leading, spacing: 14) {
                Text("How to Sort Photos")
                    .font(.title2.bold())
                row(.left, "Delete", "Moves it to the delete queue and hides it from the list")
                row(.right, "Keep", "Leave it as is and go to the next photo")
                row(.up, "Save to Album", "Saves to the target album right away (asks for one if none is set)")
                row(.down, "Show Grid", "Return to the photo grid")
                #if os(macOS)
                Divider()
                extra("1 ~ 0", "Save to the album with that number")
                extra("↑ ↑", "Open the album picker")
                extra("Esc", "Back to the grid")
                extra("⌘ Z", "Undo the last action")
                #else
                Divider()
                extra("Shake", "Undo the last action")
                #endif
                Button("Get Started", action: onDismiss)
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
            if press.key == .return || press.key == .escape || press.key == .space { onDismiss() }
            return .handled
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

    private func arrow(_ direction: SwipeDirection) -> String {
        switch direction {
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
