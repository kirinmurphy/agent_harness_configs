# Harness Configs

Version controlled Codex & Claude global harness configurations that symlink to local file system. Primary focus on optimizing token efficiency and implementing tool/resource/skill parity across harnesses.

## Start Here

Works with Claude Code, Codex, or both. Supports macOS and Linux; Windows support is available but less tested.

**One command is the front door: `roborepo`.** After the first install it is on your `PATH`, and everything a consumer of this repo does — installing/updating, indexing, working with skills, registering MCP servers, maintenance — runs through it. Run `roborepo` with no arguments for an interactive menu, or a subcommand directly. The first install bootstraps it:

```sh
./scripts/roborepo-install.sh   # first install; puts roborepo on PATH. After that: roborepo update
```

- **Full roborepo reference (every subcommand): [docs/reference/services/roborepo.md](docs/reference/services/roborepo.md)**
- Install and daily commands: [docs/guides/setup-and-daily-use.md](docs/guides/setup-and-daily-use.md)
- Install workflow choices: [docs/guides/install-workflows.md](docs/guides/install-workflows.md)
- Documentation index: [docs/README.md](docs/README.md)
- System reference: [docs/reference/services/architecture.md](docs/reference/services/architecture.md)

## Install Workflow Choices

`./scripts/roborepo-install.sh` installs repo-managed config where it can do so cleanly. If it finds existing user-owned root config, it asks whether to manage from this repo or adopt the repo defaults into local config.

| Workflow | What it gives you | What it hinders | User responsibility |
| --- | --- | --- | --- |
| `managed` | Logic stays in this repo and is observed by global config through symlinks. Updates are simple. | Local root config is no longer independently curated. | Edit repo files or sync local changes back into the repo. |
| `adopt` | Repo defaults are copied or merged into user-owned global config. Existing files can be replaced/archived, kept while repo candidates are staged, or reviewed through an agent prompt. | No automatic semantic merge unless implemented for a specific path. | Review archived/staged files or agent output, then merge wanted settings. |

No option should delete existing user config. Conflicted files are preserved either as active local files, archived files, staged repo candidates, or agent-review input. Non-root conflicts, such as existing hooks, skills, commands, rules, or global command targets, stop install before changes in the current implementation. See [docs/guides/install-workflows.md](docs/guides/install-workflows.md) for tradeoffs and [docs/reference/internal/config-collision-handling.md](docs/reference/internal/config-collision-handling.md) for exact behavior.

For filesystem diagrams showing what lives in the repo vs `~/.claude`/`~/.codex` under managed and adopt modes, see [docs/reference/services/architecture.md#install-workflow-filesystem-shapes](docs/reference/services/architecture.md#install-workflow-filesystem-shapes).

## Global Behavior

Implemented across both Codex and Claude:

| Behavior | Description |
| --- | --- |
| **[jcodemunch-mcp](docs/reference/services/jcodemunch.md)** | Indexes repo code to allow for easier access by agents. Eliminates token waste by providing a mapping for agents to find relevant code without excessive expensive grep/glob/read tool calls. |
| **[jdocmunch-mcp](docs/reference/services/jdocmunch.md)** | Section-based documentation indexer. Same token-efficiency principle as jcodemunch but for `.md`/`.rst`/etc. files. Agents query sections by heading instead of reading full doc files. |
| **Caveman plugin** | Me make agent talk like caveman to no make big output tokens. |
| **Minimal verification** | Run only the narrowest check that proves an edit; final answer includes receipt like `Verified: npm run check -> pass`. |
| **[Convention capture](docs/reference/services/convention-capture.md)** | When a decision or pattern is surfaced from a chat, the agent uniquely highlights it in the response, allowing the user to trigger an instruction to write this new convention to agent rules, skills or a file for later review. Updates can be saved to the local repo doc or the global test harness repo (this repo). |

## Shared Skills

Lives once in `./skills` and symlinked to `./[harness]/skills`.

| Skill | Description |
| --- | --- |
| **test-harness** | Choosing, running, and explaining tests; debugging CI failures; deciding scoped vs. full checks. |
| **technical-planning-docs** | Recommendations for agents to write effective technical documentation, for architecture notes, migration docs, runbooks, design proposals; structured for future readers with facts/recommendations/risks/open-questions separated. |
| **frontend-design** | Production-grade UI components and pages; avoids generic AI aesthetics. |
| **blog** | Long-form architecture blog posts; fixed 6-beat storyline arc, readable from non-technical to highly technical without becoming a coding tutorial. |
| **harness-config** | Working on this repo itself: adding/editing shared skills, the two-level symlink model, global rules/hooks/settings, Claude/Codex parity. Activates only in global-config context. |

Each skill's source lives once in `./agents/skills/<name>/`, the canonical shared source. Codex scans `~/.agents/skills` **exclusively** (there is no `~/.codex/skills` fallback), so the installer links `~/.agents/skills → agents/skills` directly (plus a transitional `~/.codex/skills` for cross-compat). Claude reads `~/.claude/skills`, a folder symlink to `claude/skills/`, which holds one **per-skill symlink** each (`<name> -> ../../agents/skills/<name>`). Codex's own `.system/` skills are real files at `agents/skills/.system/`. Editing a skill's source under `./agents/skills/` is instantly visible to both harnesses; no sync step needed.

**Adding a new skill:** create `agents/skills/<name>/SKILL.md`, then run `scripts/link-skills.sh`. The script scans `agents/skills/` and creates any missing Claude per-skill symlinks (idempotent — safe to run anytime to heal drift). The source folder alone is not enough for Claude; without the per-skill symlinks it won't see the skill.

Verify with `scripts/link-skills.sh --check` or `scripts/doctor.sh` — both derive the skill list from `agents/skills/`, so neither needs editing when you add a skill.

### Internal (repo-only) skills

Skills that describe how to develop/maintain **this repo itself** live in `skills-local/<name>/`, a separate layer that is **never** symlinked to global config and **never** exported to client repos. `scripts/link-skills.sh` runs a second pass linking `skills-local/<name>` into this repo's own project-scope dotdirs (`.claude/skills/`, `.agents/skills/`, `.codex/skills/`), so they auto-load only when an agent works inside harness_configs. The firewall is structural: the export/installer tools read only `agents/skills/`. The `harness-platform-dev` skill (the platform mechanic's manual) lives here.

## The `roborepo` CLI

One command, installed to `~/.local/bin` by the installer, is the single front door for everything a consumer of this repo does. Run `roborepo` for an interactive menu, or a subcommand directly. The categories:

| Category | Subcommands |
| --- | --- |
| Skills | `skill export`, `skill link` |
| Day to day | `index code\|docs`, `watch code`, `mcp add`, `run` |
| Lifecycle | `update`, `sync`, `doctor`, `verify` |

**See [docs/reference/services/roborepo.md](docs/reference/services/roborepo.md) for the complete reference** — every flag, the interactive menu, MCP registration, PATH wiring, and the `scripts/cli/` module layout. The first install is the shell bootstrap `scripts/roborepo-install.sh` (that puts `roborepo` on `PATH`); from then on you only ever `roborepo update`. Maintainer-only scripts (`render-rules.sh`, `link-skills.sh`, `test-*.sh`) are deliberately not exposed through `roborepo`.

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

- **[Hooks](docs/reference/services/claude-hooks.md):** session hooks detect code-watcher status, auto-index `docs/` via jdocmunch, remind model to use jcodemunch/jdocmunch; tool hooks block `Grep`/`Glob`, nudge broad reads, trim noisy Bash output
- **Convention capture:** `/capture-convention` slash command (Codex: natural language only — "capture this", "remember this")
- **Behavior flags:** thinking/away-summary stay quiet; dangerous-mode prompt skipped
