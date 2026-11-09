import SwiftUI

#if os(iOS)
/// Shake events travel up the responder chain and end at the app delegate, so this hears a shake
/// whichever view has focus (a view-level first responder is taken over by SwiftUI's focus system).
final class ShakeAppDelegate: UIResponder, UIApplicationDelegate {
    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .undoRequested, object: nil)
        } else {
            super.motionEnded(motion, with: event)
        }
    }
}
#endif

@main struct PhotoSwipeApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(ShakeAppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            // Own the Undo shortcut (⌘Z); the card view listens for it. iPhone uses shake instead.
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { NotificationCenter.default.post(name: .undoRequested, object: nil) }
                    .keyboardShortcut("z")
            }
        }
    }
}
