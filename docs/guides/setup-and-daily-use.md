# Setup and Daily Use

This repo owns your agent harness config (Claude Code, Codex) and exposes it at the paths agents already read. One install script wires everything up.

For install workflow tradeoffs, see [install-workflows.md](install-workflows.md). For system details, see [../reference/services/architecture.md](../reference/services/architecture.md).

---

## Platform Support

| Platform | Status                                                                                   |
| -------- | ---------------------------------------------------------------------------------------- |
| macOS    | Primary                                                                                  |
| Linux    | Primary                                                                                  |
| Windows  | Available — less tested; requires Git for Windows or WSL — see [Windows notes](#windows) |

---

## Setup

### Clone the repo, then run:

```sh
./scripts/install/main.sh
```

This detects which harnesses are installed (Claude Code, Codex, or both), installs clean repo-managed symlinks, exports mutable root config as local files, installs global commands, and adds shell snippets to your profile.

The installer has three workflows. See [install-workflows.md](install-workflows.md) for what each option offers, what it hinders, and how local user config can live alongside downloaded repo defaults.

- `managed`: read-mostly target path is missing or already points to this repo. The installer creates or keeps the symlink. Mutable root config is copied into a local active file instead of symlinked.
- `adopt`: a user-owned root config exists, so the installer leaves it in place and installs only other clean harness links.
- `agent prompt`: a user-owned root config exists and needs manual comparison, so the installer prints a merge prompt and leaves it unchanged.

Root config export is only automatic when the target path is missing, already an identical local copy, or still symlinked to this repo from an older install. The installer does not auto-merge user config or silently replace non-root conflicts. If another harness file or global command target already exists and is not managed by this repo, install stops before changing files and prints an agent prompt. See [Config Collision Handling](../reference/internal/config-collision-handling.md) for exact behavior.

**The script is safe to re-run** — managed links are left alone, fresh paths are linked, identical root config copies are accepted, and user-owned root config files are preserved unless you explicitly merge them later. Re-run it for a new machine, broken symlink, added harness, or new commands/snippets added to the repo.

### Preview without modifying anything:

```sh
./scripts/install/main.sh --dry-run
```

### Verify the install:

```sh
./scripts/verify-install.sh
```

### Test installer collision behavior:

```sh
./scripts/test/test-install-collisions.sh
```

This runs against temporary `HOME` directories only. See [Config Collision Handling](../reference/internal/config-collision-handling.md#validation) for what it covers.

---

## Maintenance

### Sync live config changes back to the repo

Claude Code and Codex sometimes write directly to active files under `~/.claude` or `~/.codex` during a session. Use this to review those live changes and selectively copy intentional changes back into the repo.

```sh
./scripts/sync-from-home.sh
```

For each changed item, the script shows a diff before writing to the repo. Choose `keep repo`, `overwrite repo`, or `agent prompt`.

By default, sync skips root config files: `~/.claude/settings.json` and `~/.codex/config.toml`. Those files are active local files because Claude and Codex can write personal state there. Use `--include-root-config` only when you intentionally want to review and promote selected local root config changes into the repo baseline:

```sh
./scripts/sync-from-home.sh --include-root-config
```

For the decision model, see [Config Collision Handling](../reference/internal/config-collision-handling.md#sync-workflow).

---

## Daily Use

Everything below is driven by one command, **`roborepo`** — the single front door for setup,
indexing, skills, and maintenance. It is installed and added to your `PATH` automatically by the
installer (no manual PATH step on macOS/Linux); open a new shell after the first install so it
resolves. Run `roborepo` with no arguments for an interactive menu, or call a subcommand directly
as shown below. Full reference: [roborepo CLI](../reference/services/roborepo.md).

### Index and watch a repo

Keep the jcodemunch index current so Claude can navigate your codebase. Start this when opening a project you'll be actively coding in. The watcher runs continuously — edits are picked up automatically within the session.

```sh
roborepo watch code               # watch the current dir (runs continuously)
roborepo watch code path/to/dir
roborepo index code path/to/dir   # one-shot index instead of watching
```

### Index docs

Index a project's documentation so Claude can search sections and headings rather than reading full files. Run once per project to initialize. After that, edits to existing files are picked up automatically via mtime detection — no manual reindex needed. Re-run only when doc files are added or deleted.

```sh
roborepo index docs               # index docs in the current dir
roborepo index docs path/to/dir
```

### Add a shared skill

A shared skill's content lives once in `globals/agents/skills/<name>/`, the canonical source. Codex
reaches it via `~/.agents/skills`; Claude reaches it through a per-skill symlink (see
[architecture.md](../reference/services/architecture.md#shared-skills-canonical-source--per-harness-fan-out)).
After creating `globals/agents/skills/<name>/SKILL.md`, run the linker — it creates any missing
Claude per-skill symlinks and prunes orphaned ones, deriving everything from `globals/agents/skills/`:

```sh
scripts/build/link-skills.sh          # create/prune links for all skills
scripts/build/link-skills.sh --check  # verify only, non-zero exit if out of sync
```

The source folder alone is not enough; without the symlinks the harnesses won't see the
skill (and the active skill list only refreshes on harness reload).

### Edit global rules

Global instruction files are generated tracked outputs:

- `globals/claude/CLAUDE.md`
- `globals/codex/AGENTS.md`

Edit source fragments instead:

- `globals/rules/shared/` for behavior shared by Claude and Codex
- `globals/rules/claude/` for Claude-only behavior
- `globals/rules/codex/` for Codex-only behavior

Then render and check:

```sh
./scripts/build/render-rules.sh
./scripts/build/render-rules.sh --check
```

### Check harness health

Something feels off — commands missing, config not loading, hooks not firing. Run this to verify key files, JSON/TOML config, helpers, and dependencies. The skill checks are derived from `globals/agents/skills/`, so adding a skill needs no edit here.

```sh
roborepo doctor        # (dispatches to scripts/doctor.sh)
scripts/doctor.sh --installed     # also checks the global ~/.claude·~/.codex·~/.agents links
scripts/doctor.sh --installed -q  # --quiet: failures + a one-line summary only
```

`doctor.sh`, `verify-install.sh`, `test-roborepo.sh`, and `link-skills.sh` all accept
`--quiet`/`-q` — prints only failures plus a summary line, exit code unchanged. Prefer that over
piping a checker through `grep`/`head`.

### Run noisy commands with trimmed output

Some commands flood the terminal. Wrap them to get only the useful tail.

```sh
roborepo run <command> [args]
```

---

## Windows

Git Bash is required — hook scripts and bin commands are bash and will not run without it.

**Requirements:**

- **Git for Windows** (https://git-scm.com) — install this first; provides Git Bash
- **Windows Developer Mode** or **admin PowerShell** — required for symlinks (`Settings > System > For Developers > Developer Mode`)

**Install from Git Bash:**

```bash
./scripts/install/main.sh
```

**Config paths on Windows:**

| Item          | Path                    |
| ------------- | ----------------------- |
| Claude config | `%APPDATA%\Claude\`     |
| Codex config  | `%USERPROFILE%\.codex\` |
