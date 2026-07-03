//
//  LocalCLIBackend.swift
//  leanring-buddy
//

import Foundation

struct LocalCLIBackendConfiguration: Equatable, Sendable {
    let kind: AssistantBackendKind
    let displayName: String
    let executableName: String
    let commandProfile: LocalCLICommandProfile
    let supportedInputModes: Set<LocalCLIBackendInputMode>
    let disabledMessage: String

    init(
        kind: AssistantBackendKind,
        displayName: String,
        executableName: String,
        commandProfile: LocalCLICommandProfile,
        supportedInputModes: Set<LocalCLIBackendInputMode> = [.text],
        disabledMessage: String
    ) {
        self.kind = kind
        self.displayName = displayName
        self.executableName = executableName
        self.commandProfile = commandProfile
        self.supportedInputModes = supportedInputModes
        self.disabledMessage = disabledMessage
    }
}

enum LocalCLICommandProfile: Equatable, Sendable {
    case codexReadOnlyOneShot
    case fixedArguments([String])

    func arguments(
        workingDirectoryURL: URL,
        attachedImageFileURLs: [URL] = []
    ) -> [String] {
        switch self {
        case .codexReadOnlyOneShot:
            var arguments = [
                "exec",
                "--sandbox",
                "read-only",
                "--skip-git-repo-check",
                "--ephemeral",
                "--color",
                "never",
                "--cd",
                workingDirectoryURL.path
            ]

            for attachedImageFileURL in attachedImageFileURLs {
                arguments.append("--image")
                arguments.append(attachedImageFileURL.path)
            }

            arguments.append("-")
            return arguments
        case .fixedArguments(let arguments):
            return arguments
        }
    }
}

enum LocalCLIBackendInputMode: String, Equatable, Hashable, Sendable {
    case text
    case imageFile = "image-file"
}

struct LocalCLIBackendGate: Equatable, Sendable {
    let isEnabled: Bool
    let authority: AssistantBackendAuthority
    let requiresExplicitWorkingDirectory: Bool
    let allowsImageAttachments: Bool
    let timeoutSeconds: TimeInterval

    init(
        isEnabled: Bool,
        authority: AssistantBackendAuthority,
        requiresExplicitWorkingDirectory: Bool,
        allowsImageAttachments: Bool,
        timeoutSeconds: TimeInterval
    ) {
        self.isEnabled = isEnabled
        self.authority = authority
        self.requiresExplicitWorkingDirectory = requiresExplicitWorkingDirectory
        self.allowsImageAttachments = allowsImageAttachments
        self.timeoutSeconds = timeoutSeconds
    }

    static let disabledReadOnly = LocalCLIBackendGate(
        isEnabled: false,
        authority: .readOnly,
        requiresExplicitWorkingDirectory: true,
        allowsImageAttachments: false,
        timeoutSeconds: 120
    )

    static let enabledReadOnlyOneShot = LocalCLIBackendGate(
        isEnabled: true,
        authority: .readOnly,
        requiresExplicitWorkingDirectory: true,
        allowsImageAttachments: true,
        timeoutSeconds: 120
    )

    func validationFailure(
        context: AssistantSessionContext,
        request: AssistantPromptRequest
    ) -> String? {
        guard isEnabled else {
            return "CLI backend execution is disabled while the local runner is being designed."
        }

        if requiresExplicitWorkingDirectory && context.workingDirectory == nil {
            return "Choose a working directory before using a CLI backend."
        }

        if !allowsImageAttachments && !request.attachedImageFileURLs.isEmpty {
            return "This CLI backend is currently text-only."
        }

        return nil
    }
}

struct LocalCLICommandPlan: Equatable, Sendable {
    let executableURL: URL
    let arguments: [String]
    let workingDirectoryURL: URL
    let standardInputText: String
    let timeoutSeconds: TimeInterval
    let authority: AssistantBackendAuthority
}

struct LocalCLIBackend: AssistantBackend {
    let configuration: LocalCLIBackendConfiguration
    let gate: LocalCLIBackendGate
    let executableResolver: CLIExecutableResolver
    let processRunner: any CLIProcessRunning

    var kind: AssistantBackendKind {
        configuration.kind
    }

    var displayName: String {
        configuration.displayName
    }

    init(
        configuration: LocalCLIBackendConfiguration,
        gate: LocalCLIBackendGate = .disabledReadOnly,
        executableResolver: CLIExecutableResolver = .standard,
        processRunner: any CLIProcessRunning = CLIProcessRunner()
    ) {
        self.configuration = configuration
        self.gate = gate
        self.executableResolver = executableResolver
        self.processRunner = processRunner
    }

    func checkAvailability() async -> AssistantBackendAvailability {
        makeAvailabilityReport().availability
    }

    func makeStatusSummary() async -> AssistantBackendStatusSummary {
        let availabilityReport = makeAvailabilityReport()

        return AssistantBackendStatusSummary(
            kind: kind,
            displayName: displayName,
            availability: availabilityReport.availability,
            authority: gate.authority,
            statusText: availabilityReport.availability.message,
            detailText: availabilityReport.detailText
        )
    }

    func startSession(context: AssistantSessionContext) async throws -> AssistantBackendSession {
        let availabilityReport = makeAvailabilityReport()
        guard availabilityReport.availability.canStartSession else {
            throw AssistantBackendError.backendDisabled(availabilityReport.availability.message)
        }

        guard let executableURL = availabilityReport.availability.executableURL else {
            throw AssistantBackendError.backendDisabled("CLI executable is missing or is not executable.")
        }

        if gate.requiresExplicitWorkingDirectory && context.workingDirectory == nil {
            throw AssistantBackendError.backendDisabled("Choose a working directory before using a CLI backend.")
        }

        return LocalCLIBackendSession(
            displayName: displayName,
            configuration: configuration,
            gate: gate,
            executableURL: executableURL,
            context: context,
            processRunner: processRunner
        )
    }

    func makeCommandPlan(
        executableURL: URL,
        context: AssistantSessionContext,
        request: AssistantPromptRequest,
        arguments: [String]
    ) throws -> LocalCLICommandPlan {
        if let validationFailure = gate.validationFailure(context: context, request: request) {
            throw AssistantBackendError.backendDisabled(validationFailure)
        }

        guard let workingDirectory = context.workingDirectory else {
            throw AssistantBackendError.backendDisabled("Choose a working directory before using a CLI backend.")
        }

        return LocalCLICommandPlan(
            executableURL: executableURL,
            arguments: arguments,
            workingDirectoryURL: workingDirectory,
            standardInputText: request.promptText,
            timeoutSeconds: min(request.timeoutSeconds, gate.timeoutSeconds),
            authority: gate.authority
        )
    }

    private func makeAvailabilityReport() -> (
        availability: AssistantBackendAvailability,
        detailText: String
    ) {
        let executableResolution = executableResolver.resolve(
            executableName: configuration.executableName
        )
        let executionGateText = gate.isEnabled
            ? "CLI launch is enabled in read-only one-shot mode."
            : "CLI launch is intentionally disabled in this migration phase."

        switch executableResolution {
        case .found(_, let executableURL, _):
            if gate.isEnabled {
                return (
                    availability: .loginUnknown(
                        message: "\(displayName) was found. Login status is not checked yet.",
                        executableURL: executableURL
                    ),
                    detailText: "\(executableResolution.statusMessage) \(executionGateText)"
                )
            }

            return (
                availability: .unavailable(
                    message: "\(configuration.disabledMessage) \(displayName) was found at \(executableURL.path).",
                    executableURL: executableURL
                ),
                detailText: "\(executableResolution.statusMessage) \(executionGateText)"
            )
        case .notFound, .notExecutable, .invalidExecutableName:
            let setupMessage = gate.isEnabled
                ? "\(displayName) is selected but not ready."
                : configuration.disabledMessage
            return (
                availability: .unavailable(
                    message: "\(setupMessage) \(executableResolution.statusMessage)"
                ),
                detailText: "\(executableResolution.statusMessage) \(executionGateText)"
            )
        }
    }
}

struct CodexCLIBackend: AssistantBackend {
    private let backend: LocalCLIBackend

    init(
        gate: LocalCLIBackendGate = .disabledReadOnly,
        executableResolver: CLIExecutableResolver = .standard,
        processRunner: any CLIProcessRunning = CLIProcessRunner()
    ) {
        self.backend = LocalCLIBackend(
            configuration: LocalCLIBackendConfiguration(
                kind: .codexCLI,
                displayName: "Codex CLI",
                executableName: "codex",
                commandProfile: .codexReadOnlyOneShot,
                disabledMessage: "Codex CLI backend is scaffolded but disabled."
            ),
            gate: gate,
            executableResolver: executableResolver,
            processRunner: processRunner
        )
    }

    var kind: AssistantBackendKind {
        backend.kind
    }

    var displayName: String {
        backend.displayName
    }

    func checkAvailability() async -> AssistantBackendAvailability {
        await backend.checkAvailability()
    }

    func makeStatusSummary() async -> AssistantBackendStatusSummary {
        await backend.makeStatusSummary()
    }

    func startSession(context: AssistantSessionContext) async throws -> AssistantBackendSession {
        try await backend.startSession(context: context)
    }
}

struct ClaudeCodeBackend: AssistantBackend {
    private let backend: LocalCLIBackend

    init(
        gate: LocalCLIBackendGate = .disabledReadOnly,
        executableResolver: CLIExecutableResolver = .standard,
        processRunner: any CLIProcessRunning = CLIProcessRunner()
    ) {
        self.backend = LocalCLIBackend(
            configuration: LocalCLIBackendConfiguration(
                kind: .claudeCode,
                displayName: "Claude Code",
                executableName: "claude",
                commandProfile: .fixedArguments([]),
                disabledMessage: "Claude Code backend is scaffolded but disabled."
            ),
            gate: gate,
            executableResolver: executableResolver,
            processRunner: processRunner
        )
    }

    var kind: AssistantBackendKind {
        backend.kind
    }

    var displayName: String {
        backend.displayName
    }

    func checkAvailability() async -> AssistantBackendAvailability {
        await backend.checkAvailability()
    }

    func makeStatusSummary() async -> AssistantBackendStatusSummary {
        await backend.makeStatusSummary()
    }

    func startSession(context: AssistantSessionContext) async throws -> AssistantBackendSession {
        try await backend.startSession(context: context)
    }
}
