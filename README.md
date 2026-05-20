# Harness Configs

Version-controlled behavior for local AI agents. Goal: make Codex and Claude use the same habits for code lookup, testing, terse communication, and low-noise output.

Install and symlink details: [docs/symlinking.md](docs/symlinking.md).

## Global Behavior

Both harnesses use `jcodemunch-mcp` for code indexing (eliminates token waste from parsing unrelated files), default to caveman terse mode, share the same skill playbooks, and run only the narrowest verification command that proves an edit. Final answers include an explicit receipt like `Verified: npm run check -> pass`.

## Codex

- **MCP:** `jcodemunch-mcp` via `uvx`
- **Plugins:** GitHub, caveman
- **Hooks:** startup/resume activates caveman mode
- **Rules:** pre-approved safe commands for test, build, dev, Docker/Colima, and local doctor checks — fewer approval prompts
- **Model/features:** `gpt-5.5`, medium reasoning, hooks, JavaScript REPL, idle-sleep prevention

## Claude

- **Plugins:** caveman, Vercel
- **Hooks:** session hook reminds to use jcodemunch; tool hooks block `Grep`/`Glob`, nudge broad reads, trim noisy Bash output
- **Commands:** `/capture-and-clear` captures durable session learnings into repo docs after confirmation
- **Behavior flags:** thinking/away-summary stay quiet; dangerous-mode prompt skipped

## Shared Skills

`test-harness`, `technical-planning-docs`, and `frontend-design` live once in `skills/` and are symlinked into both harnesses — same playbooks, no duplicate files.

## Tools & Scripts

- `bin/harness-run` — runs noisy commands and prints only a useful tail
- `bin/jcmindex` — one-shot jcodemunch index for a file or folder
- `shell/jcodemunch.zsh` — shell function version of the jcodemunch helper
- `scripts/doctor.sh` — checks repo config health: key files, JSON, TOML, helpers, and `uvx`

## Parity TODO

- Confirm whether Codex supports a stable shell `PreToolUse` hook; until then use `harness-run` for noisy commands
- Watch whether Claude needs explicit safe allow rules for common test commands
- Consider replacing duplicated user skill files with a generated or symlinked shared source

## Not Tracked

Auth, logs, history, caches, sessions, SQLite state, local settings, generated plugin caches, and other runtime files stay outside git.
