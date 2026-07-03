//
//  CLIExecutableResolver.swift
//  leanring-buddy
//

import Foundation

struct CLIExecutableResolver: Equatable, Sendable {
    let searchDirectoryURLs: [URL]

    init(searchDirectoryURLs: [URL] = Self.standardSearchDirectoryURLs) {
        self.searchDirectoryURLs = searchDirectoryURLs
    }

    static let standard = CLIExecutableResolver()

    static let standardSearchDirectoryURLs: [URL] = [
        URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true),
        URL(fileURLWithPath: "/usr/local/bin", isDirectory: true),
        URL(fileURLWithPath: "/usr/bin", isDirectory: true),
        URL(fileURLWithPath: "/bin", isDirectory: true),
        URL(fileURLWithPath: "/usr/sbin", isDirectory: true),
        URL(fileURLWithPath: "/sbin", isDirectory: true)
    ]

    func resolve(
        executableName: String,
        fileManager: FileManager = .default
    ) -> CLIExecutableResolution {
        let trimmedExecutableName = executableName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedExecutableName.isEmpty,
              trimmedExecutableName.rangeOfCharacter(from: CharacterSet(charactersIn: "/")) == nil else {
            return .invalidExecutableName(executableName)
        }

        var firstNonExecutableCandidateURL: URL?

        for searchDirectoryURL in searchDirectoryURLs {
            guard searchDirectoryURL.isFileURL else {
                continue
            }

            let candidateURL = searchDirectoryURL.appendingPathComponent(trimmedExecutableName, isDirectory: false)
            var isDirectory: ObjCBool = false
            let fileExists = fileManager.fileExists(atPath: candidateURL.path, isDirectory: &isDirectory)

            guard fileExists else {
                continue
            }

            guard !isDirectory.boolValue,
                  fileManager.isExecutableFile(atPath: candidateURL.path) else {
                if firstNonExecutableCandidateURL == nil {
                    firstNonExecutableCandidateURL = candidateURL
                }
                continue
            }

            return .found(
                executableName: trimmedExecutableName,
                executableURL: candidateURL,
                searchedDirectoryURLs: searchDirectoryURLs
            )
        }

        if let firstNonExecutableCandidateURL {
            return .notExecutable(
                executableName: trimmedExecutableName,
                candidateURL: firstNonExecutableCandidateURL,
                searchedDirectoryURLs: searchDirectoryURLs
            )
        }

        return .notFound(
            executableName: trimmedExecutableName,
            searchedDirectoryURLs: searchDirectoryURLs
        )
    }
}

enum CLIExecutableResolution: Equatable, Sendable {
    case found(
        executableName: String,
        executableURL: URL,
        searchedDirectoryURLs: [URL]
    )
    case notFound(
        executableName: String,
        searchedDirectoryURLs: [URL]
    )
    case notExecutable(
        executableName: String,
        candidateURL: URL,
        searchedDirectoryURLs: [URL]
    )
    case invalidExecutableName(String)

    var executableURL: URL? {
        if case .found(_, let executableURL, _) = self {
            return executableURL
        }

        return nil
    }

    var statusMessage: String {
        switch self {
        case .found(let executableName, let executableURL, _):
            return "\(executableName) found at \(executableURL.path)."
        case .notFound(let executableName, let searchedDirectoryURLs):
            let searchedDirectories = searchedDirectoryURLs.map(\.path).joined(separator: ", ")
            return "\(executableName) was not found in: \(searchedDirectories)."
        case .notExecutable(let executableName, let candidateURL, _):
            return "\(executableName) exists at \(candidateURL.path), but it is not executable."
        case .invalidExecutableName(let executableName):
            return "Invalid CLI executable name: \(executableName)."
        }
    }
}
