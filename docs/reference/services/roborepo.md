# roborepo CLI

`roborepo` is the single command for everything a consumer of this harness does — setting up the
install on a machine, day-to-day indexing, working with skills, and maintenance. It replaces the
old one-off commands (`harness_helper`, `harness-run`, `jcmindex`, `jcmwatch`, `jdmindex`,
`harness-install-local-skills`), so there is one name to remember and one entry on `PATH`.

It is a Node program invoked via the `bin/roborepo` shim, installed to `~/.local/bin/roborepo`.
`scripts/roborepo.mjs` is a thin orchestrator (usage, interactive menu, dispatch table); the
subcommand implementations live under `scripts/cli/`, one module per category:

| Module | Owns |
| --- | --- |
| `scripts/cli/skills.mjs` | `skill export`, `skill link` |
| `scripts/cli/index.mjs` | `index code\|docs`, `watch code`, `run` |
| `scripts/cli/mcp.mjs` | `mcp add` (Claude + Codex registration) |
| `scripts/cli/paths.mjs` | shared `repoRoot` / `sharedSkillsDir` |
| `scripts/cli/skill-lib.mjs` | shared Node core (zip, prompts, symlink helpers) |

Pure `node:` built-ins — no external `zip`/`unzip`/`ln` — so it runs on macOS, Linux, and Windows
(Git Bash). On Windows without Git Bash, call the Node entry directly:
`node <repo>/scripts/roborepo.mjs <args>`.

## Install and PATH

`roborepo` is wired automatically by the installer — there is no manual PATH step on macOS/Linux.
`scripts/install-global-commands.sh` (run by `scripts/roborepo-install.sh`, and again by every
`roborepo update`):

1. symlinks `bin/roborepo` into `~/.local/bin/roborepo`, and
2. appends `export PATH="${HOME}/.local/bin:${PATH}"` to your shell profile if it is not already
   present (idempotent).

Open a new shell (or `source` your profile) after the first install, then `roborepo` resolves from
anywhere.

The installer picks the profile from your `$SHELL`, choosing the file your shell actually sources
on a new terminal:

- **zsh** → `~/.zshrc`
- **bash** → `~/.bash_profile` on macOS (Terminal launches login shells), `~/.bashrc` on Linux
  (interactive shells); prefers whichever already exists
- **other** → `~/.profile` if it exists; otherwise the installer does **not** guess — it prints the
  exact line to add (e.g. `fish_add_path ~/.local/bin`) rather than writing a file the shell never
  reads

A missing profile file is created. Set `HARNESS_CONFIG_SHELL_PROFILE=/path/to/profile` to override
the choice.

Windows + PowerShell is the one case that needs a manual PATH addition (the POSIX installer cannot
edit a PowerShell profile): add `~/.local/bin` via System Environment Variables or your
`$PROFILE`, then restart the shell.

**Confirm it worked:** `roborepo doctor` checks that `roborepo` actually resolves on `PATH`, not
just that the symlink exists. If the command is installed but not yet on `PATH` (a fresh install
before opening a new shell, or a Windows manual add that hasn't taken effect), doctor prints a
`warn:` with the exact `export PATH=...` line and tells you to open a new shell. Re-run
`roborepo doctor` to verify.

## Interactive menu

Running `roborepo` with no arguments opens an interactive menu. On an interactive terminal it is
arrow-key driven (↑/↓ to move, Enter to select, Esc/`q`/Ctrl-C to cancel); on a non-interactive
terminal (a pipe, CI, a dumb terminal) it falls back to a numbered list read from stdin. Items are
grouped into sections by significance, each with a short description:

```
roborepo — choose an action:

  Setup
> update         re-apply harness config on this machine (pick up new config)

  Day to day
  index code     index this repo's code for jcodemunch
  index docs     index this repo's docs for jdocmunch
  mcp add        register an MCP server with Claude + Codex
  watch code     live-index code as files change
  run            run a command with trimmed output

  Skills
  skill export   copy shared skills into this repo
  skill link     link this repo's .agents/skills into .claude + .codex

  Maintenance
  sync           pull live config back into the repo
  doctor         health check
  verify         post-install verification

  Other
  help           show full usage
  exit           quit
```

## Subcommands

```
roborepo skill export [--yes] [--on-conflict=skip|override]
roborepo skill link  [--dry-run] [--uninstall]

roborepo index code  [path]
roborepo index docs  [path]
roborepo mcp add <name-or-url> [--scope=user|local|project] [--name=<name>] [--dry-run] [--only-claude|--only-codex] [--skip-claude-permission]
roborepo addMCP <name-or-url>
roborepo watch code  [path]

roborepo run <cmd> [args...]

roborepo update  [--dry-run]
roborepo sync
roborepo doctor  [--installed]
roborepo verify

roborepo --help | -h
```

`[path]` is optional everywhere it appears: it defaults to the current directory and may be
relative or absolute — roborepo resolves it to an absolute path before use.

### Categories

- **Setup** — `update` re-applies the harness config on this machine (re-runs the symlink/command/
  shell install to pick up new config). The *first* install is the shell bootstrap
  `scripts/roborepo-install.sh` — that is what puts `roborepo` on `PATH` — so the CLI has no
  separate `install` verb; once `roborepo` exists you only ever `update`.
- **Day to day** — `index code|docs` are one-shot indexers; `watch code` runs a live indexer (and
  writes the pidfile the Claude SessionStart hook reads to report watcher status); `mcp add`
  registers MCP servers with Claude + Codex; `run` executes a command and prints only a trimmed
  tail of its output.
- **Skills** — `skill export` bundles the shared skills into a `.zip` and copies them into the
  current repo's `.claude/skills` (+ `.agents/skills`, which Codex scans) with per-skill
  override/skip (override backs the old one up under `archived/`). `skill link` symlinks the current
  repo's own `.agents/skills/<name>` (its canonical source, also what Codex scans) into its
  `.claude/skills` + `.codex/skills` (purely in-repo, never global) and prunes links whose source is
  gone. See [architecture.md](architecture.md#two-skill-layers-shared-vs-internal).
- **Maintenance** — `sync` pulls live config back into the repo; `doctor` and `verify` are health
  and post-install checks. These dispatch to the existing bash scripts.

The lifecycle verbs dispatch to `scripts/roborepo-install.sh`, `scripts/sync-from-home.sh`,
`scripts/doctor.sh`, and `scripts/verify-install.sh`; those filenames are an internal detail.
Maintainer-only scripts (`render-rules.sh`, `link-skills.sh`, `test-*.sh`) are intentionally not
exposed through `roborepo`.

## MCP registration

`roborepo mcp add <name-or-url>` wraps the Claude registration step and the Codex config update so
common MCP setup is repeatable instead of hand-typed. After Claude registration succeeds it also:

- adds `mcp__<name>` to `claude/settings.json` so the server's tools are allowed without repeated
  approval prompts (skip with `--skip-claude-permission`), and
- adds an MCP block to `codex/config.toml`.

Default target is both harnesses; `--only-claude` / `--only-codex` scope it. Presets exist for the
two bundled servers (`jcodemunch`, `jdocmunch`, both `uvx`-based); any other non-URL value is
treated as a `uvx` package, and HTTP URLs default to `--transport http` and are written to Codex as
a `url = "..."` block. `addMCP` is an alias for `mcp add`. Use `--dry-run` to print the exact
`claude mcp add ...` command plus the planned Claude-permission and Codex-config writes without
touching anything.

## Tests

`scripts/test-roborepo.sh` smoke-tests the subcommands (skill link/prune/uninstall/conflict,
export/override/firewall/self-pollution guard, run, `mcp add` dry-runs + real Codex/Claude writes
against a throwaway harness root, lifecycle dispatch, menu fallback) against throwaway temp repos.
It touches no global state.
