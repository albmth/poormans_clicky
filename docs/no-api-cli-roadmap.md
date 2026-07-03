# No-API CLI Roadmap

This document is the execution roadmap for moving Poor Man's Clicky from the current API/provider/voice-backed app to a no-API local CLI-backed product.
It is planning-only and does not authorize app code changes, file deletion, Xcode project changes, or commits.

## Related Docs

- [Local CLI Backend Architecture Plan](./local-cli-backend-plan.md) covers the target backend abstraction and CLI subprocess design.
- [No-API CLI Migration Plan](./no-api-cli-migration-plan.md) covers what must be removed from the current app and how to prove removal.

## Execution Principles

Keep the app buildable between phases.
Prefer safe incremental migration over a rewrite.
Main Claude should usually implement later.
Subagents should handle planning, audits, architecture, security review, code review, and docs compliance.
Text-only v1 is preferred unless Phase 1 proves CLI image support and safe permission behavior.
No phase may add cloud APIs, API-key configuration, browser scraping, or credential storage.

## Phase Roadmap

| Phase | Goal | Primary Gate |
|---|---|---|
| 0 | Branch, rollback tag, stale-doc warning plan, and release safety awareness. | No app behavior changes. |
| 1 | CLI capability spike. | Verified facts table and final backend surface. |
| 2 | Backend abstraction and mock path. | App builds with `DisabledBackend` and `MockBackend`. |
| 3 | Cut app flow over to local mock backend. | Current hosted paths are no longer required by `CompanionManager`. |
| 4 | Remove analytics, email capture, and tracking. | No prompt/output/email telemetry paths remain. |
| 5 | Remove voice, transcription, TTS, hotkey, and audio surfaces. | No mic/speech/audio UI or code paths remain. |
| 6 | Remove hosted provider clients and Worker. | No hosted model, transcription, TTS, or Worker paths remain. |
| 7 | Permission, entitlement, UserDefaults, and dependency cleanup. | Static gates pass for app target and packages. |
| 8 | Implement first real CLI backend. | Read-only one-shot backend works with safe subprocess policy. |
| 9 | Implement second CLI backend if still desired. | Backend selector can switch safely. |
| 10 | Productization docs and release safety. | Attribution preserved and no stale release trust path is used. |
| 11 | Final review and verification. | Code review, security review, static gates, and Xcode validation complete. |

## Task Split By Phase

### Phase 0

- Create a feature branch.
- Create a pre-migration rollback tag.
- Record that root `AGENTS.md`/`CLAUDE.md` and `leanring-buddy/AGENTS.md` are stale.
- Do not modify app source unless a later implementation prompt explicitly asks for it.

### Phase 1

- Run only safe CLI capability checks.
- Confirm installed CLI paths, versions, streaming flags, output shapes, login-status commands, and instruction support.
- Confirm image-input and permission behavior only through CLI help/docs or synthetic fixtures inside a temporary directory.
- Use a temporary working directory for capability tests.
- Do not run login flows.
- Do not read auth files, keychain entries, browser data, provider configs, or session files.
- Do not send screenshots to a CLI.
- Redact sensitive CLI output before recording findings.

### Phase 2

- Define `AssistantBackend`, session context, prompt request, availability, status, and event model.
- Add `DisabledBackend` and `MockBackend`.
- Add backend tests described in the architecture plan.

### Phase 3

- Cut app orchestration over to the backend abstraction.
- Keep `MockBackend` as the default driver.
- Preserve launch behavior and panel behavior.

### Phase 4

- Remove PostHog, FormSpark, email capture, and inherited feedback/tracking paths.
- Remove analytics package only after imports and call sites are gone.

### Phase 5

- Remove dictation, transcription providers, push-to-talk monitor, audio conversion, TTS, local speech fallback, voice UI, and audio assets.
- Remove microphone and speech permission UI and plist keys.

### Phase 6

- Remove hosted provider clients and Worker references.
- Remove `worker/` after app references and product docs outside these migration planning docs are gone.
- Remove Mux onboarding fetch and any cloud onboarding media path.

### Phase 7

- Clean permissions, entitlements, stale `UserDefaults`, and package dependencies.
- Decide whether Screen Recording and Accessibility remain.
- Keep `app-sandbox=false` for local CLI process spawning.

### Phase 8

- Implement the first real CLI backend per the architecture plan.
- Prefer Claude Code first only if Phase 1 confirms the safer and better-understood path.
- Keep v1 read-only and one-shot.

### Phase 9

- Implement the second real CLI backend only after the first is stable.
- Add backend selection, status, send, cancel, and error UI.

### Phase 10

- Update README, root `AGENTS.md`, `leanring-buddy/AGENTS.md`, and `NOTICE.md` when those edits are explicitly allowed.
- Do not use current `appcast.xml` or release scripts until productization replaces ownership and trust paths.
- Record public-release history-scrub decision.

### Phase 11

- Run `api-removal-auditor`, `security-reviewer`, and `code-reviewer`.
- Run static gates.
- Validate in Xcode.
- Fix only migration-related regressions.

## Task Split By Subagent

- Main Claude: integration edits, final decisions, `CompanionManager` cutover, build fixes, and final assembly.
- `tech-lead`: sequencing, tradeoffs, phase structure, and overlap checks.
- `api-removal-auditor`: API/provider/voice/Worker/telemetry removal surfaces and static gates.
- `cli-bridge-architect`: backend abstraction, CLI runner, streaming, cancellation, status events, and subprocess policy.
- `security-reviewer`: credentials, sessions, subprocess safety, logs, telemetry, permissions, and release trust.
- `docs-compliance-editor`: attribution, license, clone/fork disclosure, no-affiliation wording, and docs clarity.
- `code-reviewer`: final correctness, dead code, regressions, missing tests, and migration completeness.

## Phase 1 Exact Scope

Phase 1 is read-only with respect to the app repository and real user data.
It may use synthetic fixtures inside a temporary directory to test CLI behavior.
No app code changes, docs edits, source deletion, Xcode project changes, commits, screenshot forwarding, sandbox changes, or backend implementation.

Phase 1 should determine:

- `codex --version`.
- `claude --version`.
- `which -a codex claude`.
- Non-interactive streaming flags and output schemas.
- Whether Claude Code needs `--verbose` with `--output-format stream-json`.
- Whether Codex CLI has a stable machine-readable `exec` event format.
- Whether either CLI accepts synthetic images in headless one-shot mode.
- Whether read-only or plan modes prevent file writes and shell mutation inside a temporary directory.
- Whether one-shot processes surface approval requests or deny blocked actions.
- Safe non-interactive login-status commands.
- Whether ad-hoc system instructions are supported.
- The finalized `AssistantBackend` type surface and `MockBackend` behavior based only on verified facts.

## Phase 1 Non-Goals

- No Swift code.
- No app code edits.
- No docs edits.
- No source deletion.
- No package changes.
- No Xcode project changes.
- No CLI login flows.
- No auth-file reads.
- No keychain reads.
- No browser session reads.
- No screenshot forwarding.
- No file mutation tests outside a temporary directory.
- No API integration.
- No API key configuration.
- No commits.

## Verification Gates By Phase

- Phase 0: `git status --short` shows only intentional planning/doc changes.
- Phase 1: findings table distinguishes verified facts from unknowns.
- Phase 2: mock and disabled backend tests exist and require no CLI or network.
- Phase 3: app can launch from Xcode with mock backend and no hosted request required for normal UI.
- Phase 4: telemetry and email static gates pass.
- Phase 5: mic, speech, voice, audio, TTS, and transcription static gates pass.
- Phase 6: hosted provider and Worker static gates pass.
- Phase 7: package, entitlement, permission, and stale state gates pass.
- Phase 8: subprocess cancellation kills the OS process and output remains sanitized.
- Phase 9: missing CLI and login-unknown states are clear and non-crashing.
- Phase 10: attribution is preserved and release trust paths are not stale.
- Phase 11: `code-reviewer`, `security-reviewer`, and static verification complete.

## Test And Build Commands

Do not run `xcodebuild` from the terminal.

Allowed planning and verification commands:

```bash
git status --short
rg --files docs
plutil -lint leanring-buddy/Info.plist leanring-buddy/leanring-buddy.entitlements
```

Manual build and test gates:

- Open `leanring-buddy.xcodeproj` in Xcode.
- Use Cmd+R after implementation phases.
- Use Cmd+U or the Xcode test navigator when tests are ready.

Static removal gates live in [No-API CLI Migration Plan](./no-api-cli-migration-plan.md).

## Open Decisions

- Does v1 keep pointing?
- Does v1 send screenshots to local CLIs?
- Does v1 keep Screen Recording permission?
- Does v1 keep Accessibility permission?
- Which backend ships first?
- Does the repo need a git-history scrub before public release?
- Is `worker/` deleted outright or retained only in history?
- What is the final app name and brand?
- When are `appcast.xml`, release scripts, icons, and distribution updated?
- Should README wording about browser profiles be tightened when README edits are allowed?
- Should the README development setup code fence be closed when README edits are allowed?

## Prompt To Begin Phase 1

```text
Begin Phase 1 only: CLI capability spike for the no-API local CLI migration.

Read docs/local-cli-backend-plan.md, docs/no-api-cli-migration-plan.md, and docs/no-api-cli-roadmap.md first.
Do not edit app code.
Do not edit docs.
Do not delete files.
Do not change the Xcode project.
Do not run xcodebuild.
Do not commit.

Run only safe read-only CLI discovery commands for installed codex and claude.
Record exact versions, paths, flags, non-interactive streaming output schemas, login-status support, and system-prompt/instruction support.
For image-input support and read-only permission behavior, use only CLI help/docs or synthetic fixtures inside a temporary directory.
Use a temporary working directory for any command that could inspect or act on files.
Do not run login flows.
Do not read auth files.
Do not inspect browser sessions.
Do not scrape cookies.
Do not read keychain entries.
Do not store credentials.
Do not send screenshots to a CLI.
Do not mutate real project files.
Do not run file-mutation tests outside a temporary directory.
Redact sensitive CLI output before recording findings.

Return a known-vs-unknown findings table and a proposed AssistantBackend type surface based only on verified facts.
Also specify MockBackend behavior for tests.
```

## Prompt To Begin Implementation After Phase 1

```text
Begin implementation after Phase 1 for the no-API local CLI migration.

Read docs/local-cli-backend-plan.md, docs/no-api-cli-migration-plan.md, docs/no-api-cli-roadmap.md, and the Phase 1 findings first.
Do not add cloud APIs.
Do not add API key configuration.
Do not scrape browser sessions.
Do not store user credentials.
Do not run xcodebuild from the terminal.

Implement the next roadmap phase only.
Keep the app buildable.
Preserve attribution and license notices.
Start by adding the AssistantBackend abstraction, DisabledBackend, and MockBackend if they do not already exist.
Do not delete voice/API/provider files until CompanionManager is cut over to the abstraction and the mock path works.
Use apply_patch for manual edits.
After the phase, report changed files, verification performed, and remaining blockers.
```
