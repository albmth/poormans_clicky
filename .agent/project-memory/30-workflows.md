# Workflow Memory

General repo workflow:

- Preserve user changes.
- Keep edits scoped to the requested files.
- Do not edit generated files, including `CHANGELOG.md`.
- Do not auto-add an agent co-author.
- Do not use the em dash character.
- In long Markdown files, put each full sentence on its own line.
- Project memory stores facts about this product.
- Skills store reusable ways of working.

Build and test rules:

- Do not run `xcodebuild` from the terminal because repo docs say it invalidates TCC permissions.
- Use Xcode Cmd+R as the build gate after migration phases.
- Use Xcode Cmd+U or the Xcode test navigator for tests.
- Use terminal-safe `rg` static gates between phases.
- Known non-blocking warnings are Swift 6 concurrency warnings and a deprecated `onChange` warning in `OverlayWindow.swift`.
- Do not try to fix those warnings unless explicitly asked.

Migration sequence rules:

- Do not delete voice or provider files before `CompanionManager.swift` is cut over to a backend abstraction.
- Add `AssistantBackend`, `DisabledBackend`, `MockBackend`, and process-runner scaffolding before deleting live call paths.
- Remove analytics and FormSpark during the `CompanionManager` rewrite, not as a docs-only cleanup.
- Remove imports and usages before unlinking package dependencies.
- Unlink package dependencies through `project.pbxproj` and `Package.resolved` only after app imports and uses are gone.
- Do not add cloud APIs, API-key UI, provider SDKs, browser scraping, or credential storage.

Review and subagent routing:

- Main Claude should own integration edits, final decisions, build fixes, and `CompanionManager` cutover.
- Use `tech-lead` for architecture sequencing, phase planning, tradeoffs, and rollback strategy.
- Use `api-removal-auditor` for API key, provider SDK, cloud path, env var, Worker, voice, and telemetry cleanup checks.
- Use `cli-bridge-architect` for Codex CLI, Claude Code CLI, subprocess, PTY, streaming, cancellation, session, and sandbox design.
- Use `security-reviewer` for subprocess safety, credentials, logs, permissions, network remnants, and session risks.
- Use `docs-compliance-editor` for README, NOTICE, attribution, license, no-affiliation language, and no-API setup docs.
- Use `code-reviewer` after changes for correctness, regressions, dead code, missing tests, and migration completeness.
