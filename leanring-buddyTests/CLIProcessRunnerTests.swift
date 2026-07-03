//
//  CLIProcessRunnerTests.swift
//  leanring-buddyTests
//

import Foundation
import Testing
@testable import leanring_buddy

struct CLIProcessRunnerTests {

    @Test func minimalEnvironmentContainsOnlyExpectedKeys() {
        let environment = CLIProcessEnvironmentBuilder.minimalEnvironment(
            homeDirectory: "/Users/tester",
            path: "/usr/bin:/bin"
        )

        #expect(environment == [
            "HOME": "/Users/tester",
            "PATH": "/usr/bin:/bin",
            "TERM": "dumb",
            "LANG": "C",
            "LC_ALL": "C"
        ])
    }

    @Test func sanitizedEnvironmentStripsCredentialLikeKeys() {
        let environment = CLIProcessEnvironmentBuilder.sanitizedEnvironment(from: [
            "HOME": "/Users/tester",
            "PATH": "/usr/bin:/bin",
            "TERM": "xterm",
            "OPENAI_API_KEY": "secret",
            "GITHUB_TOKEN": "secret",
            "AWS_SECRET_ACCESS_KEY": "secret",
            "UNRELATED": "drop"
        ])

        #expect(environment["HOME"] == "/Users/tester")
        #expect(environment["PATH"] == "/usr/bin:/bin")
        #expect(environment["TERM"] == "xterm")
        #expect(environment["OPENAI_API_KEY"] == nil)
        #expect(environment["GITHUB_TOKEN"] == nil)
        #expect(environment["AWS_SECRET_ACCESS_KEY"] == nil)
        #expect(environment["UNRELATED"] == nil)
    }

    @Test func requestValidationRejectsShellExecutable() throws {
        let request = CLIProcessRequest(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "echo unsafe"],
            workingDirectoryURL: URL(fileURLWithPath: "/private/tmp"),
            standardInputText: nil,
            timeoutSeconds: 1
        )
        var capturedError: AssistantBackendError?

        do {
            try request.validate()
        } catch let error as AssistantBackendError {
            capturedError = error
        }

        #expect(capturedError == .backendDisabled("CLI runner does not launch shell or env executables."))
    }

    @Test func commandPlanCreatesProcessRequestWithoutChangingArguments() throws {
        let commandPlan = LocalCLICommandPlan(
            executableURL: URL(fileURLWithPath: "/bin/cat"),
            arguments: ["--help"],
            workingDirectoryURL: URL(fileURLWithPath: "/private/tmp"),
            standardInputText: "hello",
            timeoutSeconds: 2,
            authority: .readOnly
        )
        let processRequest = commandPlan.makeProcessRequest(
            environment: ["PATH": "/usr/bin:/bin", "TERM": "dumb", "GITHUB_TOKEN": "secret"],
            terminationGraceSeconds: 0.5
        )

        #expect(processRequest.executableURL.path == "/bin/cat")
        #expect(processRequest.arguments == ["--help"])
        #expect(processRequest.workingDirectoryURL.path == "/private/tmp")
        #expect(processRequest.standardInputText == "hello")
        #expect(processRequest.environment["GITHUB_TOKEN"] == nil)
        #expect(processRequest.terminationGraceSeconds == 0.5)
    }

    @Test func runnerStreamsStandardInputToStdout() async throws {
        let runner = CLIProcessRunner()
        let request = CLIProcessRequest(
            executableURL: URL(fileURLWithPath: "/bin/cat"),
            arguments: [],
            workingDirectoryURL: URL(fileURLWithPath: "/private/tmp"),
            standardInputText: "hello",
            timeoutSeconds: 2
        )

        let events = try await collectEvents(from: runner.run(request))
        let stdoutText = events.compactMap { event in
            if case .stdoutTextDelta(let textDelta) = event {
                return textDelta
            }

            return nil
        }.joined()

        #expect(stdoutText == "hello")
        #expect(events.contains(.exit(CLIProcessExit(exitCode: 0, reason: .completed))))
    }

    @Test func runnerSeparatesStderrAndNonzeroExit() async throws {
        let runner = CLIProcessRunner()
        let missingPath = "/private/tmp/clicky-cli-runner-missing-file"
        let request = CLIProcessRequest(
            executableURL: URL(fileURLWithPath: "/bin/ls"),
            arguments: [missingPath],
            workingDirectoryURL: URL(fileURLWithPath: "/private/tmp"),
            standardInputText: nil,
            timeoutSeconds: 2
        )

        let events = try await collectEvents(from: runner.run(request))
        let stderrLines = events.compactMap { event in
            if case .stderrLine(let stderrLine) = event {
                return stderrLine
            }

            return nil
        }

        #expect(stderrLines.contains { $0.contains("clicky-cli-runner-missing-file") })
        #expect(events.contains(.exit(CLIProcessExit(exitCode: 1, reason: .failed))))
    }

    @Test func runnerCancelsRunningProcess() async throws {
        let runner = CLIProcessRunner()
        let request = CLIProcessRequest(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["2"],
            workingDirectoryURL: URL(fileURLWithPath: "/private/tmp"),
            standardInputText: nil,
            timeoutSeconds: 5,
            terminationGraceSeconds: 0.1
        )
        let run = runner.run(request)
        var events: [CLIProcessEvent] = []

        for try await event in run.events {
            events.append(event)
            if case .started = event {
                run.cancel()
            }
        }

        #expect(events.contains(.cancelled))
    }

    private func collectEvents(from run: CLIProcessRun) async throws -> [CLIProcessEvent] {
        var events: [CLIProcessEvent] = []

        for try await event in run.events {
            events.append(event)
        }

        return events
    }
}
