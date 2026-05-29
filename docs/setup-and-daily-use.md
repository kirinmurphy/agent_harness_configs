# Setup and Daily Use

This repo owns your agent harness config (Claude Code, Codex) and exposes it at the paths agents already read. One install script wires everything up.

View [this doc](architecture.md) for more details on how it works.

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

If `~/.claude/settings.json` or `~/.codex/config.toml` already exists and is not managed by this repo, the installer treats it as a collision and asks what to do:

- `adopt`: keep the local root config file as the source of truth. The installer still installs other harness-managed files only when their target paths are missing or already managed by this repo.
- `agent prompt`: print a merge prompt for a coding agent and leave the root config unchanged.

Managed root config is only automatic when the target path is missing or already managed by this repo. The installer does not auto-merge user config or silently replace non-root conflicts. If another harness file or global command target already exists and is not managed by this repo, install stops before changing files and prints an agent prompt. See [Config Collision Handling](config-collision-handling.md) for the full workflow.

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

This runs against temporary `HOME` directories only. See [Config Collision Handling](config-collision-handling.md#validation) for what it covers.

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

For the decision model, see [Config Collision Handling](config-collision-handling.md#sync-workflow).

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

### Check harness health

Something feels off — commands missing, config not loading, hooks not firing. Run this to verify key files, JSON/TOML config, helpers, and dependencies.

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
