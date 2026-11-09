import SwiftUI

/// 처음 실행할 때 한 번 보여주는 조작 안내.
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
        // 안내가 떠 있는 동안 뒤의 사진이 키 입력에 반응하지 않게 키를 모두 받는다.
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

    private func extra(_ keys: String, _ detail: LocalizedStringKey) -> some View {
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

/// Mac은 방향키를 누르면 바로 끝나서 드래그 힌트가 안 보이므로, 왼쪽/오른쪽 안내를 항상 보여준다.
/// 사진 양옆 빈 여백의 한가운데에 놓는다(사진이 화면 폭을 거의 채우면 가장자리에서 조금만 들어온다).
struct EdgeHints: View {
    /// 사진을 보여주는 영역의 크기.
    let container: CGSize
    /// 사진의 가로/세로 비율.
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
