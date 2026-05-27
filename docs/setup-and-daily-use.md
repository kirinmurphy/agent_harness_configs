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

This detects which harnesses are installed (Claude Code, Codex, or both), symlinks their config from this repo, installs global commands, and adds shell snippets to your profile. Existing files are backed up to `~/.harness-configs-backups/<timestamp>/` before replacement.

**The script is idempotent** — re-run it any time: new machine, broken symlink, added a harness, new commands or snippets added to the repo.

### Preview without modifying anything:

```sh
./scripts/install-symlinks.sh --dry-run
```

### Verify the install:

```sh
./scripts/verify-install.sh
```

---

## Maintenance

### Sync live config changes back to the repo

Claude Code and Codex sometimes write directly to `~/.claude` or `~/.codex` during a session — for example, when you approve a new permission, it updates `settings.json` in place. Use this to pull those changes back into the repo so they're versioned and portable.

```sh
./scripts/sync-from-home.sh
```

> **Always run `git diff` after** — the script overwrites repo files with live state. Review the diff before committing to avoid silently regressing intentional repo edits.

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
