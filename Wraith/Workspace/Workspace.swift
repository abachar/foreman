import Foundation
import Observation
import os

/// A folder opened in a window, and everything Wraith knows about it: its config today, its
/// persisted state and file watching with the next tasks (config, architecture).
@Observable
@MainActor
final class Workspace {
    let root: URL

    /// The last valid configuration: an invalid file never replaces it (config R7).
    private(set) var config: WorkspaceConfig = .empty

    /// Why the last reload was rejected, `nil` when `config` is current.
    private(set) var configError: WorkspaceConfigError?

    private let logger = Logger(subsystem: "dev.crafters.wraith", category: "workspace")

    init(root: URL) {
        self.root = root
    }

    /// Reads `config.json` again.
    ///
    /// Warnings are logged, an error keeps the previous config.
    func reloadConfig() async {
        do {
            let loaded = try await WorkspaceConfig.load(root: root)
            for warning in loaded.warnings {
                logger.warning("\(warning, privacy: .public)")
            }
            config = loaded
            configError = nil
        } catch let error as WorkspaceConfigError {
            logger.error("config.json rejected: \(error.description, privacy: .public)")
            configError = error
        } catch {
            logger.error("config.json rejected: \(error.localizedDescription, privacy: .public)")
            configError = .invalidJSON(file: root, line: nil, message: error.localizedDescription)
        }
    }
}
