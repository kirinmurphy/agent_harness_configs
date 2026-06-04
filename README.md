# Harness Configs

Version controlled Codex & Claude global harness configurations that symlink to local file system. Primary focus on optimizing token efficiency and implementing tool/resource/skill parity across harnesses.

## Start Here

Works with Claude Code, Codex, or both. Supports macOS and Linux; Windows support is available but less tested.

- Install and daily commands: [docs/guides/setup-and-daily-use.md](docs/guides/setup-and-daily-use.md)
- Install workflow choices: [docs/guides/install-workflows.md](docs/guides/install-workflows.md)
- Documentation index: [docs/README.md](docs/README.md)
- System reference: [docs/reference/services/architecture.md](docs/reference/services/architecture.md)

## Install Workflow Choices

`./scripts/install-symlinks.sh` installs repo-managed config where it can do so cleanly. If it finds existing user-owned root config, it asks whether to manage from this repo or adopt the repo defaults into local config.

| Workflow | What it gives you | What it hinders | User responsibility |
| --- | --- | --- | --- |
| `managed` | Logic stays in this repo and is observed by global config through symlinks. Updates are simple. | Local root config is no longer independently curated. | Edit repo files or sync local changes back into the repo. |
| `adopt` | Repo defaults are copied or merged into user-owned global config. Existing files can be replaced/archived, kept while repo candidates are staged, or reviewed through an agent prompt. | No automatic semantic merge unless implemented for a specific path. | Review archived/staged files or agent output, then merge wanted settings. |

No option should delete existing user config. Conflicted files are preserved either as active local files, archived files, staged repo candidates, or agent-review input. Non-root conflicts, such as existing hooks, skills, commands, rules, or global command targets, stop install before changes in the current implementation. See [docs/guides/install-workflows.md](docs/guides/install-workflows.md) for tradeoffs and [docs/reference/internal/config-collision-handling.md](docs/reference/internal/config-collision-handling.md) for exact behavior.

## Global Behavior

Implemented across both Codex and Claude:

- **[jcodemunch-mcp](docs/reference/services/jcodemunch.md)** — indexes repo code to allow for easier access by agents. Eliminates token waste by providing a mapping for agents to find relevant code without excessive expensive grep/glob/read tool calls.
- **[jdocmunch-mcp](docs/reference/services/jdocmunch.md)** — section-based documentation indexer. Same token-efficiency principle as jcodemunch but for `.md`/`.rst`/etc. files. Agents query sections by heading instead of reading full doc files.
- **Caveman plugin** — me make agent talk like caveman to no make big output tokens
- **Minimal verification** — run only the narrowest check that proves an edit; final answer includes receipt like `Verified: npm run check -> pass`
- **[Convention capture](docs/reference/services/convention-capture.md)** — when a decision or pattern is surfaced from a chat, the agent uniquely highlights it in the response, allowing the user to trigger an instruction to write this new convention to agent rules, skills or a file for later review. Updates can be saved to the local repo doc or the global test harness repo (this repo).

## Shared Skills

Lives once in `./skills` and symlinked to `./[harness]/skills`.

- **test-harness** — choosing, running, and explaining tests; debugging CI failures; deciding scoped vs. full checks
- **technical-planning-docs** — recommendations for agents to write effective technical documentation, for architecture notes, migration docs, runbooks, design proposals; structured for future readers with facts/recommendations/risks/open-questions separated
- **frontend-design** — production-grade UI components and pages; avoids generic AI aesthetics
- **blog** — long-form architecture blog posts; fixed 6-beat storyline arc, readable from non-technical to highly technical without becoming a coding tutorial
- **harness-config** — working on this repo itself: adding/editing shared skills, the two-level symlink model, global rules/hooks/settings, Claude/Codex parity. Activates only in global-config context

Each skill's source lives once in `./skills/<name>/`. `claude/skills/` and `codex/skills/` are real directories holding one **per-skill symlink** each (`<name> -> ../../skills/<name>`), so each harness can share the common skills while keeping its own (e.g. Codex's `.system/` skills). Editing a skill's source under `./skills/` is instantly visible to both harnesses; no sync step needed.

**Adding a new skill:** create `skills/<name>/SKILL.md`, then run `scripts/link-skills.sh`. The script scans `skills/` and creates any missing per-harness symlinks (idempotent — safe to run anytime to heal drift). The source folder alone is not enough; without the per-skill symlinks the harnesses won't see it.

Verify with `scripts/link-skills.sh --check` or `scripts/doctor.sh` — both derive the skill list from `skills/`, so neither needs editing when you add a skill.

### Internal (repo-only) skills

Skills that describe how to develop/maintain **this repo itself** live in `skills-local/<name>/`, a separate layer that is **never** symlinked to global config and **never** exported to client repos. `scripts/link-skills.sh` runs a second pass linking `skills-local/<name>` into this repo's own project-scope dotdirs (`.claude/skills/`, `.codex/skills/`), so they auto-load only when an agent works inside harness_configs. The firewall is structural: the export/installer tools read only `skills/`. The `harness-platform-dev` skill (the platform mechanic's manual) lives here.

## Client utilities

This repo ships two cross-platform (Node) commands for use **inside other repos** (installed to `~/.local/bin` by `scripts/install-global-commands.sh`):

- **`harness_helper --export-skill`** — bundles the shared skills into a timestamped `.zip` (shareable artifact) and copies them into the current repo's `.claude/skills` (+ `.codex/skills`), prompting override/skip per skill (override backs the old one up to `archived/<name>_backup_<ts>`). Run from the target repo root.
- **`harness-install-local-skills`** — symlinks a client repo's own `.claude/skills/<name>` into the installed global harnesses (and mirrors into the repo's `.codex/skills`), so app-specific skills get the same dual-harness treatment. Flags: `--dry-run`, `--uninstall`, `--no-mirror-codex`. **Reminder:** after creating a new local skill, re-run it so both harnesses pick the skill up.

Both share `scripts/skill-lib.mjs` and operate only on the shared / client-local layer — never `skills-local/`. Windows without Git Bash: invoke the Node core directly, e.g. `node <repo>/scripts/harness_helper.mjs --export-skill`.

## Shared Rules

Global instruction files are generated tracked outputs:

- `claude/CLAUDE.md`
- `codex/AGENTS.md`

Edit source fragments under `rules/shared/`, `rules/claude/`, and `rules/codex/`, then run `scripts/render-rules.sh`. `scripts/doctor.sh` checks for generated-output drift.

## Codex Specifics

- **Plugins:** GitHub
- **[Hooks](docs/reference/services/codex-hooks.md):** startup/resume activates caveman mode
- **Rules:** pre-approved safe commands for test, build, dev, Docker/Colima, and local doctor checks — fewer approval prompts
- **Model/features:** `gpt-5.5`, medium reasoning, hooks, JavaScript REPL, idle-sleep prevention

## Claude Specifics

- **[Hooks](docs/reference/services/claude-hooks.md):** session hooks detect jcmwatch status, auto-index `docs/` via jdocmunch, remind model to use jcodemunch/jdocmunch; tool hooks block `Grep`/`Glob`, nudge broad reads, trim noisy Bash output
- **Convention capture:** `/capture-convention` slash command (Codex: natural language only — "capture this", "remember this")
- **Behavior flags:** thinking/away-summary stay quiet; dangerous-mode prompt skipped
