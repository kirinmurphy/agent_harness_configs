#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
zshrc="${HOME}/.zshrc"
backup_root="${HARNESS_CONFIG_BACKUP_ROOT:-${HOME}/.harness-configs-backups/$(date +%Y%m%d-%H%M%S)}"
dry_run=0

case "${1:-}" in
  --dry-run) dry_run=1 ;;
  "") ;;
  *) echo "usage: $0 [--dry-run]" >&2; exit 2 ;;
esac

if [[ "${dry_run}" -eq 1 ]]; then
  [[ -e "${zshrc}" ]] || echo "would touch: ${zshrc}"
else
  touch "${zshrc}"
fi

source_snippets=(
  "shell/jcodemunch.zsh"
  "shell/jdocmunch.zsh"
)

needs_backup=true

for snippet in "${source_snippets[@]}"; do
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
