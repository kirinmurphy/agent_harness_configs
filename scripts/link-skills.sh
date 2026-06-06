#!/usr/bin/env bash
set -euo pipefail

# Two-layer skill linking for this repo.
#
# SHARED layer (advisory, global + exportable):
#   agents/skills/<name>  ->  claude/skills/<name>   (../../agents/skills/<name>)
#   agents/skills/ is the canonical shared source. claude/skills is symlinked into
#   ~/.claude/skills by roborepo-install.sh (Claude reads ~/.claude/skills). Codex has NO
#   per-skill intermediate dir: Codex reads ~/.agents/skills, which roborepo-install.sh
#   points straight at agents/skills/ (Codex scans .agents/skills exclusively — there is no
#   .codex/skills fallback). The export tool reads agents/skills/ directly.
#
# INTERNAL layer (repo-only firewall, NEVER global, NEVER exported):
#   skills-local/<name>  ->  .claude/skills/<name>, .codex/skills/<name>, .agents/skills/<name>
#                            (../../skills-local/<name>)
#   The repo dotdirs are project-scope only; Claude Code auto-loads <repo>/.claude/skills/
#   and Codex scans <repo>/.agents/skills/ when an agent works inside harness_configs. The
#   .codex/skills copy is kept as a transitional cross-compat link. These are not symlinked
#   to global and have no path into the export tool — the separation is structural.
#
# Idempotent: creates what's missing, prunes symlinks whose source is gone, leaves correct
# links untouched. Run after adding/removing a skill, or anytime to heal drift. Use --check
# to verify only (no changes), exit non-zero if out of sync.
#
# The source of truth for "what is a skill" is list_source_skills() in skill-lib.sh
# (folder with a SKILL.md, not itself a symlink). No hardcoded skill list here.
#
# Safety: prune only ever removes a SYMLINK whose target points back into the layer's source
# (../../agents/skills/<name> or ../../skills-local/<name>). It never touches real files or
# directories (e.g. agents/skills/.system/ Codex system skills, or .claude/settings.local.json).

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

# shellcheck source=scripts/skill-lib.sh
source "${repo_root}/scripts/skill-lib.sh"

check_only=0
quiet=0
# --check  : verify only, no changes, non-zero exit if out of sync
# --quiet  : suppress per-link "+ linked" / "- pruned" lines; keep errors + the summary
for arg in "$@"; do
  case "${arg}" in
    --check) check_only=1 ;;
    --quiet|-q) quiet=1 ;;
    *) echo "usage: $0 [--check] [--quiet|-q]" >&2; exit 2 ;;
  esac
done

created=0
missing=0
pruned=0
orphans=0
total=0

# link_layer <src_dir> <expected_prefix> <harness_dir_1> [<harness_dir_2> ...]
#   src_dir        : where skill sources live (relative to repo root), e.g. "skills"
#   expected_prefix: the symlink target prefix, e.g. "../../skills"
#   harness_dir_*  : per-harness skills dirs to populate, e.g. "claude/skills" ".claude/skills"
link_layer() {
  local src_dir="$1"; shift
  local expected_prefix="$1"; shift
  local harness_dirs=("$@")

  local name link expected
  while IFS= read -r name; do
    [[ -n "${name}" ]] || continue
    total=$((total + 1))

    for hdir in "${harness_dirs[@]}"; do
      link="${hdir}/${name}"
      expected="${expected_prefix}/${name}"

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

      mkdir -p "${hdir}"
      ln -sfn "${expected}" "${link}"
      [[ "${quiet}" -eq 0 ]] && echo "  + linked ${link}"
      created=$((created + 1))
    done
  done < <(list_source_skills "${src_dir}")
}

# prune_layer <src_dir> <expected_prefix> <harness_dir_1> [<harness_dir_2> ...]
#   Removes per-harness skill symlinks of this layer whose <src_dir>/<name> source is gone.
prune_layer() {
  local src_dir="$1"; shift
  local expected_prefix="$1"; shift
  local harness_dirs=("$@")

  local hdir link target name
  for hdir in "${harness_dirs[@]}"; do
    [[ -d "${hdir}" ]] || continue

    for link in "${hdir}"/*; do
      [[ -L "${link}" ]] || continue  # only symlinks; never real files/dirs

      target="$(readlink "${link}")"
      case "${target}" in
        "${expected_prefix}/"*) ;;     # a link this layer manages
        *) continue ;;                 # points elsewhere — not ours, leave it
      esac

      name="$(basename "${link}")"
      [[ -f "${src_dir}/${name}/SKILL.md" ]] && continue  # source still exists — keep

      if [[ ${check_only} -eq 1 ]]; then
        echo "orphan: ${link} -> ${target} (no source)"
        orphans=$((orphans + 1))
        continue
      fi

      rm "${link}"
      [[ "${quiet}" -eq 0 ]] && echo "  - pruned ${link} (source gone)"
      pruned=$((pruned + 1))
    done
  done
}

# SHARED layer — Claude only (Codex reads ~/.agents/skills -> agents/skills directly).
link_layer  "agents/skills" "../../agents/skills" "claude/skills"
prune_layer "agents/skills" "../../agents/skills" "claude/skills"

# INTERNAL layer (repo-only): Claude project dir, plus Codex via both .agents (canonical)
# and .codex (transitional cross-compat).
link_layer  "skills-local" "../../skills-local" ".claude/skills" ".agents/skills" ".codex/skills"
prune_layer "skills-local" "../../skills-local" ".claude/skills" ".agents/skills" ".codex/skills"

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
