#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

copy_item() {
  local home_path="$1"
  local repo_rel="$2"
  local dst="${repo_root}/${repo_rel}"

  if [[ ! -e "${home_path}" ]]; then
    echo "skip missing: ${home_path}"
    return 0
  fi

  rm -rf "${dst}"
  mkdir -p "$(dirname "${dst}")"
  cp -Rp "${home_path}" "${dst}"
  echo "sync: ${home_path} -> ${repo_rel}"
}

copy_item "${HOME}/.codex/AGENTS.md" "codex/AGENTS.md"
copy_item "${HOME}/.codex/config.toml" "codex/config.toml"
copy_item "${HOME}/.codex/hooks.json" "codex/hooks.json"
copy_item "${HOME}/.codex/MANAGED_BY_HARNESS_CONFIGS.md" "codex/MANAGED_BY_HARNESS_CONFIGS.md"
copy_item "${HOME}/.codex/rules" "codex/rules"
copy_item "${HOME}/.claude/CLAUDE.md" "claude/CLAUDE.md"
copy_item "${HOME}/.claude/settings.json" "claude/settings.json"
copy_item "${HOME}/.claude/MANAGED_BY_HARNESS_CONFIGS.md" "claude/MANAGED_BY_HARNESS_CONFIGS.md"
copy_item "${HOME}/.claude/commands" "claude/commands"
copy_item "${HOME}/.claude/hooks" "claude/hooks"
copy_item "${HOME}/.claude/plugins/blocklist.json" "claude/plugins/blocklist.json"

echo "skip shared skills: maintained in repo/skills and symlinked into both harnesses"
