//
//  MockBackend.swift
//  leanring-buddy
//

import Foundation

struct MockBackend: AssistantBackend {
    let configuration: MockBackendConfiguration

    let kind: AssistantBackendKind = .mock
    let displayName = "Mock Assistant"

    init(configuration: MockBackendConfiguration = .standard) {
        self.configuration = configuration
    }

    func checkAvailability() async -> AssistantBackendAvailability {
        .available(message: "Mock backend is ready.")
    }

    func makeStatusSummary() async -> AssistantBackendStatusSummary {
        let availability = await checkAvailability()

        return AssistantBackendStatusSummary(
            kind: kind,
            displayName: displayName,
            availability: availability,
            authority: .readOnly,
            statusText: availability.message,
            detailText: "Uses deterministic local output for development and tests."
        )
    }

    func startSession(context: AssistantSessionContext) async throws -> AssistantBackendSession {
        MockBackendSession(displayName: displayName, configuration: configuration)
    }
}

struct MockBackendConfiguration: Equatable, Sendable {
    let responseTextChunks: [String]
    let statusMessages: [String]
    let delayNanoseconds: UInt64
    let behavior: MockBackendBehavior

    init(
        responseTextChunks: [String] = ["Mock response from the local assistant backend."],
        statusMessages: [String] = ["Preparing local mock response."],
        delayNanoseconds: UInt64 = 0,
        behavior: MockBackendBehavior = .normal
    ) {
        self.responseTextChunks = responseTextChunks
        self.statusMessages = statusMessages
        self.delayNanoseconds = delayNanoseconds
        self.behavior = behavior
    }

    static let standard = MockBackendConfiguration()
}

enum MockBackendBehavior: Equatable, Sendable {
    case normal
    case emitsStderr(line: String)
    case emitsMalformedOutput(String)
    case exitsWithFailure(exitCode: Int32, stderr: String)
    case timesOut
}

final class MockBackendSession: AssistantBackendSession, @unchecked Sendable {
    private let displayName: String
    private let configuration: MockBackendConfiguration
    private let cancellationState = MockBackendCancellationState()

    init(displayName: String, configuration: MockBackendConfiguration) {
        self.displayName = displayName
        self.configuration = configuration
    }

    func sendPrompt(_ request: AssistantPromptRequest) -> AsyncThrowingStream<AssistantBackendEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await streamResponse(for: request, continuation: continuation)
                } catch is CancellationError {
                    yieldCancelledIfNeeded(continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { [cancellationState] _ in
                cancellationState.cancel()
                task.cancel()
            }
        }
    }

    func cancel() {
        cancellationState.cancel()
    }

    private func streamResponse(
        for request: AssistantPromptRequest,
        continuation: AsyncThrowingStream<AssistantBackendEvent, Error>.Continuation
    ) async throws {
        continuation.yield(.started(displayName: displayName))

        guard !request.trimmedPromptText.isEmpty else {
            let message = AssistantBackendError.emptyPrompt.localizedDescription
            continuation.yield(.failed(message: message))
            continuation.finish(throwing: AssistantBackendError.emptyPrompt)
            return
        }

        guard !yieldCancelledIfNeeded(continuation) else {
            return
        }

        for statusMessage in configuration.statusMessages {
            continuation.yield(.statusChanged(statusMessage))
            try await pauseIfNeeded()

            guard !yieldCancelledIfNeeded(continuation) else {
                return
            }
        }

        switch configuration.behavior {
        case .normal:
            break
        case .emitsStderr(let line):
            continuation.yield(.stderrLine(AssistantBackendTextSanitizer.sanitizedForDisplay(line)))
        case .emitsMalformedOutput(let output):
            continuation.yield(.stderrLine(AssistantBackendTextSanitizer.sanitizedForDisplay(output)))
        case .exitsWithFailure(let exitCode, let stderr):
            let sanitizedStderr = AssistantBackendTextSanitizer.sanitizedForDisplay(stderr)
            let error = AssistantBackendError.processExitedWithNonzeroStatus(
                exitCode: exitCode,
                stderr: sanitizedStderr
            )
            continuation.yield(.stderrLine(sanitizedStderr))
            continuation.yield(.failed(message: error.localizedDescription))
            continuation.yield(
                .exit(
                    AssistantBackendExit(
                        exitCode: exitCode,
                        reason: .failed,
                        message: sanitizedStderr
                    )
                )
            )
            continuation.finish(throwing: error)
            return
        case .timesOut:
            try await pauseUntilTimeout(for: request)

            let error = AssistantBackendError.timedOut(request.timeoutSeconds)
            continuation.yield(.failed(message: error.localizedDescription))
            continuation.finish(throwing: error)
            return
        }

        for responseTextChunk in configuration.responseTextChunks {
            let sanitizedResponseTextChunk = AssistantBackendTextSanitizer.sanitizedForDisplay(responseTextChunk)

            if !sanitizedResponseTextChunk.isEmpty {
                continuation.yield(.stdoutTextDelta(sanitizedResponseTextChunk))
            }

            try await pauseIfNeeded()

            guard !yieldCancelledIfNeeded(continuation) else {
                return
            }
        }

        continuation.yield(
            .usage(
                AssistantBackendUsage(
                    inputUnits: request.trimmedPromptText.count,
                    outputUnits: configuration.responseTextChunks.joined().count
                )
            )
        )
        continuation.yield(
            .exit(
                AssistantBackendExit(
                    exitCode: 0,
                    reason: .completed,
                    message: nil
                )
            )
        )
        continuation.finish()
    }

    @discardableResult
    private func yieldCancelledIfNeeded(
        _ continuation: AsyncThrowingStream<AssistantBackendEvent, Error>.Continuation
    ) -> Bool {
        guard cancellationState.isCancelled || Task.isCancelled else {
            return false
        }

        continuation.yield(.cancelled)
        continuation.finish()
        return true
    }

    private func pauseIfNeeded() async throws {
        guard configuration.delayNanoseconds > 0 else {
            return
        }

        try await Task.sleep(nanoseconds: configuration.delayNanoseconds)
    }

    private func pauseUntilTimeout(for request: AssistantPromptRequest) async throws {
        let timeoutSeconds = max(0, request.timeoutSeconds)
        let timeoutNanoseconds = UInt64(timeoutSeconds * 1_000_000_000)
        let fallbackTimeoutNanoseconds: UInt64 = 1_000_000

        try await Task.sleep(nanoseconds: min(timeoutNanoseconds, fallbackTimeoutNanoseconds))
    }
}

final class MockBackendCancellationState: @unchecked Sendable {
    private let lock = NSLock()
    private var isCancelledValue = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }

        return isCancelledValue
    }

    func cancel() {
        lock.lock()
        isCancelledValue = true
        lock.unlock()
    }
}
