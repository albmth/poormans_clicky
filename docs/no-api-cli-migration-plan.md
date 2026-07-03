# No-API Local CLI Migration Plan (Consolidated)

Poor Man's Clicky is an independent, MIT-licensed fork derived from Clicky by Farza.
This document is planning-only.
It authorizes no code changes, no file deletions, no Xcode project changes, and no commits by itself.

## Relationship to existing docs

This document consolidates and supersedes `docs/local-cli-backend-plan.md` as the working migration plan.
The earlier plan remains valid as background and its file-by-file inventory is still useful, but this document corrects its sequencing and coverage gaps.

Two existing agent docs are known to be stale and must not be trusted while executing this migration.
Root `AGENTS.md` (and its `CLAUDE.md` symlink) still documents the old hosted voice, Worker, Claude, AssemblyAI, and ElevenLabs architecture as if it were current.
`leanring-buddy/AGENTS.md` references source files that do not exist in the repo (`FloatingSessionButton.swift`, `ContentView.swift`, `ScreenshotManager.swift`).
Correcting those docs is scheduled inside this plan (Phase 0 for the wrong target-level doc, Phase 11 for the root doc); this migration plan does not edit them.

## Product direction (must hold throughout)

- This is a Clicky-derived clone/fork.
- Preserve attribution and license notices.
- Do not imply official affiliation with Clicky, Farza, OpenAI, Anthropic, Claude, or Codex.
- Remove API key setup, provider SDK wiring, voice features, cloud request paths, and cloud usage/billing references.
- The future brain is local CLI-backed control via the user's own Codex CLI or Claude CLI sessions.
- Do not add OpenAI, Anthropic, Groq, or other cloud API integrations.
- Do not add API key configuration.
- Do not scrape browser sessions.
- Do not store user credentials in the app.

---

## 1. Executive summary

This fork replaces a hosted AI brain (Claude via a Cloudflare Worker proxy, plus AssemblyAI/ElevenLabs voice and dead OpenAI/Anthropic direct clients) with a local CLI backend that drives the user's own Codex CLI or Claude Code sessions.
No API keys ship, no cloud request paths remain, no credentials are stored, and no browser sessions are scraped.

Three audits (sequencing/architecture, removal-surface, CLI-bridge design) converged on the same conclusions.
The prior plan is directionally correct and safety-conscious, but has one structural sequencing flaw and several coverage gaps.

The flaw: the prior plan deletes voice/API code before the replacement abstraction exists, producing a multi-phase window where `CompanionManager.swift` references deleted types and the app cannot compile.
The fix is to build the `AssistantBackend` abstraction and cut `CompanionManager` over to a `MockBackend` first, then delete.

The gaps: two files it treats as live provider clients are dead code; it misses a live Mux video fetch, orphan audio assets, a second hardcoded Worker URL, and a Sparkle auto-update feed pointing at a third party's repo; and it asserts "no blocking questions" when the entire screen-aware pointing feature hinges on an unverified unknown (do the local CLIs accept image input in headless mode).

The conceptual shift the prior plan understates: Codex CLI and Claude Code are cwd-scoped agents that read/modify files and run shell, which is a far larger security surface than the old "screenshot in, text out" proxy.
This plan defaults hard to read-only, one-shot, text-only for v1.

---

## 2. Current confirmed findings

Live hosted call paths (must be removed):

- Claude via Worker: `ClaudeAPI.swift` (constructed in `CompanionManager.swift:75-77`).
- ElevenLabs TTS via Worker: `ElevenLabsTTSClient.swift` (`CompanionManager.swift:79-81`).
- AssemblyAI (Worker token + direct websocket): `AssemblyAIStreamingTranscriptionProvider.swift`.
- OpenAI audio transcription (direct, reachable via provider factory): `OpenAIAudioTranscriptionProvider.swift`.
- Mux onboarding video fetch: `CompanionManager.swift:830` (missed by the prior plan).
- FormSpark email sink: `CompanionManager.swift:167`.
- PostHog analytics: `ClickyAnalytics.swift` plus call sites.
- Cloudflare Worker proxy: `worker/` (`/chat`, `/tts`, `/transcribe-token`).

Dead code (zero-risk deletes; the prior plan mischaracterized these as live):

- `OpenAIAPI.swift` calls `api.openai.com` directly and is never instantiated.
- `ElementLocationDetector.swift` calls `api.anthropic.com` Computer Use directly and is never instantiated.

Pointing is local, not hosted.
The `[POINT:x,y:label:screenN]` feature is parsed on-device in `CompanionManager.swift:784` (`parsePointingCoordinates`).
It depends on no API.
Its survival depends only on whether a local CLI can be fed an image.

No live provider API keys are committed.
The app ships only a placeholder Worker URL; real keys live in Cloudflare runtime secrets.
Do not spend effort scrubbing provider keys from the app, because there are none.

Committed low-secrecy sinks that persist in git history after file deletion:

- PostHog project key (`ClickyAnalytics.swift:18`).
- FormSpark form ID (`CompanionManager.swift:167`).
- Sparkle public key and feed URL pointing at a third party's repo `julianjear/makesomething-mac-app` (`Info.plist:7-10`).
- `ELEVENLABS_VOICE_ID` (`worker/wrangler.toml:6`).

The app is unsandboxed: `com.apple.security.app-sandbox = false` (`leanring-buddy.entitlements:5-6`).
This must stay, because it is what permits `Process` spawning of the local CLIs.
Consequently the other `com.apple.security.*` entitlements are largely inert, so removing `network.client` will not block network egress.

Highest-coupling file: `CompanionManager.swift` (~1026 lines).
It owns voice state, dictation, shortcut monitor, Claude model selection, Worker URL, TTS, onboarding media, POINT parsing, coordinate math, and 17 analytics call sites.

---

## 3. Biggest gaps in the previous plan

1. Build-order gap (severe): deletion (prior phases 2-4) precedes the abstraction (prior phases 5-6), producing a non-compiling window.
2. No `CompanionManager` split phase, though "split before major deletion" is stated.
3. Analytics/PII removal deferred to the docs phase, but it is deeply entangled in `CompanionManager` and must be cut during the rewrite.
4. Missed removal targets: Mux fetch (`CompanionManager.swift:830`), second Worker URL (`AssemblyAIStreamingTranscriptionProvider.swift:22`), orphan `enter.mp3`/`eshop.mp3` (bundled, unreferenced), the direct provider endpoints inside the two dead files, and the specific Sparkle Swift lines (`leanring_buddyApp.swift:12,34,75-88`).
5. No dependency-unlink sequencing for Sparkle/PostHog/plcrashreporter (usage, then import, then `project.pbxproj`, then `Package.resolved`).
6. No Phase 0 (branch and rollback) and no build-verification gate.
7. `AssistantBackend` under-specified: missing image-input path, CLI binary discovery (GUI PATH problem), stdout/stderr event separation, pipe-drain deadlock, SIGINT-then-SIGKILL cancel, timeout, and working-directory/permission model.
8. Wrong `leanring-buddy/AGENTS.md` describes files that do not exist; root `AGENTS.md` documents the old architecture as current, so both mislead any agent executing mid-migration.

---

## 4. Risky assumptions

- "No blocking questions at this stage" is false; four product-defining unknowns are open (see sections 13 and 14).
- "Everything goes through the Worker" is false, because the dead files call `api.openai.com`/`api.anthropic.com` directly.
- "`ElementLocationDetector` powers pointing" is false, because pointing is local string parsing.
- "Entitlement removal is a security control" is misleading while unsandboxed; it is mostly cosmetic, and `app-sandbox=false` must stay.
- "Sparkle feed is a branding detail" is false; it is a live auto-update trust anchor pointing at a third party's release repo (supply-chain risk).
- "Local CLIs are a drop-in brain" is understated; they can modify files and run shell, so read-only confinement must be proven before shipping.
- "Screenshots can simply be forwarded to the CLI" is unverified, because headless image input support is unknown for both CLIs.

---

## 5. Final phased migration plan

| Phase | Goal | Build state |
|---|---|---|
| 0 | Feature branch and pre-migration tag. Fix wrong `leanring-buddy/AGENTS.md`; add a migration banner to root `AGENTS.md`. Establish build gate (Xcode Cmd+R plus `rg` checks). | builds |
| 1 | CLI capability spike (no code changes). Resolve the hard unknowns by running the real CLIs. Finalize `AssistantBackend` type surface and `MockBackend` behavior from confirmed facts. | builds |
| 2 | Define full `AssistantBackend` type surface (availability plus version plus login, session context plus working dir plus posture, prompt request plus optional images-as-file-paths, event model, timeout, cancel). | builds |
| 3 | Add `DisabledBackend`, `MockBackend`, and a shared `CLIProcessRunner`. No external deps. | builds |
| 4 | Extract non-backend concerns out of `CompanionManager`; remove all PostHog/FormSpark/analytics call sites; cut over to the abstraction with `MockBackend` default. | builds (critical gate) |
| 5 | Delete voice pipeline (dictation, shortcut monitor, all transcription providers, audio conversion). | builds |
| 6 | Delete hosted clients (`ClaudeAPI`, `ElevenLabsTTSClient`, dead `OpenAIAPI`, dead `ElementLocationDetector`), Mux fetch, both Worker URL placeholders, orphan audio (`ff/enter/eshop.mp3`). | builds |
| 7 | Strip voice UI (`CompanionPanelView`, `OverlayWindow`); remove Info.plist mic/speech keys plus `VoiceTranscriptionProvider`; remove camera/audio entitlements; remove Sparkle Swift usage plus Info.plist feed keys. Do NOT enable app-sandbox. | builds |
| 8 | Unlink dependencies in order: imports, then `project.pbxproj`, then `Package.resolved` (PostHog drops transitive plcrashreporter; Sparkle too). | builds |
| 9 | Implement real backends: `ClaudeCodeBackend` first (text-only, read-only, one-shot), then `CodexCLIBackend`. | builds |
| 10 | Backend selector, status, text composer, and cancel UI. | builds |
| 11 | Delete `worker/`; update README plus root `AGENTS.md`; add `NOTICE.md`. Defer branding/`appcast.xml`/`scripts/release.sh` to a separate productization pass. | builds |
| 12 | Wire `MockBackend` unit/UI tests; keep permission-flow tests; run manual checklist plus grep gate. | builds |

---

## 6. Phase 1 scope only

Phase 1 is a read-only capability spike.
No app code changes, no deletions, no commits.
The goal is to convert every "verify" unknown into a known fact by running the CLIs the user actually has installed, then finalize the `AssistantBackend` type surface and `MockBackend` behavior on paper.

In scope:

1. Streaming/non-interactive flags: confirm `claude -p --output-format stream-json` (does it require `--verbose`? what is the JSONL delta schema?) and the Codex `codex exec` machine-output flag plus event shape.
2. Headless image input: can either CLI accept a screenshot (file path arg? stdin base64?) in `-p`/`exec`? This decides the pointing feature.
3. Permission semantics: does `claude -p --permission-mode plan` fully prevent file/shell mutation headlessly, and can a one-shot process surface an approval or only deny? Same for Codex's approval/sandbox policy.
4. Safe login/status detection: is there a non-interactive `login status`/`whoami`-style command for each (no auth-file reading)?
5. System-prompt injection: confirm `claude --append-system-prompt`; determine whether `codex exec` accepts an ad-hoc instruction or only `AGENTS.md`/config.
6. Binary discovery: `which -a codex claude`; record absolute paths (`/opt/homebrew/bin`, `~/.local/bin`, nvm/fnm shims) to design PATH resolution.
7. Deliverable: a known-vs-unknown findings table; finalized `AssistantBackend` type surface; specified `MockBackend` behavior.

---

## 7. Out-of-scope items for Phase 1

- Any file deletion, edit, or refactor (including the wrong `AGENTS.md`, which is Phase 0).
- Any Swift code, new backend files, or `CompanionManager` changes.
- Xcode project, package, or entitlement changes.
- Any real Codex/Claude backend implementation.
- Any screenshot or image forwarding to a CLI.
- Any edit/write posture, permission-approval UI, or session resume work.
- Any commit, branch push, or release/appcast/script changes.
- Git-history scrubbing.
- Enabling or disabling app-sandbox.

---

## 8. Exact files/directories to inspect or change

Inspect first (before touching anything):

- `leanring-buddy/CompanionManager.swift` - split/cut-over hub (pipeline 473-540, 586-726; POINT parse 784; Mux 830; PostHog identify/FormSpark 161-171; `import PostHog` 13).
- `leanring-buddy/ClaudeAPI.swift` - event-contract reference (accumulated-text closure around 101/206) before deletion.
- `leanring-buddy/OverlayWindow.swift` - confirm it does not instantiate `CompanionResponseOverlayManager`; voice visuals.
- `leanring-buddy/CompanionPanelView.swift` - mic row (468-470); largest UI surface.
- `leanring-buddy/leanring_buddyApp.swift` - `import Sparkle` 12, dead `startSparkleUpdater` 75-88, analytics configure 42-43.
- `leanring-buddy/ClickyAnalytics.swift` - PostHog key (18), transcript/response capture (83-96).
- `leanring-buddy/CompanionScreenCaptureUtility.swift` - JPEG producer (around 99) if images survive.
- `leanring-buddy/leanring-buddy.entitlements` and `leanring-buddy/Info.plist`.
- `leanring-buddy.xcodeproj/project.pbxproj` and `leanring-buddy.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.
- `worker/` (`src/index.ts`, `wrangler.toml`, `package.json`).
- `leanring-buddy/AGENTS.md` (factually wrong) and root `AGENTS.md`/`CLAUDE.md` symlink.

Change later (by phase):

- Delete: all transcription providers, `BuddyDictationManager`, `GlobalPushToTalkShortcutMonitor`, `BuddyAudioConversionSupport`, `ClaudeAPI`, `ElevenLabsTTSClient`, `OpenAIAPI`, `ElementLocationDetector`, `ClickyAnalytics`, `ff/enter/eshop.mp3`, `worker/`.
- Add: `AssistantBackend.swift`, `DisabledBackend.swift`, `MockBackend.swift`, `CLIProcessRunner.swift`, `CodexCLIBackend.swift`, `ClaudeCodeBackend.swift`, `NOTICE.md`.
- Edit: `CompanionManager.swift`, `CompanionPanelView.swift`, `OverlayWindow.swift`, `leanring_buddyApp.swift`, `Info.plist`, `leanring-buddy.entitlements`, `project.pbxproj`, `Package.resolved`, `README.md`, root `AGENTS.md`.
- Defer to productization: `appcast.xml`, `scripts/release.sh`, `scripts/README.md`, branding/rename.

---

## 9. Static verification gates

Run from repo root; each must be empty in the app target after removal (scope with `leanring-buddy` where noted):

```bash
rg -n 'NSMicrophoneUsageDescription|NSSpeechRecognitionUsageDescription|VoiceTranscriptionProvider'
rg -n 'AssemblyAI|ElevenLabs|assemblyai|elevenlabs'
rg -n 'OpenAIAPIKey|api\.openai\.com|api\.anthropic\.com|x-api-key|xi-api-key|Bearer '
rg -n 'workers\.dev|your-worker-name|/chat|/tts|/transcribe-token'
rg -n 'PostHog|PostHogSDK|phc_|posthog'
rg -n 'submit-form\.com|FormSpark|submitEmail|\.identify\('
rg -n 'stream\.mux\.com'
rg -n 'import Sparkle|SPUStandardUpdaterController|SUFeedURL|SUPublicEDKey|appcast'
rg -n 'ClaudeAPI|OpenAIAPI|ElementLocationDetector|ElevenLabsTTSClient|BuddyDictationManager'
rg -n 'AVAudioEngine|AVAudioPlayer|AVCaptureDevice|enter\.mp3|eshop\.mp3|ff\.mp3'
rg -n 'com.apple.security.device.camera|com.apple.security.device.audio-input' leanring-buddy/leanring-buddy.entitlements
rg -n 'Sparkle|PostHog|posthog' leanring-buddy.xcodeproj/project.pbxproj leanring-buddy.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
git ls-files 'leanring-buddy/*.mp3'   # expect empty
test ! -d worker                       # Worker directory removed
```

Ensure app-sandbox stays false:

```bash
rg -n 'com.apple.security.app-sandbox' leanring-buddy/leanring-buddy.entitlements   # expect <false/>
```

If the repo is or will be public, confirm a history-scrub decision was made:

```bash
git log -p -S 'phc_' | head        # committed PostHog key in history
git log -p -S 'submit-form.com' | head
```

---

## 10. Test/build commands

Build verification.
Per `AGENTS.md`, do NOT run `xcodebuild` from the terminal, because it invalidates TCC permissions and the app will need to re-request screen recording, accessibility, and so on.

- Manual gate: open `leanring-buddy.xcodeproj` in Xcode, select the scheme, and press Cmd+R after each phase. The app must launch after phases 0-4 and every phase thereafter.
- Automated substitute between phases: the ripgrep static gates in section 9 (terminal-safe, no TCC impact).

Tests:

- Xcode test navigator or Cmd+U for `leanring-buddyTests` and `leanring-buddyUITests`.
- `MockBackend` is the deterministic, network-free driver for new unit/UI tests (streams fixed output, no CLI/account/network).
- Keep the existing permission-flow tests in `leanring_buddyTests.swift` (not API-related).

Manual checklist (Phase 12): first launch prompts for no mic/speech permission; no voice UI; no API-key UI; missing-CLI states are clear and non-crashing; Mock backend streams; send/cancel work; subprocess cancellation kills the OS process; no prompt/output telemetry; screenshots (if any) only after explicit action.

Note: `scripts/release.sh` does invoke `xcodebuild archive`/`-exportArchive`, but that is release-only and intentional and is out of scope until productization.

---

## 11. Security concerns

Highest priority, content/PII leakage (cut in Phase 4):

- Full user transcript to PostHog (`ClickyAnalytics.swift:83-88`), full AI response (`91-96`), email to PostHog identify (`CompanionManager.swift:161-163`), email to FormSpark (`167`). These violate the plan's own no-telemetry boundary and are GDPR/PII exposure.

Supply-chain/auto-update trust:

- Sparkle feed plus Ed public key point at a third party's repo (`Info.plist:8-10`). `startSparkleUpdater()` is already commented out (`leanring_buddyApp.swift:53`), so auto-update is inert, but the trust anchor must be removed, not merely deferred.

Subprocess safety (Phase 9 `CLIProcessRunner` design rules):

- `app-sandbox=false` must stay for `Process` spawn.
- Binary discovery: resolve via an explicit absolute-path allowlist plus a `stat` check for an executable file. Never run a login shell such as `zsh -lic 'which claude'`, because that executes user rc files and is the "shell through user strings" pattern to avoid.
- Argv-only: `executableURL` is the resolved absolute path and `arguments` is a fixed array. Never `/bin/sh -c`. Prompt text, paths, and labels are argv elements or file contents, never interpolated into a command string (this neutralizes prompt-injection-into-shell).
- Pipe draining: separate `Pipe`s for stdout and stderr, drained concurrently on background reads to avoid buffer-full deadlock.
- Cancellation: SIGINT first (`interrupt()`), then escalate to SIGKILL after a short grace window; must kill the OS process, not just the Swift Task.
- Timeout: per-request watchdog triggering the same SIGINT-then-SIGKILL escalation.
- Environment sanitization: pass a minimal explicit env (sane `PATH`, `HOME`, `TERM=dumb`); strip `ANTHROPIC_API_KEY`/`OPENAI_API_KEY` from the child env so the CLI bills the user's login, not a key.

Working-directory/agent authority (Phase 9):

- Codex/Claude are cwd-scoped agents that can read/modify files and run shell. The working directory must be an explicit user-granted `NSOpenPanel` selection, never a default of `$HOME`, repo root, or last project.
- Default posture is read-only (`--permission-mode plan` or read-only sandbox). No "full access" or `--dangerously-skip-permissions` path is exposed in v1 UI. Any future edit posture gates every mutating action behind explicit in-app confirmation.
- Screenshots, if ever forwarded, are written to a private per-request temp dir as file paths (never argv base64) and deleted after the process exits.

Login detection:

- Only official non-interactive status commands. Never read `~/.claude`, `~/.codex`, keychain, cookies, or config files. When unknown, show "Installed, login unknown".

Do NOT do: cloud proxy, provider API keys, in-app key entry, browser-cookie extraction, session scraping, hidden web automation, bypassing provider limits/login flows, account sharing, or reselling provider access.

---

## 12. Docs and attribution requirements

Must preserve (legal/MIT obligation):

- `LICENSE` (Copyright Farza) unchanged.
- README attribution block (`README.md:23-42`) linking to the original project, author, and MIT notice. Keep for any substantial derived source.

Must add:

- `NOTICE.md` with clear upstream attribution to the original Clicky project.

Must update (Phase 11, after architecture settles):

- Root `AGENTS.md`/`CLAUDE.md` to remove old voice/Worker/Claude/AssemblyAI/ElevenLabs architecture and document the local CLI backend.
- `leanring-buddy/AGENTS.md` corrected or deleted early (Phase 0), because it references files that do not exist.
- README setup to replace hosted API/voice/Worker-secret instructions with "authenticate through your own Codex/Claude CLI login" language. No API-key setup.

Positioning (must remain true throughout):

- Not the official Clicky project; not affiliated with Farza, Clicky, OpenAI, Anthropic, Claude, or Codex.
- Does not resell or proxy provider access; controls only local user-owned tooling.
- Removable Farza-branding copy (for example the "DM Farza" fallback string, `CompanionManager.swift:762`) is distinct from the load-bearing MIT/README attribution that must stay.

Defer to a separate productization pass: app/product rename, `appcast.xml`, `scripts/release.sh`, `scripts/README.md`, icon/branding.

---

## 13. Open decisions before implementation

1. Pointing feature fate: (A) keep only if headless image input verifies; (B) text-only, drop pointing for v1 (recommended); (C) local OCR/Accessibility pointing with no pixels sent to the agent (best long-term privacy, later phase).
2. Screenshots in v1: if pointing is dropped, do we send screenshots at all? If no, drop screen-recording permission and `CompanionScreenCaptureUtility` from v1.
3. Edit posture: v1 read-only only (recommended) vs attempt edit-with-confirm (requires headless permission-approval semantics to be proven first).
4. Which backend ships first: Claude Code first (recommended; flags better documented) vs Codex first.
5. Git-history scrub: will the repo be public? If so, the committed PostHog key, FormSpark form, and Sparkle key survive in history after deletion and need a rewrite decision.
6. `worker/` and `ELEVENLABS_VOICE_ID`: delete outright now, or keep the Worker in history as reference?

---

## 14. Exact next implementation prompt for Phase 1

Phase 1 - CLI capability spike.
Read-only.
No app code changes, no deletions, no commits.

On this machine, run the installed `codex` and `claude` (Claude Code) CLIs and record exact observed flags and output shapes (do not assume or fabricate flags; if something is not present on the installed version, mark it UNKNOWN):

1. Versions and locations: `codex --version`, `claude --version`, `which -a codex claude`. Note absolute paths and any nvm/fnm/homebrew shim locations.
2. Non-interactive streaming: confirm `claude -p --output-format stream-json` (does it need `--verbose`? capture the JSONL schema for text deltas vs the final `result`/usage object). Find and confirm the Codex `codex exec` machine-output flag and its event shape.
3. Headless image input: determine whether either CLI accepts a screenshot in `-p`/`exec` mode (file-path arg? stdin base64?). This decides the pointing feature.
4. Permission semantics: test whether `claude -p --permission-mode plan` fully prevents file/shell mutation headlessly, and whether a one-shot process can surface an approval or only denies. Do the same for Codex's approval/sandbox policy; confirm the exact sandbox/read-only token set.
5. Safe login/status detection: find a non-interactive `login status`/`whoami`-style command for each. Do not read auth files.
6. System-prompt injection: confirm `claude --append-system-prompt`; determine whether `codex exec` accepts an ad-hoc instruction or only `AGENTS.md`/config.

Deliverable: a known-verified vs still-unknown findings table, then a finalized `AssistantBackend` Swift type surface (availability plus version plus login, session context plus working dir plus posture, prompt request plus optional images-as-file-paths, event model separating text-delta/tool-activity/permission-request/usage/stderr/exit/error, timeout, cancel) and a specified `MockBackend` behavior, all derived only from confirmed facts.

Do not modify app code, delete files, change the Xcode project, add any API integration or key configuration, forward screenshots to a CLI, or commit.
Do not enable or disable app-sandbox.
