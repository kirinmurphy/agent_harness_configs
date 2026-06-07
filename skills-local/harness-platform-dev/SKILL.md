---
name: harness-platform-dev
description: >
  INTERNAL to the harness_configs repo. Use when developing or maintaining the platform
  ITSELF — its install pipeline, symlink model, skill-linking machinery, rules generation,
  sync/verify scripts, bin/ commands, and the consumer CLI (roborepo). This is
  the mechanic's manual: which doc answers which question, plus the operational judgment that
  is NOT in the docs. Triggers: "how does this repo work", "harness_configs architecture",
  "install scripts", "add an install step", "the symlink model", working on scripts/ or bin/.
  SKIP for ordinary skill/rule CONTENT authoring — use harness-config for that instead.
  This skill is never shared globally or exported to client repos.
---

# Harness Platform Development (internal)

Mechanic's manual for developing **harness_configs** itself. Distinct from `harness-config`
(authoring shared skill/rule *content*). This skill is firewalled to this repo — it loads only
when an agent works inside harness_configs.

**This file does NOT restate the docs.** The docs are the source of truth; this skill is a map
to them plus the judgment that isn't written down. Read the doc, then apply the gotchas below.

## Which doc answers which question

| Question | Doc |
|----------|-----|
| Symlink map, sync flow, two skill layers, client utilities | `docs/reference/services/architecture.md` |
| The `roborepo` CLI — subcommands, menu, install/PATH | `docs/reference/services/roborepo.md` |
| Conflict / collision behavior on install | `docs/reference/internal/config-collision-handling.md` |
| Rules generation + layering | `docs/reference/internal/rules-parity-and-layering.md` |
| Hook behavior (Claude / Codex) | `docs/reference/services/{claude,codex}-hooks.md` |
| Install UX + daily commands | `docs/guides/setup-and-daily-use.md`, `docs/guides/install-workflows.md` |
| Skills, two layers, client utilities (user-facing) | `README.md` |

## Repo dir convention (the one thing to internalize first)

- `claude/` + `codex/` + `agents/` = SOURCE symlinked into the user's GLOBAL
  `~/.claude`/`~/.codex`/`~/.agents`.
- `.claude/` + `.codex/` + `.agents/` (dotdirs) = THIS repo's own PROJECT-SCOPE config, NOT global.
- `agents/skills/` = canonical shared/advisory layer (global + exportable; Codex reads it via
  `~/.agents/skills`, Claude via per-skill links in `claude/skills/`). `skills-local/` = internal
  layer (this repo only). The firewall between them is structural — see below.
- Codex scans `.agents/skills` **exclusively** for skills (no `.codex/skills` fallback);
  `~/.codex/skills` is kept only as a transitional cross-compat link.

Everything else (the two symlink levels, the layer table) lives in
`docs/reference/services/architecture.md`. Read it there.

## Operational judgment (not in the docs)

- **Adding any skill:** create the source folder, then ALWAYS run `scripts/link-skills.sh` —
  never hand-write `ln`. It derives links from source and is idempotent, so it can't drift.
  Shared skill → `agents/skills/`. Internal/repo-only skill → `skills-local/`. The script's two
  passes handle each. Source folder alone is never enough; the active skill list refreshes only on
  harness reload.
- **The firewall is code, not convention.** `link-skills.sh` runs one pass per layer;
  `roborepo` reads only `agents/skills/`. There is no code path from `skills-local/` to global
  config or to a client export. Don't add one.
- **Reuse the link/conflict primitives.** Bash: `scripts/install/install-lib.sh` (`link_item`,
  `link_item_clean`, collision prompts) and `scripts/skill-lib.sh` (`list_source_skills`). Node:
  `scripts/cli/skill-lib.mjs` (`listSourceSkills`, `ensureSymlink`, `linkLocalSkills`, `writeZip`).
  Don't re-derive the "what is a skill" rule or hand-roll `ln`/`symlink` logic.
- **Generated outputs are not editable.** `claude/CLAUDE.md` and `codex/AGENTS.md` are rendered
  from `rules/{shared,claude,codex}/` by `scripts/render-rules.sh`. Edit fragments, re-render.
  `doctor.sh` flags drift.
- **Adding global commands:** there is now ONE global command (`roborepo`); prefer adding a
  `roborepo` subcommand over a new `bin/` entry. If you ever DO add a `bin/` command, wire it in
  three places — `install-global-commands.sh` (preflight + `link_command`), `doctor.sh` (file +
  link check), `verify-install.sh` (link check) — or it's half-installed.
- **Script conventions:** idempotent; `--dry-run`; verifiers take `--check`. Collisions warn,
  preserve the local copy, print an agent merge prompt — never clobber.
- **`--quiet`/`-q` on the checkers.** `doctor.sh`, `verify-install.sh`, `test-roborepo.sh`, and
  `link-skills.sh` all accept `--quiet`: suppress the per-check `ok:`/`+ linked` lines, still
  print every failure plus a one-line `… (N checks)` / `N passed, M failed` summary, exit code
  unchanged. Use the bare script + `--quiet` for a readable, permissionable check — never pipe a
  verifier through `grep`/`head` to trim output. `doctor.sh` also folds `link-skills.sh --check`,
  so it is the single repo-health entrypoint (`--installed` adds the global ~/.claude·~/.codex·
  ~/.agents link checks); `test-roborepo.sh` stays the separate test suite.
- **Cross-platform floor:** Node cores use only `node:` built-ins (no shelling to
  `zip`/`unzip`/`ln`), so the same code runs on macOS/Linux/Windows. Keep it that way.
- **Codex skill discovery path (VERIFIED).** Codex scans `.agents/skills` — repo-up-to-root for
  project scope, and `~/.agents/skills` globally — and does NOT read any `.codex/skills` path
  (per OpenAI Codex docs). Claude Code auto-loads `<repo>/.claude/skills/` for project scope. The
  `~/.codex/skills` and repo `.codex/skills` links we still create are transitional cross-compat
  only; Codex ignores them. Symlinked skill folders are followed, so linking these dirs at the
  canonical `agents/skills` source works.

## The `roborepo` CLI (the single consumer front door)

`roborepo` is the ONE command a consumer runs. `scripts/roborepo.mjs` is a thin orchestrator
(usage, menu, dispatch); the subcommand impls live under `scripts/cli/` — `skills.mjs`,
`index.mjs`, `mcp.mjs`, `paths.mjs` (shared `repoRoot`/`sharedSkillsDir`), and `skill-lib.mjs`
(shared Node core: zip, prompts, symlink helpers). Bash shim is `bin/roborepo`. No-arg =
interactive menu (arrow keys + numbered fallback via `selectMenu` in `cli/skill-lib.mjs`).
Subcommands, grouped by category:

- `skill export` / `skill link` (`cli/skills.mjs`) — the dual-harness skill tools (export bundles +
  copies into `.claude/skills` + `.agents/skills`; link is purely in-repo `.agents/skills` →
  `.claude/skills` + `.codex/skills`, with prune). Read only the shared / client-local layer —
  never `skills-local/`.
- `index code|docs [path]`, `watch code [path]`, `run <cmd>` (`cli/index.mjs`) — jcodemunch/jdocmunch
  wrappers + the trimmed-output runner. `[path]` optional, defaults to cwd, resolved to absolute.
  `watch code` writes the pidfile `/tmp/jcmwatch-<md5(absdir)>.pid` that the Claude SessionStart
  hook reads — keep that in sync with `claude/settings.json` if you change it.
- `mcp add <name-or-url>` / `addMCP` (`cli/mcp.mjs`) — register an MCP server with Claude
  (`claude mcp add` + a `mcp__<name>` permission in `claude/settings.json`) and Codex (a block in
  `codex/config.toml`). Presets for `jcodemunch`/`jdocmunch`; URLs default to HTTP transport.
- `update`/`sync`/`doctor`/`verify` — lifecycle verbs that DISPATCH to the existing bash scripts
  (`roborepo-install.sh`, `sync-from-home.sh`, `doctor.sh`, `verify-install.sh`). There is no
  `install` verb: the FIRST install is the shell bootstrap `roborepo-install.sh` (that is what puts
  `roborepo` on PATH), so from the CLI you only ever `update` — which re-runs that same install
  script to pick up new config.

Adding a new `roborepo` subcommand: write/extend the module under `scripts/cli/`, export the
handler, then wire it in `roborepo.mjs` (import + `dispatch()` case + usage line + menu item). Only
ONE global command exists (`roborepo`), so the old per-command 3-place wiring is gone —
`install-global-commands.sh`, `doctor.sh`, `verify-install.sh` each reference only `roborepo`.
MAINTAINER scripts (`render-rules.sh`, `link-skills.sh`, `test-*.sh`) stay OUT of `roborepo`.

**Tests:** `scripts/test-roborepo.sh` smoke-tests the subcommands (skill link/prune/uninstall/
conflict, export/override/firewall/self-pollution guard, run, `mcp add` dry-runs + real
Codex/Claude writes against a throwaway harness root, lifecycle dispatch, menu fallback) against
throwaway temp repos. Run it after touching `roborepo.mjs` or anything under `scripts/cli/`.
`doctor.sh` also asserts `skill-lib.sh` and `cli/skill-lib.mjs` agree on the skill list (parity
guard).
