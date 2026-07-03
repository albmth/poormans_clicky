//
//  LocalCLIBackendSessionTests.swift
//  leanring-buddyTests
//

import Foundation
import Testing
@testable import leanring_buddy

struct LocalCLIBackendSessionTests {

    @Test func codexSessionBuildsReadOnlyOneShotRequestAndStreamsOutput() async throws {
        let temporaryDirectoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectoryURL) }

        let executableURL = try writeExecutableFixture(named: "codex", in: temporaryDirectoryURL)
        let processRunner = CapturingCLIProcessRunner(events: [
            .started(processIdentifier: 123),
            .stdoutTextDelta("hello from codex"),
            .exit(CLIProcessExit(exitCode: 0, reason: .completed))
        ])
        let backend = CodexCLIBackend(
            gate: .enabledReadOnlyOneShot,
            executableResolver: CLIExecutableResolver(searchDirectoryURLs: [temporaryDirectoryURL]),
            processRunner: processRunner
        )
        let session = try await backend.startSession(
            context: AssistantSessionContext(workingDirectory: temporaryDirectoryURL)
        )
        let imageFileURL = temporaryDirectoryURL.appendingPathComponent("screen1.png")

        let events = try await collectEvents(
            from: session.sendPrompt(
                AssistantPromptRequest(
                    promptText: "explain this",
                    attachedImageFileURLs: [imageFileURL]
                )
            )
        )
        let processRequest = try #require(processRunner.lastRequest())

        #expect(processRequest.executableURL == executableURL)
        #expect(processRequest.arguments == [
            "exec",
            "--sandbox",
            "read-only",
            "--skip-git-repo-check",
            "--ephemeral",
            "--color",
            "never",
            "--cd",
            temporaryDirectoryURL.path,
            "--image",
            imageFileURL.path,
            "-"
        ])
        #expect(processRequest.workingDirectoryURL == temporaryDirectoryURL)
        #expect(processRequest.standardInputText == "explain this")
        #expect(events.contains(.started(displayName: "Codex CLI")))
        #expect(events.contains(.stdoutTextDelta("hello from codex")))
        #expect(events.contains(.exit(AssistantBackendExit(exitCode: 0, reason: .completed, message: nil))))
    }

    @Test func codexSessionMapsNonzeroExitToAssistantBackendError() async throws {
        let temporaryDirectoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectoryURL) }

        _ = try writeExecutableFixture(named: "codex", in: temporaryDirectoryURL)
        let processRunner = CapturingCLIProcessRunner(events: [
            .started(processIdentifier: 123),
            .stderrLine("not logged in"),
            .exit(CLIProcessExit(exitCode: 1, reason: .failed))
        ])
        let backend = CodexCLIBackend(
            gate: .enabledReadOnlyOneShot,
            executableResolver: CLIExecutableResolver(searchDirectoryURLs: [temporaryDirectoryURL]),
            processRunner: processRunner
        )
        let session = try await backend.startSession(
            context: AssistantSessionContext(workingDirectory: temporaryDirectoryURL)
        )
        var capturedError: AssistantBackendError?

        do {
            _ = try await collectEvents(
                from: session.sendPrompt(AssistantPromptRequest(promptText: "hello"))
            )
        } catch let error as AssistantBackendError {
            capturedError = error
        }

        #expect(capturedError == .processExitedWithNonzeroStatus(exitCode: 1, stderr: "not logged in"))
    }

    @Test func catalogCanSelectMockWhenUserDefaultsOverrideIsSet() throws {
        let userDefaults = try makeIsolatedUserDefaults()
        defer {
            userDefaults.removePersistentDomain(forName: userDefaultsSuiteName)
        }

        userDefaults.set(
            AssistantBackendKind.mock.rawValue,
            forKey: AssistantBackendCatalog.selectedBackendUserDefaultsKey
        )

        let backend = AssistantBackendCatalog.defaultDevelopmentBackend(userDefaults: userDefaults)

        #expect(backend.kind == .mock)
    }

    private let userDefaultsSuiteName = "LocalCLIBackendSessionTests"

    private func collectEvents(
        from stream: AsyncThrowingStream<AssistantBackendEvent, Error>
    ) async throws -> [AssistantBackendEvent] {
        var events: [AssistantBackendEvent] = []

        for try await event in stream {
            events.append(event)
        }

        return events
    }

    private func makeTemporaryDirectory() throws -> URL {
        let temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(
                "clicky-local-cli-backend-session-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: temporaryDirectoryURL,
            withIntermediateDirectories: true
        )
        return temporaryDirectoryURL
    }

    private func writeExecutableFixture(
        named executableName: String,
        in directoryURL: URL
    ) throws -> URL {
        let executableURL = directoryURL.appendingPathComponent(executableName, isDirectory: false)
        try Data("fixture".utf8).write(to: executableURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )
        return executableURL
    }

    private func makeIsolatedUserDefaults() throws -> UserDefaults {
        let userDefaults = try #require(UserDefaults(suiteName: userDefaultsSuiteName))
        userDefaults.removePersistentDomain(forName: userDefaultsSuiteName)
        return userDefaults
    }
}

private final class CapturingCLIProcessRunner: CLIProcessRunning, @unchecked Sendable {
    private let events: [CLIProcessEvent]
    private let stateLock = NSLock()
    private var capturedRequest: CLIProcessRequest?

    init(events: [CLIProcessEvent]) {
        self.events = events
    }

    func run(_ request: CLIProcessRequest) -> CLIProcessRun {
        stateLock.lock()
        capturedRequest = request
        stateLock.unlock()

        let eventStream = AsyncThrowingStream<CLIProcessEvent, Error> { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }

        return CLIProcessRun(events: eventStream) {}
    }

    func lastRequest() -> CLIProcessRequest? {
        stateLock.lock()
        defer { stateLock.unlock() }

        return capturedRequest
    }
}
