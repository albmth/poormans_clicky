//
//  AssistantBackendCatalog.swift
//  leanring-buddy
//

import Foundation

enum AssistantBackendCatalog {
    static let selectedBackendUserDefaultsKey = "Clicky.AssistantBackendKind.v1"
    static let workingDirectoryUserDefaultsKey = "Clicky.AssistantBackendWorkingDirectory.v1"

    static func defaultDevelopmentBackend(
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) -> any AssistantBackend {
        switch userDefaults.string(forKey: selectedBackendUserDefaultsKey) {
        case AssistantBackendKind.mock.rawValue:
            return MockBackend()
        case AssistantBackendKind.disabled.rawValue:
            return DisabledBackend()
        default:
            return CodexCLIBackend(gate: .enabledReadOnlyOneShot)
        }
    }

    static func safeFallbackBackend() -> any AssistantBackend {
        DisabledBackend()
    }

    static func configuredWorkingDirectory(
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) -> URL? {
        if let configuredPath = userDefaults.string(forKey: workingDirectoryUserDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !configuredPath.isEmpty {
            return URL(fileURLWithPath: configuredPath, isDirectory: true)
        }

        let temporaryWorkingDirectoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("clicky-assistant-backend-workspace", isDirectory: true)

        do {
            try fileManager.createDirectory(
                at: temporaryWorkingDirectoryURL,
                withIntermediateDirectories: true
            )
            return temporaryWorkingDirectoryURL
        } catch {
            return nil
        }
    }

    static func scaffoldedCLIBackends() -> [any AssistantBackend] {
        [
            CodexCLIBackend(),
            ClaudeCodeBackend()
        ]
    }
}
