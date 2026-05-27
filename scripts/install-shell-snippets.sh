#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
zshrc="${HOME}/.zshrc"
backup_root="${HARNESS_CONFIG_BACKUP_ROOT:-${HOME}/.harness-configs-backups/$(date +%Y%m%d-%H%M%S)}"

touch "${zshrc}"

source_snippets=(
  "shell/jcodemunch.zsh"
  "shell/jdocmunch.zsh"
)

needs_backup=true

for snippet in "${source_snippets[@]}"; do
  source_line="source \"${repo_root}/${snippet}\""
  if grep -Fqx "${source_line}" "${zshrc}"; then
    echo "ok: ${zshrc} already sources ${snippet}"
  else
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
