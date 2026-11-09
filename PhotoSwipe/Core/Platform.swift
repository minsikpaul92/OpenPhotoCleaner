import SwiftUI

enum Platform {
    /// True on Mac and iPad: large screen, keyboard likely. These use the desktop-style layout
    /// (black photo background, always-visible key hints, numbered-album list, bottom button bars, key-driven selection).
    /// iPhone keeps the touch-first layout.
    static var desktopStyle: Bool {
        #if os(macOS)
        true
        #else
        UIDevice.current.userInterfaceIdiom == .pad
        #endif
    }
}

extension Color {
    /// System background that exists on both platforms.
    static var platformBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }
}
