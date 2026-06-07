# How It Works

## Relationship

```mermaid
flowchart LR
  repo["harness_configs repo"]
  codexRepo["codex/"]
  claudeRepo["claude/"]
  codexHome["~/.codex"]
  claudeHome["~/.claude"]
  codexRuntime["Codex runtime state<br/>auth, logs, history, sqlite, cache, sessions"]
  claudeRuntime["Claude runtime state<br/>local settings, logs, history, cache, sessions, todos"]

  repo --> codexRepo
  repo --> claudeRepo

  codexRepo -. managed config symlinks .-> codexHome
  claudeRepo -. managed config symlinks .-> claudeHome

  codexRuntime --- codexHome
  claudeRuntime --- claudeHome

  codexRuntime -. ignored .-> gitignore[".gitignore"]
  claudeRuntime -. ignored .-> gitignore

  shellRepo["shell/"]
  zshrc["~/.zshrc"]
  repo --> shellRepo
  shellRepo -. sourced .-> zshrc
```

## Symlink Map

Most files are symlinked directly from the repo into the tool home directory. Root config files are conditional: `~/.claude/settings.json` and `~/.codex/config.toml` may be user-owned, so the installer asks before replacing them.

Codex (`~/.codex/` ← `codex/`, plus skills under `~/.agents/` ← `agents/`):

- `AGENTS.md`
- `config.toml` when managed
- `hooks.json`
- `MANAGED_BY_HARNESS_CONFIGS.md`
- `rules/`
- `skills/` — Codex scans `~/.agents/skills` **exclusively** (there is no `~/.codex/skills`
  fallback), so the canonical link is `~/.agents/skills → agents/skills`. `~/.codex/skills`
  is kept as a transitional cross-compat link to the same source.

Claude (`~/.claude/` ← `claude/`):

- `CLAUDE.md`
- `settings.json` when managed
- `MANAGED_BY_HARNESS_CONFIGS.md`
- `commands/`
- `hooks/`
- `skills/`

## Install Workflow Filesystem Shapes

Root config files have two possible ownership shapes today: managed from this repo, or adopted into user-owned global config. A future layered model is still open work.

### Managed

Repo file is the source of truth. The global harness path observes it through a symlink.

```text
harness_configs/
  codex/config.toml
  claude/settings.json
        ▲
        │ symlink target
        │
~/.codex/config.toml      -> harness_configs/codex/config.toml
~/.claude/settings.json   -> harness_configs/claude/settings.json
```

Implication: updates in this repo become active globally. User edits at the global path edit the repo file through the symlink.

### Adopt: replace existing files

Repo version becomes active in the global config location. Existing local files are preserved in an archive folder.

```text
~/.codex/
  config.toml                    # copied/adopted repo version, active
  archived/
    config_archived_<timestamp>.toml

~/.claude/
  settings.json                  # copied/adopted repo version, active
  archived/
    settings_archived_<timestamp>.json
```

Implication: user does not lose old config, but must merge wanted local settings back from `archived/`.

### Adopt: keep existing files

User-owned config remains active. Repo candidates are preserved in a staging folder for later merge.

```text
~/.codex/
  config.toml                    # existing local version, active
  not_adopted/
    config_repo_<timestamp>.toml

~/.claude/
  settings.json                  # existing local version, active
  not_adopted/
    settings_repo_<timestamp>.json
```

Implication: user keeps current behavior, but must merge wanted repo defaults from `not_adopted/`.

### Adopt: agent prompt

User-owned config remains active. The installer prints an agent prompt that points at both local and repo paths.

```text
harness_configs/codex/config.toml       # repo candidate
~/.codex/config.toml                    # existing local version, active

harness_configs/claude/settings.json    # repo candidate
~/.claude/settings.json                 # existing local version, active
```

Implication: no automatic merge. The agent/user compares both sides and applies intentional edits.

### Future layered model

Desired but not implemented:

```text
harness_configs baseline
        ↓ inherited by
user global config overlay
        ↓ refined by
local repo context
```

This needs either native harness include support or a generated/merged config pipeline. Track this in [../../plans/harness-parity-todo.md](../../plans/harness-parity-todo.md).

### Shared skills: canonical source + per-harness fan-out

The canonical shared source is `agents/skills/<name>/` (each a folder with a `SKILL.md`).
The two harnesses reach it differently because Codex and Claude scan different paths:

- **Codex** scans `~/.agents/skills` exclusively. So `roborepo-install.sh` links
  `~/.agents/skills → agents/skills` directly (plus a transitional `~/.codex/skills →
  agents/skills` for cross-compat). Codex needs **no** per-skill intermediate dir, and there
  is no longer a `codex/skills/` directory in the repo. Codex's own `.system/` skills
  (imagegen, openai-docs, skill-creator, …) are real files living at `agents/skills/.system/`,
  so they ride into `~/.agents/skills/.system` automatically.
- **Claude** scans `~/.claude/skills`. That is a folder symlink to the repo's `claude/skills/`,
  inside which each shared skill is an individual symlink `<name> -> ../../agents/skills/<name>`.
  The per-skill layer lets Claude carry the shared skills alongside any Claude-only ones.

A skill's source folder alone is therefore not enough for Claude; without the per-skill
symlinks Claude does not see it. `scripts/link-skills.sh` derives the Claude per-skill symlinks
from `agents/skills/` — it creates any missing links and prunes orphaned ones (symlinks whose
source is gone), and is idempotent. `scripts/doctor.sh` verifies the same set, also derived
from `agents/skills/`, so neither needs editing when a skill is added or removed.

### Two skill layers: shared vs. internal

There are two distinct, firewalled skill layers:

- **Shared** — `agents/skills/<name>/`, the canonical source. Linked into `claude/skills` (for
  Claude) and reached by Codex via `~/.agents/skills`; thus global on both harnesses, and
  exportable to other repos. Advisory coding skills any repo may receive.
- **Internal** — `skills-local/<name>/`, linked **only** into this repo's own project-scope
  dotdirs (`.claude/skills`, `.agents/skills`, `.codex/skills`) by a second pass of
  `link-skills.sh`. These describe how to develop/maintain this repo and are **never** global and
  **never** exported. The separation is structural: the export/installer tools read only
  `agents/skills/`, with no code path to `skills-local/`.

### Client utilities (same model, for other repos)

One Node command, `roborepo`, is the consumer front door (see the README for the full subcommand
list). For the dual-harness skill model it offers:

- `skill export`: bundles shared skills into a `.zip` and copies them into a target repo's
  `.agents/skills` plus harness-specific skill folders.
- `skill install`: treats the target repo's own `.agents/skills/<name>` as the canonical project
  skill source, then symlinks those skills into selected `.claude/skills` and/or `.codex/skills`
  folders. Existing `.claude` and `.codex` roots are used automatically; when run interactively and
  a root is missing, it asks whether to create/link that target. Noninteractive runs do not create
  new agent roots. `skill link` is a compatibility alias.

This is purely in-repo and never touches global `~/.claude`, `~/.codex`, or `~/.agents`.
`.agents/skills` is canonical because Codex scans that path directly; Claude and the transitional
Codex path are fan-out links from that source.

`roborepo` also folds in `mcp add`/`index`/`watch`/`run` and dispatches the lifecycle verbs
`update`/`sync`/`doctor`/`verify` to the existing bash scripts (the first install is the shell
bootstrap `roborepo-install.sh`, so there is no root-level `install` verb). Shared skill logic lives
in `scripts/cli/skill-lib.mjs`.

## Sync Flow

```mermaid
sequenceDiagram
  participant Home as ~/.codex and ~/.claude
  participant Repo as harness_configs repo
  participant Backup as ~/.harness-configs-backups

  Home->>Repo: ./scripts/sync-from-home.sh reviews diffs before copying selected live config
  Repo->>Home: ./scripts/roborepo-install.sh installs repo-owned config
  Home-->>Home: user-owned config collisions are preserved for adopt/agent merge
  Repo-->>Home: symlinks created for tracked or managed config
  Home-->>Home: runtime files remain local and ignored
```
