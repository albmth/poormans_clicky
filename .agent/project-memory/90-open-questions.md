# Open Questions

Open questions before implementation:

- Do installed `codex` and `claude` CLIs exist on this machine, and where are their executable paths?
- What exact non-interactive flags and output schemas do the installed CLIs support?
- Does Claude Code require `--verbose` for `--output-format stream-json`?
- What is the Codex CLI machine-readable event format for `codex exec`, if available?
- Can either CLI accept screenshot or image input headlessly in one-shot mode?
- If image input is not proven, should v1 be text-only and drop pointing?
- If pointing is dropped for v1, should `CompanionScreenCaptureUtility.swift` and Screen Recording permission be removed for v1?
- Do CLI read-only modes fully prevent file writes and shell mutation headlessly?
- Can one-shot CLI processes surface approval requests, or do they only deny blocked actions?
- What safe non-interactive login-status command exists for each CLI?
- Does Codex CLI support ad-hoc system instructions, or only repo/config instructions such as `AGENTS.md`?
- Should Claude Code or Codex CLI ship first?
- Should Accessibility permission remain after voice/global hotkey/window-resize features are removed?
- Should any local OCR or Accessibility-based pointing feature be designed later as a privacy-preserving alternative?
- Will this repo become public, requiring a decision about committed PostHog key, FormSpark form ID, Sparkle key, and Worker history?
- Should `appcast.xml`, `scripts/release.sh`, and `scripts/README.md` be disabled before productization to avoid stale third-party release paths?
- What final app/product name and branding should replace inherited Clicky, leanring-buddy, and makesomething references?
