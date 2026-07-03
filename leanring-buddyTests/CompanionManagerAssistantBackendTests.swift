//
//  CompanionManagerAssistantBackendTests.swift
//  leanring-buddyTests
//

import Testing
@testable import leanring_buddy

@MainActor
struct CompanionManagerAssistantBackendTests {

    @Test func companionManagerStreamsMockBackendChunksInOrder() async throws {
        let companionManager = CompanionManager(
            assistantBackend: MockBackend(
                configuration: MockBackendConfiguration(
                    responseTextChunks: ["first ", "second"],
                    statusMessages: ["thinking"],
                    delayNanoseconds: 0
                )
            )
        )

        let responseTask = companionManager.sendPromptToAssistantBackend(promptText: "hello")
        await responseTask.value

        #expect(companionManager.assistantBackendDisplayName == "Mock Assistant")
        #expect(companionManager.assistantStreamingResponseText == "first second")
        #expect(companionManager.assistantBackendStatusText == "Completed")
        #expect(companionManager.assistantErrorMessage == nil)
        #expect(companionManager.assistantRunState == .idle)
    }

    @Test func companionManagerCancelsMockBackendRequest() async throws {
        let companionManager = CompanionManager(
            assistantBackend: MockBackend(
                configuration: MockBackendConfiguration(
                    responseTextChunks: ["late response"],
                    statusMessages: ["thinking"],
                    delayNanoseconds: 100_000_000
                )
            )
        )

        let responseTask = companionManager.sendPromptToAssistantBackend(promptText: "hello")
        companionManager.cancelCurrentAssistantBackendRequest()
        await responseTask.value

        #expect(companionManager.assistantBackendStatusText == "Cancelled")
        #expect(companionManager.assistantRunState == .idle)
    }

    @Test func companionManagerSurfacesMockBackendFailure() async throws {
        let companionManager = CompanionManager(
            assistantBackend: MockBackend(
                configuration: MockBackendConfiguration(
                    responseTextChunks: [],
                    statusMessages: [],
                    behavior: .exitsWithFailure(exitCode: 42, stderr: "failed")
                )
            )
        )

        let responseTask = companionManager.sendPromptToAssistantBackend(promptText: "hello")
        await responseTask.value

        #expect(companionManager.assistantBackendStatusText == "The assistant backend exited with status 42: failed")
        #expect(companionManager.assistantErrorMessage == "The assistant backend exited with status 42: failed")
        #expect(companionManager.assistantStreamingResponseText == "The assistant backend exited with status 42: failed")
        #expect(companionManager.assistantRunState == .idle)
    }

    @Test func tutorialGuidePromptIncludesOverlayGuidance() {
        let tutorialGuidePrompt = CompanionManager.tutorialGuidePrompt(
            for: "open the export settings"
        )

        #expect(tutorialGuidePrompt.contains("game tutorial guide"))
        #expect(tutorialGuidePrompt.contains("open the export settings"))
        #expect(tutorialGuidePrompt.contains("[CLEAR]"))
        #expect(tutorialGuidePrompt.contains("[RECT]"))
        #expect(tutorialGuidePrompt.contains("[POINT]"))
        #expect(tutorialGuidePrompt.contains("[LINE]"))
    }

    @Test func companionManagerIgnoresBlankTutorialGuidePrompt() {
        let companionManager = CompanionManager(
            assistantBackend: MockBackend()
        )

        let responseTask = companionManager.sendTutorialGuidePrompt(userGoal: "   ")

        #expect(responseTask == nil)
        #expect(companionManager.assistantRunState == .idle)
        #expect(companionManager.assistantStreamingResponseText.isEmpty)
    }
}
