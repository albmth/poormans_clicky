# Product Memory

Poor Man's Clicky is an independent fork derived from the open-source Clicky project by Farza.
It must preserve original attribution and MIT license notices.
It must not imply official affiliation with Clicky, Farza, OpenAI, Anthropic, Claude, Codex, or any other AI provider.

The product direction is a local-first macOS menu bar companion and desktop controller.
The migration goal is to replace hosted API/provider-backed behavior with a no-API, local CLI-backed assistant brain.
The intended local backends are the user's own Codex CLI and/or Claude Code CLI sessions.
The app should use official local CLI login flows where possible and must not store user credentials.

The target product removes API key setup, provider SDK wiring, voice features, transcription, TTS, cloud model request paths, cloud usage and billing references, and analytics or tracking unless explicitly kept later.
The product should remain usable as a desktop companion/controller while the backend is migrated incrementally.

Explicit non-goals:

- No OpenAI, Anthropic, Groq, or other cloud API integrations in the app.
- No in-app provider API key configuration.
- No cloud proxy.
- No browser session scraping.
- No browser cookie extraction.
- No hidden web automation of ChatGPT or Claude pages.
- No account sharing.
- No provider access resale.
- No bypassing login flows, rate limits, usage limits, restrictions, or provider terms.
- No prompt, output, account, token, file-content, screenshot, or credential telemetry.
