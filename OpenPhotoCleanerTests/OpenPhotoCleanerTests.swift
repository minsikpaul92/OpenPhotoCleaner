import Testing
import Foundation
import SwiftUI
@testable import OpenPhotoCleaner

/// Pure-logic tests: nothing here touches the real Photos library.
struct SwipeDirectionTests {
    @Test func dominantAxisWins() {
        #expect(SwipeDirection(translation: CGSize(width: -120, height: 30)) == .left)
        #expect(SwipeDirection(translation: CGSize(width: 90, height: -20)) == .right)
        #expect(SwipeDirection(translation: CGSize(width: 10, height: -130)) == .up)
        #expect(SwipeDirection(translation: CGSize(width: -10, height: 130)) == .down)
    }

    @Test func noMovementHasNoDirection() {
        #expect(SwipeDirection(translation: .zero) == nil)
    }

    @Test func upOnlyAdvancesWithATargetAlbum() {
        #expect(SwipeDirection.up.advances(hasTarget: true))
        #expect(!SwipeDirection.up.advances(hasTarget: false))
        #expect(SwipeDirection.left.advances(hasTarget: false))
        #expect(!SwipeDirection.down.advances(hasTarget: true))
    }
}

struct LetterShortcutTests {
    @Test func albumKeyMatchesEnglishAndKorean() {
        #expect(CharacterSet.albumKey.contains("a"))
        #expect(CharacterSet.albumKey.contains("A"))
        #expect(CharacterSet.albumKey.contains("ㅁ"))
        #expect(!CharacterSet.albumKey.contains("s"))
    }

    @Test func sortAndRotateKeysMatchEnglishAndKorean() {
        #expect(CharacterSet.sortKey.contains("s") && CharacterSet.sortKey.contains("ㄴ"))
        #expect(CharacterSet.rotateKey.contains("t") && CharacterSet.rotateKey.contains("ㅅ"))
    }
}

/// Each test uses its own throwaway UserDefaults suite, never the app's real one.
@Suite(.serialized)
struct StoredStateTests {
    private func makeDefaults() -> UserDefaults {
        let name = "OpenPhotoCleanerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func numberStaysWithOneAlbum() {
        let library = AlbumLibrary(defaults: makeDefaults())
        let a = Album(id: "a", title: "A"), b = Album(id: "b", title: "B")

        library.toggleSlot("1", for: a)
        #expect(library.slot(of: a) == "1")

        library.toggleSlot("2", for: a)                       // an album keeps only one number
        #expect(library.slot(of: a) == "2")
        #expect(library.album(forSlot: "1") == nil)

        library.toggleSlot("2", for: b)                       // another album overwrites the number
        #expect(library.slot(of: b) == "2")
        #expect(library.slot(of: a) == nil)

        library.toggleSlot("2", for: b)                       // the same number again clears it
        #expect(library.slot(of: b) == nil)
    }

    @Test func placeholderAlbumNeverGetsANumber() {
        let library = AlbumLibrary(defaults: makeDefaults())
        library.toggleSlot("3", for: Album(id: "x", title: "Pending Share", isPlaceholder: true))
        #expect(library.album(forSlot: "3") == nil)
    }

    @Test func sortOrderToggleIsRemembered() {
        let defaults = makeDefaults()
        let library = AlbumLibrary(defaults: defaults)
        #expect(!library.sortsByName)
        library.toggleSort()
        #expect(AlbumLibrary(defaults: defaults).sortsByName)
    }

    @Test func deletionQueueLoadsStoredIdentifiers() {
        let defaults = makeDefaults()
        defaults.set(["id1", "id2", "id3"], forKey: "deletionQueue.ids")
        let queue = DeletionQueue(defaults: defaults)
        #expect(queue.count == 3)
        #expect(queue.idSet == ["id1", "id2", "id3"])
    }
}

struct PlatformTests {
    @Test func macUsesTheDesktopLayout() {
        #if os(macOS)
        #expect(Platform.desktopStyle)
        #endif
    }
}
