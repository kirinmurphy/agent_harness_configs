# Per-Repo Skill Installer

> **Status: IMPLEMENTED** (revised from this plan). Shipped as the `roborepo skill link`
> subcommand (Node, `scripts/roborepo.mjs` + shared `scripts/skill-lib.mjs::linkLocalSkills`),
> chosen Node-over-bash for cross-platform reach incl. Windows. **Scope was corrected during
> implementation:** the tool is *purely in-repo* — it symlinks the client repo's own
> `.agents/skills/<name>` into that repo's `.claude/skills` + `.codex/skills` and does NOT touch
> the global `~/.claude`/`~/.codex` (this plan's original "symlink into `~/.claude/skills`"
> wording was the wrong scope). Source convention is `.agents/skills/` in the client repo — the
> dir Codex scans for project skills, doubling as the canonical source. The bash skeleton below
> is historical context only.

## Problem

Global skills in `harness_configs/skills/` are symlinked into both `~/.claude/skills/` and `~/.codex/skills/`. App-specific skills (deploy flows, domain-specific agents) need the same dual-harness treatment but should live in the app repo, not the global harness.

## Convention

App skills live at `.claude/skills/<skill-name>/` inside the app repo.

- `.claude/` is the natural per-project config home for Claude Code
- Codex skills use the same format — one source directory, two symlink targets
- Prefix skill names with the app name (e.g., `myapp-deploy`) to avoid collisions with global skills

## Script: `bin/harness-install-local-skills`

Run from any app repo. Detects `$PWD/.claude/skills/`, symlinks each skill into `~/.claude/skills/` and `~/.codex/skills/` (whichever harnesses exist).

```
harness-install-local-skills [--dry-run] [--uninstall]
```

### Behavior

- Detects which harnesses are present (`~/.claude`, `~/.codex`, or both)
- Iterates subdirectories of `.claude/skills/`
- For each skill, creates an absolute symlink in each harness skills dir
- **Conflict**: if target exists and points elsewhere, prints a warning and skips — does not abort
- **`--dry-run`**: prints what would happen, makes no changes
- **`--uninstall`**: removes symlinks only if they point back to the current app (ownership check)

### Conflict Handling

Per-skill, non-fatal. Matches the `link_item_clean` pattern in `scripts/install-lib.sh` — warn loudly, leave existing intact, let the user resolve manually.

## Files to Create/Modify

| File | Change |
|------|--------|
| `bin/harness-install-local-skills` | New script |
| `scripts/install-global-commands.sh` | Add `link_command "harness-install-local-skills"` alongside existing four |
| `scripts/doctor.sh` | Add `check_file "bin/harness-install-local-skills"` and `check_link` for `~/.local/bin/harness-install-local-skills` |
| `scripts/verify-install.sh` | Add `check_link "bin/harness-install-local-skills" "${HOME}/.local/bin/harness-install-local-skills"` |

## Script Skeleton

```bash
#!/usr/bin/env bash
set -euo pipefail

app_root="$(pwd)"
skills_src="${app_root}/.claude/skills"
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
  echo "create .claude/skills/<skill-name>/ in this repo first." >&2
  exit 1
fi

harness_dirs=()
[[ -d "${HOME}/.claude" ]] && harness_dirs+=("${HOME}/.claude/skills")
[[ -d "${HOME}/.codex"  ]] && harness_dirs+=("${HOME}/.codex/skills")

if [[ ${#harness_dirs[@]} -eq 0 ]]; then
  echo "error: neither ~/.claude nor ~/.codex found." >&2; exit 1
fi

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

    [[ $dry_run -eq 0 ]] && ln -s "${skill_abs}" "${target}"
    echo "link: ${target} -> ${skill_abs}"
  done
done
```

## Verification

1. Create `.claude/skills/test-skill/` with a dummy `SKILL.md` in any test repo
2. `harness-install-local-skills --dry-run` — confirm expected output, no changes
3. `harness-install-local-skills` — confirm symlinks in `~/.claude/skills/` and `~/.codex/skills/`
4. `harness-install-local-skills --uninstall` — confirm symlinks removed
5. Re-run `scripts/install-symlinks.sh` to wire script into `~/.local/bin`
6. `which harness-install-local-skills` resolves correctly
