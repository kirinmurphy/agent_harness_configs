# Per-Repo Skill Installer

> **Status: IMPLEMENTED** (revised from this plan). Shipped as the `roborepo skill link`
> subcommand (Node, `scripts/roborepo.mjs` + shared `scripts/cli/skill-lib.mjs::linkLocalSkills`),
> chosen Node-over-bash for cross-platform reach incl. Windows. **Scope was corrected during
> implementation:** the tool is *purely in-repo* — it symlinks the client repo's own
> `.agents/skills/<name>` into that repo's `.claude/skills` + `.codex/skills` and does NOT touch
> the global `~/.claude`/`~/.codex` (this plan's original "symlink into `~/.claude/skills`"
> wording was the wrong scope). Source convention is `.agents/skills/` in the client repo — the
> dir Codex scans for project skills, doubling as the canonical source. The bash skeleton below
> is historical context only.

## Problem

Global shared skills live in `harness_configs/agents/skills/`. Claude reaches them through
per-skill links in `~/.claude/skills/`; Codex reaches them through the whole-dir
`~/.agents/skills -> agents/skills` link. App-specific skills (deploy flows,
domain-specific agents) need the same local dual-harness treatment but should live in the app
repo, not the global harness.

## Convention

App skills live at `.agents/skills/<skill-name>/` inside the app repo.

- `.agents/skills/` is the canonical source because Codex scans it for project skills
- `roborepo skill link` creates per-harness links into `.claude/skills` and `.codex/skills`
- Prefix skill names with the app name (e.g., `myapp-deploy`) to avoid collisions with global skills

## Command: `roborepo skill link`

Run from any app repo. Detects `$PWD/.agents/skills/`, then symlinks each skill into that
repo's `.claude/skills/` and `.codex/skills/`. It never touches global `~/.claude`,
`~/.codex`, or `~/.agents`.

```
roborepo skill link [--dry-run] [--uninstall]
```

### Behavior

- Iterates subdirectories of `.agents/skills/`
- For each skill, creates relative symlinks in `.claude/skills/` and `.codex/skills/`
- **Conflict**: if target exists and points elsewhere, prints a warning and skips — does not abort
- **`--dry-run`**: prints what would happen, makes no changes
- **`--uninstall`**: removes symlinks only if they point back to the current app (ownership check)

### Conflict Handling

Per-skill, non-fatal. Matches the `link_item_clean` pattern in `scripts/install-lib.sh` — warn loudly, leave existing intact, let the user resolve manually.

## Files to Create/Modify

| File | Change |
|------|--------|
| `scripts/roborepo.mjs` | Dispatches `roborepo skill link` |
| `scripts/cli/skills.mjs` | Implements user-facing skill commands |
| `scripts/cli/skill-lib.mjs` | Implements `linkLocalSkills` |
| `scripts/test-roborepo.sh` | Covers link, prune, uninstall, dry-run, conflict behavior |

## Historical Script Skeleton

```bash
#!/usr/bin/env bash
set -euo pipefail

app_root="$(pwd)"
skills_src="${app_root}/.agents/skills"
dry_run=0
uninstall=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)   dry_run=1 ;;
    --uninstall) uninstall=1 ;;
    *) echo "usage: $0 [--dry-run] [--uninstall]" >&2; exit 2 ;;
  esac
  shift
done

if [[ ! -d "${skills_src}" ]]; then
  echo "no skills found at ${skills_src}" >&2
  echo "create .agents/skills/<skill-name>/ in this repo first." >&2
  exit 1
fi

harness_dirs=("${app_root}/.claude/skills" "${app_root}/.codex/skills")

for skill_path in "${skills_src}"/*/; do
  [[ -d "${skill_path}" ]] || continue
  skill_name="$(basename "${skill_path}")"
  skill_abs="${skill_path%/}"

  for harness_skills_dir in "${harness_dirs[@]}"; do
    target="${harness_skills_dir}/${skill_name}"

    if [[ $uninstall -eq 1 ]]; then
      if [[ -L "${target}" && "$(readlink "${target}")" == "${skill_abs}" ]]; then
        [[ $dry_run -eq 0 ]] && rm "${target}"
        echo "unlink: ${target}"
      else
        echo "skip (not owned): ${target}"
      fi
      continue
    fi

    if [[ -e "${target}" || -L "${target}" ]]; then
      current="$(readlink "${target}" 2>/dev/null || true)"
      if [[ "${current}" == "${skill_abs}" ]]; then
        echo "ok (exists): ${target}"; continue
      fi
      echo "conflict: ${target} -> ${current}"
      echo "  wanted:  ${skill_abs}"
      echo "  rename skill or resolve manually."
      continue
    fi

    [[ $dry_run -eq 0 ]] && mkdir -p "${harness_skills_dir}" && ln -s "${skill_abs}" "${target}"
    echo "link: ${target} -> ${skill_abs}"
  done
done
```

## Verification

1. Create `.agents/skills/test-skill/` with a dummy `SKILL.md` in any test repo.
2. `roborepo skill link --dry-run` — confirm expected output, no changes.
3. `roborepo skill link` — confirm symlinks in `.claude/skills/` and `.codex/skills/`.
4. `roborepo skill link --uninstall` — confirm symlinks removed.
5. `roborepo update --dry-run` — confirm global command wiring remains healthy.
6. `which roborepo` resolves correctly.
