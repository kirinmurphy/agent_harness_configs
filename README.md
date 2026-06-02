# Harness Configs

Version controlled Codex & Claude global harness configurations that symlink to local file system. Primary focus on optimizing token efficiency and implementing tool/resource/skill parity across harnesses.

## Setup

Works with Claude Code, Codex, or both. Supports macOS and Linux; Windows support is available but less tested. See [docs/setup-and-daily-use.md](docs/setup-and-daily-use.md) for platform-specific instructions and details.

## Global Behavior

Implemented across both Codex and Claude:

- **[jcodemunch-mcp](docs/jcodemunch.md)** — indexes repo code to allow for easier access by agents. Eliminates token waste by providing a mapping for agents to find relevant code without excessive expensive grep/glob/read tool calls.
- **[jdocmunch-mcp](docs/jdocmunch.md)** — section-based documentation indexer. Same token-efficiency principle as jcodemunch but for `.md`/`.rst`/etc. files. Agents query sections by heading instead of reading full doc files.
- **Caveman plugin** — me make agent talk like caveman to no make big output tokens
- **Minimal verification** — run only the narrowest check that proves an edit; final answer includes receipt like `Verified: npm run check -> pass`
- **[Convention capture](docs/convention-capture.md)** — when a decision or pattern is surfaced from a chat, the agent uniquely highlights it in the response, allowing the user to trigger an instruction to write this new convention to agent rules, skills or a file for later review. Updates can be saved to the local repo doc or the global test harness repo (this repo).

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

## Shared Rules

Global instruction files are generated tracked outputs:

- `claude/CLAUDE.md`
- `codex/AGENTS.md`

Edit source fragments under `rules/shared/`, `rules/claude/`, and `rules/codex/`, then run `scripts/render-rules.sh`. `scripts/doctor.sh` checks for generated-output drift.

## Codex Specifics

- **Plugins:** GitHub
- **[Hooks](docs/codex-hooks.md):** startup/resume activates caveman mode
- **Rules:** pre-approved safe commands for test, build, dev, Docker/Colima, and local doctor checks — fewer approval prompts
- **Model/features:** `gpt-5.5`, medium reasoning, hooks, JavaScript REPL, idle-sleep prevention

## Claude Specifics

- **[Hooks](docs/claude-hooks.md):** session hooks detect jcmwatch status, auto-index `docs/` via jdocmunch, remind model to use jcodemunch/jdocmunch; tool hooks block `Grep`/`Glob`, nudge broad reads, trim noisy Bash output
- **Convention capture:** `/capture-convention` slash command (Codex: natural language only — "capture this", "remember this")
- **Behavior flags:** thinking/away-summary stay quiet; dangerous-mode prompt skipped
