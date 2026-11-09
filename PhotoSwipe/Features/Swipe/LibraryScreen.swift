import SwiftUI

/// 메인은 사진 그리드이고, 사진 한 장 보기는 그리드 위에 띄운 창이다.
/// 처음 열 때 보던 사진이 있으면 그 사진의 창이 열린 채로 시작한다(이어서 시작).
struct LibraryScreen: View {
    @State private var session: SwipeSession
    @State private var showCard: Bool
    @AppStorage("tutorial.seen") private var tutorialSeen = false

    init(library: PhotoLibrary) {
        let session = SwipeSession(library: library)
        _session = State(initialValue: session)
        // 마지막에 한 장 보기가 열려 있었으면 거기서, 그리드에 있었으면 그리드에서 시작한다(처음 실행은 한 장 보기).
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
        .onChange(of: showCard) { UserDefaults.standard.set(showCard, forKey: "ui.cardOpen") }
        .alert("Notice", isPresented: Binding(get: { session.lastError != nil }, set: { if !$0 { session.lastError = nil } })) {
            Button("OK") {}
        } message: {
            Text(session.lastError ?? "")
        }
    }
}
