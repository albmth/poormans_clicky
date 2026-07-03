# Local CLI Backend Migration Plan

## Status

This is the living implementation plan for Poor Man's Clicky, an independent fork derived from the open-source Clicky project by Farza.
The original MIT license and attribution must remain intact.
This fork should evolve into a separate product with its own branding, architecture, and commercial direction, while staying clear that it is not official Clicky, OpenAI, Anthropic, Claude, or Codex.

This document is planning-only.
It does not authorize product code changes, file removal, Xcode project changes, or release changes by itself.

## Goals

- Remove voice features.
- Remove API-key features.
- Remove direct hosted provider wiring.
- Replace the assistant brain with local CLI backend adapters.
- Support Codex CLI and Claude Code later.
- Keep the app usable as a desktop companion/controller.
- Preserve attribution and commercial-safe fork notes.
- Build around user-owned local tooling and official login flows.

## Non-goals

- No cloud proxy.
- No provider API keys.
- No scraping browser sessions.
- No browser cookie extraction.
- No hidden automation of ChatGPT or Claude web pages.
- No account sharing.
- No resale of OpenAI, Anthropic, Claude, or Codex access.
- No bypassing rate limits, usage limits, login flows, or provider restrictions.
- No shared hosted service that fronts one user's paid account for other users.

## Current Architecture Audit

### App Entry Points

- `leanring_buddyApp.swift` is the SwiftUI app entry point.
- `CompanionAppDelegate` creates `MenuBarPanelManager`, starts `CompanionManager`, configures analytics, and registers the app as a login item.
- The app is menu-bar-only through `LSUIElement=true`.
- The Xcode project still builds a product named `Clicky.app` with `Clicky` display names.

### UI Layers

- `MenuBarPanelManager.swift` owns the `NSStatusItem` and custom `NSPanel`.
- `CompanionPanelView.swift` renders the menu bar panel content.
- `OverlayWindow.swift` creates one transparent overlay window per screen and hosts the cursor companion.
- `CompanionResponseOverlay.swift` contains a separate cursor-following response bubble manager, but it appears unused by the current main flow.
- `DesignSystem.swift` provides shared colors, button styles, cursor helpers, and visual tokens.

### State Management

- `CompanionManager.swift` is the central `ObservableObject`.
- It currently owns voice state, permission state, onboarding media state, cursor overlay state, Claude model selection, conversation history, response tasks, transient overlay hiding, and detected element pointing state.
- This file is the highest-coupling point and should be split before major deletion work.

### Assistant Flow

The current assistant path is:

1. User presses `ctrl+option`.
2. `GlobalPushToTalkShortcutMonitor` detects the shortcut.
3. `BuddyDictationManager` starts microphone capture.
4. A transcription provider produces a final transcript.
5. `CompanionManager` captures screenshots with `CompanionScreenCaptureUtility`.
6. `ClaudeAPI` sends images and transcript to the Worker proxy.
7. Claude response text may include a `[POINT:x,y:label:screenN]` tag.
8. `CompanionManager` parses the point tag and updates overlay pointing state.
9. `ElevenLabsTTSClient` sends response text to the Worker proxy for speech playback.
10. The overlay shows spinner/listening/responding states and cursor pointing.

### Voice Flow

- `BuddyDictationManager.swift` owns push-to-talk sessions, microphone permission checks, `AVAudioEngine`, transcript finalization, audio power levels, and speech privacy settings links.
- `GlobalPushToTalkShortcutMonitor.swift` owns the listen-only `CGEvent` tap for the modifier shortcut.
- `BuddyTranscriptionProvider.swift` chooses AssemblyAI, OpenAI audio transcription, or Apple Speech.
- `AssemblyAIStreamingTranscriptionProvider.swift` fetches a temporary token from a Worker endpoint, opens a websocket to AssemblyAI, and streams PCM16 audio.
- `OpenAIAudioTranscriptionProvider.swift` reads an `OpenAIAPIKey` value from app bundle configuration, buffers mic audio, uploads WAV audio, and requests hosted transcription.
- `AppleSpeechTranscriptionProvider.swift` uses Apple's Speech framework and requires speech recognition permission.
- `BuddyAudioConversionSupport.swift` converts microphone buffers to PCM16/WAV.
- `OverlayWindow.swift` renders the waveform and spinner UI for voice states.

### API and Provider Flow

- `CompanionManager.swift` hardcodes a Worker base URL placeholder and constructs `/chat` and `/tts` endpoints.
- `ClaudeAPI.swift` sends Claude vision requests through the Worker proxy and parses SSE text deltas.
- `ElevenLabsTTSClient.swift` sends text to the Worker proxy and plays returned audio.
- `AssemblyAIStreamingTranscriptionProvider.swift` calls the Worker `/transcribe-token` endpoint and connects to AssemblyAI websocket APIs.
- `OpenAIAPI.swift` is a direct hosted OpenAI vision client.
- `OpenAIAudioTranscriptionProvider.swift` is a direct hosted OpenAI audio transcription client.
- `ElementLocationDetector.swift` is a direct Anthropic Computer Use client and takes an Anthropic API key in its initializer.
- `worker/src/index.ts` is the Cloudflare Worker proxy for Anthropic, ElevenLabs, and AssemblyAI.

### Permissions and Entitlements

- `Info.plist` includes microphone, speech recognition, and screen capture usage descriptions.
- `Info.plist` includes `VoiceTranscriptionProvider=assemblyai`.
- `leanring-buddy.entitlements` includes network client, camera, and audio-input entitlements.
- The project build settings enable outgoing network connections.
- `WindowPositionManager.swift` includes screen recording permission helpers and Accessibility permission helpers.
- Accessibility appears mostly tied to the old global shortcut/window control story and should be revalidated against actual product needs.

### Telemetry Concerns

- `ClickyAnalytics.swift` configures PostHog with a project key.
- Current analytics captures prompt transcripts and AI responses.
- `CompanionManager.submitEmail` identifies users in PostHog and posts email addresses to FormSpark.
- The target product direction requires no prompt, output, account, token, file-content, or screenshot telemetry.

### Inherited Branding

- `README.md` correctly states this is Poor Man's Clicky, an independent fork derived from Clicky.
- `LICENSE` preserves the upstream MIT license notice.
- App build settings, product name, logs, panel text, menu bar icon names, `AGENTS.md`, release scripts, appcast files, and some comments still use `Clicky`, `leanring-buddy`, `makesomething`, Farza-specific copy, and old release repository names.
- Branding should be renamed later in a dedicated productization phase, while preserving upstream attribution.

## File-by-file Removal and Change Plan

### `CompanionManager.swift`

Planned action: split and heavily rewrite.
Remove voice state, shortcut bindings, dictation manager ownership, Claude model selection, Worker URL, Claude API calls, ElevenLabs TTS, FormSpark email submission, prompt/output analytics, remote onboarding media, and Claude-driven onboarding demo.
Keep or move cursor overlay state, screen capture permission state if screenshot context remains, backend session state, response streaming state, cancellation state, and point-tag parsing if still useful.

### `CompanionPanelView.swift`

Planned action: replace panel content.
Remove voice copy, microphone permission row, speech-to-text row, Claude model picker, email capture, Farza feedback link, and API/provider-specific text.
Add backend selector, backend status, text composer, send/cancel controls, safe setup hints, and unaffiliated disclaimer.

### `OverlayWindow.swift`

Planned action: keep the cursor companion and pointing animation, remove voice-only visuals.
Remove waveform UI, voice-specific responding/listening state assumptions, remote onboarding video player, onboarding audio/video prompts, and `AVFoundation` needs if no local media remains.
Keep spinner or processing state if needed for CLI requests.

### `CompanionResponseOverlay.swift`

Planned action: decide whether to reuse or delete.
If the new CLI flow needs a cursor-following response bubble, integrate this explicitly.
If the panel becomes the primary response surface, remove this unused manager.

### `BuddyDictationManager.swift`

Planned action: delete after UI and `CompanionManager` stop referencing it.
This file is voice-only.

### Transcription Provider Files

Planned action: delete after dictation removal.
Files:

- `BuddyTranscriptionProvider.swift`
- `AssemblyAIStreamingTranscriptionProvider.swift`
- `OpenAIAudioTranscriptionProvider.swift`
- `AppleSpeechTranscriptionProvider.swift`
- `BuddyAudioConversionSupport.swift`

These files exist only for speech-to-text, microphone audio conversion, hosted transcription, or Apple Speech.

### `GlobalPushToTalkShortcutMonitor.swift`

Planned action: delete unless a future non-voice global hotkey is explicitly designed.
The current implementation exists for push-to-talk and brings Accessibility complexity.

### `ClaudeAPI.swift`

Planned action: delete from the app target.
The new architecture should not call hosted Claude APIs directly or through a proxy.
Claude Code support should go through the official local CLI controlled by the user.

### `OpenAIAPI.swift`

Planned action: delete from the app target.
The new architecture should not call hosted OpenAI APIs directly.
Codex support should go through the official local Codex CLI controlled by the user.

### `ElevenLabsTTSClient.swift`

Planned action: delete.
Voice output is out of scope for this migration.
The app should not call ElevenLabs or any hosted TTS provider.

### `ElementLocationDetector.swift`

Planned action: delete or replace with backend-agnostic point parsing.
The current file directly calls Anthropic Computer Use with an API key.
If pointing remains, it should come from local backend output or a local deterministic UI feature, not direct hosted provider calls.

### `CompanionScreenCaptureUtility.swift`

Planned action: keep with guardrails if screen-aware prompts remain.
Screenshots should only be captured after explicit user action and should be passed only to the selected local backend when the user expects it.
The UI must make screenshot usage clear.

### `WindowPositionManager.swift`

Planned action: trim.
Keep screen recording helpers if screenshot context remains.
Remove Accessibility permission helpers and AX window-resizing helpers unless a visible product feature needs them.

### `ClickyAnalytics.swift`

Planned action: delete PostHog or replace with an opt-in, content-free telemetry facade.
No prompts, outputs, account identifiers, file contents, screenshots, tokens, or CLI config details should be sent.

### `Info.plist`

Planned action: remove voice-related configuration.
Remove `VoiceTranscriptionProvider`, `NSMicrophoneUsageDescription`, and `NSSpeechRecognitionUsageDescription`.
Revise screen capture copy for local CLI use.
Review Sparkle keys and feed URL during productization.

### `leanring-buddy.entitlements`

Planned action: remove voice and unused device entitlements.
Remove audio input and camera entitlements.
Review network client entitlement after hosted provider removal.
Keep only entitlements needed for the local desktop companion.

### `worker/src/index.ts` and `worker/`

Planned action: remove from the product path in a dedicated commit.
This is the Cloudflare proxy and conflicts with the no-cloud-proxy product direction.
README and agent docs should no longer instruct users to configure Worker secrets.

### `README.md`

Planned action: preserve and update.
Keep attribution to the original Clicky project and MIT license.
Replace inherited hosted API/voice setup language with official local CLI setup language.
State that users authenticate through supported CLIs, not through app API keys.

### `AGENTS.md` and `leanring-buddy/AGENTS.md`

Planned action: update after architecture changes.
Root `AGENTS.md` currently documents the old voice, Worker, Claude, AssemblyAI, and ElevenLabs architecture.
Target-level `AGENTS.md` appears stale and references old files not present in this menu-bar-only code path.

### `appcast.xml`, `scripts/release.sh`, and `scripts/README.md`

Planned action: update later during productization.
They currently reference `makesomething`, an old release repo, Sparkle release flow, and `xcodebuild`.
Do not touch them during initial backend migration unless release work is explicitly requested.

### Xcode Project Files

Planned action: update only when code files are actually removed or package dependencies change.
Remove Sparkle and PostHog packages only when their imports and usage are gone.
Do not rename the project or scheme during the initial backend migration unless a dedicated branding phase is approved.

## New Local Backend Architecture

Introduce a small backend abstraction, tentatively named `AssistantBackend`.

Suggested shape:

```swift
protocol AssistantBackend {
    var name: String { get }

    func checkAvailability() async -> AssistantBackendAvailability
    func explainSetupStatus() async -> String
    func startSession(context: AssistantSessionContext) async throws -> AssistantBackendSession
}

protocol AssistantBackendSession {
    func sendPrompt(_ request: AssistantPromptRequest) -> AsyncThrowingStream<AssistantBackendEvent, Error>
    func cancel()
}
```

The exact types should be refined during implementation, but the interface should cover:

- Backend display name.
- Availability check.
- Setup/status explanation.
- Session start if needed.
- Prompt submission.
- Streaming response events.
- Cancellation.
- Graceful error reporting.

### Proposed Backends

- `DisabledBackend`
  - Always available.
  - Explains that no backend is selected.
  - Useful as the default safe state.

- `MockBackend`
  - Used for app development and UI tests.
  - Streams deterministic fake output.
  - Requires no external CLI, account, or network.

- `CodexCLIBackend`
  - Calls the official local Codex CLI binary only.
  - Uses the user's existing Codex CLI login/session.
  - Never asks for OpenAI API keys.

- `ClaudeCodeBackend`
  - Calls the official local Claude Code CLI binary only.
  - Uses the user's existing Claude Code login/session.
  - Never asks for Anthropic API keys.

### Backend Safety Rules

- Use official CLI binaries only.
- Use `Process` with fixed argv arrays.
- Do not shell out through user-provided strings.
- Do not build command strings with untrusted prompt text.
- Do not read CLI auth files.
- Do not read browser cookies.
- Do not scrape browser sessions.
- Do not store auth tokens.
- Do not inspect provider config files for secrets.
- Detect missing CLIs gracefully.
- Detect login status only through safe official CLI commands where possible.
- If login status cannot be safely determined, show `Installed, login unknown`.
- Stream stdout and stderr into app state where feasible.
- Support cancellation by terminating the active subprocess.
- Treat nonzero exits as user-visible backend errors.
- Avoid destructive filesystem or shell actions unless the user explicitly confirms.

## UX Plan

- Keep the floating menu bar companion feel.
- Add a backend selector with options such as `Disabled`, `Mock`, `Codex CLI`, and `Claude Code`.
- Show backend status:
  - Installed or missing.
  - Login known, login unknown, or unavailable.
  - Selected backend.
  - Current session/request state.
- Add a text composer for prompts.
- Add send and cancel controls.
- Show streamed CLI output in the panel or cursor-adjacent response surface.
- Provide setup hints:
  - Install Codex CLI.
  - Run Codex CLI and sign in with the user's ChatGPT plan.
  - Install Claude Code.
  - Run Claude Code's official login flow.
- Remove all voice UI.
- Remove all API-key UI.
- Add clear unaffiliated disclaimers:
  - Poor Man's Clicky is not official Clicky.
  - Poor Man's Clicky is not affiliated with OpenAI, Anthropic, Claude, or Codex.
  - The app does not resell provider access.
  - The app only controls local user-owned tooling.

## Safety and Productization Boundaries

- No prompt/output telemetry.
- No account identifiers in telemetry.
- No screenshots sent without explicit user action.
- No screenshots in telemetry.
- No file contents in telemetry.
- No tokens, cookies, or auth config in telemetry.
- No destructive shell commands without explicit user confirmation.
- No remote command execution.
- No cloud proxy.
- No browser-cookie extraction.
- No hidden automation of ChatGPT or Claude web pages.
- No bypassing provider limits or login flows.
- No account sharing.
- No provider access resale.
- Preserve the upstream MIT license.
- Preserve attribution to the original Clicky project.
- Add `NOTICE.md` later with clear upstream attribution.
- Rename app branding later in a dedicated productization phase.
- Avoid implying official association with Clicky, OpenAI, Anthropic, Claude, or Codex.

## Implementation Phases

1. Audit and document current voice/API/provider paths.
2. Remove voice UI and microphone/speech permissions.
3. Remove voice pipeline files.
4. Remove API-key lookup, Worker references, and hosted provider clients.
5. Add backend protocol and backend event model.
6. Add mock and disabled backends.
7. Add Codex CLI backend.
8. Add Claude Code backend.
9. Add backend selector, status UI, text composer, and cancellation UI.
10. Update README, AGENTS, NOTICE, branding notes, and safety boundaries.
11. Add focused tests and a manual verification checklist.

## Test Checklist

### Static Checks

- `rg` finds no `NSMicrophoneUsageDescription`.
- `rg` finds no `NSSpeechRecognitionUsageDescription`.
- `rg` finds no `VoiceTranscriptionProvider`.
- `rg` finds no `AssemblyAI`, `ElevenLabs`, `OpenAIAPIKey`, or Worker URL in the app target.
- `rg` finds no hosted model API client path in active source.
- `rg` finds no PostHog prompt/output capture.
- Xcode project no longer links removed voice/provider packages after implementation phases that remove them.

### Manual Checks

- App still launches from Xcode.
- First launch does not prompt for microphone permission.
- First launch does not prompt for speech recognition permission.
- No voice button or push-to-talk instruction is visible.
- No API-key UI is visible.
- Missing Codex CLI state is clear and non-crashing.
- Missing Claude Code state is clear and non-crashing.
- Mock backend streams deterministic output.
- Send and cancel controls work.
- CLI subprocess cancellation works.
- No prompt/output telemetry is emitted.
- Screenshot capture occurs only after explicit user action.
- Screen capture permission, if still needed, has accurate local-use copy.

## Open Questions

No blocking questions at this stage.
