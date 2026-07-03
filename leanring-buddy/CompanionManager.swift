//
//  CompanionManager.swift
//  leanring-buddy
//

import AppKit
import Combine
import Foundation

enum AssistantRunState: Equatable {
    case idle
    case running
    case cancelling
}

@MainActor
final class CompanionManager: ObservableObject {
    @Published private(set) var assistantRunState: AssistantRunState = .idle
    @Published private(set) var assistantBackendDisplayName: String
    @Published private(set) var assistantBackendStatusText: String = "Ready"
    @Published private(set) var assistantStreamingResponseText: String = ""
    @Published private(set) var assistantErrorMessage: String?
    @Published private(set) var assistantBackendLastUsage: AssistantBackendUsage?
    @Published private(set) var workingDirectoryPath: String
    @Published private(set) var hasScreenCapturePermission: Bool
    @Published private(set) var screenCaptureStatusText: String

    private let assistantBackend: any AssistantBackend
    private let screenOverlayWindowManager = ScreenOverlayWindowManager()
    private var currentResponseTask: Task<Void, Never>?
    private var currentAssistantBackendSession: (any AssistantBackendSession)?

    var isRequestInFlight: Bool {
        assistantRunState == .running || assistantRunState == .cancelling
    }

    init(assistantBackend: any AssistantBackend = AssistantBackendCatalog.defaultDevelopmentBackend()) {
        self.assistantBackend = assistantBackend
        self.assistantBackendDisplayName = assistantBackend.displayName
        self.workingDirectoryPath = AssistantBackendCatalog.configuredWorkingDirectory()?.path ?? ""
        let initialHasScreenCapturePermission = LocalScreenCaptureService.hasScreenCapturePermission()
        self.hasScreenCapturePermission = initialHasScreenCapturePermission
        self.screenCaptureStatusText = Self.screenCaptureStatusText(
            hasScreenCapturePermission: initialHasScreenCapturePermission
        )
    }

    func start() {
        refreshScreenCapturePermissionStatus()

        Task {
            await refreshBackendStatus()
        }
    }

    func stop() {
        cancelCurrentAssistantBackendRequest()
        clearScreenOverlay()
    }

    func refreshBackendStatus() async {
        let statusSummary = await assistantBackend.makeStatusSummary()
        assistantBackendDisplayName = statusSummary.displayName
        assistantBackendStatusText = statusSummary.statusText
        assistantErrorMessage = statusSummary.availability.canStartSession ? nil : statusSummary.statusText
    }

    func updateWorkingDirectoryPath(_ newPath: String) {
        let trimmedPath = newPath.trimmingCharacters(in: .whitespacesAndNewlines)
        workingDirectoryPath = trimmedPath

        if trimmedPath.isEmpty {
            UserDefaults.standard.removeObject(
                forKey: AssistantBackendCatalog.workingDirectoryUserDefaultsKey
            )
        } else {
            UserDefaults.standard.set(
                trimmedPath,
                forKey: AssistantBackendCatalog.workingDirectoryUserDefaultsKey
            )
        }
    }

    func resetWorkingDirectoryToTemporaryDirectory() {
        UserDefaults.standard.removeObject(
            forKey: AssistantBackendCatalog.workingDirectoryUserDefaultsKey
        )
        workingDirectoryPath = AssistantBackendCatalog.configuredWorkingDirectory()?.path ?? ""
    }

    func cancelCurrentAssistantBackendRequest() {
        guard isRequestInFlight else {
            return
        }

        assistantRunState = .cancelling
        currentAssistantBackendSession?.cancel()
        currentResponseTask?.cancel()
        finishCancelledAssistantBackendRequest()
    }

    func clearScreenOverlay() {
        screenOverlayWindowManager.clear()
    }

    func requestScreenCapturePermission() {
        let wasGranted = LocalScreenCaptureService.requestScreenCapturePermission()
        refreshScreenCapturePermissionStatus()

        if !wasGranted {
            screenCaptureStatusText = "Grant Screen Recording in System Settings, then relaunch if macOS asks."
        }
    }

    func refreshScreenCapturePermissionStatus() {
        hasScreenCapturePermission = LocalScreenCaptureService.hasScreenCapturePermission()
        screenCaptureStatusText = Self.screenCaptureStatusText(
            hasScreenCapturePermission: hasScreenCapturePermission
        )
    }

    @discardableResult
    func sendPromptToAssistantBackend(promptText: String) -> Task<Void, Never> {
        currentAssistantBackendSession?.cancel()
        currentAssistantBackendSession = nil
        currentResponseTask?.cancel()

        assistantStreamingResponseText = ""
        assistantErrorMessage = nil
        assistantBackendLastUsage = nil
        assistantBackendDisplayName = assistantBackend.displayName
        assistantBackendStatusText = "Starting \(assistantBackend.displayName)"
        assistantRunState = .running
        clearScreenOverlay()

        let responseTask = Task {
            await self.runAssistantBackendRequest(promptText: promptText)
        }
        currentResponseTask = responseTask
        return responseTask
    }

    @discardableResult
    func sendTutorialGuidePrompt(userGoal: String) -> Task<Void, Never>? {
        let trimmedUserGoal = userGoal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUserGoal.isEmpty else {
            return nil
        }

        return sendPromptToAssistantBackend(
            promptText: Self.tutorialGuidePrompt(for: trimmedUserGoal)
        )
    }

    static func tutorialGuidePrompt(for userGoal: String) -> String {
        """
        Act like an in-context game tutorial guide for the user's current macOS screen.
        The user wants to do this:
        \(userGoal)

        Give the next one to three concrete actions only.
        Keep each step short enough to scan while the user is working.
        Prefer one clear next target over many competing targets.
        Use the local overlay commands to draw directly on the screen.
        Start with [CLEAR] when replacing older guidance.
        Use [RECT] for buttons, fields, menus, windows, and regions.
        Use [POINT] for an exact click or focus target.
        Use [LINE] when the user should move from one place to another.
        Label overlays like a game tutorial callout, such as "1. Click Send" or "Next: Settings".
        """
    }

    private func runAssistantBackendRequest(promptText: String) async {
        var accumulatedResponseText = ""
        var screenCaptureBatch: LocalScreenCaptureBatch?

        defer {
            LocalScreenCaptureService.removeTemporaryCaptureDirectory(for: screenCaptureBatch)
        }

        do {
            let selectedBackendAvailability = await assistantBackend.checkAvailability()
            guard selectedBackendAvailability.canStartSession else {
                throw AssistantBackendError.backendDisabled(selectedBackendAvailability.message)
            }

            assistantBackendStatusText = selectedBackendAvailability.message

            guard let workingDirectoryURL = AssistantBackendCatalog.configuredWorkingDirectory() else {
                throw AssistantBackendError.backendDisabled("Choose a working directory before sending a prompt.")
            }

            workingDirectoryPath = workingDirectoryURL.path
            let sessionContext = AssistantSessionContext(
                workingDirectory: workingDirectoryURL,
                authority: .readOnly
            )
            let assistantBackendSession = try await assistantBackend.startSession(context: sessionContext)
            currentAssistantBackendSession = assistantBackendSession
            screenCaptureBatch = await makeScreenCaptureBatchForCurrentRequest()

            let promptRequest = AssistantPromptRequest(
                promptText: promptTextForBackend(
                    promptText,
                    screenCaptureBatch: screenCaptureBatch
                ),
                attachedImageFileURLs: screenCaptureBatch?.imageFileURLs ?? []
            )
            for try await event in assistantBackendSession.sendPrompt(promptRequest) {
                guard !Task.isCancelled else {
                    assistantBackendSession.cancel()
                    throw CancellationError()
                }

                let shouldContinue = handleAssistantBackendEvent(
                    event,
                    accumulatedResponseText: &accumulatedResponseText
                )

                guard shouldContinue else {
                    break
                }
            }

            guard !Task.isCancelled else {
                throw CancellationError()
            }

            finishAssistantBackendRequest(accumulatedResponseText: accumulatedResponseText)
        } catch is CancellationError {
            finishCancelledAssistantBackendRequest()
        } catch {
            finishFailedAssistantBackendRequest(error)
        }

        currentAssistantBackendSession = nil
        currentResponseTask = nil
    }

    @discardableResult
    private func handleAssistantBackendEvent(
        _ event: AssistantBackendEvent,
        accumulatedResponseText: inout String
    ) -> Bool {
        switch event {
        case .availabilityChanged(let availability):
            assistantBackendStatusText = availability.message
            assistantErrorMessage = availability.canStartSession ? nil : availability.message
        case .started(let displayName):
            assistantBackendDisplayName = displayName
            assistantBackendStatusText = "Started \(displayName)"
        case .statusChanged(let statusText):
            assistantBackendStatusText = statusText
        case .stdoutTextDelta(let textDelta):
            accumulatedResponseText += textDelta
            assistantStreamingResponseText = accumulatedResponseText
            assistantBackendStatusText = "Responding"
            screenOverlayWindowManager.applyCommands(in: accumulatedResponseText)
        case .stderrLine(let stderrLine):
            assistantBackendStatusText = stderrLine
        case .toolActivity(let toolActivity):
            if let detail = toolActivity.detail {
                assistantBackendStatusText = "\(toolActivity.title): \(detail)"
            } else {
                assistantBackendStatusText = toolActivity.title
            }
        case .permissionRequest(let permissionRequest):
            assistantBackendStatusText = permissionRequest.title
            assistantErrorMessage = permissionRequest.message
        case .usage(let usage):
            assistantBackendLastUsage = usage
        case .exit(let exit):
            if exit.reason == .completed {
                assistantBackendStatusText = exit.message ?? "Completed"
            } else {
                assistantBackendStatusText = exit.message ?? "Backend exited with status \(exit.exitCode)"
            }
        case .cancelled:
            finishCancelledAssistantBackendRequest()
            return false
        case .failed(let message):
            assistantErrorMessage = message
            assistantBackendStatusText = message
            assistantStreamingResponseText = message
        }

        return true
    }

    private func finishAssistantBackendRequest(accumulatedResponseText: String) {
        let finalResponseText = accumulatedResponseText.trimmingCharacters(in: .whitespacesAndNewlines)

        if !finalResponseText.isEmpty {
            assistantStreamingResponseText = finalResponseText
        }

        assistantBackendStatusText = "Completed"
        assistantRunState = .idle
    }

    private func finishCancelledAssistantBackendRequest() {
        currentAssistantBackendSession?.cancel()
        assistantErrorMessage = nil
        assistantBackendStatusText = "Cancelled"
        assistantRunState = .idle
    }

    private func finishFailedAssistantBackendRequest(_ error: Error) {
        let errorMessage = error.localizedDescription
        assistantErrorMessage = errorMessage
        assistantBackendStatusText = errorMessage
        assistantStreamingResponseText = errorMessage
        assistantRunState = .idle
    }

    private func makeScreenCaptureBatchForCurrentRequest() async -> LocalScreenCaptureBatch? {
        guard assistantBackend.kind == .codexCLI else {
            return nil
        }

        refreshScreenCapturePermissionStatus()

        guard hasScreenCapturePermission else {
            screenCaptureStatusText = "Screen Recording is off. Codex will receive text only."
            return nil
        }

        do {
            let screenCaptureBatch = try await LocalScreenCaptureService.captureAllDisplays()
            screenCaptureStatusText = "Attached \(screenCaptureBatch.captures.count) screen image(s) to Codex."
            return screenCaptureBatch
        } catch {
            screenCaptureStatusText = "\(error.localizedDescription) Sending text only."
            return nil
        }
    }

    private func promptTextForBackend(
        _ userPromptText: String,
        screenCaptureBatch: LocalScreenCaptureBatch?
    ) -> String {
        guard assistantBackend.kind == .codexCLI else {
            return userPromptText
        }

        return """
        You are powering a local macOS screen overlay.
        Keep the answer useful and concise.

        You can draw on the user's screen by appending overlay commands at the end of your response.
        Coordinates use screen points with origin at the top-left of the target screen.
        Available commands:
        [POINT:x,y:label:screenN]
        [RECT:x,y,width,height:label:screenN]
        [LINE:x1,y1,x2,y2:label:screenN]
        [CLEAR]

        Use overlay commands only when they help.
        If no overlay is useful, do not include overlay commands.
        Current screen geometry:
        \(Self.screenDescription())

        Attached screen context:
        \(Self.screenCaptureDescription(screenCaptureBatch))

        For overlay commands, use screen points, not screenshot pixels.
        Convert screenshot pixels to points by dividing by the listed scale factor for that screen.

        User prompt:
        \(userPromptText)
        """
    }

    private static func screenDescription() -> String {
        NSScreen.screens.enumerated().map { screenIndex, screen in
            let frame = screen.frame
            return "screen\(screenIndex + 1): \(Int(frame.width))x\(Int(frame.height)) points"
        }
        .joined(separator: "\n")
    }

    private static func screenCaptureDescription(
        _ screenCaptureBatch: LocalScreenCaptureBatch?
    ) -> String {
        guard let screenCaptureBatch else {
            return "No screenshots are attached to this prompt."
        }

        return screenCaptureBatch.promptDescription
    }

    private static func screenCaptureStatusText(
        hasScreenCapturePermission: Bool
    ) -> String {
        if hasScreenCapturePermission {
            return "Screen context ready."
        }

        return "Grant Screen Recording so Codex can see the screen."
    }
}
