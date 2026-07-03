# Clicky - Agent Instructions

<!-- This is the single source of truth for all AI coding agents. CLAUDE.md is a symlink to this file. -->
<!-- AGENTS.md spec: https://github.com/agentsmd/agents.md - supported by Claude Code, Cursor, Copilot, Gemini CLI, and others. -->

## Overview

macOS menu bar-only local assistant app.
It lives entirely in the macOS status bar with no dock icon and no main window.
Clicking the menu bar icon opens a custom floating panel where the user types prompts and sends them to their installed Codex CLI.
Screen capture is local only: the app writes per-request screenshots to temporary PNG files and passes them to Codex CLI with `--image`.
There is no voice input, transcription, TTS, hosted model provider, analytics, email capture, Worker proxy, or provider API-key path in the active app path.
The app does include a local screen overlay drawing engine for live visual annotations.

## Architecture

- **App Type**: Menu bar-only (`LSUIElement=true`), no dock icon or main window
- **Framework**: SwiftUI with AppKit bridging for the menu bar panel
- **Pattern**: MVVM with `@StateObject` / `@Published` state management
- **Assistant Brain**: Codex CLI via `codex exec` in read-only one-shot mode
- **Backend Abstraction**: `AssistantBackend` with `CodexCLIBackend`, `DisabledBackend`, and `MockBackend`
- **CLI Execution**: `CLIProcessRunner` runs explicit executable URLs with structured argv, sanitized output, separate stdout/stderr events, timeout, and cancellation
- **Local Screen Context**: ScreenCaptureKit captures each display to temporary PNG files per prompt and passes them to Codex CLI as `--image` attachments
- **Screen Overlay**: Codex output can append `[POINT]`, `[RECT]`, `[LINE]`, and `[CLEAR]` tags that render as local transparent overlay annotations
- **Custom Cursor Companion**: A click-through AppKit overlay follows the mouse as the always-visible Clicky cursor companion
- **Tutorial Prompt Shortcut**: A modifier polling controller opens a focused guide prompt when Command and Option are pressed together
- **Working Directory**: User-entered path stored in `Clicky.AssistantBackendWorkingDirectory.v1`, with a controlled temporary directory fallback
- **Concurrency**: `@MainActor` isolation, async/await throughout

### Key Architecture Decisions

**Menu Bar Panel Pattern**: The panel uses `NSStatusItem` for the menu bar icon and a custom borderless `NSPanel` for the floating prompt panel.
This gives full control over appearance and avoids standard macOS menu/popover chrome.
The panel can become key so the prompt editor and workspace field accept keyboard input.
A global event monitor auto-dismisses it on outside clicks.

**Custom Cursor Companion**: `ClickyCursorFollowerWindowManager` owns a transparent click-through `NSPanel` at screen-saver level.
It polls the mouse position on the main run loop and keeps the visual cursor near the system pointer without intercepting clicks.

**Tutorial Prompt Shortcut**: `TutorialPromptPanelManager` polls `CGEventSource` modifier flags instead of installing an event tap.
Pressing Command and Option together opens a compact keyable prompt panel near the cursor and submits through the existing `CompanionManager` backend path.

**Codex CLI Boundary**: The app resolves `codex` from fixed local search paths without launching a shell or reading auth files.
Prompt text is passed through stdin.
The command uses `codex exec --sandbox read-only --skip-git-repo-check --ephemeral --color never --cd <working-dir> [--image <screen.png>...] -`.

**No Hosted Provider Path**: The active app target has no Worker, hosted model API, API key configuration, transcription, TTS, analytics, email capture, or hosted vision code.

**Local Screenshot Context**: `LocalScreenCaptureService` uses ScreenCaptureKit only after Screen Recording permission is granted.
It captures each display into a private per-request temporary directory, passes the PNG paths to Codex CLI, and deletes the directory after the process finishes.

**Local Screen Overlay**: `ScreenOverlayCommandParser` extracts drawing commands from assistant output.
`ScreenOverlayWindowManager` renders those commands in click-through transparent `NSPanel` windows above each display.
This preserves the original visual-control idea without voice or hosted vision APIs.

**Sandbox Posture**: `com.apple.security.app-sandbox` remains false so the app can spawn the user-installed CLI.
The app requests Screen Recording permission for local screenshots.
It no longer requests microphone, camera, speech recognition, or outgoing network entitlements.

## Key Files

| File | Lines | Purpose |
|------|-------|---------|
| `leanring_buddyApp.swift` | ~43 | Menu bar app entry point. Creates `MenuBarPanelManager`, starts `CompanionManager`, starts the cursor follower and tutorial shortcut, and shows the prompt panel on launch. |
| `CompanionManager.swift` | ~401 | Main local assistant orchestrator. Owns Codex prompt lifecycle, local screenshot attachment, backend status, streamed response text, cancellation, errors, workspace path state, overlay command updates, and tutorial guide prompt shaping. |
| `CompanionPanelView.swift` | ~365 | SwiftUI panel content. Provides Codex status, Screen Recording status, workspace path field, prompt editor, send/stop buttons, response output, overlay clear, refresh, and quit. |
| `MenuBarPanelManager.swift` | ~238 | NSStatusItem and custom NSPanel lifecycle. Creates the menu bar icon, manages panel show/hide/position, and installs click-outside dismissal. |
| `ClickyCursorFollowerWindowManager.swift` | ~172 | Click-through AppKit overlay window that keeps the custom Clicky cursor companion near the system pointer across Spaces. |
| `TutorialPromptPanelManager.swift` | ~382 | Command plus Option shortcut polling, focused prompt panel lifecycle, and tutorial guide submission into `CompanionManager`. |
| `AssistantBackend.swift` | ~271 | Local assistant backend abstraction, request and event model, availability/status types, errors, and output text sanitizer for the no-API CLI migration. |
| `AssistantBackendCatalog.swift` | ~60 | Central catalog for the default Codex CLI backend, safe fallback backend, mock override, and controlled default working directory. |
| `CLIExecutableResolver.swift` | ~119 | FileManager-based resolver that checks fixed local search paths for CLI binaries without using a shell, login environment, network, credentials, or process execution. |
| `CLIProcessRunner.swift` | ~412 | Local process runner for CLI backends. Uses explicit executable URLs and argv arrays, minimal sanitized environment, separate stdout/stderr events, timeout, cancellation, and forced-kill fallback. |
| `DisabledBackend.swift` | ~61 | Safe null backend that reports no selected assistant backend and never emits assistant text or spawns a process. |
| `LocalCLIBackend.swift` | ~358 | Local CLI backend for Codex CLI and future Claude Code. Defines backend metadata, launch gate, executable availability status, command profiles, image attachment argv, and structured command-plan data. |
| `LocalCLIBackendSession.swift` | ~202 | Assistant backend session that maps `CLIProcessRunner` events into assistant events for local CLI execution. |
| `LocalScreenCaptureService.swift` | ~235 | ScreenCaptureKit screenshot helper. Captures displays into per-request temporary PNG files for Codex `--image` attachments and cleans them up after execution. |
| `MockBackend.swift` | ~243 | Deterministic local-only backend for development and tests. Streams fixed chunks, supports fake stderr, failure, timeout, malformed output, and cancellation behavior. |
| `ScreenOverlayCommandParser.swift` | ~185 | Parses assistant output drawing tags into local overlay annotation commands. |
| `ScreenOverlayWindowManager.swift` | ~303 | Creates transparent click-through per-screen overlay panels and renders point, rectangle, and line annotations. |
| `DesignSystem.swift` | ~880 | Design system tokens - colors, corner radii, shared styles. All UI references `DS.Colors`, `DS.CornerRadius`, etc. |
| `leanring-buddyTests/AssistantBackendTests.swift` | ~137 | Swift Testing coverage for disabled and mock backend behavior, structured events, cancellation, nonzero exits, and text sanitization. |
| `leanring-buddyTests/CLIExecutableResolverTests.swift` | ~74 | Swift Testing coverage for deterministic local executable resolution, non-executable candidates, and path-like executable-name rejection. |
| `leanring-buddyTests/CLIProcessRunnerTests.swift` | ~167 | Swift Testing coverage for CLI runner environment sanitization, shell-executable rejection, process request conversion, stdout/stderr separation, nonzero exits, and cancellation. |
| `leanring-buddyTests/CompanionManagerAssistantBackendTests.swift` | ~96 | Swift Testing coverage for `CompanionManager` prompt routing through `MockBackend`, streamed chunk ordering, cancellation, failure handling, and tutorial guide prompt shaping. |
| `leanring-buddyTests/LocalCLIBackendSessionTests.swift` | ~188 | Swift Testing coverage for opt-in Codex CLI argv construction, image attachments, process event mapping, and nonzero exit handling with a fake runner. |
| `leanring-buddyTests/LocalCLIBackendTests.swift` | ~219 | Swift Testing coverage for disabled Codex CLI and Claude Code scaffolds, catalog defaults, executable status reporting, image attachment argv, and structured command-plan validation. |
| `leanring-buddyTests/LocalScreenCaptureServiceTests.swift` | ~28 | Swift Testing coverage for pure local screenshot metadata used in Codex prompts. |
| `leanring-buddyTests/ScreenOverlayCommandParserTests.swift` | ~49 | Swift Testing coverage for overlay point, rectangle, line, clear, and no-point command parsing. |

## Build & Run

```bash
# Open in Xcode
open leanring-buddy.xcodeproj

# Select the leanring-buddy scheme, set signing team, Cmd+R to build and run
```

**Do NOT run `xcodebuild` from the terminal** - it invalidates TCC (Transparency, Consent, and Control) permissions and the app will need to re-request screen recording, accessibility, etc.

## Code Style & Conventions

### Variable and Method Naming

IMPORTANT: Follow these naming rules strictly. Clarity is the top priority.

- Be as clear and specific with variable and method names as possible
- **Optimize for clarity over concision.** A developer with zero context on the codebase should immediately understand what a variable or method does just from reading its name
- Use longer names when it improves clarity. Do NOT use single-character variable names
- Example: use `originalQuestionLastAnsweredDate` instead of `originalAnswered`
- When passing props or arguments to functions, keep the same names as the original variable. Do not shorten or abbreviate parameter names. If you have `currentCardData`, pass it as `currentCardData`, not `card` or `cardData`

### Code Clarity

- **Clear is better than clever.** Do not write functionality in fewer lines if it makes the code harder to understand
- Write more lines of code if additional lines improve readability and comprehension
- Make things so clear that someone with zero context would completely understand the variable names, method names, what things do, and why they exist
- When a variable or method name alone cannot fully explain something, add a comment explaining what is happening and why

### Swift/SwiftUI Conventions

- Use SwiftUI for all UI unless a feature is only supported in AppKit (e.g., `NSPanel` for floating windows)
- All UI state updates must be on `@MainActor`
- Use async/await for all asynchronous operations
- Comments should explain "why" not just "what", especially for non-obvious AppKit bridging
- AppKit `NSPanel`/`NSWindow` bridged into SwiftUI via `NSHostingView`
- All buttons must show a pointer cursor on hover
- For any interactive element, explicitly think through its hover behavior (cursor, visual feedback, and whether hover should communicate clickability)

### Do NOT

- Do not add features, refactor code, or make "improvements" beyond what was asked
- Do not add docstrings, comments, or type annotations to code you did not change
- Do not try to fix the known non-blocking warnings (Swift 6 concurrency, deprecated onChange)
- Do not rename the project directory or scheme (the "leanring" typo is intentional/legacy)
- Do not run `xcodebuild` from the terminal - it invalidates TCC permissions

## Git Workflow

- Branch naming: `feature/description` or `fix/description`
- Commit messages: imperative mood, concise, explain the "why" not the "what"
- Do not force-push to main

## Self-Update Instructions

<!-- AI agents: follow these instructions to keep this file accurate. -->

When you make changes to this project that affect the information in this file, update this file to reflect those changes. Specifically:

1. **New files**: Add new source files to the "Key Files" table with their purpose and approximate line count
2. **Deleted files**: Remove entries for files that no longer exist
3. **Architecture changes**: Update the architecture section if you introduce new patterns, frameworks, or significant structural changes
4. **Build changes**: Update build commands if the build process changes
5. **New conventions**: If the user establishes a new coding convention during a session, add it to the appropriate conventions section
6. **Line count drift**: If a file's line count changes significantly (>50 lines), update the approximate count in the Key Files table

Do NOT update this file for minor edits, bug fixes, or changes that don't affect the documented architecture or conventions.
