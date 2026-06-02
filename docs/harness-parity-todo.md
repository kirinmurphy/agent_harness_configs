# Harness Parity Todo

## Purpose

Track open work for keeping Claude and Codex harness behavior aligned while preserving user and repo-level override paths.

## Current Model

- Shared global skills live in `skills/<skill-name>/`.
- Claude skill links live at `claude/skills/<skill-name> -> ../../skills/<skill-name>`.
- Codex skill links live at `codex/skills/<skill-name> -> ../../skills/<skill-name>`.
- Installer links `claude/skills` into `~/.claude/skills`.
- Installer links `codex/skills` into `~/.codex/skills`.
- Global root configs are defaults, not forced overrides when user-owned config exists:
  - `~/.claude/settings.json`
  - `~/.codex/config.toml`
- Local repo context can still layer through repo-local `CLAUDE.md`, `AGENTS.md`, and related project files.

## Completed

- Added shared `react` skill with React stack detection and hooks guidance.
- Added shared `supabase-integration-testing` skill with narrow trigger conditions for real/remote Supabase tests.
- Keep `frontend-design` scoped to visual/UI design; place JS/TS conventions in `javascript-typescript` and cross-language conventions in `code-style`.
- Added generic testing guidance to `test-harness`: user-visible behavior, semantic selectors, failing test first, Playwright when unit tests mock away integration behavior, and E2E regression coverage.
- Implemented global rule parity through shared fragments in `rules/shared/`, harness fragments in `rules/claude/` and `rules/codex/`, and generated tracked outputs `claude/CLAUDE.md` and `codex/AGENTS.md`.
- Documented override priority in `docs/plans/rules-parity-and-layering.md`: shared global defaults, harness-specific defaults, user-owned root config, repo-local instructions, direct user instructions.
- Symlinked both skills into `claude/skills/` and `codex/skills/`.
- Updated `scripts/doctor.sh` and `scripts/verify-install.sh` to validate the new shared skills.

## Todo

1. Implement per-repo skill installer.
   - Existing plan: `docs/plans/per-repo-skill-installer.md`.
   - Goal: install repo-local skills into both Claude and Codex without losing global skill parity.

2. Decide placement for global coding conventions.
   - Candidate rule topics:
     - pure utilities use `function`
     - named exports preferred
     - helpers at file bottom
     - no procedural comments
     - constants over loose enum/status strings
     - no emoji in UI; use icons where appropriate
   - Open question: compact global rules only, expanded skill references, or both.

## Open Decisions

- Whether stack-specific context should be expressed as skills only, rules only, or rules that trigger skills.
- How much local repo config should override global behavior automatically versus by explicit user opt-in.
