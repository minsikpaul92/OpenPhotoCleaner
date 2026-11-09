import SwiftUI
import Photos

struct ContentView: View {
    @State private var library = PhotoLibrary()

    var body: some View {
        Group {
            if library.isAuthorized {
                LibraryScreen(library: library)
            } else {
                permissionView
            }
        }
        .task {
            if library.status == .notDetermined {
                await library.requestAccess()
            }
        }
    }

    private var permissionView: some View {
        ContentUnavailableView {
            Label("Photo Access Needed", systemImage: "photo.on.rectangle")
        } description: {
            Text("Allow access to \"All Photos\" in Settings.")
        } actions: {
            if library.status == .notDetermined {
                Button("Allow Access") { Task { await library.requestAccess() } }
            }
        }
    }
}

#Preview {
    ContentView()
}
