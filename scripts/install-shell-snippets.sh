#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
zshrc="${HOME}/.zshrc"
source_line="source \"${repo_root}/shell/jcodemunch.zsh\""
backup_root="${HOME}/.harness-configs-backups/$(date +%Y%m%d-%H%M%S)"

touch "${zshrc}"

if grep -Fqx "${source_line}" "${zshrc}"; then
  echo "ok: ${zshrc} already sources shell/jcodemunch.zsh"
  exit 0
fi

mkdir -p "${backup_root}${HOME}"
cp -p "${zshrc}" "${backup_root}${zshrc}"
printf '\n# Harness config shell helpers\n%s\n' "${source_line}" >> "${zshrc}"
echo "backup: ${zshrc} -> ${backup_root}${zshrc}"
echo "source: ${source_line}"
