# Harness Configs

Version controlled codex & claude global harness configurations with the ability to symlink to local (Mac) file system.

## Setup

Install and symlink details: [docs/symlinking.md](docs/symlinking.md).

## Global Behavior

Implemented across both Codex and Claude:

- **[jcodemunch-mcp](docs/jcodemunch.md)** — indexes repo code to allow for easier access by agents. Eliminates token waste by providing a mapping for agents to find relevant code without excessive expensive grep/glob/read tool calls.
- **[jdocmunch-mcp](docs/jdocmunch.md)** — section-based documentation indexer. Same token-efficiency principle as jcodemunch but for `.md`/`.rst`/etc. files. Agents query sections by heading instead of reading full doc files.
- **Caveman plugin** — me make agent talk like caveman to reduce output token use
- **Minimal verification** — run only the narrowest check that proves an edit; final answer includes receipt like `Verified: npm run check -> pass`
- **[Convention capture](docs/convention-capture.md)** — when a decision or pattern is surfaced from a chat, the agent uniquely highlights it in the response, allowing the user to trigger an instruction to write this new convention to a file for later review, to ultimately update agent rules. Updates can be saved to the local repo doc or the global test harness repo (this repo).

## Shared Skills

Lives once in `/skills` and symlinked to `/[harness]/skills`.

- **test-harness** — choosing, running, and explaining tests; debugging CI failures; deciding scoped vs. full checks
- **technical-planning-docs** — recommendations for agents to write effective technical documentation, for architecture notes, migration docs, runbooks, design proposals; structured for future readers with facts/recommendations/risks/open-questions separated
- **frontend-design** — production-grade UI components and pages; avoids generic AI aesthetics

`claude/skills/` and `codex/skills/` are symlinks pointing back to `skills/` — not copies. Editing `skills/` is instantly visible to both harnesses; no sync step needed. See [docs/symlinking.md](docs/symlinking.md) for setup.

## Codex Specifics

- **Plugins:** GitHub
- **[Hooks](docs/codex-hooks.md):** startup/resume activates caveman mode
- **Rules:** pre-approved safe commands for test, build, dev, Docker/Colima, and local doctor checks — fewer approval prompts
- **Model/features:** `gpt-5.5`, medium reasoning, hooks, JavaScript REPL, idle-sleep prevention

## Claude Specifics

- **[Hooks](docs/claude-hooks.md):** session hooks detect jcmwatch status, auto-index `docs/` via jdocmunch, remind model to use jcodemunch/jdocmunch; tool hooks block `Grep`/`Glob`, nudge broad reads, trim noisy Bash output
- **Convention capture:** `/capture-convention` slash command (Codex: natural language only — "capture this", "remember this")
- **Behavior flags:** thinking/away-summary stay quiet; dangerous-mode prompt skipped

## Tools & Scripts

- `bin/harness-run` — runs noisy commands and prints only a useful tail
- `bin/jcmindex` — one-shot jcodemunch index for a file or folder
- `bin/jcmwatch` — continuous watch mode; writes a pidfile so the harness knows it's running and skips stale-index warnings
- `bin/jdmindex` — one-shot jdocmunch index for a docs folder; writes `.jdm-indexed` marker so session hooks can detect per-repo index state
- `shell/jcodemunch.zsh` — shell function version of jcmwatch/jcmindex helpers
- `shell/jdocmunch.zsh` — shell function version of jdmindex helper
- `scripts/install-gitignore-globals.sh` — adds `.jdm-indexed` to `~/.gitignore_global` and sets `git core.excludesfile`; called automatically by `install-symlinks.sh`
- `scripts/doctor.sh` — checks repo config health: key files, JSON, TOML, helpers, and `uvx`

## Config Files

- `~/.claude/CLAUDE.md` (symlinked from `claude/CLAUDE.md`) — global rules for all repos: caveman mode, jcodemunch, verification discipline, session capture
- `CLAUDE.md` at repo root — harness-maintenance rules only; not symlinked globally
- `~/.codex/AGENTS.md` (symlinked from `codex/AGENTS.md`) — equivalent global rules for Codex

## Not Tracked

Auth, logs, history, caches, sessions, SQLite state, local settings, generated plugin caches, and other runtime files stay outside git.
