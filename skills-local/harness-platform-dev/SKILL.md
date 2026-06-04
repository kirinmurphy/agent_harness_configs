---
name: harness-platform-dev
description: >
  INTERNAL to the harness_configs repo. Use when developing or maintaining the platform
  ITSELF — its install pipeline, symlink model, skill-linking machinery, rules generation,
  sync/verify scripts, bin/ commands, and the client-facing utilities (harness_helper,
  harness-install-local-skills). This is the mechanic's manual: how the machine works under
  the hood. Triggers: "how does this repo work", "harness_configs architecture", "install
  scripts", "add an install step", "the symlink model", working on scripts/ or bin/.
  SKIP for ordinary skill/rule CONTENT authoring — use harness-config for that instead.
  This skill is never shared globally or exported to client repos.
---

# Harness Platform Development (internal)

Mechanic's manual for developing **harness_configs** itself. Distinct from `harness-config`
(which is for authoring shared skill/rule *content*). This one is about the *machinery* and is
firewalled to this repo — it loads only when an agent works inside harness_configs.

**Source of truth docs** (read when relevant — these reorganized; current paths):
- `docs/reference/services/architecture.md` — Relationship, Symlink Map, Sync Flow.
- `docs/reference/internal/config-collision-handling.md` — conflict rules.
- `docs/reference/internal/rules-parity-and-layering.md` — rules generation/layering.
- `docs/reference/services/claude-hooks.md`, `docs/reference/services/codex-hooks.md` — hooks.
- `docs/guides/setup-and-daily-use.md`, `docs/guides/install-workflows.md` — install UX.

## Two repo dir conventions (get this right first)

- `claude/` and `codex/` = the SOURCE that is symlinked into the user's GLOBAL `~/.claude`
  and `~/.codex` by `scripts/install-symlinks.sh`. Editing these changes every machine that
  installs this repo.
- `.claude/` and `.codex/` (dotdirs) = THIS repo's own PROJECT-SCOPE config. Not symlinked to
  global. Claude Code auto-loads `<repo>/.claude/skills/` as project skills when working here.

## Two skill layers (the firewall)

| Layer | Source | Linked into | Reaches | Exported to clients? |
|-------|--------|-------------|---------|----------------------|
| **Shared** (advisory) | `skills/<name>/` | `claude/skills/<name>`, `codex/skills/<name>` (`../../skills/<name>`) | global `~/.claude`/`~/.codex` | **Yes** (via `harness_helper`) |
| **Internal** (repo-only) | `skills-local/<name>/` | `.claude/skills/<name>`, `.codex/skills/<name>` (`../../skills-local/<name>`) | this repo only | **No** |

The firewall is **structural**: `scripts/link-skills.sh` runs two independent passes, and the
export/installer tools read only `skills/` — there is no code path from `skills-local/` to global
config or to a client repo. To add an internal skill: create `skills-local/<name>/SKILL.md`, then
run `scripts/link-skills.sh`. The source folder alone is not enough.

`scripts/skill-lib.sh` (`list_source_skills`) and `scripts/skill-lib.mjs` (`listSourceSkills`)
hold the single "what is a real skill folder" rule (dir with `SKILL.md`, not a symlink) for bash
and Node respectively. Reuse them; don't re-derive the rule.

## Install pipeline map

`scripts/install-symlinks.sh` is the orchestrator:

- sources `scripts/install-lib.sh` — the link primitives: `link_item`, `link_item_clean`,
  `link_user_config`, `config_collision_action`, backup helpers. **Reuse these**; don't write
  ad-hoc `ln` logic.
- preflights clean targets + root-config collisions (never clobbers user-owned
  `~/.claude/settings.json` / `~/.codex/config.toml` — prompts adopt/agent-merge).
- delegates to `install-claude.sh`, `install-codex.sh`, `install-global-commands.sh`,
  `install-shell-snippets.sh`, `install-gitignore-globals.sh`.
- Windows path: `scripts/install-windows.ps1` (PowerShell), invoked from the bash orchestrator
  under MINGW/MSYS/CYGWIN.

`scripts/install-global-commands.sh` symlinks `bin/*` into `~/.local/bin` (with conflict
preflight) and ensures `~/.local/bin` is on PATH. New `bin/` commands must be wired here AND in
`doctor.sh` / `verify-install.sh`.

## bin/ commands

`bin/` entries become global commands via `~/.local/bin`. Bash shims that exec a Node impl in
`scripts/` (e.g. `harness_helper`, `harness-install-local-skills`) resolve their own symlinked
path back to the repo, so they work from any cwd. Node cores live in `scripts/*.mjs`; Windows
fallback is `node scripts/<name>.mjs`.

## Rules generation

Global instruction files `claude/CLAUDE.md` and `codex/AGENTS.md` are GENERATED. Edit fragments
under `rules/shared/`, `rules/claude/`, `rules/codex/`, then run `scripts/render-rules.sh`. Never
hand-edit the generated outputs. `scripts/doctor.sh` checks for generated-output drift.

## Sync / verify loop

- `scripts/sync-from-home.sh` — review diffs, pull selected live config back into the repo.
- `scripts/doctor.sh` — health checks (skill links, generated-rule drift, bin links).
- `scripts/verify-install.sh` — post-install verification of the global symlink set.
- `scripts/test-install-collisions.sh` — exercises the collision-handling paths.

## Conventions for scripts here

- Idempotent; support `--dry-run`; verification scripts support `--check`.
- Collisions: warn, preserve the local/user copy, print an agent merge prompt — never clobber.
  Follow `docs/reference/internal/config-collision-handling.md`.
- Cross-platform: Node cores use only `node:` built-ins (no shelling to `zip`/`unzip`/`ln`).
- Keep Claude/Codex in parity unless a difference is intentional — say so explicitly.

## Client-facing utilities (live here, run in client repos)

- `harness_helper --export-skill` — bundle SHARED skills into a `.zip` and copy into a client
  repo's `.claude/skills` (+ `.codex/skills`) with override/skip/backup. Core:
  `scripts/harness_helper.mjs` + `scripts/skill-lib.mjs`.
- `harness-install-local-skills` — symlink a client repo's own `.claude/skills/<name>` into the
  global harnesses (and mirror into the client's `.codex/skills`). Core:
  `scripts/install-local-skills.mjs` + `scripts/skill-lib.mjs`.

Both read only the SHARED layer / client-local skills — never `skills-local/`.
