# Manifest & Symlink Model

How roborepo gets its version-controlled config from the repo into a user's harness homes
(`~/.claude`, `~/.codex`, `~/.agents`), and how every script agrees on what is managed.

## The one-sentence version

The repo holds the real files under `globals/`; the install scripts create **symlinks** in
your home harness dirs that point back at them; and a single data file —
`manifests/manifest.tsv` — is the **one list** every script reads to know what to link, verify,
or clean up.

## Glossary

Grouped by the kind of thing each term names.

### Places (where config lives)

| Term | Meaning |
| --- | --- |
| **harness** | An agent runtime that reads config from a home dir. Here: **Claude** (`~/.claude`) and **Codex** (`~/.codex` + `~/.agents`). |
| **globals/** | Repo dir holding the real, version-controlled config meant to go global. Subdirs: `claude/`, `codex/`, `agents/`, `rules/`. |
| **harness home** | The per-harness config dir in `$HOME`: `~/.claude`, `~/.codex`, `~/.agents`. |

### Data files (the lists, and who reads them)

| Term | Meaning |
| --- | --- |
| **manifest** | `manifests/manifest.tsv` — the single list of managed home↔repo paths. An inventory: *these things are managed, and how.* |
| **source-files list** | `manifests/source-files.tsv` — separate checklist of repo files that must exist (asserted by doctor). Tracks repo health, not home symlinks. |
| **Bash reader** | `scripts/lib/manifests-data.sh` — bash funcs (`manifest_rows`, `source_files`) that parse the data files so POSIX scripts do not hardcode the list. |
| **PowerShell reader** | `scripts/install/install-windows.ps1` — parses `manifests/manifest.tsv` directly for Windows installs. |
| **consumer** | A script that reads the manifest: `main.sh`, `install-claude.sh`, `install-codex.sh`, `install-windows.ps1`, `verify-install.sh`, `doctor.sh`, `sync-from-home.sh`. |

### Manifest row vocabulary (what a row says)

| Term | Meaning |
| --- | --- |
| **row kind** | What a row *does*: `link`, `root_config`, or `cleanup`. |
| **`link`** | Clean symlink: `~/.harness/<sub>` → `repo/globals/...`. Repo is source of truth. |
| **`root_config`** | Mutable user state (`settings.json`, `config.toml`). **Copied**, not linked; left in place on collision ("adopt"). User owns it. |
| **`cleanup`** | A path roborepo *used* to manage. Install **prunes** the old repo-symlink there; never re-created. `src_rel` is `-`. |
| **flag `nodoctor`** | Row is checked by `verify-install.sh` but intentionally **not** by `doctor --installed`. |
| **flag `nosync`** | Row is skipped by `sync-from-home.sh` (e.g. skills — maintained in-repo and symlinked outward, never pulled back). |

### Behaviors (verbs the installer performs)

| Term | Meaning |
| --- | --- |
| **adopt** | "Keep the local file, don't overwrite." Triggered on a `root_config` collision, or pre-declared via `HARNESS_ADOPT_<HARNESS>_CONFIG=1` for unattended runs. |
| **prune** | Remove a retired repo-symlink from a home path (the action a `cleanup` row drives), backing it up first. |

## How a managed file flows from repo to home

The example below uses one Claude file (`CLAUDE.md`), but the flow is identical for **every
`link` row of every harness** — `~/.codex/AGENTS.md`, `~/.agents/skills`, etc. all work the
same way: real file in `globals/`, symlink in the home dir, agent reads the symlink.

```mermaid
flowchart LR
  subgraph repo["repo: globals/"]
    src["globals/claude/CLAUDE.md<br/>(real file)"]
  end
  subgraph manifest["manifests/manifest.tsv"]
    row["row: claude | link |<br/>globals/claude/CLAUDE.md |<br/>CLAUDE.md | claude"]
  end
  subgraph home["harness home"]
    link["~/.claude/CLAUDE.md<br/>(symlink)"]
  end
  claude["Claude reads<br/>~/.claude/CLAUDE.md"]

  row -- "tells installer what to link" --> link
  link -- "symlink target" --> src
  claude --> link
```

The agent reads its home dir; the home dir is a symlink; the symlink resolves to the real
repo file. Edit the repo file → every harness sees the change with no re-copy.

## One manifest, many consumers

Before this model, the same home↔repo list was hand-copied across 7+ scripts. Change one,
forget another, and they drift. Now they all read one file:

```mermaid
flowchart TD
  tsv["manifests/manifest.tsv<br/>(single source of truth)"]
  reader["scripts/lib/manifests-data.sh<br/>manifest_rows()"]
  tsv --> reader

  reader --> main["install/main.sh<br/>preflight"]
  reader --> ic["install-claude.sh<br/>link + adopt + cleanup"]
  reader --> icx["install-codex.sh<br/>link + adopt + cleanup"]
  reader --> verify["verify-install.sh<br/>check links exist"]
  reader --> doctor["doctor.sh --installed<br/>check links + guard"]
  reader --> sync["sync-from-home.sh<br/>(reverse: home → repo)"]
  tsv --> win["install-windows.ps1<br/>PowerShell reader"]

  doctor --> guard["check_manifest_sources:<br/>every src_rel must exist"]
```

`check_manifest_sources` (in doctor) is the **drift guard**: if a row names a repo file that
was renamed or deleted, doctor fails loudly instead of the installer silently skipping it.

The PowerShell installer does not source the bash reader. It parses the same TSV file itself,
then applies the same row kinds: `link`, `root_config`, and `cleanup`. That keeps Windows off
the old hand-copied path list without making PowerShell depend on a POSIX shell.

## Row kind → behavior

```mermaid
flowchart TD
  row["manifest row"]
  row --> k{"kind?"}
  k -->|link| L["symlink home → repo<br/>(repo is truth)"]
  k -->|root_config| R["copy to home,<br/>adopt-on-collision<br/>(user owns it)"]
  k -->|cleanup| C["prune stale repo-symlink<br/>at home (never re-create)"]

  L --> f{"flag?"}
  f -->|nodoctor| nd["verify checks it,<br/>doctor skips"]
  f -->|nosync| ns["sync-from-home skips it<br/>(e.g. skills)"]
  f -->|none| nn["checked / synced everywhere"]
```

## The skills layout

roborepo manages Codex's shared skills at `~/.agents/skills` (the modern open "Agent Skills"
path). It does **not** manage `~/.codex/skills` — that legacy path is left to Codex's own
tooling (see below).

```mermaid
flowchart LR
  agsrc["repo: globals/agents/skills<br/>(real shared skills)"]
  agents["~/.agents/skills<br/>(roborepo-managed)"]
  codexsk["~/.codex/skills<br/>(NOT managed:<br/>Codex's own writable dir)"]
  claudesk["~/.claude/skills/&lt;name&gt;<br/>(per-skill links)"]

  agents -- symlink --> agsrc
  claudesk -- per-skill symlink --> agsrc

  codexreads["Codex discovers shared skills"] --> agents
  claudereads["Claude discovers shared skills"] --> claudesk
  nativetool["Codex skill-installer<br/>(.system helper)"] -- "writes ad-hoc installs" --> codexsk
```

### Why `~/.codex/skills` is not managed (legacy-decoupling)

OpenAI is mid-migration and is internally inconsistent about the skills path:

- The **modern standard** is `~/.agents/skills` (open "Agent Skills"). roborepo targets this,
  and Codex discovers shared skills there.
- But Codex's **own bundled `.system` helper** `skill-installer` still hardcodes the **legacy**
  `$CODEX_HOME/skills` (= `~/.codex/skills`): `list-skills.py` reads it, and
  `install-skill-from-github.py` writes downloaded skills into it. That helper has not caught
  up to the new path.

These two tools do different jobs and are complementary:

| roborepo (this repo) | Codex `skill-installer` (.system helper) |
| --- | --- |
| Curated, version-controlled, shared-across-machines skill set | Ad-hoc, per-user, fetched on demand |
| Serves only what is committed to `globals/agents/skills/` | Downloads arbitrary skills from `openai/skills` or any GitHub repo |
| Targets the modern `~/.agents/skills` | Writes to the legacy `~/.codex/skills` |

**The bug we removed:** the installer used to symlink `~/.codex/skills` → the repo's
read-only `globals/agents/skills`. If the native helper ever ran, its downloaded skills would
land **inside the version-controlled repo**, mixing personal installs into the shared set.

**Resolution (implemented):** roborepo commits to the modern path and fully decouples from the
legacy one.
- `~/.agents/skills` → repo shared skills (managed `link`).
- `~/.codex/skills` → left as a plain local dir Codex's helper owns; any old repo-symlink
  there is pruned via a `cleanup` row so installs never reach the repo.

When OpenAI updates `skill-installer` to the `.agents/skills` standard, the two converge with
no change needed here.

> Note on "exclusively": prior code comments claimed Codex scans `~/.agents/skills`
> *exclusively*. That came from in-repo comments, not verified Codex docs. The decoupling above
> does not depend on it — even if Codex also reads `~/.codex/skills`, keeping it unmanaged is
> correct, because that dir is exactly where the native helper expects to own its installs.

## Related

- `docs/architecture/config-code-separation.md` — simple breakdown of what belongs in
  config versus code, plus remaining extraction candidates.
- `docs/plans/sync-from-home-manifest.md` — history of the `sync-from-home.sh` manifest
  migration (now done), the `blocklist.json` decision it resolved, and the FD-3 interactive
  prompt gotcha.
- `docs/reference/services/architecture.md` — broader repo/install architecture.
