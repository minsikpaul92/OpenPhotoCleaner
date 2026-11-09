#if os(macOS)
import SwiftUI
import AppKit

extension View {
    /// Runs `action` when the physical key with `keyCode` is pressed (no modifiers), whatever the input language is:
    /// on a Korean layout the A key still counts as A. Ignored while a text field is being edited or when `enabled` is false.
    func onPhysicalKey(_ keyCode: UInt16, enabled: Bool = true, perform action: @escaping () -> Void) -> some View {
        modifier(PhysicalKeyModifier(keyCode: keyCode, enabled: enabled, action: action))
    }
}

/// US-layout key codes of the letter shortcuts.
enum PhysicalKeyCode {
    static let a: UInt16 = 0
    static let s: UInt16 = 1
}

private struct PhysicalKeyModifier: ViewModifier {
    let keyCode: UInt16
    let enabled: Bool
    let action: () -> Void
    @State private var monitor: Any?
    /// The monitor outlives a single render, so it reads the latest `enabled` from here.
    @State private var latest = Latest()

    private final class Latest {
        var enabled = true
    }

    func body(content: Content) -> some View {
        latest.enabled = enabled
        return content
            .onAppear {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    guard latest.enabled, !event.isARepeat, event.keyCode == keyCode,
                          event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                          !(NSApp.keyWindow?.firstResponder is NSText) else { return event }
                    action()
                    return nil
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }
}
#endif
