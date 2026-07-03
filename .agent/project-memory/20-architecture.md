# Architecture Memory

Current app architecture:

- macOS menu bar-only app with `LSUIElement=true`.
- SwiftUI app with AppKit bridging for `NSStatusItem`, custom `NSPanel`, and transparent overlay windows.
- `MenuBarPanelManager.swift` owns the status item and floating panel.
- `CompanionPanelView.swift` renders the panel UI.
- `OverlayWindow.swift` hosts the blue cursor companion, response bubble, waveform, spinner, and pointing animation.
- `CompanionManager.swift` is the highest-coupling central state machine.
- Current `CompanionManager.swift` owns voice state, dictation, shortcut monitoring, screen capture, Claude model selection, Worker URLs, TTS, onboarding media, analytics calls, conversation history, cursor visibility, and point-tag parsing.

Current hosted/provider paths to remove:

- `ClaudeAPI.swift` through the Cloudflare Worker `/chat` path.
- `ElevenLabsTTSClient.swift` through the Worker `/tts` path.
- `AssemblyAIStreamingTranscriptionProvider.swift` through Worker token fetch plus AssemblyAI websocket.
- `OpenAIAudioTranscriptionProvider.swift` direct hosted transcription.
- Dead direct hosted clients `OpenAIAPI.swift` and `ElementLocationDetector.swift`.
- `worker/` Cloudflare proxy.
- PostHog analytics and FormSpark email submission.
- Mux onboarding video fetch and bundled voice/onboarding audio assets.

Target architecture:

- Introduce a small `AssistantBackend` abstraction before deleting live providers.
- Use `DisabledBackend` and `MockBackend` as safe defaults and test drivers.
- Use `ClaudeCodeBackend` and `CodexCLIBackend` later through official local CLI binaries only.
- Default v1 posture should be text-only, one-shot, and read-only unless CLI capability checks prove more.
- Keep cursor and pointing only if the local CLI and product decision support screenshot/image input safely.
- Keep ScreenCaptureKit only if screenshot-aware prompts remain.

CLI runner safety constraints:

- Keep `com.apple.security.app-sandbox` false because local CLI process spawning needs it.
- Do not treat entitlement removal as a complete network security control while the app is unsandboxed.
- Resolve CLI binaries to explicit executable paths.
- Use `Process` with `executableURL` and fixed argv arrays.
- Never use `/bin/sh -c` or interpolate prompt text into shell commands.
- Drain stdout and stderr concurrently to avoid deadlock.
- Separate stdout, stderr, text deltas, tool activity, usage, exit, and error events.
- Cancel by interrupting the OS process first, then escalating to kill after a short timeout.
- Pass a minimal environment and strip provider API-key environment variables from child processes.
- Do not read CLI auth files, provider config files, browser cookies, keychain secrets, or session storage.
- Choose working directories only from explicit user selection, never by defaulting to `$HOME` or repo root.
