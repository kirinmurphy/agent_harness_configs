# Install Workflows

## Purpose

This repo installs downloaded harness defaults next to user-curated Claude and Codex config. The mental model has two top-level choices: manage config from this repo, or adopt repo defaults into user-owned global config. No install workflow should delete existing user config.

## Workflow Summary

| Workflow | What it means | What lives where |
| --- | --- | --- |
| `managed` | Read-mostly logic stays in this repo and global paths observe it through symlinks. Mutable root config is exported as a local file. | Skills, hooks, commands, rules, and managed marker files are symlinked. Root config is copied/merged into `~/.claude/settings.json` and `~/.codex/config.toml`. |
| `adopt` | Existing user-owned root config remains active and repo defaults are copied, staged, or merged only by explicit choice. | User-owned config remains the long-term place where local choices live. |

`agent prompt` is a sub-option of `adopt`, not a separate ownership mode. It means "help me adopt by giving an agent the comparison and merge instructions."

Adopt sub-options under discussion:

| Adopt sub-option | Active after install | Preserved files |
| --- | --- | --- |
| replace existing files | Repo version becomes active. | Existing local files move to an archive folder with timestamped names. |
| keep existing files | Local version remains active. | Repo candidates move to a not-adopted/staging folder. |
| use agent prompt | Local version remains active until an agent/user merge happens. | Both sides stay available for comparison; installer prints merge instructions. |

Root config means:

- `~/.claude/settings.json`
- `~/.codex/config.toml`

Non-root harness targets include skills, hooks, commands, rules, managed marker files, and global command links. If those paths already exist and are not managed by this repo, install stops before changing files.

## `managed`

`managed` gives the simplest update path for read-mostly harness assets. The downloaded repo code is the source of truth for skills, hooks, commands, rules, generated guidance, and helper links. Those home paths point to the repo through symlinks, so repo updates become active immediately after pull or edit.

Mutable root config is the explicit exception:

- `~/.claude/settings.json`
- `~/.codex/config.toml`

Those files are active local files, not symlinks. If missing, the installer copies the repo baseline into place. If already symlinked to the repo from an older install, the installer converts the symlink to a local copy. If a user-owned file exists, the installer asks whether to keep it or print an agent merge prompt.

Best when:

- new machine has no existing Claude/Codex config
- user wants this repo to own global defaults
- local edits should be version-controlled here

Tradeoffs:

- direct edits under `~/.claude` or `~/.codex` may edit repo files through symlinks for read-mostly assets
- root config updates do not automatically track repo baseline changes; they need explicit merge/adoption
- tool-generated changes need review with `scripts/sync-from-home.sh` or normal git diff

User responsibility:

- inspect repo diffs before commit
- keep machine-specific secrets and local state out of tracked config
- merge root config intentionally when the repo baseline changes

## `adopt`

`adopt` keeps user-owned global config as the long-term home for local choices. Repo defaults are copied, staged, or merged into that local config instead of making the global config a symlink to this repo.

Best when:

- user already has curated MCP servers, model settings, hooks, permissions, projects, or profiles
- root config includes machine-specific assumptions
- user wants repo defaults available without handing over global config ownership

Tradeoffs:

- repo defaults do not stay live through symlinks
- future repo changes must be adopted again or handled by a separate update workflow
- merge behavior must be explicit: replace/archive, keep/stage, or agent-assisted merge
- Claude and Codex may support different layering behavior, so adoption can produce harness-specific differences

User responsibility:

- review archived local files, staged repo candidates, or agent output
- copy only wanted settings into the active global config
- rerun `./scripts/install/main.sh --dry-run` or future update command to confirm expected state

## Known Gaps

- The installer can detect collisions, but it cannot prove semantic compatibility between two config files.
- Root config merge remains manual because MCP servers, profiles, project trust, hooks, and permissions can be user- or machine-specific.
- Non-root conflicts are not merged by the installer. Move, adopt outside the installer, or manually reconcile those paths before rerunning.
- Sync from home skips user-owned root config by default. Use `--include-root-config` only when intentionally promoting local root config into the repo baseline.
- Current implementation does not yet support the full adopt sub-option model. It preserves local root config and can print an agent prompt, but does not yet archive replaced files or stage not-adopted repo candidates.

## Next Step

Run a preview first:

```sh
./scripts/install/main.sh --dry-run
```

If preview is clean, run install:

```sh
./scripts/install/main.sh
```

For exact prompt behavior, noninteractive behavior, backups, sync, and regression tests, see [../reference/internal/config-collision-handling.md](../reference/internal/config-collision-handling.md).
