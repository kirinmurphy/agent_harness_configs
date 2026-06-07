#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
zshrc="${HOME}/.zshrc"
backup_root="${ROBOREPO_BACKUP_ROOT:-${HOME}/.roborepo-backups/$(date +%Y%m%d-%H%M%S)}"
dry_run=0

case "${1:-}" in
  --dry-run) dry_run=1 ;;
  "") ;;
  *) echo "usage: $0 [--dry-run]" >&2; exit 2 ;;
esac

# No shell snippets are wired today — jcmwatch/jdmindex were folded into the `roborepo`
# command. This array is intentionally empty; add entries here to source future helpers.
source_snippets=()

# Only create ~/.zshrc if we actually have something to write into it. With no snippets wired
# and no existing profile, do nothing — don't leave behind an empty ~/.zshrc the user never had.
if [[ ${#source_snippets[@]} -gt 0 ]]; then
  if [[ "${dry_run}" -eq 1 ]]; then
    [[ -e "${zshrc}" ]] || echo "would touch: ${zshrc}"
  else
    touch "${zshrc}"
  fi
fi

needs_backup=true

for snippet in "${source_snippets[@]+"${source_snippets[@]}"}"; do
  source_line="source \"${repo_root}/${snippet}\""
  if [[ -e "${zshrc}" ]] && grep -Fqx "${source_line}" "${zshrc}"; then
    echo "ok: ${zshrc} already sources ${snippet}"
  else
    if [[ "${dry_run}" -eq 1 ]]; then
      echo "source: ${source_line}"
      continue
    fi
    if [[ "${needs_backup}" == "true" ]]; then
      mkdir -p "${backup_root}${HOME}"
      cp -p "${zshrc}" "${backup_root}${zshrc}"
      echo "backup: ${zshrc} -> ${backup_root}${zshrc}"
      needs_backup=false
    fi
    printf '\n# Harness config shell helpers\n%s\n' "${source_line}" >> "${zshrc}"
    echo "source: ${source_line}"
  fi
done

# Prune stale snippet `source` lines from a prior install. Earlier versions sourced
# shell/jcodemunch.zsh and shell/jdocmunch.zsh; those helpers were folded into roborepo, so any
# stale `source ".../shell/*.zsh"` line that is no longer in source_snippets is removed.
# Also drops the "# Harness config shell helpers" marker comment that preceded each.
prune_stale_snippets() {
  [[ -e "${zshrc}" ]] || return 0

  # Build the set of source lines we still want, to spare them from pruning.
  local wanted=()
  local s
  for s in "${source_snippets[@]+"${source_snippets[@]}"}"; do
    wanted+=("source \"${repo_root}/${s}\"")
  done

  # Find managed snippet source lines currently present but not wanted.
  local stale_found=0 line
  while IFS= read -r line; do
    case "${line}" in
      "source \"${repo_root}/shell/"*.zsh\")
        local keep=0 w
        for w in "${wanted[@]+"${wanted[@]}"}"; do
          [[ "${line}" == "${w}" ]] && keep=1 && break
        done
        [[ "${keep}" -eq 0 ]] && stale_found=1
        ;;
    esac
  done < "${zshrc}"

  [[ "${stale_found}" -eq 0 ]] && return 0

  if [[ "${dry_run}" -eq 1 ]]; then
    echo "prune: would remove stale shell/*.zsh source line(s) from ${zshrc}"
    return 0
  fi

  if [[ "${needs_backup}" == "true" ]]; then
    mkdir -p "${backup_root}${HOME}"
    cp -p "${zshrc}" "${backup_root}${zshrc}"
    echo "backup: ${zshrc} -> ${backup_root}${zshrc}"
    needs_backup=false
  fi

  # Rewrite without the stale source lines and their immediately-preceding marker comment.
  local tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/zshrc.XXXXXX")"
  awk -v repo="${repo_root}" '
    {
      line = $0
      is_stale = (line ~ ("^source \"" repo "/shell/.*\\.zsh\"$"))
      if (is_stale) {
        # Drop a buffered "# Harness config shell helpers" marker that preceded this line.
        if (held != "") { held = "" }
        next
      }
      if (held != "") { print held; held = "" }
      if (line == "# Harness config shell helpers") { held = line; next }
      print line
    }
    END { if (held != "") print held }
  ' "${zshrc}" > "${tmp}"
  mv "${tmp}" "${zshrc}"
  echo "prune: removed stale shell/*.zsh source line(s) from ${zshrc}"
}
prune_stale_snippets
