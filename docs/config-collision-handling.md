# Config Collision Handling

## Purpose

The harness owns shared Claude Code and Codex defaults, but `~/.claude/settings.json` and `~/.codex/config.toml` can also contain personal config. The installer protects those files from silent replacement when they already exist outside this repo.

## Concept Model

- **Managed config**: a home config file is a symlink to this repo. Repo changes flow into the tool automatically.
- **User-owned config**: a home config file is a regular file, or a symlink somewhere other than this repo.
- **Collision**: the installer finds a user-owned `~/.claude/settings.json` or `~/.codex/config.toml` where it would normally create a harness symlink.
- **Non-root harness target**: a harness path such as skills, hooks, commands, rules, or managed marker files. These are not merged by the installer.

## Installer Choices

The installer has three different workflows:

- `managed`: target path is missing or already symlinked to this repo. The installer creates or keeps the symlink. Repo defaults are the active source.
- `adopt`: root config exists outside this repo. The installer leaves the local root config in place, marks that harness as adopted for this install run, and still installs other clean harness links.
- `agent prompt`: root config exists outside this repo and needs manual comparison. The installer prints a merge prompt, leaves the root config unchanged, and continues only after user confirmation.

Root config collisions are interactive because root config files are likely to contain personal settings:

- `~/.claude/settings.json`
- `~/.codex/config.toml`

Managed root config is only automatic when the target path is missing or already managed by this repo. The installer does not auto-merge config or silently replace non-root conflicts. Claude and Codex do not have identical layering behavior, and MCP/server settings can include machine-specific assumptions.

If any non-root harness target or global command target already exists and is not managed by this repo, install stops before changing files and prints an agent prompt. This keeps `managed` and `adopt` limited to clean installs instead of forcing the user to recover from backups.

## Agent Prompt Behavior

Generated agent prompts are intentionally conservative. The installer prints the relevant repo and local paths, but it does not claim to provide an exhaustive conflict summary. The prompt tells the agent to compute a complete comparison first, including recursive file lists for directories and parsed key/table/array comparisons for structured config where possible.

For install conflicts, the default stance is `adopt`: preserve local behavior and add harness behavior only when it is clearly non-conflicting. For sync conflicts, the default stance is to keep the repo baseline unless a local live change is clearly intentional and safe to promote.

## Happy Path

Run a preview first:

```sh
./scripts/install-symlinks.sh --dry-run
```

If the preview reports no collisions, run:

```sh
./scripts/install-symlinks.sh
```

If a collision is reported, choose:

- `adopt` when the existing local root config should remain the active source for now.
- `agent prompt` when the repo config and local config need manual comparison before any merge.

For non-root conflicts, resolve or move the local path first, then rerun the installer.

## Backups

Config collision handling avoids replacement instead of depending on backups. The installer still backs up unrelated shell/global-command files when those helper installers intentionally edit or replace them. Those backups are written under:

```text
~/.harness-configs-backups/<timestamp>/
```

If a backup path already exists, the installer adds a numeric suffix instead of overwriting the older backup.

## Noninteractive Runs

If stdin is not interactive and a config collision exists, the installer exits before making unrelated changes. Use `--dry-run` to inspect the collision, then run the installer interactively or move the config aside yourself.

## Sync Workflow

`scripts/sync-from-home.sh` reviews live home config and lets you selectively copy changes back into this repo. For each changed item, it shows a diff and asks whether to keep the repo version, overwrite the repo from home, or print an agent merge prompt.

This workflow does not require every path to be a symlink. It reviews the listed home paths and prompts before copying changed content into the repo. For root config files, sync is conservative: adopted root configs are user-owned, so sync skips these files by default:

- `~/.claude/settings.json`
- `~/.codex/config.toml`

Use `--include-root-config` only when you intentionally want to review and promote those user-owned root config files into the repo baseline:

```sh
./scripts/sync-from-home.sh --include-root-config
```

`HARNESS_CONFIG_REPO_ROOT` is available for tests that need to point sync at a temporary repo fixture. Do not set it during normal use.

Still inspect the final repo diff before committing.

## Validation

Run the collision regression tests:

```sh
./scripts/test-install-collisions.sh
```

The test uses temporary `HOME` directories only. It covers fresh installs, dry-run collisions, noninteractive blocking, interactive choices, aborts, backup uniqueness, malformed config reporting, idempotency, and sync guards.
