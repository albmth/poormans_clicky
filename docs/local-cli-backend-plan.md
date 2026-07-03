# Local CLI Backend Architecture Plan

This document defines the target local CLI backend architecture for Poor Man's Clicky.
It is planning-only and does not authorize app code changes, file deletion, Xcode project changes, or commits.

## Related Docs

- [No-API CLI Migration Plan](./no-api-cli-migration-plan.md) covers what must be removed from the current API/provider/voice-backed app.
- [No-API CLI Roadmap](./no-api-cli-roadmap.md) covers execution phases, task ownership, verification gates, and next prompts.

## Product Boundary

Poor Man's Clicky is an independent fork derived from the open-source Clicky project by Farza.
It is not the official Clicky project and is not affiliated with or endorsed by Farza, Clicky, OpenAI, Anthropic, Claude, Codex, or any other AI provider.

The future assistant brain should use user-installed local CLI tools and the user's own official CLI login flows.
The app must not ask for, store, read, or transmit provider API keys, browser cookies, CLI auth files, keychain items, session tokens, or credentials.
The app must not scrape browser sessions, proxy provider access, resell provider access, or bypass provider login flows or limits.

## Target Architecture

The app should route assistant requests through a small backend abstraction named `AssistantBackend`.
The abstraction should be added before current voice/API/provider code is removed, so the app can stay buildable during migration.
The default implementation during migration should be deterministic and local-only.

Target backend implementations:

- `DisabledBackend`: null backend and safe default when no backend is selected.
- `MockBackend`: deterministic backend for development, unit tests, and UI tests.
- `ClaudeCodeBackend`: future adapter for the user-installed Claude Code CLI.
- `CodexCLIBackend`: future adapter for the user-installed Codex CLI.

V1 should default to text-only, one-shot, and read-only unless Phase 1 proves CLI image input and permission semantics are safe.
Screenshot and pointing support must remain optional until CLI image support is verified.

## AssistantBackend Direction

The exact Swift API should be finalized after the Phase 1 CLI capability spike.
The interface should cover these concepts:

```swift
protocol AssistantBackend {
    var displayName: String { get }

    func checkAvailability() async -> AssistantBackendAvailability
    func makeStatusSummary() async -> AssistantBackendStatusSummary
    func startSession(context: AssistantSessionContext) async throws -> AssistantBackendSession
}

protocol AssistantBackendSession {
    func sendPrompt(_ request: AssistantPromptRequest) -> AsyncThrowingStream<AssistantBackendEvent, Error>
    func cancel()
}
```

Required type surface:

- Backend display name.
- Backend kind, availability, version, and install path when safely known.
- Login state only from official non-interactive CLI status commands.
- Session context with explicit working directory.
- Authority posture such as disabled, read-only, or future explicit-confirm edit mode.
- Prompt request text.
- Optional image file paths only if Phase 1 proves headless image input.
- Per-request timeout.
- Cancellation.
- Structured status, text, stderr, usage, exit, and error events.

## Backend Events

Do not collapse assistant text, stderr, process errors, and status into one string stream.
Use structured events so UI and tests can distinguish backend behavior from assistant output.

Recommended event categories:

- `availabilityChanged`
- `started`
- `statusChanged`
- `stdoutTextDelta`
- `stderrLine`
- `toolActivity`
- `permissionRequest`
- `usage`
- `exit`
- `cancelled`
- `failed`

`permissionRequest` is only a surfaced state in v1.
V1 should not expose full-access or dangerously-skip-permissions flows.

## DisabledBackend

`DisabledBackend` is a null object, not a real assistant backend.
It should always be available, never spawn a process, emit no assistant output, and return clear setup text explaining that no backend is selected.
It is useful as a safe default and for empty-state UI.

## MockBackend

`MockBackend` must require no CLI, account, network, API key, or external process.
It should stream deterministic fixed chunks.
It should emit realistic status transitions.
It should support deterministic cancel behavior.
It should have optional test modes for fake stderr, fake nonzero exit, timeout, and malformed output.
It should be the default backend for unit and UI tests.

## CLIProcessRunner

`CLIProcessRunner` should be a shared subprocess utility used by CLI backends.
It should not know provider-specific prompt semantics.
It should only run a resolved executable path with a fixed argv array.

Required constraints:

- Resolve binaries to explicit executable paths before launch.
- Do not run a login shell to discover binaries.
- Do not use `/bin/sh -c`.
- Do not interpolate prompt text, file paths, or labels into command strings.
- Put user text in stdin, a temp file, or a single argv element only when the CLI contract requires it.
- Drain stdout and stderr concurrently.
- Keep stdout and stderr separate.
- Enforce per-request timeout.
- Cancel with interrupt first, then escalate to kill after a short grace window.
- Kill the OS process, not only the Swift task.
- Surface nonzero exits as user-visible backend errors.
- Use bounded buffers for captured output.
- Sanitize control characters and ANSI escape sequences before UI rendering.
- Do not persist raw prompts, screenshots, stdout, stderr, argv, environment, or tool output.
- Do not dump child environment variables to logs.

## Environment And Working Directory

The app is currently unsandboxed and `com.apple.security.app-sandbox` must remain false for local CLI process spawning.
Entitlement cleanup is not a strong network security boundary while the app is unsandboxed.
The real safety gates are removal of hosted call paths, strict subprocess policy, and verification.

CLI processes should receive a deny-by-default environment.
Set only values needed for normal terminal-compatible behavior, such as `HOME`, a controlled `PATH`, and `TERM=dumb`.
Strip broad secret patterns from child processes, including `*_TOKEN`, `*_SECRET`, `*_API_KEY`, `AWS_*`, `GITHUB_TOKEN`, provider-specific key variables, and similar credential-bearing values.

The working directory must be explicit.
Do not default to `$HOME`, the repository root, or a remembered last project.
V1 should use a user-selected working directory or a controlled temporary directory during capability tests.

## Credential And Session Boundaries

Login detection may use only official non-interactive CLI commands.
Never read `~/.claude`, `~/.codex`, provider config files, browser cookies, web storage, keychain items, or auth files.
If login state cannot be safely detected, show `Installed, login unknown`.

The app must not store credentials.
The app must not scrape browser sessions.
The app must not automate hidden web pages to obtain access.
The app must not proxy or resell access.

## CLI Capability Unknowns

These facts must be verified in Phase 1 before real backend implementation:

- Installed `codex` and `claude` versions and absolute executable paths.
- Non-interactive streaming flags and output schemas.
- Whether Claude Code requires `--verbose` for `--output-format stream-json`.
- Whether Codex CLI has a stable machine-readable `exec` output format.
- Whether either CLI accepts synthetic image fixtures in headless one-shot mode.
- Whether read-only or plan modes prevent file writes and shell mutation headlessly when tested only inside a temporary directory.
- Whether one-shot processes can surface approval requests or only deny blocked actions.
- Whether safe non-interactive login-status commands exist.
- Whether Codex CLI supports ad-hoc system instructions or only repo/config instructions.

## Screenshot And Pointing Policy

Text-only v1 is preferred unless Phase 1 proves image input is available and safe.
If screenshots are supported later, write them to a private per-request temporary directory as files.
Do not pass screenshot bytes through argv.
Delete screenshot temp files after the process exits.
Never include screenshots in telemetry or logs.

Pointing should remain backend-agnostic.
If retained, it should parse local backend output tags or use a separate local deterministic approach.
It must not use direct hosted provider APIs.

## Backend Tests

Backend architecture tests should cover:

- `MockBackend` deterministic streaming.
- `DisabledBackend` safe empty-state behavior.
- Binary missing and binary not executable states.
- Safe argv construction.
- Shell-injection resistance for prompt text and paths.
- Separate stdout and stderr handling.
- ANSI/control-character sanitization.
- Nonzero exit mapping.
- Timeout escalation.
- Cancellation killing the OS process.
- Minimal environment and provider API-key stripping.
- No raw prompt/stdout/stderr persistence.
- Login-status unknown fallback.
