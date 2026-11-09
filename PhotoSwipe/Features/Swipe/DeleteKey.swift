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

extension CharacterSet {
    // Letter shortcuts also match what the same physical key types with the Korean 2-set layout
    // (compatibility jamo, plus the conjoining jamo some input methods send), so they work without
    // switching to English. shortcut: other non-Latin layouts are not covered; use key codes if needed.
    /// A (Album): opens the album picker.
    static let albumKey = CharacterSet(charactersIn: "aAㅁ\u{1106}")
    /// S (Sort): toggles the album order.
    static let sortKey = CharacterSet(charactersIn: "sSㄴ\u{1102}")
}
