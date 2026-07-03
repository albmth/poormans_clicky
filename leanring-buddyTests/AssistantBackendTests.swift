//
//  AssistantBackendTests.swift
//  leanring-buddyTests
//

import Testing
@testable import leanring_buddy

struct AssistantBackendTests {

    @Test func disabledBackendReportsSetupStateWithoutAssistantOutput() async throws {
        let backend = DisabledBackend()
        let availability = await backend.checkAvailability()

        #expect(availability.isAvailable)
        #expect(availability.message == DisabledBackend.setupMessage)

        let session = try await backend.startSession(context: AssistantSessionContext(authority: .disabled))
        let events = try await collectEvents(
            from: session.sendPrompt(AssistantPromptRequest(promptText: "hello"))
        )

        #expect(events.contains(.started(displayName: "No Assistant")))
        #expect(events.contains(.statusChanged(DisabledBackend.setupMessage)))
        #expect(events.contains(where: { event in
            if case .stdoutTextDelta = event {
                return true
            }

            return false
        }) == false)
    }

    @Test func mockBackendStreamsDeterministicTextChunks() async throws {
        let backend = MockBackend(
            configuration: MockBackendConfiguration(
                responseTextChunks: ["first ", "second"],
                statusMessages: ["thinking"],
                delayNanoseconds: 0
            )
        )
        let session = try await backend.startSession(context: AssistantSessionContext())
        let events = try await collectEvents(
            from: session.sendPrompt(AssistantPromptRequest(promptText: "test prompt"))
        )

        #expect(events.contains(.started(displayName: "Mock Assistant")))
        #expect(events.contains(.statusChanged("thinking")))
        #expect(events.contains(.stdoutTextDelta("first ")))
        #expect(events.contains(.stdoutTextDelta("second")))
        #expect(events.contains(.exit(AssistantBackendExit(exitCode: 0, reason: .completed, message: nil))))
    }

    @Test func mockBackendCanEmitSeparateStderrLines() async throws {
        let backend = MockBackend(
            configuration: MockBackendConfiguration(
                responseTextChunks: ["ok"],
                statusMessages: [],
                behavior: .emitsStderr(line: "\u{001B}[31mwarning\u{001B}[0m")
            )
        )
        let session = try await backend.startSession(context: AssistantSessionContext())
        let events = try await collectEvents(
            from: session.sendPrompt(AssistantPromptRequest(promptText: "test prompt"))
        )

        #expect(events.contains(.stderrLine("warning")))
        #expect(events.contains(.stdoutTextDelta("ok")))
    }

    @Test func mockBackendSurfacesNonzeroExitAsEventAndThrownError() async throws {
        let backend = MockBackend(
            configuration: MockBackendConfiguration(
                responseTextChunks: [],
                statusMessages: [],
                behavior: .exitsWithFailure(exitCode: 42, stderr: "failed")
            )
        )
        let session = try await backend.startSession(context: AssistantSessionContext())
        var collectedEvents: [AssistantBackendEvent] = []
        var collectedError: AssistantBackendError?

        do {
            for try await event in session.sendPrompt(AssistantPromptRequest(promptText: "test prompt")) {
                collectedEvents.append(event)
            }
        } catch let error as AssistantBackendError {
            collectedError = error
        }

        #expect(collectedEvents.contains(.stderrLine("failed")))
        #expect(collectedEvents.contains(.failed(message: "The assistant backend exited with status 42: failed")))
        #expect(collectedEvents.contains(.exit(AssistantBackendExit(exitCode: 42, reason: .failed, message: "failed"))))
        #expect(collectedError == .processExitedWithNonzeroStatus(exitCode: 42, stderr: "failed"))
    }

    @Test func mockBackendSupportsDeterministicCancellation() async throws {
        let backend = MockBackend(
            configuration: MockBackendConfiguration(
                responseTextChunks: ["should not finish"],
                statusMessages: [],
                delayNanoseconds: 50_000_000
            )
        )
        let session = try await backend.startSession(context: AssistantSessionContext())
        let eventCollectionTask = Task {
            try await collectEvents(
                from: session.sendPrompt(AssistantPromptRequest(promptText: "test prompt"))
            )
        }

        session.cancel()
        let events = try await eventCollectionTask.value

        #expect(events.contains(.cancelled))
    }

    @Test func backendTextSanitizerRemovesANSIAndControlCharacters() {
        let sanitizedText = AssistantBackendTextSanitizer.sanitizedForDisplay(
            "\u{001B}[32mok\u{001B}[0m\u{0007}\nnext"
        )

        #expect(sanitizedText == "ok\nnext")
    }

    private func collectEvents(
        from stream: AsyncThrowingStream<AssistantBackendEvent, Error>
    ) async throws -> [AssistantBackendEvent] {
        var events: [AssistantBackendEvent] = []

        for try await event in stream {
            events.append(event)
        }

        return events
    }
}
