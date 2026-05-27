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

  codexRepo -. symlinked config .-> codexHome
  claudeRepo -. symlinked config .-> claudeHome

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

Codex (`~/.codex/` ← `codex/`):

- `AGENTS.md`
- `config.toml`
- `hooks.json`
- `MANAGED_BY_HARNESS_CONFIGS.md`
- `rules/`
- `skills/`

Claude (`~/.claude/` ← `claude/`):

- `CLAUDE.md`
- `settings.json`
- `MANAGED_BY_HARNESS_CONFIGS.md`
- `commands/`
- `hooks/`
- `skills/`

## Sync Flow

```mermaid
sequenceDiagram
  participant Home as ~/.codex and ~/.claude
  participant Repo as harness_configs repo
  participant Backup as ~/.harness-configs-backups

  Home->>Repo: ./scripts/sync-from-home.sh copies selected live config
  Repo->>Home: ./scripts/install-symlinks.sh installs repo-owned config
  Home->>Backup: existing paths moved before replacement
  Repo-->>Home: symlinks created for tracked config
  Home-->>Home: runtime files remain local and ignored
```
