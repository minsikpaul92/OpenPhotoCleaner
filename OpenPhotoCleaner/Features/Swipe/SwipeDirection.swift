import SwiftUI

/// The four directions shared by swipes (iPhone) and arrow keys (Mac).
enum SwipeDirection: CaseIterable {
    case left, right, up, down

    /// Direction of the larger drag component; nil if there was no movement.
    init?(translation: CGSize) {
        guard translation != .zero else { return nil }
        if abs(translation.width) >= abs(translation.height) {
            self = translation.width < 0 ? .left : .right
        } else {
            self = translation.height < 0 ? .up : .down
        }
    }

    /// The action of a touch swipe. The card is pushed toward one side and the action whose hint sits on the
    /// opposite (revealed) side runs: drag left = Keep (hint on the right), drag right = Delete (hint on the left).
    /// Up and down are unchanged. Keys are not affected: ← is still Delete, → is still Keep.
    init?(swipe translation: CGSize) {
        guard let moved = SwipeDirection(translation: translation) else { return nil }
        self = moved.mirroredHorizontally
    }

    /// Left and right swapped; up and down unchanged.
    var mirroredHorizontally: SwipeDirection {
        switch self {
        case .left: .right
        case .right: .left
        case .up, .down: self
        }
    }

    /// Up is "Add to <album>" with a target album, otherwise "Choose Album".
    func label(target: Album?) -> String {
        switch self {
        case .left: String(localized: "Delete")
        case .right: String(localized: "Keep")
        case .up: target.map { String(localized: "Add to \($0.title)") } ?? String(localized: "Choose Album")
        case .down: String(localized: "Back to Grid")
        }
    }

    func symbol(hasTarget: Bool) -> String {
        switch self {
        case .left: "trash"
        case .right: "checkmark"
        case .up: hasTarget ? "folder.badge.plus" : "folder"
        case .down: "square.grid.3x3"
        }
    }

    var color: Color {
        switch self {
        case .left: .red
        case .right: .green
        case .up: .blue
        case .down: .indigo
        }
    }

    var alignment: Alignment {
        switch self {
        case .left: .leading
        case .right: .trailing
        case .up: .top
        case .down: .bottom
        }
    }

    /// Whether the card flies off screen and the next photo follows.
    func advances(hasTarget: Bool) -> Bool {
        switch self {
        case .left, .right: true
        case .up: hasTarget
        case .down: false
        }
    }

    func offscreenOffset(in size: CGSize) -> CGSize {
        switch self {
        case .left: CGSize(width: -size.width * 1.3, height: 0)
        case .right: CGSize(width: size.width * 1.3, height: 0)
        case .up: CGSize(width: 0, height: -size.height * 0.6)
        case .down: CGSize(width: 0, height: size.height * 1.3)
        }
    }
}

/// Light per-direction hint shown while dragging.
struct SwipeHintOverlay: View {
    let drag: CGSize
    let threshold: CGFloat
    let target: Album?

    var body: some View {
        ZStack {
            ForEach(SwipeDirection.allCases, id: \.self) { direction in
                Label(direction.label(target: target), systemImage: direction.symbol(hasTarget: target != nil))
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(direction.color)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.thinMaterial, in: Capsule())
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: direction.alignment)
                    .opacity(opacity(for: direction))
            }
        }
        .allowsHitTesting(false)
    }

    private func opacity(for direction: SwipeDirection) -> Double {
        guard SwipeDirection(swipe: drag) == direction else { return 0 }
        return min(Double(hypot(drag.width, drag.height) / threshold), 1)
    }
}
