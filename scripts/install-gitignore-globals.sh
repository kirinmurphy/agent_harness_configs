#!/usr/bin/env bash
set -euo pipefail

gitignore_global="${HOME}/.gitignore_global"
excludesfile_line="[core]"

entries=(
  ".jdm-indexed"
)

touch "${gitignore_global}"

added=0
for entry in "${entries[@]}"; do
  if grep -Fqx "${entry}" "${gitignore_global}"; then
    echo "ok: ${gitignore_global} already contains ${entry}"
  else
    printf '%s\n' "${entry}" >> "${gitignore_global}"
    echo "added: ${entry} -> ${gitignore_global}"
    added=1
  fi
done

current_excludesfile="$(git config --global core.excludesfile 2>/dev/null || true)"
if [[ "${current_excludesfile}" == "${gitignore_global}" ]]; then
  echo "ok: git core.excludesfile already set to ${gitignore_global}"
else
  git config --global core.excludesfile "${gitignore_global}"
  echo "set: git core.excludesfile -> ${gitignore_global}"
fi
