#!/usr/bin/env bash
set -euo pipefail

# Ensure every shared skill in ./skills/ has its per-harness symlink in
# claude/skills/ and codex/skills/, and that no orphaned skill symlinks remain.
# Idempotent: creates what's missing, prunes symlinks whose source is gone, and
# leaves correct links untouched. Run after adding/removing a skill, or anytime to
# heal drift. Use --check to verify only (no changes), exit non-zero if out of sync.
#
# The source of truth is the set of folders in ./skills/ that contain a SKILL.md.
# There is no hardcoded skill list here — add or remove a skill folder, run this, done.
#
# Safety: prune only ever removes a SYMLINK whose target (../../skills/<name>) no
# longer resolves. It never touches real files or directories (e.g. Codex's
# .system/ skills), because those are not symlinks into ./skills/.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

check_only=0
case "${1:-}" in
  --check) check_only=1 ;;
  "") ;;
  *) echo "usage: $0 [--check]" >&2; exit 2 ;;
esac

harnesses=(claude codex)
created=0
missing=0
pruned=0
orphans=0
total=0

for skill_dir in skills/*/; do
  name="$(basename "${skill_dir}")"

  # Only real shared skills (must have a SKILL.md). Skip stray files/dirs.
  [[ -f "skills/${name}/SKILL.md" ]] || continue

  total=$((total + 1))

  for harness in "${harnesses[@]}"; do
    link="${harness}/skills/${name}"
    expected="../../skills/${name}"

    if [[ -L "${link}" && "$(readlink "${link}")" == "${expected}" ]]; then
      continue
    fi

    if [[ -e "${link}" && ! -L "${link}" ]]; then
      echo "fail: ${link} exists and is not a symlink — refusing to touch" >&2
      missing=$((missing + 1))
      continue
    fi

    if [[ ${check_only} -eq 1 ]]; then
      echo "missing: ${link} -> ${expected}"
      missing=$((missing + 1))
      continue
    fi

    mkdir -p "${harness}/skills"
    ln -sfn "${expected}" "${link}"
    echo "  + linked ${link}"
    created=$((created + 1))
  done
done

# Prune pass: remove per-harness skill symlinks whose ./skills/<name> source is gone.
for harness in "${harnesses[@]}"; do
  skills_dir="${harness}/skills"
  [[ -d "${skills_dir}" ]] || continue

  for link in "${skills_dir}"/*; do
    [[ -L "${link}" ]] || continue  # only symlinks; never real files/dirs

    target="$(readlink "${link}")"
    case "${target}" in
      ../../skills/*) ;;            # a shared-skill link we manage
      *) continue ;;               # points elsewhere — not ours, leave it
    esac

    name="$(basename "${link}")"
    [[ -f "skills/${name}/SKILL.md" ]] && continue  # source still exists — keep

    if [[ ${check_only} -eq 1 ]]; then
      echo "orphan: ${link} -> ${target} (no source)"
      orphans=$((orphans + 1))
      continue
    fi

    rm "${link}"
    echo "  - pruned ${link} (source gone)"
    pruned=$((pruned + 1))
  done
done

if [[ ${check_only} -eq 1 ]]; then
  if [[ ${missing} -gt 0 || ${orphans} -gt 0 ]]; then
    echo "${total} skills checked, ${missing} missing, ${orphans} orphaned link(s)" >&2
    exit 1
  fi
  echo "${total} skills checked, all per-harness links present, no orphans"
  exit 0
fi

echo "${total} skills, ${created} link(s) created, ${pruned} pruned"
[[ ${missing} -gt 0 ]] && exit 1
exit 0
