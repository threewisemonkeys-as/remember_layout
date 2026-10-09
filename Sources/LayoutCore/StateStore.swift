import Foundation

public final class StateStore {
    public let url: URL
    public init(url: URL) { self.url = url }

    public func load() throws -> AppState {
        guard FileManager.default.fileExists(atPath: url.path) else { return AppState() }
        let state = try JSONDecoder().decode(AppState.self, from: Data(contentsOf: url))
        guard state.schemaVersion == 1 else {
            throw NSError(domain: "Remember", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "This layout file was created by a newer version of Remember."])
        }
        // Never send corrupted geometry to another application's windows.
        guard state.profiles.allSatisfy({ profile in
            !profile.id.isEmpty && profile.displays.allSatisfy { $0.frame.isValid && $0.visibleFrame.isValid } &&
            profile.windows.allSatisfy { $0.normalizedFrame.isValid }
        }) else {
            throw NSError(domain: "Remember", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "The saved layout file contains invalid window positions."])
        }
        return state
    }

    public func save(_ state: AppState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
