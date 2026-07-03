# No-API CLI Migration Plan

This document defines what must be removed or replaced to migrate the current Clicky-derived app away from API/provider/voice-backed behavior.
It is planning-only and does not authorize app code changes, file deletion, Xcode project changes, or commits.

## Related Docs

- [Local CLI Backend Architecture Plan](./local-cli-backend-plan.md) covers the target backend abstraction and CLI subprocess design.
- [No-API CLI Roadmap](./no-api-cli-roadmap.md) covers execution phases, task ownership, verification gates, and next prompts.

## Migration Boundary

Poor Man's Clicky is an independent fork derived from the open-source Clicky project by Farza.
Preserve the original attribution and MIT license notices.
Do not imply official affiliation with Clicky, Farza, OpenAI, Anthropic, Claude, Codex, or any other AI provider.

The migration must remove:

- API key setup.
- Provider SDK wiring.
- Cloud model request paths.
- Cloud usage and billing references.
- Voice input.
- Transcription.
- TTS.
- Worker proxy code.
- Analytics, email capture, and tracking unless explicitly kept later.

The migration must not add:

- OpenAI, Anthropic, Groq, or other cloud API integrations.
- In-app API key configuration.
- Browser-session scraping.
- Browser cookie extraction.
- Credential storage.
- Hidden web automation.

## Current Removal Surfaces

Live hosted or external call paths:

- `leanring-buddy/ClaudeAPI.swift` via the Worker `/chat` endpoint.
- `leanring-buddy/ElevenLabsTTSClient.swift` via the Worker `/tts` endpoint.
- `leanring-buddy/AssemblyAIStreamingTranscriptionProvider.swift` via Worker token fetch and AssemblyAI websocket.
- `leanring-buddy/OpenAIAudioTranscriptionProvider.swift` direct hosted OpenAI transcription.
- `leanring-buddy/CompanionManager.swift` Worker base URL and Mux onboarding video fetch.
- `leanring-buddy/CompanionManager.swift` FormSpark email submission.
- `leanring-buddy/ClickyAnalytics.swift` PostHog analytics.
- `worker/` Cloudflare Worker proxy.

Dead hosted-provider code that should be deleted once no longer referenced:

- `leanring-buddy/OpenAIAPI.swift`.
- `leanring-buddy/ElementLocationDetector.swift`.

Voice, audio, and transcription surfaces:

- `leanring-buddy/BuddyDictationManager.swift`.
- `leanring-buddy/BuddyTranscriptionProvider.swift`.
- `leanring-buddy/AssemblyAIStreamingTranscriptionProvider.swift`.
- `leanring-buddy/OpenAIAudioTranscriptionProvider.swift`.
- `leanring-buddy/AppleSpeechTranscriptionProvider.swift`.
- `leanring-buddy/BuddyAudioConversionSupport.swift`.
- `leanring-buddy/GlobalPushToTalkShortcutMonitor.swift`.
- `AVAudioEngine`, `AVAudioPlayer`, `AVPlayer`, `NSSpeechSynthesizer`, `SFSpeechRecognizer`, and voice-specific UI.
- Bundled audio files `leanring-buddy/ff.mp3`, `leanring-buddy/enter.mp3`, and `leanring-buddy/eshop.mp3` if no longer used.

Telemetry and tracking surfaces:

- PostHog package, import, configuration, and event calls.
- Prompt transcript capture.
- AI response capture.
- Permission and onboarding analytics.
- FormSpark email sink.
- X feedback link and inherited external tracking-oriented feedback paths unless intentionally retained.

Permission and entitlement surfaces:

- `NSMicrophoneUsageDescription`.
- `NSSpeechRecognitionUsageDescription`.
- `VoiceTranscriptionProvider`.
- `NSCameraUsageDescription` if present later.
- `NSScreenCaptureUsageDescription` if screenshots are dropped for v1.
- `com.apple.security.device.audio-input`.
- `com.apple.security.device.camera`.
- `com.apple.security.network.client`.
- `com.apple.screencapturekit.picker` temporary exception if ScreenCaptureKit is removed.
- Accessibility permission helpers and AX window mutation helpers if no visible product feature needs them.

State and configuration cleanup surfaces:

- `selectedClaudeModel`.
- `hasSubmittedEmail`.
- `hasCompletedOnboarding` if onboarding is replaced.
- `hasScreenContentPermission` if screen capture is removed.
- `com.learningbuddy.hasPreviouslyConfirmedScreenRecordingPermission` if screen capture is removed.
- `AppBundleConfiguration.swift` once provider Info.plist lookups are gone.

Supply-chain and release trust surfaces:

- Sparkle import and updater code.
- `SUFeedURL` and `SUPublicEDKey`.
- Sparkle and PostHog package references.
- Transitive `plcrashreporter` package residue.
- `appcast.xml` and release scripts before any public distribution.

History residue requiring a release decision:

- PostHog project key in git history.
- FormSpark form ID in git history.
- Sparkle public key and third-party feed URL in git history.
- `ELEVENLABS_VOICE_ID` in Worker config history.

## Migration Sequencing Rules

Add the backend abstraction before deleting current provider code.
Cut `CompanionManager.swift` over to `MockBackend` or another safe local backend before deleting voice/API files.
Remove PostHog and FormSpark call sites during the `CompanionManager` cutover, not as a final docs cleanup.
Strip UI references before deleting backing types.
Remove imports and usage before unlinking package dependencies.
Remove Sparkle runtime/feed trust anchors before unlinking Sparkle.
Delete `worker/` only after app references and product docs outside these migration planning docs are gone.
Keep `com.apple.security.app-sandbox` false for local CLI process spawning.
Do not treat entitlement cleanup as a complete security boundary while the app is unsandboxed.

## Removal Plan

### 1. Preparation

- Work on a feature branch and create a pre-migration rollback tag.
- Confirm `docs/no-api-cli-roadmap.md` has the current phase plan and Phase 1 prompt.
- Treat root `AGENTS.md`/`CLAUDE.md` and `leanring-buddy/AGENTS.md` as stale until updated.
- Do not run `xcodebuild` from the terminal.

### 2. Abstraction Cutover Prerequisite

- Require the target backend abstraction described in [Local CLI Backend Architecture Plan](./local-cli-backend-plan.md) before provider deletion begins.
- Require `DisabledBackend` and `MockBackend` before provider deletion begins.
- Require the app flow to be cut over to a safe local backend before deleting current providers.
- Keep app launchable after this cutover.

### 3. Analytics, Email, And Tracking Removal

- Remove PostHog setup from app launch.
- Remove PostHog imports and event calls.
- Remove prompt, transcript, response, permission, and onboarding telemetry.
- Remove FormSpark email submission and email state.
- Remove inherited external feedback paths unless explicitly kept.
- Remove PostHog package references after imports and usage are gone.

### 4. Voice, Transcription, And TTS Removal

- Remove push-to-talk and dictation state from `CompanionManager.swift`.
- Remove microphone, waveform, speech-to-text provider, model picker, and voice copy from `CompanionPanelView.swift`.
- Remove voice-only visuals from `OverlayWindow.swift`.
- Remove dictation, transcription, audio conversion, global hotkey, TTS, and local speech fallback files after references are gone.
- Remove bundled audio assets that no longer have references.

### 5. Cloud Provider And Worker Removal

- Remove Worker URL placeholders and `/chat`, `/tts`, `/transcribe-token` paths.
- Remove `ClaudeAPI.swift`, `OpenAIAPI.swift`, `OpenAIAudioTranscriptionProvider.swift`, `ElevenLabsTTSClient.swift`, `AssemblyAIStreamingTranscriptionProvider.swift`, and `ElementLocationDetector.swift`.
- Remove `worker/`.
- Remove Worker setup text from docs when docs are allowed to be updated.

### 6. Permission And State Cleanup

- Remove microphone and speech plist keys.
- Remove audio and camera entitlements.
- Remove network entitlement only as cleanup, not as the only security control.
- Decide whether Screen Recording and ScreenCaptureKit stay for v1.
- Remove screen capture permission copy, ScreenCaptureKit picker entitlement, and screen-recording state if screenshots are not in v1.
- Remove Accessibility helpers and AX mutation paths if no visible feature needs them.
- Migrate or clear stale `UserDefaults` keys listed above.

### 7. Dependency And Project Cleanup

- Remove Sparkle and PostHog imports and usage first.
- Remove Sparkle and PostHog framework links from `project.pbxproj`.
- Remove Sparkle, PostHog, and transitive package residue from `Package.resolved`.
- Keep Xcode project changes scoped to removed files and packages.

### 8. Docs, Attribution, And Release Safety

- Preserve `LICENSE`.
- Preserve README attribution to the original Clicky project and MIT license.
- Track the requirement to add `NOTICE.md` later with upstream attribution when docs edits are in scope.
- Update root `AGENTS.md` and its `CLAUDE.md` symlink after architecture settles.
- Correct or delete stale `leanring-buddy/AGENTS.md`.
- Do not use current `appcast.xml` or release scripts for distribution until ownership, trust, and branding are replaced.
- Record a git-history scrub or do-not-scrub decision before public release.

## Static Verification Gates

Run from repo root.
Scope app-target removal checks to avoid self-matching docs.

### App Target Gates

These should return no matches after the relevant removal phase:

```bash
rg -n 'NSMicrophoneUsageDescription|NSSpeechRecognitionUsageDescription|VoiceTranscriptionProvider' leanring-buddy
rg -n 'AssemblyAI|ElevenLabs|assemblyai|elevenlabs' leanring-buddy
rg -n 'OpenAIAPIKey|api\.openai\.com|api\.anthropic\.com|x-api-key|xi-api-key|Bearer ' leanring-buddy
rg -n 'workers\.dev|your-worker-name|/chat|/tts|/transcribe-token' leanring-buddy
rg -n 'PostHog|PostHogSDK|phc_|posthog' leanring-buddy
rg -n 'submit-form\.com|FormSpark|submitEmail|\.identify\(' leanring-buddy
rg -n 'stream\.mux\.com|x\.com/farzatv' leanring-buddy
rg -n 'import Sparkle|SPUStandardUpdaterController|SUFeedURL|SUPublicEDKey|appcast' leanring-buddy
rg -n 'ClaudeAPI|OpenAIAPI|ElementLocationDetector|ElevenLabsTTSClient|BuddyDictationManager|GlobalPushToTalkShortcutMonitor' leanring-buddy
rg -n 'AVAudioEngine|AVAudioPlayer|AVPlayer|AVCaptureDevice|NSSpeechSynthesizer|SFSpeechRecognizer|enter\.mp3|eshop\.mp3|ff\.mp3' leanring-buddy
rg -n 'selectedClaudeModel|hasSubmittedEmail|OpenAITranscriptionModel|OpenAIAPIKey' leanring-buddy
rg -n 'URLSession|URLRequest|URLSessionWebSocketTask|http://|https://|HTTPCookieStorage|WKWebsiteDataStore|SecItem|Cookies|Application Support/.*/(Chrome|Chromium|Arc|Brave|Edge|Safari)' leanring-buddy
rg -n '\\.claude|\\.codex|provider config|auth file|keychain|session token|browser cookie' leanring-buddy
```

### Entitlement And Package Gates

```bash
rg -n 'com.apple.security.device.camera|com.apple.security.device.audio-input' leanring-buddy/leanring-buddy.entitlements
rg -n 'com.apple.security.network.client' leanring-buddy/leanring-buddy.entitlements
rg -n 'com.apple.screencapturekit.picker' leanring-buddy/leanring-buddy.entitlements
rg -n 'Sparkle|PostHog|posthog|plcrashreporter' leanring-buddy.xcodeproj/project.pbxproj leanring-buddy.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
rg -n 'com.apple.security.app-sandbox' leanring-buddy/leanring-buddy.entitlements
```

The app-sandbox gate should still show `<false/>`.

### Repository Gates

```bash
git ls-files 'leanring-buddy/*.mp3'
test ! -d worker
rg -n 'Cloudflare Worker|Worker secrets|ANTHROPIC_API_KEY|ASSEMBLYAI_API_KEY|ELEVENLABS_API_KEY|AssemblyAI|ElevenLabs|PostHog|FormSpark' AGENTS.md CLAUDE.md README.md
rg -n 'makesomething-mac-app|SUFeedURL|SUPublicEDKey|appcast' appcast.xml scripts leanring-buddy
```

The README attribution block is protected content and should not be treated as a generic `Clicky` or `Farza` removal failure.

### History Decision Gates

Before any public release, record a decision for these:

```bash
git log -p -S 'phc_' --all
git log -p -S 'submit-form.com' --all
git log -p -S 'ELEVENLABS_VOICE_ID' --all
git log -p -S 'SUPublicEDKey' --all
```

## Build And Validation Gates

Do not run `xcodebuild` from the terminal.
Use Xcode Cmd+R as the manual build gate after each phase.
Use Xcode Cmd+U or the Xcode test navigator for tests.
Use `rg` static gates between phases.

Manual validation after removal:

- First launch does not request microphone permission.
- First launch does not request speech recognition permission.
- No voice button, push-to-talk instruction, waveform, model picker, API-key UI, or email capture is visible.
- Missing backend state is clear and non-crashing.
- Mock backend streams deterministic output.
- Send and cancel work.
- No prompt, output, account, token, file-content, screenshot, or CLI-config telemetry is emitted.
- Screenshots, if retained, happen only after explicit user action.
