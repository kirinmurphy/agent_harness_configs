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
./scripts/install-symlinks.sh
```

This detects which harnesses are installed (Claude Code, Codex, or both), installs clean repo-managed symlinks, installs global commands, and adds shell snippets to your profile.

The installer has three workflows. See [install-workflows.md](install-workflows.md) for what each option offers, what it hinders, and how local user config can live alongside downloaded repo defaults.

- `managed`: target path is missing or already points to this repo. The installer creates or keeps the symlink.
- `adopt`: a user-owned root config exists, so the installer leaves it in place and installs only other clean harness links.
- `agent prompt`: a user-owned root config exists and needs manual comparison, so the installer prints a merge prompt and leaves it unchanged.

Managed root config is only automatic when the target path is missing or already managed by this repo. The installer does not auto-merge user config or silently replace non-root conflicts. If another harness file or global command target already exists and is not managed by this repo, install stops before changing files and prints an agent prompt. See [Config Collision Handling](../reference/internal/config-collision-handling.md) for exact behavior.

**The script is safe to re-run** — managed links are left alone, fresh paths are linked, and user-owned root config files are preserved unless you explicitly merge them later. Re-run it for a new machine, broken symlink, added harness, or new commands/snippets added to the repo.

### Preview without modifying anything:

```sh
./scripts/install-symlinks.sh --dry-run
```

### Verify the install:

```sh
./scripts/verify-install.sh
```

### Test installer collision behavior:

```sh
./scripts/test-install-collisions.sh
```

This runs against temporary `HOME` directories only. See [Config Collision Handling](../reference/internal/config-collision-handling.md#validation) for what it covers.

---

## Maintenance

### Sync live config changes back to the repo

Claude Code and Codex sometimes write directly to managed files under `~/.claude` or `~/.codex` during a session. Use this to review those live changes and selectively copy them back into the repo.

```sh
./scripts/sync-from-home.sh
```

For each changed item, the script shows a diff before writing to the repo. Choose `keep repo`, `overwrite repo`, or `agent prompt`.

By default, sync skips user-owned root config files: `~/.claude/settings.json` and `~/.codex/config.toml`. Those files are user-owned when you chose `adopt`, or when they are regular local files instead of symlinks to this repo. Use `--include-root-config` only when you intentionally want to review and promote those local root config files into the repo baseline:

```sh
./scripts/sync-from-home.sh --include-root-config
```

For the decision model, see [Config Collision Handling](../reference/internal/config-collision-handling.md#sync-workflow).

---

## Daily Use

### Index and watch a repo

Keep the jcodemunch index current so Claude can navigate your codebase. Start this when opening a project you'll be actively coding in. The watcher runs continuously — edits are picked up automatically within the session.

```sh
jcmwatch              # watch $PWD (runs continuously)
jcmwatch path/to/dir
jcmindex path/to/dir  # one-shot index instead of watching
```

### Index docs

Index a project's documentation so Claude can search sections and headings rather than reading full files. Run once per project to initialize. After that, edits to existing files are picked up automatically via mtime detection — no manual reindex needed. Re-run only when doc files are added or deleted.

```sh
jdmindex              # index docs/ in $PWD
jdmindex path/to/dir
```

### Add a shared skill

A shared skill's content lives once in `skills/<name>/`, but each harness reaches it
through a per-skill symlink (see [architecture.md](../reference/services/architecture.md#shared-skills-use-two-symlink-levels)).
After creating `skills/<name>/SKILL.md`, run the linker — it creates any missing
per-harness symlinks and prunes orphaned ones, deriving everything from `skills/`:

```sh
scripts/link-skills.sh          # create/prune links for all skills
scripts/link-skills.sh --check  # verify only, non-zero exit if out of sync
```

The source folder alone is not enough; without the symlinks the harnesses won't see the
skill (and the active skill list only refreshes on harness reload).

### Edit global rules

Global instruction files are generated tracked outputs:

- `claude/CLAUDE.md`
- `codex/AGENTS.md`

Edit source fragments instead:

- `rules/shared/` for behavior shared by Claude and Codex
- `rules/claude/` for Claude-only behavior
- `rules/codex/` for Codex-only behavior

Then render and check:

```sh
./scripts/render-rules.sh
./scripts/render-rules.sh --check
```

### Check harness health

Something feels off — commands missing, config not loading, hooks not firing. Run this to verify key files, JSON/TOML config, helpers, and dependencies. The skill checks are derived from `skills/`, so adding a skill needs no edit here.

```sh
doctor.sh
```

### Run noisy commands with trimmed output

Some commands flood the terminal. Wrap them to get only the useful tail.

```sh
harness-run <command> [args]
```

---

## Windows

Git Bash is required — hook scripts and bin commands are bash and will not run without it.

**Requirements:**

- **Git for Windows** (https://git-scm.com) — install this first; provides Git Bash
- **Windows Developer Mode** or **admin PowerShell** — required for symlinks (`Settings > System > For Developers > Developer Mode`)

**Install from Git Bash:**

```bash
./scripts/install-symlinks.sh
```

**Config paths on Windows:**

| Item          | Path                    |
| ------------- | ----------------------- |
| Claude config | `%APPDATA%\Claude\`     |
| Codex config  | `%USERPROFILE%\.codex\` |
