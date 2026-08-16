import Combine
import Foundation

/// Holds the live settings and pushes them to disk. Writes are coalesced
/// because dragging a thumbnail changes a stored position on every frame.
@MainActor
final class ConfigStore: ObservableObject {
    @Published var settings: Settings {
        didSet {
            guard settings != oldValue else { return }
            scheduleSave()
        }
    }

    private let directory: URL
    private var saveTask: Task<Void, Never>?

    init(directory: URL = SettingsFile.directory()) {
        self.directory = directory
        settings = SettingsFile.load(from: directory)
    }

    func flush() {
        saveTask?.cancel()
        saveTask = nil
        write()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.write()
        }
    }

    private func write() {
        do {
            try SettingsFile.save(settings, to: directory)
        } catch {
            Log.error("cannot write settings: \(error.localizedDescription)")
        }
    }
}
