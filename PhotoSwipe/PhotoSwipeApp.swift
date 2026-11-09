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
            CommandMenu("Photo") {
                Button("Delete") { NotificationCenter.default.post(name: .cardCommand, object: "delete") }
                Button("Keep") { NotificationCenter.default.post(name: .cardCommand, object: "keep") }
                Button("Save to Album") { NotificationCenter.default.post(name: .cardCommand, object: "save") }
                Button("Choose Album") { NotificationCenter.default.post(name: .cardCommand, object: "albums") }
                Divider()
                Button("Rotate Clockwise") { NotificationCenter.default.post(name: .cardCommand, object: "rotate") }
                Button("Favorite") { NotificationCenter.default.post(name: .cardCommand, object: "favorite") }
                Divider()
                Button("Back to Grid") { NotificationCenter.default.post(name: .cardCommand, object: "grid") }
            }
            CommandGroup(replacing: .help) {
                Button("How to Sort Photos") { NotificationCenter.default.post(name: .showTutorial, object: nil) }
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { NotificationCenter.default.post(name: .undoRequested, object: nil) }
                    .keyboardShortcut("z")
            }
        }
    }
}
