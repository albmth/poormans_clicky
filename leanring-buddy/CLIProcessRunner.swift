//
//  CLIProcessRunner.swift
//  leanring-buddy
//

import Darwin
import Foundation

struct CLIProcessRequest: Equatable, Sendable {
    let executableURL: URL
    let arguments: [String]
    let workingDirectoryURL: URL
    let standardInputText: String?
    let environment: [String: String]
    let timeoutSeconds: TimeInterval
    let terminationGraceSeconds: TimeInterval

    init(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL,
        standardInputText: String? = nil,
        environment: [String: String] = CLIProcessEnvironmentBuilder.minimalEnvironment(),
        timeoutSeconds: TimeInterval,
        terminationGraceSeconds: TimeInterval = 1
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.workingDirectoryURL = workingDirectoryURL
        self.standardInputText = standardInputText
        self.environment = CLIProcessEnvironmentBuilder.sanitizedEnvironment(from: environment)
        self.timeoutSeconds = timeoutSeconds
        self.terminationGraceSeconds = terminationGraceSeconds
    }

    func validate(fileManager: FileManager = .default) throws {
        guard executableURL.isFileURL, executableURL.path.hasPrefix("/") else {
            throw AssistantBackendError.backendDisabled("CLI executable must be an absolute file URL.")
        }

        guard !Self.disallowedExecutablePaths.contains(executableURL.path) else {
            throw AssistantBackendError.backendDisabled("CLI runner does not launch shell or env executables.")
        }

        guard fileManager.isExecutableFile(atPath: executableURL.path) else {
            throw AssistantBackendError.backendDisabled("CLI executable is missing or is not executable.")
        }

        var workingDirectoryIsDirectory: ObjCBool = false
        guard workingDirectoryURL.isFileURL,
              fileManager.fileExists(
                atPath: workingDirectoryURL.path,
                isDirectory: &workingDirectoryIsDirectory
              ),
              workingDirectoryIsDirectory.boolValue else {
            throw AssistantBackendError.backendDisabled("CLI working directory does not exist.")
        }

        guard timeoutSeconds > 0 else {
            throw AssistantBackendError.backendDisabled("CLI timeout must be greater than zero.")
        }

        guard terminationGraceSeconds >= 0 else {
            throw AssistantBackendError.backendDisabled("CLI termination grace period cannot be negative.")
        }
    }

    private static let disallowedExecutablePaths: Set<String> = [
        "/bin/bash",
        "/bin/csh",
        "/bin/ksh",
        "/bin/sh",
        "/bin/tcsh",
        "/bin/zsh",
        "/usr/bin/env"
    ]
}

enum CLIProcessEnvironmentBuilder {
    static func minimalEnvironment(
        homeDirectory: String = NSHomeDirectory(),
        path: String = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    ) -> [String: String] {
        [
            "HOME": homeDirectory,
            "PATH": path,
            "TERM": "dumb",
            "LANG": "C",
            "LC_ALL": "C"
        ]
    }

    static func sanitizedEnvironment(from environment: [String: String]) -> [String: String] {
        var sanitizedEnvironment: [String: String] = [:]
        let allowedKeys: Set<String> = ["HOME", "PATH", "TERM", "LANG", "LC_ALL", "TMPDIR"]

        for (key, value) in environment {
            guard allowedKeys.contains(key) else {
                continue
            }

            guard !looksLikeCredentialKey(key) else {
                continue
            }

            sanitizedEnvironment[key] = value
        }

        if sanitizedEnvironment["TERM"] == nil {
            sanitizedEnvironment["TERM"] = "dumb"
        }

        if sanitizedEnvironment["PATH"] == nil {
            sanitizedEnvironment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        }

        return sanitizedEnvironment
    }

    static func looksLikeCredentialKey(_ key: String) -> Bool {
        let uppercasedKey = key.uppercased()
        let credentialFragments = [
            "TOKEN",
            "SECRET",
            "API_KEY",
            "ACCESS_KEY",
            "PRIVATE_KEY",
            "PASSWORD",
            "CREDENTIAL",
            "COOKIE",
            "SESSION"
        ]

        if uppercasedKey.hasPrefix("AWS_") {
            return true
        }

        return credentialFragments.contains { uppercasedKey.contains($0) }
    }
}

enum CLIProcessEvent: Equatable, Sendable {
    case started(processIdentifier: Int32)
    case stdoutTextDelta(String)
    case stderrLine(String)
    case exit(CLIProcessExit)
    case cancelled
    case failed(message: String)
}

enum CLIProcessExitReason: String, Equatable, Sendable {
    case completed
    case failed
    case timedOut = "timed-out"
}

struct CLIProcessExit: Equatable, Sendable {
    let exitCode: Int32
    let reason: CLIProcessExitReason
}

final class CLIProcessRun: @unchecked Sendable {
    let events: AsyncThrowingStream<CLIProcessEvent, Error>
    private let cancelHandler: @Sendable () -> Void

    init(
        events: AsyncThrowingStream<CLIProcessEvent, Error>,
        cancelHandler: @escaping @Sendable () -> Void
    ) {
        self.events = events
        self.cancelHandler = cancelHandler
    }

    func cancel() {
        cancelHandler()
    }
}

protocol CLIProcessRunning: Sendable {
    func run(_ request: CLIProcessRequest) -> CLIProcessRun
}

final class CLIProcessRunner: CLIProcessRunning, @unchecked Sendable {
    func run(_ request: CLIProcessRequest) -> CLIProcessRun {
        let controller = CLIProcessRunController(request: request)
        return controller.start()
    }
}

private enum CLIProcessStopReason: Equatable {
    case none
    case cancelled
    case timedOut
}

private final class CLIProcessRunController: @unchecked Sendable {
    private let request: CLIProcessRequest
    private let stateLock = NSLock()
    private var process: Process?
    private var stopReason: CLIProcessStopReason = .none
    private var hasFinished = false

    init(request: CLIProcessRequest) {
        self.request = request
    }

    func start() -> CLIProcessRun {
        let eventStream = AsyncThrowingStream<CLIProcessEvent, Error> { continuation in
            startProcess(continuation: continuation)
            continuation.onTermination = { [weak self] _ in
                self?.cancel()
            }
        }

        return CLIProcessRun(events: eventStream) { [weak self] in
            self?.cancel()
        }
    }

    private func startProcess(
        continuation: AsyncThrowingStream<CLIProcessEvent, Error>.Continuation
    ) {
        do {
            try request.validate()
        } catch {
            continuation.finish(throwing: error)
            return
        }

        let process = Process()
        process.executableURL = request.executableURL
        process.arguments = request.arguments
        process.currentDirectoryURL = request.workingDirectoryURL
        process.environment = request.environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()

        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = stdinPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let availableData = handle.availableData
            guard !availableData.isEmpty,
                  let rawText = String(data: availableData, encoding: .utf8) else {
                return
            }

            let sanitizedText = AssistantBackendTextSanitizer.sanitizedForDisplay(rawText)
            guard !sanitizedText.isEmpty else {
                return
            }

            continuation.yield(.stdoutTextDelta(sanitizedText))
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let availableData = handle.availableData
            guard !availableData.isEmpty,
                  let rawText = String(data: availableData, encoding: .utf8) else {
                return
            }

            let sanitizedText = AssistantBackendTextSanitizer.sanitizedForDisplay(rawText)
            for stderrLine in sanitizedText.split(whereSeparator: \.isNewline) {
                continuation.yield(.stderrLine(String(stderrLine)))
            }
        }

        process.terminationHandler = { [weak self] terminatedProcess in
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            self?.finishProcess(
                terminatedProcess,
                continuation: continuation
            )
        }

        do {
            stateLock.lock()
            self.process = process
            stateLock.unlock()

            try process.run()
            continuation.yield(.started(processIdentifier: process.processIdentifier))

            if let standardInputText = request.standardInputText,
               let standardInputData = standardInputText.data(using: .utf8) {
                stdinPipe.fileHandleForWriting.write(standardInputData)
            }
            stdinPipe.fileHandleForWriting.closeFile()

            scheduleTimeout()
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            continuation.finish(throwing: error)
        }
    }

    private func scheduleTimeout() {
        let timeoutNanoseconds = UInt64(request.timeoutSeconds * 1_000_000_000)

        Task.detached { [weak self] in
            try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            self?.timeout()
        }
    }

    private func timeout() {
        stateLock.lock()
        guard let process, process.isRunning, stopReason == .none else {
            stateLock.unlock()
            return
        }

        stopReason = .timedOut
        stateLock.unlock()

        process.interrupt()
        scheduleForcedKillIfNeeded(for: process)
    }

    private func cancel() {
        stateLock.lock()
        guard let process, process.isRunning, stopReason == .none else {
            stateLock.unlock()
            return
        }

        stopReason = .cancelled
        stateLock.unlock()

        process.interrupt()
        scheduleForcedKillIfNeeded(for: process)
    }

    private func scheduleForcedKillIfNeeded(for process: Process) {
        let graceNanoseconds = UInt64(request.terminationGraceSeconds * 1_000_000_000)

        Task.detached {
            try? await Task.sleep(nanoseconds: graceNanoseconds)
            guard process.isRunning else {
                return
            }

            kill(process.processIdentifier, SIGKILL)
        }
    }

    private func finishProcess(
        _ terminatedProcess: Process,
        continuation: AsyncThrowingStream<CLIProcessEvent, Error>.Continuation
    ) {
        stateLock.lock()
        guard !hasFinished else {
            stateLock.unlock()
            return
        }

        hasFinished = true
        let finalStopReason = stopReason
        process = nil
        stateLock.unlock()

        switch finalStopReason {
        case .cancelled:
            continuation.yield(.cancelled)
        case .timedOut:
            continuation.yield(.failed(message: AssistantBackendError.timedOut(request.timeoutSeconds).localizedDescription))
            continuation.yield(
                .exit(
                    CLIProcessExit(
                        exitCode: terminatedProcess.terminationStatus,
                        reason: .timedOut
                    )
                )
            )
        case .none:
            let exitReason: CLIProcessExitReason = terminatedProcess.terminationStatus == 0 ? .completed : .failed
            continuation.yield(
                .exit(
                    CLIProcessExit(
                        exitCode: terminatedProcess.terminationStatus,
                        reason: exitReason
                    )
                )
            )
        }

        continuation.finish()
    }
}

extension LocalCLICommandPlan {
    func makeProcessRequest(
        environment: [String: String] = CLIProcessEnvironmentBuilder.minimalEnvironment(),
        terminationGraceSeconds: TimeInterval = 1
    ) -> CLIProcessRequest {
        CLIProcessRequest(
            executableURL: executableURL,
            arguments: arguments,
            workingDirectoryURL: workingDirectoryURL,
            standardInputText: standardInputText,
            environment: environment,
            timeoutSeconds: timeoutSeconds,
            terminationGraceSeconds: terminationGraceSeconds
        )
    }
}
