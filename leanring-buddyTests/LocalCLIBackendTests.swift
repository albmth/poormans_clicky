//
//  LocalCLIBackendTests.swift
//  leanring-buddyTests
//

import Foundation
import Testing
@testable import leanring_buddy

struct LocalCLIBackendTests {

    @Test func codexCLIBackendIsUnavailableWhileGateIsDisabled() async throws {
        let emptySearchDirectoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: emptySearchDirectoryURL) }

        let backend = CodexCLIBackend(
            executableResolver: CLIExecutableResolver(searchDirectoryURLs: [emptySearchDirectoryURL])
        )
        let availability = await backend.checkAvailability()

        #expect(backend.kind == .codexCLI)
        #expect(backend.displayName == "Codex CLI")
        #expect(availability.state == .unavailable)
        #expect(availability.message.contains("Codex CLI backend is scaffolded but disabled."))
        #expect(availability.message.contains("codex was not found"))
    }

    @Test func claudeCodeBackendIsUnavailableWhileGateIsDisabled() async throws {
        let emptySearchDirectoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: emptySearchDirectoryURL) }

        let backend = ClaudeCodeBackend(
            executableResolver: CLIExecutableResolver(searchDirectoryURLs: [emptySearchDirectoryURL])
        )
        let availability = await backend.checkAvailability()

        #expect(backend.kind == .claudeCode)
        #expect(backend.displayName == "Claude Code")
        #expect(availability.state == .unavailable)
        #expect(availability.message.contains("Claude Code backend is scaffolded but disabled."))
        #expect(availability.message.contains("claude was not found"))
    }

    @Test func disabledCLIBackendThrowsBeforeStartingSession() async throws {
        let backend = CodexCLIBackend()
        var capturedError: AssistantBackendError?

        do {
            _ = try await backend.startSession(context: AssistantSessionContext())
        } catch let error as AssistantBackendError {
            capturedError = error
        }

        #expect(capturedError == .backendDisabled("Codex CLI backend is scaffolded but disabled."))
    }

    @Test func disabledCLIBackendReportsExecutableWhenFound() async throws {
        let temporaryDirectoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectoryURL) }

        let executableURL = try writeExecutableFixture(named: "codex", in: temporaryDirectoryURL)
        let backend = CodexCLIBackend(
            executableResolver: CLIExecutableResolver(searchDirectoryURLs: [temporaryDirectoryURL])
        )
        let statusSummary = await backend.makeStatusSummary()

        #expect(statusSummary.availability.state == .unavailable)
        #expect(statusSummary.availability.executableURL == executableURL)
        #expect(statusSummary.statusText.contains("Codex CLI backend is scaffolded but disabled."))
        #expect(statusSummary.detailText?.contains("codex found at \(executableURL.path).") == true)
        #expect(statusSummary.detailText?.contains("CLI launch is intentionally disabled") == true)
    }

    @Test func enabledCLIBackendReportsLoginUnknownWithoutStartingSession() async throws {
        let temporaryDirectoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectoryURL) }

        let executableURL = try writeExecutableFixture(named: "codex", in: temporaryDirectoryURL)
        let gate = LocalCLIBackendGate(
            isEnabled: true,
            authority: .readOnly,
            requiresExplicitWorkingDirectory: true,
            allowsImageAttachments: false,
            timeoutSeconds: 30
        )
        let backend = CodexCLIBackend(
            gate: gate,
            executableResolver: CLIExecutableResolver(searchDirectoryURLs: [temporaryDirectoryURL])
        )
        let availability = await backend.checkAvailability()

        #expect(availability.state == .loginUnknown)
        #expect(availability.executableURL == executableURL)
        #expect(availability.message == "Codex CLI was found. Login status is not checked yet.")
    }

    @Test func localCLICommandPlanRequiresEnabledGateAndWorkingDirectory() throws {
        let backend = LocalCLIBackend(
            configuration: LocalCLIBackendConfiguration(
                kind: .codexCLI,
                displayName: "Codex CLI",
                executableName: "codex",
                commandProfile: .codexReadOnlyOneShot,
                disabledMessage: "disabled"
            )
        )
        let request = AssistantPromptRequest(promptText: "hello")
        var capturedError: AssistantBackendError?

        do {
            _ = try backend.makeCommandPlan(
                executableURL: URL(fileURLWithPath: "/usr/local/bin/codex"),
                context: AssistantSessionContext(),
                request: request,
                arguments: ["exec"]
            )
        } catch let error as AssistantBackendError {
            capturedError = error
        }

        #expect(capturedError == .backendDisabled("CLI backend execution is disabled while the local runner is being designed."))
    }

    @Test func enabledLocalCLICommandPlanKeepsExecutableAndArgumentsSeparate() throws {
        let gate = LocalCLIBackendGate(
            isEnabled: true,
            authority: .readOnly,
            requiresExplicitWorkingDirectory: true,
            allowsImageAttachments: false,
            timeoutSeconds: 30
        )
        let backend = LocalCLIBackend(
            configuration: LocalCLIBackendConfiguration(
                kind: .codexCLI,
                displayName: "Codex CLI",
                executableName: "codex",
                commandProfile: .codexReadOnlyOneShot,
                disabledMessage: "disabled"
            ),
            gate: gate
        )
        let request = AssistantPromptRequest(promptText: "hello", timeoutSeconds: 120)
        let workingDirectory = URL(fileURLWithPath: "/private/tmp")
        let commandPlan = try backend.makeCommandPlan(
            executableURL: URL(fileURLWithPath: "/usr/local/bin/codex"),
            context: AssistantSessionContext(workingDirectory: workingDirectory),
            request: request,
            arguments: ["exec", "--sandbox", "read-only"]
        )

        #expect(commandPlan.executableURL.path == "/usr/local/bin/codex")
        #expect(commandPlan.arguments == ["exec", "--sandbox", "read-only"])
        #expect(commandPlan.workingDirectoryURL == workingDirectory)
        #expect(commandPlan.standardInputText == "hello")
        #expect(commandPlan.timeoutSeconds == 30)
        #expect(commandPlan.authority == .readOnly)
    }

    @Test func codexReadOnlyOneShotCommandProfileAddsImageAttachmentsBeforeStdin() {
        let workingDirectory = URL(fileURLWithPath: "/private/tmp/clicky-workspace", isDirectory: true)
        let firstImageFileURL = URL(fileURLWithPath: "/private/tmp/screen1.png")
        let secondImageFileURL = URL(fileURLWithPath: "/private/tmp/screen2.png")
        let arguments = LocalCLICommandProfile.codexReadOnlyOneShot.arguments(
            workingDirectoryURL: workingDirectory,
            attachedImageFileURLs: [firstImageFileURL, secondImageFileURL]
        )

        #expect(arguments == [
            "exec",
            "--sandbox",
            "read-only",
            "--skip-git-repo-check",
            "--ephemeral",
            "--color",
            "never",
            "--cd",
            workingDirectory.path,
            "--image",
            firstImageFileURL.path,
            "--image",
            secondImageFileURL.path,
            "-"
        ])
    }

    @Test func assistantBackendCatalogUsesCodexAsDefault() {
        let defaultBackend = AssistantBackendCatalog.defaultDevelopmentBackend()
        let scaffoldedBackendNames = AssistantBackendCatalog.scaffoldedCLIBackends().map { $0.displayName }

        #expect(defaultBackend.kind == .codexCLI)
        #expect(scaffoldedBackendNames == ["Codex CLI", "Claude Code"])
    }

    private func makeTemporaryDirectory() throws -> URL {
        let temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(
                "clicky-local-cli-backend-\(UUID().uuidString)",
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
}
