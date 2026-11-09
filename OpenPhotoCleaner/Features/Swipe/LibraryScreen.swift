import SwiftUI

/// The main screen is the photo grid; the one-photo view is a window above it.
/// Resumes where the user left off: with the last photo's window open, or in the grid.
struct LibraryScreen: View {
    @State private var session: SwipeSession
    @State private var showCard: Bool
    @AppStorage("tutorial.seen") private var tutorialSeen = false

    init(library: PhotoLibrary) {
        let session = SwipeSession(library: library)
        _session = State(initialValue: session)
        // Start in the one-photo view if it was open last time, otherwise in the grid (the first launch opens the one-photo view).
        let cardWasOpen = UserDefaults.standard.object(forKey: "ui.cardOpen") as? Bool ?? true
        _showCard = State(initialValue: cardWasOpen && session.current != nil)
    }

    var body: some View {
        ZStack {
            PhotoGridView(session: session, isActive: !showCard && tutorialSeen) { index in
                session.go(to: index)
                withAnimation(.easeInOut(duration: 0.3)) { showCard = true }
            }
            if showCard {
                SwipeScreen(session: session, isBlocked: !tutorialSeen) {
                    withAnimation(.easeInOut(duration: 0.3)) { showCard = false }
                }
                .transition(.move(edge: .bottom))
                .zIndex(1)
            }
            if !tutorialSeen {
                TutorialOverlay { tutorialSeen = true }
                    .zIndex(2)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showTutorial)) { _ in tutorialSeen = false }
        .onChange(of: showCard) { UserDefaults.standard.set(showCard, forKey: "ui.cardOpen") }
        .alert("Couldn't Finish", isPresented: Binding(get: { session.lastError != nil }, set: { if !$0 { session.lastError = nil } })) {
            Button("OK") {}
        } message: {
            Text(session.lastError ?? "")
        }
    }
}
