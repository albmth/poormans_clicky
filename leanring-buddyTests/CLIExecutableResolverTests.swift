//
//  CLIExecutableResolverTests.swift
//  leanring-buddyTests
//

import Foundation
import Testing
@testable import leanring_buddy

struct CLIExecutableResolverTests {

    @Test func resolverFindsExecutableInConfiguredSearchPath() throws {
        let temporaryDirectoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectoryURL) }

        let executableURL = temporaryDirectoryURL.appendingPathComponent("codex", isDirectory: false)
        try Data("fixture".utf8).write(to: executableURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        let resolver = CLIExecutableResolver(searchDirectoryURLs: [temporaryDirectoryURL])
        let resolution = resolver.resolve(executableName: "codex")

        #expect(resolution.executableURL == executableURL)
        #expect(resolution.statusMessage == "codex found at \(executableURL.path).")
    }

    @Test func resolverReportsNonExecutableCandidate() throws {
        let temporaryDirectoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectoryURL) }

        let candidateURL = temporaryDirectoryURL.appendingPathComponent("codex", isDirectory: false)
        try Data("fixture".utf8).write(to: candidateURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: candidateURL.path
        )

        let resolver = CLIExecutableResolver(searchDirectoryURLs: [temporaryDirectoryURL])
        let resolution = resolver.resolve(executableName: "codex")

        #expect(resolution == .notExecutable(
            executableName: "codex",
            candidateURL: candidateURL,
            searchedDirectoryURLs: [temporaryDirectoryURL]
        ))
        #expect(resolution.statusMessage == "codex exists at \(candidateURL.path), but it is not executable.")
    }

    @Test func resolverRejectsPathLikeExecutableName() {
        let resolver = CLIExecutableResolver(searchDirectoryURLs: [
            URL(fileURLWithPath: "/private/tmp", isDirectory: true)
        ])
        let resolution = resolver.resolve(executableName: "/bin/codex")

        #expect(resolution == .invalidExecutableName("/bin/codex"))
        #expect(resolution.executableURL == nil)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(
                "clicky-cli-executable-resolver-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: temporaryDirectoryURL,
            withIntermediateDirectories: true
        )
        return temporaryDirectoryURL
    }
}
