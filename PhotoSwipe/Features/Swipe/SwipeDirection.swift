import SwiftUI

/// 스와이프(iPhone)와 방향키(Mac)가 공유하는 4방향.
enum SwipeDirection: CaseIterable {
    case left, right, up, down

    /// 드래그 이동량에서 더 많이 움직인 쪽 방향. 움직이지 않았으면 nil.
    init?(translation: CGSize) {
        guard translation != .zero else { return nil }
        if abs(translation.width) >= abs(translation.height) {
            self = translation.width < 0 ? .left : .right
        } else {
            self = translation.height < 0 ? .up : .down
        }
    }

    /// 위쪽은 대상 앨범이 있으면 "앨범에 추가", 없으면 "앨범 선택".
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

    /// 카드가 화면 밖으로 날아가 다음 사진으로 넘어가는 방향인가.
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
        case .up: CGSize(width: 0, height: -size.height * 1.3)
        case .down: CGSize(width: 0, height: size.height * 1.3)
        }
    }
}

/// 드래그하는 동안 방향별로 가볍게 보여주는 힌트.
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
        guard SwipeDirection(translation: drag) == direction else { return 0 }
        return min(Double(hypot(drag.width, drag.height) / threshold), 1)
    }
}
