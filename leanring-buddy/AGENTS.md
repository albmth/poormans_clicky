# AGENTS.md - leanring-buddy App Target

This target is a menu bar-only SwiftUI and AppKit app.
The active product path is a typed local assistant panel backed by the user's installed Codex CLI.
The app captures local screenshots per prompt and passes them to Codex CLI as temporary `--image` files.

## Active Source Files

- `leanring_buddyApp.swift` creates the menu bar app delegate, starts `CompanionManager`, starts the cursor follower and tutorial prompt shortcut, and opens the panel on launch.
- `MenuBarPanelManager.swift` owns the `NSStatusItem`, custom keyable `NSPanel`, panel positioning, and click-outside dismissal.
- `CompanionPanelView.swift` renders Codex status, Screen Recording status, workspace path controls, prompt editor, send/stop actions, response output, refresh, and quit.
- `CompanionPanelView.swift` also exposes a clear overlay action.
- `CompanionManager.swift` owns assistant request state, local screenshot attachment, Codex backend status, streaming response text, cancellation, errors, workspace path persistence, overlay command updates, and tutorial guide prompt shaping.
- `ClickyCursorFollowerWindowManager.swift` keeps the custom Clicky cursor companion visible near the system pointer using a click-through AppKit overlay panel.
- `TutorialPromptPanelManager.swift` polls for Command plus Option, opens the compact guide prompt panel near the cursor, and submits guide requests through `CompanionManager`.
- `AssistantBackend.swift`, `AssistantBackendCatalog.swift`, `LocalCLIBackend.swift`, `LocalCLIBackendSession.swift`, `CLIExecutableResolver.swift`, and `CLIProcessRunner.swift` implement the local backend abstraction and read-only Codex CLI execution.
- `LocalScreenCaptureService.swift` uses ScreenCaptureKit to capture display screenshots into per-request temporary PNG files for Codex.
- `ScreenOverlayCommandParser.swift` and `ScreenOverlayWindowManager.swift` implement the local live screen drawing engine.
- `DisabledBackend.swift` and `MockBackend.swift` provide safe fallback and deterministic test behavior.
- `DesignSystem.swift` provides shared colors, styles, and hover cursor helpers.

## Removed Product Surfaces

Voice input, push-to-talk, transcription, TTS, hosted model clients, Worker proxy, onboarding video, analytics, email capture, Sparkle, and provider API code have been removed from the active app target.
The local screen overlay drawing engine remains active because it is the core visual interaction layer.
Screen capture remains only as local ScreenCaptureKit screenshots passed to the user's Codex CLI.

## Codex CLI Contract

The default assistant backend is Codex CLI.
It resolves `codex` from fixed local search paths without shelling out.
It runs `codex exec --sandbox read-only --skip-git-repo-check --ephemeral --color never --cd <working-dir> [--image <screen.png>...] -`.
Prompt text is passed through stdin.
Screen images are written to a per-request temporary directory and deleted after the Codex process exits.
The app does not read Codex auth files, browser data, keychain items, API keys, or provider configs.
Codex can append `[POINT:x,y:label:screenN]`, `[RECT:x,y,width,height:label:screenN]`, `[LINE:x1,y1,x2,y2:label:screenN]`, or `[CLEAR]` to draw local overlay annotations.
