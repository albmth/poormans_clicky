//
//  AssistantBackend.swift
//  leanring-buddy
//

import Foundation

protocol AssistantBackend: Sendable {
    var kind: AssistantBackendKind { get }
    var displayName: String { get }

    func checkAvailability() async -> AssistantBackendAvailability
    func makeStatusSummary() async -> AssistantBackendStatusSummary
    func startSession(context: AssistantSessionContext) async throws -> AssistantBackendSession
}

protocol AssistantBackendSession: Sendable {
    func sendPrompt(_ request: AssistantPromptRequest) -> AsyncThrowingStream<AssistantBackendEvent, Error>
    func cancel()
}

enum AssistantBackendKind: String, Equatable, Sendable {
    case disabled
    case mock
    case codexCLI = "codex-cli"
    case claudeCode = "claude-code"
}

enum AssistantBackendAuthority: String, Equatable, Sendable {
    case disabled
    case readOnly = "read-only"
    case explicitUserApproval = "explicit-user-approval"
}

struct AssistantSessionContext: Equatable, Sendable {
    let workingDirectory: URL?
    let authority: AssistantBackendAuthority
    let sessionIdentifier: UUID

    init(
        workingDirectory: URL? = nil,
        authority: AssistantBackendAuthority = .readOnly,
        sessionIdentifier: UUID = UUID()
    ) {
        self.workingDirectory = workingDirectory
        self.authority = authority
        self.sessionIdentifier = sessionIdentifier
    }
}

struct AssistantPromptRequest: Equatable, Sendable {
    let promptText: String
    let attachedImageFileURLs: [URL]
    let timeoutSeconds: TimeInterval

    init(
        promptText: String,
        attachedImageFileURLs: [URL] = [],
        timeoutSeconds: TimeInterval = 120
    ) {
        self.promptText = promptText
        self.attachedImageFileURLs = attachedImageFileURLs
        self.timeoutSeconds = timeoutSeconds
    }

    var trimmedPromptText: String {
        promptText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum AssistantBackendAvailabilityState: String, Equatable, Sendable {
    case available
    case unavailable
    case loginUnknown = "login-unknown"
}

struct AssistantBackendAvailability: Equatable, Sendable {
    let state: AssistantBackendAvailabilityState
    let message: String
    let version: String?
    let executableURL: URL?

    var isAvailable: Bool {
        state == .available
    }

    var canStartSession: Bool {
        state == .available || state == .loginUnknown
    }

    static func available(
        message: String,
        version: String? = nil,
        executableURL: URL? = nil
    ) -> AssistantBackendAvailability {
        AssistantBackendAvailability(
            state: .available,
            message: message,
            version: version,
            executableURL: executableURL
        )
    }

    static func unavailable(
        message: String,
        version: String? = nil,
        executableURL: URL? = nil
    ) -> AssistantBackendAvailability {
        AssistantBackendAvailability(
            state: .unavailable,
            message: message,
            version: version,
            executableURL: executableURL
        )
    }

    static func loginUnknown(
        message: String,
        version: String? = nil,
        executableURL: URL? = nil
    ) -> AssistantBackendAvailability {
        AssistantBackendAvailability(
            state: .loginUnknown,
            message: message,
            version: version,
            executableURL: executableURL
        )
    }
}

struct AssistantBackendStatusSummary: Equatable, Sendable {
    let kind: AssistantBackendKind
    let displayName: String
    let availability: AssistantBackendAvailability
    let authority: AssistantBackendAuthority
    let statusText: String
    let detailText: String?
}

enum AssistantBackendEvent: Equatable, Sendable {
    case availabilityChanged(AssistantBackendAvailability)
    case started(displayName: String)
    case statusChanged(String)
    case stdoutTextDelta(String)
    case stderrLine(String)
    case toolActivity(AssistantBackendToolActivity)
    case permissionRequest(AssistantBackendPermissionRequest)
    case usage(AssistantBackendUsage)
    case exit(AssistantBackendExit)
    case cancelled
    case failed(message: String)
}

struct AssistantBackendToolActivity: Equatable, Sendable {
    let title: String
    let detail: String?
}

struct AssistantBackendPermissionRequest: Equatable, Sendable {
    let title: String
    let message: String
}

struct AssistantBackendUsage: Equatable, Sendable {
    let inputUnits: Int?
    let outputUnits: Int?

    var totalUnits: Int? {
        guard inputUnits != nil || outputUnits != nil else {
            return nil
        }

        return (inputUnits ?? 0) + (outputUnits ?? 0)
    }
}

enum AssistantBackendExitReason: String, Equatable, Sendable {
    case completed
    case failed
}

struct AssistantBackendExit: Equatable, Sendable {
    let exitCode: Int32
    let reason: AssistantBackendExitReason
    let message: String?
}

enum AssistantBackendError: Error, Equatable, LocalizedError, Sendable {
    case backendDisabled(String)
    case emptyPrompt
    case timedOut(TimeInterval)
    case cancelled
    case processExitedWithNonzeroStatus(exitCode: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .backendDisabled(let message):
            return message
        case .emptyPrompt:
            return "Enter a prompt before sending."
        case .timedOut(let timeoutSeconds):
            return "The assistant backend timed out after \(Int(timeoutSeconds)) seconds."
        case .cancelled:
            return "The assistant request was cancelled."
        case .processExitedWithNonzeroStatus(let exitCode, let stderr):
            if stderr.isEmpty {
                return "The assistant backend exited with status \(exitCode)."
            }

            return "The assistant backend exited with status \(exitCode): \(stderr)"
        }
    }
}

enum AssistantBackendTextSanitizer {
    static func sanitizedForDisplay(_ text: String) -> String {
        var sanitizedScalars: [UnicodeScalar] = []
        var currentIndex = text.unicodeScalars.startIndex

        while currentIndex < text.unicodeScalars.endIndex {
            let currentScalar = text.unicodeScalars[currentIndex]

            if currentScalar.value == 0x1B {
                text.unicodeScalars.formIndex(after: &currentIndex)
                skipANSISequence(in: text, currentIndex: &currentIndex)
                continue
            }

            if shouldKeepForDisplay(currentScalar) {
                sanitizedScalars.append(currentScalar)
            }

            text.unicodeScalars.formIndex(after: &currentIndex)
        }

        return String(String.UnicodeScalarView(sanitizedScalars))
    }

    private static func skipANSISequence(
        in text: String,
        currentIndex: inout String.UnicodeScalarView.Index
    ) {
        guard currentIndex < text.unicodeScalars.endIndex else {
            return
        }

        guard text.unicodeScalars[currentIndex].value == 0x5B else {
            text.unicodeScalars.formIndex(after: &currentIndex)
            return
        }

        text.unicodeScalars.formIndex(after: &currentIndex)

        while currentIndex < text.unicodeScalars.endIndex {
            let scalarValue = text.unicodeScalars[currentIndex].value
            text.unicodeScalars.formIndex(after: &currentIndex)

            if scalarValue >= 0x40 && scalarValue <= 0x7E {
                return
            }
        }
    }

    private static func shouldKeepForDisplay(_ scalar: UnicodeScalar) -> Bool {
        if scalar.value >= 0x20 {
            return true
        }

        return scalar.value == 0x09 || scalar.value == 0x0A || scalar.value == 0x0D
    }
}
