import SwiftUI

extension View {
    /// Runs `action` on the Delete / Backspace key, however the keyboard reports it. Other keys pass through.
    func onDeleteKey(_ action: @escaping () -> Void) -> some View {
        onKeyPress(phases: .down) { press in
            guard press.key == .delete || press.key == .deleteForward
                    || press.characters == "\u{7F}" || press.characters == "\u{8}" else { return .ignored }
            action()
            return .handled
        }
    }
}
