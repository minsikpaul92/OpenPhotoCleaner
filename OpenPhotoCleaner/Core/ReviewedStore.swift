import Foundation
import Observation

/// Photos you kept or saved to an album through the app (they get a green check). App-local, per device.
/// Saves are delayed by a second and merged, so a swipe never rewrites thousands of identifiers.
@Observable
final class ReviewedStore {
    private let defaults: UserDefaults
    private(set) var kept: Set<String>
    private(set) var albumed: Set<String>
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    /// `defaults` is injectable so tests never touch the app's real stored state.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        kept = Set(defaults.stringArray(forKey: "review.kept") ?? [])
        albumed = Set(defaults.stringArray(forKey: "review.albumed") ?? [])
    }

    func isChecked(_ id: String) -> Bool { kept.contains(id) || albumed.contains(id) }

    func setKept(_ id: String, _ on: Bool) {
        if on { kept.insert(id) } else { kept.remove(id) }
        scheduleSave()
    }

    func setAlbumed(_ id: String, _ on: Bool) {
        if on { albumed.insert(id) } else { albumed.remove(id) }
        scheduleSave()
    }

    /// Forgets photos that are no longer in the library. Does nothing for an empty list (library not readable).
    func prune(keeping existing: Set<String>) {
        guard !existing.isEmpty else { return }
        let before = kept.count + albumed.count
        kept.formIntersection(existing)
        albumed.formIntersection(existing)
        if kept.count + albumed.count != before { flush() }
    }

    /// Writes now instead of waiting.
    func flush() {
        saveTask?.cancel()
        defaults.set(Array(kept), forKey: "review.kept")
        defaults.set(Array(albumed), forKey: "review.albumed")
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { flush() }
        }
    }
}
