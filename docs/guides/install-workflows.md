# Install Workflows

## Purpose

This repo installs downloaded harness defaults next to user-curated Claude and Codex config. The mental model has two top-level choices: manage config from this repo, or adopt repo defaults into user-owned global config. No install workflow should delete existing user config.

## Workflow Summary

| Workflow | What it means | What lives where |
| --- | --- | --- |
| `managed` | Read-mostly logic stays in this repo and global paths observe it through symlinks. Mutable root config is exported as a local file. | Skills, hooks, commands, rules, and managed marker files are symlinked. Root config is copied/merged into `~/.claude/settings.json` and `~/.codex/config.toml`. |
| `adopt` | Repo defaults are copied into user-owned global config paths instead of symlinked. Existing files are overwritten, kept, or staged for agent merge by explicit choice. | User-owned config remains the long-term place where local choices live. |

`overwrite`, `keep originals`, and `agent prompt` are conflict policies, not install modes. They appear only when a target path already exists and is not already in the desired state.

Conflict policies:

| Policy | Active after install | Preserved files |
| --- | --- | --- |
| `overwrite` | Repo version becomes active. | Existing local files move beside the original path as `*_original_TIMESTAMP`. |
| `keep originals` | Existing local version remains active. | Repo candidates are staged beside the original path as `*_update_TIMESTAMP`. Missing files are still installed normally. |
| `agent prompt` | Existing local version remains active until an agent/user merge happens. | Repo candidates are staged as `*_update_TIMESTAMP`; installer prints merge instructions. |

Root config means:

- `~/.claude/settings.json`
- `~/.codex/config.toml`

Non-root harness targets include skills, hooks, commands, rules, managed marker files, and global command links. File and directory targets use the same conflict policies when they already exist. Global command conflicts still stop before changing files.

## Permission Profile Selection

Permission profiles are rendered from `manifests/inventory/agent-permissions.json` before install or update:

```sh
./scripts/install/main.sh --permissions interactive
roborepo update --permissions interactive
```

Profiles are a render-time choice for this repo's generated harness defaults:

| Profile | Effect |
| --- | --- |
| `readonly` | Claude gets read-oriented permissions; Codex gets `read-only` sandbox defaults. |
| `interactive` | Claude gets read/write/edit permissions and allowed local commands; Codex gets workspace-write with prompts for sandbox escapes. |
| `workspace` | Same local workspace posture, with Codex approval prompts disabled for blocked actions. |
| `networked` | Workspace-write plus Codex sandbox network access. |

The renderer updates:

- `globals/claude/settings.json` permissions
- `globals/codex/config.toml` generated permission block
- `globals/codex/rules/default.rules`

These are global harness defaults. The installer does not keep a separate permission profile
registry per consumer repo. For a different posture on one machine or project, render/install that
profile for that run, or use the agent harness's one-off launch flags when starting a session.

## `managed`

`managed` gives the simplest update path for read-mostly harness assets. The downloaded repo code is the source of truth for skills, hooks, commands, rules, generated guidance, and helper links. Those home paths point to the repo through symlinks, so repo updates become active immediately after pull or edit.

Mutable root config is the explicit exception:

- `~/.claude/settings.json`
- `~/.codex/config.toml`

Those files are active local files, not symlinks. If missing, the installer copies the repo baseline into place. If already symlinked to the repo from an older install, the installer converts the symlink to a local copy. If a user-owned file exists, the installer applies the selected conflict policy.

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
- Sync from home skips user-owned root config by default. Use `--include-root-config` only when intentionally promoting local root config into the repo baseline.

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
