# Decision Memory

Decisions already made:

- The project is a Clicky-derived fork and must preserve attribution and license notices.
- The future product direction is no-API and local CLI-backed.
- The app must not imply official affiliation with Clicky, Farza, OpenAI, Anthropic, Claude, or Codex.
- The app must remove API key setup, provider SDK wiring, cloud model request paths, voice, transcription, TTS, usage/billing references, and analytics/tracking unless explicitly kept later.
- The app must not scrape browser sessions or store user credentials.
- The migration must be incremental and keep the app buildable between phases.
- `AssistantBackend` must exist before deleting current provider code.
- `MockBackend` should provide deterministic, network-free behavior for development and tests.
- `DisabledBackend` should be a safe default state.
- `app-sandbox=false` must remain for local CLI process spawning.
- CLI backends must use official local CLI binaries and the user's existing CLI login/session where possible.
- Default v1 posture should be read-only and one-shot unless the CLI spike proves safe alternatives.
- Root `AGENTS.md` and its `CLAUDE.md` symlink are currently stale for the migration.
- `leanring-buddy/AGENTS.md` is factually wrong and references files that do not exist.

Decisions not yet made:

- Whether v1 keeps pointing.
- Whether v1 sends screenshots to local CLIs at all.
- Whether Screen Recording permission remains in v1.
- Whether Accessibility permission remains in v1.
- Which real backend ships first.
- Whether the repo needs git-history scrubbing before public release.
- Whether `worker/` is deleted outright or retained only in history.
- When app naming, product branding, appcast, release scripts, and icons are productized.

Phase 1 boundaries:

- Phase 1 is a read-only CLI capability spike.
- Phase 1 may run installed `codex` and `claude` CLIs to discover versions, paths, flags, output shapes, login-status commands, image-input support, permission semantics, and system-prompt support.
- Phase 1 must not edit app code, delete files, change the Xcode project, commit, forward screenshots to a CLI, add API integrations, add API key configuration, or change sandbox settings.
