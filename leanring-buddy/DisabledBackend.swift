//
//  DisabledBackend.swift
//  leanring-buddy
//

import Foundation

struct DisabledBackend: AssistantBackend {
    static let setupMessage = "No local assistant backend is selected yet."

    let kind: AssistantBackendKind = .disabled
    let displayName = "No Assistant"

    func checkAvailability() async -> AssistantBackendAvailability {
        .available(message: Self.setupMessage)
    }

    func makeStatusSummary() async -> AssistantBackendStatusSummary {
        let availability = await checkAvailability()

        return AssistantBackendStatusSummary(
            kind: kind,
            displayName: displayName,
            availability: availability,
            authority: .disabled,
            statusText: Self.setupMessage,
            detailText: "Choose a local backend before sending assistant prompts."
        )
    }

    func startSession(context: AssistantSessionContext) async throws -> AssistantBackendSession {
        DisabledBackendSession(displayName: displayName)
    }
}

final class DisabledBackendSession: AssistantBackendSession {
    private let displayName: String

    init(displayName: String) {
        self.displayName = displayName
    }

    func sendPrompt(_ request: AssistantPromptRequest) -> AsyncThrowingStream<AssistantBackendEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.started(displayName: displayName))
            continuation.yield(.statusChanged(DisabledBackend.setupMessage))
            continuation.yield(
                .exit(
                    AssistantBackendExit(
                        exitCode: 0,
                        reason: .completed,
                        message: DisabledBackend.setupMessage
                    )
                )
            )
            continuation.finish()
        }
    }

    func cancel() {}
}
