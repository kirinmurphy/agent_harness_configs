#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
backup_root="${HOME}/.harness-configs-backups/$(date +%Y%m%d-%H%M%S)"
dry_run=0

case "${1:-}" in
  --dry-run)
    dry_run=1
    ;;
  "")
    ;;
  *)
    echo "usage: $0 [--dry-run]" >&2
    exit 2
    ;;
esac

link_item() {
  local repo_rel="$1"
  local home_path="$2"
  local src="${repo_root}/${repo_rel}"

  if [[ ! -e "${src}" ]]; then
    echo "missing source: ${src}" >&2
    return 1
  fi

  if [[ "${dry_run}" -eq 0 ]]; then
    mkdir -p "$(dirname "${home_path}")"
  fi

  if [[ -L "${home_path}" ]]; then
    local current
    current="$(readlink "${home_path}")"
    if [[ "${current}" == "${src}" ]]; then
      echo "ok: ${home_path}"
      return 0
    fi
  fi

  if [[ -e "${home_path}" || -L "${home_path}" ]]; then
    local backup_path="${backup_root}${home_path}"
    if [[ "${dry_run}" -eq 0 ]]; then
      mkdir -p "$(dirname "${backup_path}")"
      mv "${home_path}" "${backup_path}"
    fi
    echo "backup: ${home_path} -> ${backup_path}"
  fi

  if [[ "${dry_run}" -eq 0 ]]; then
    ln -s "${src}" "${home_path}"
  fi
  echo "link: ${home_path} -> ${src}"
}

remove_repo_link() {
  local home_path="$1"

  if [[ ! -L "${home_path}" ]]; then
    return 0
  fi

  local current
  current="$(readlink "${home_path}")"
  case "${current}" in
    "${repo_root}"/*)
      local backup_path="${backup_root}${home_path}"
      if [[ "${dry_run}" -eq 0 ]]; then
        mkdir -p "$(dirname "${backup_path}")"
        mv "${home_path}" "${backup_path}"
      fi
      echo "cleanup: ${home_path} -> ${backup_path}"
      ;;
  esac
}

link_item "codex/AGENTS.md" "${HOME}/.codex/AGENTS.md"
link_item "codex/config.toml" "${HOME}/.codex/config.toml"
link_item "codex/hooks.json" "${HOME}/.codex/hooks.json"
link_item "codex/MANAGED_BY_HARNESS_CONFIGS.md" "${HOME}/.codex/MANAGED_BY_HARNESS_CONFIGS.md"
link_item "codex/rules" "${HOME}/.codex/rules"
link_item "codex/skills" "${HOME}/.codex/skills"

link_item "claude/CLAUDE.md" "${HOME}/.claude/CLAUDE.md"
link_item "claude/settings.json" "${HOME}/.claude/settings.json"
link_item "claude/MANAGED_BY_HARNESS_CONFIGS.md" "${HOME}/.claude/MANAGED_BY_HARNESS_CONFIGS.md"
link_item "claude/commands" "${HOME}/.claude/commands"
link_item "claude/hooks" "${HOME}/.claude/hooks"
link_item "claude/skills" "${HOME}/.claude/skills"
link_item "claude/plugins/blocklist.json" "${HOME}/.claude/plugins/blocklist.json"
remove_repo_link "${HOME}/.claude/plugins/known_marketplaces.json"
remove_repo_link "${HOME}/.claude/plugins/installed_plugins.json"
