//
//  LocalCLIBackendSession.swift
//  leanring-buddy
//

import Foundation

final class LocalCLIBackendSession: AssistantBackendSession, @unchecked Sendable {
    private let displayName: String
    private let configuration: LocalCLIBackendConfiguration
    private let gate: LocalCLIBackendGate
    private let executableURL: URL
    private let context: AssistantSessionContext
    private let processRunner: any CLIProcessRunning
    private let stateLock = NSLock()
    private var currentProcessRun: CLIProcessRun?

    init(
        displayName: String,
        configuration: LocalCLIBackendConfiguration,
        gate: LocalCLIBackendGate,
        executableURL: URL,
        context: AssistantSessionContext,
        processRunner: any CLIProcessRunning
    ) {
        self.displayName = displayName
        self.configuration = configuration
        self.gate = gate
        self.executableURL = executableURL
        self.context = context
        self.processRunner = processRunner
    }

    func sendPrompt(_ request: AssistantPromptRequest) -> AsyncThrowingStream<AssistantBackendEvent, Error> {
        AsyncThrowingStream { continuation in
            let streamTask = Task {
                await runPrompt(
                    request,
                    continuation: continuation
                )
            }

            continuation.onTermination = { [weak self] _ in
                streamTask.cancel()
                self?.cancel()
            }
        }
    }

    func cancel() {
        stateLock.lock()
        let processRun = currentProcessRun
        stateLock.unlock()

        processRun?.cancel()
    }

    private func runPrompt(
        _ request: AssistantPromptRequest,
        continuation: AsyncThrowingStream<AssistantBackendEvent, Error>.Continuation
    ) async {
        do {
            let commandPlan = try makeCommandPlan(request: request)
            let processRequest = commandPlan.makeProcessRequest()
            let processRun = processRunner.run(processRequest)

            setCurrentProcessRun(processRun)

            continuation.yield(.started(displayName: displayName))
            continuation.yield(.statusChanged("Running \(displayName)"))

            try await forwardProcessEvents(
                from: processRun,
                continuation: continuation
            )
        } catch {
            clearCurrentProcessRun()
            continuation.finish(throwing: error)
        }
    }

    private func makeCommandPlan(request: AssistantPromptRequest) throws -> LocalCLICommandPlan {
        guard !request.trimmedPromptText.isEmpty else {
            throw AssistantBackendError.emptyPrompt
        }

        if let validationFailure = gate.validationFailure(context: context, request: request) {
            throw AssistantBackendError.backendDisabled(validationFailure)
        }

        guard let workingDirectoryURL = context.workingDirectory else {
            throw AssistantBackendError.backendDisabled("Choose a working directory before using a CLI backend.")
        }

        let arguments = configuration.commandProfile.arguments(
            workingDirectoryURL: workingDirectoryURL,
            attachedImageFileURLs: request.attachedImageFileURLs
        )

        return LocalCLICommandPlan(
            executableURL: executableURL,
            arguments: arguments,
            workingDirectoryURL: workingDirectoryURL,
            standardInputText: request.promptText,
            timeoutSeconds: min(request.timeoutSeconds, gate.timeoutSeconds),
            authority: gate.authority
        )
    }

    private func forwardProcessEvents(
        from processRun: CLIProcessRun,
        continuation: AsyncThrowingStream<AssistantBackendEvent, Error>.Continuation
    ) async throws {
        var stderrLines: [String] = []

        for try await processEvent in processRun.events {
            guard !Task.isCancelled else {
                processRun.cancel()
                throw AssistantBackendError.cancelled
            }

            switch processEvent {
            case .started:
                continuation.yield(.statusChanged("\(displayName) process started"))
            case .stdoutTextDelta(let textDelta):
                continuation.yield(.stdoutTextDelta(textDelta))
            case .stderrLine(let stderrLine):
                stderrLines.append(stderrLine)
                continuation.yield(.stderrLine(stderrLine))
            case .exit(let processExit):
                try handleProcessExit(
                    processExit,
                    stderrLines: stderrLines,
                    continuation: continuation
                )
            case .cancelled:
                continuation.yield(.cancelled)
                clearCurrentProcessRun()
                continuation.finish()
                return
            case .failed(let message):
                continuation.yield(.failed(message: message))
            }
        }

        clearCurrentProcessRun()
        continuation.finish()
    }

    private func handleProcessExit(
        _ processExit: CLIProcessExit,
        stderrLines: [String],
        continuation: AsyncThrowingStream<AssistantBackendEvent, Error>.Continuation
    ) throws {
        switch processExit.reason {
        case .completed:
            continuation.yield(
                .exit(
                    AssistantBackendExit(
                        exitCode: processExit.exitCode,
                        reason: .completed,
                        message: nil
                    )
                )
            )
        case .failed, .timedOut:
            let stderr = stderrLines.joined(separator: "\n")
            let error: AssistantBackendError

            if processExit.reason == .timedOut {
                error = .timedOut(gate.timeoutSeconds)
            } else {
                error = .processExitedWithNonzeroStatus(
                    exitCode: processExit.exitCode,
                    stderr: stderr
                )
            }

            continuation.yield(
                .exit(
                    AssistantBackendExit(
                        exitCode: processExit.exitCode,
                        reason: .failed,
                        message: error.localizedDescription
                    )
                )
            )
            throw error
        }
    }

    private func clearCurrentProcessRun() {
        stateLock.lock()
        currentProcessRun = nil
        stateLock.unlock()
    }

    private func setCurrentProcessRun(_ processRun: CLIProcessRun) {
        stateLock.lock()
        currentProcessRun = processRun
        stateLock.unlock()
    }
}
