#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
backup_root="${HARNESS_CONFIG_BACKUP_ROOT:-${HOME}/.roborepo-backups/$(date +%Y%m%d-%H%M%S)}"
dry_run=0

case "${1:-}" in
  --dry-run) dry_run=1 ;;
  "") ;;
  *) echo "usage: $0 [--dry-run]" >&2; exit 2 ;;
esac

# shellcheck source=scripts/install/install-lib.sh
source "${repo_root}/scripts/install/install-lib.sh"

if [[ ! -d "${HOME}/.claude" ]]; then
  echo "skip: ~/.claude not found — Claude Code does not appear to be installed" >&2
  exit 0
fi

conflict=0
preflight_clean_item "claude/CLAUDE.md" "${HOME}/.claude/CLAUDE.md" || conflict=1
preflight_clean_item "claude/MANAGED_BY_HARNESS_CONFIGS.md" "${HOME}/.claude/MANAGED_BY_HARNESS_CONFIGS.md" || conflict=1
preflight_clean_item "claude/commands" "${HOME}/.claude/commands" || conflict=1
preflight_clean_item "claude/hooks" "${HOME}/.claude/hooks" || conflict=1
preflight_clean_item "claude/skills" "${HOME}/.claude/skills" || conflict=1
if [[ "${conflict}" -eq 1 ]]; then
  echo "Install has non-root Claude conflicts. No files were changed." >&2
  exit 1
fi

if [[ "${HARNESS_ADOPT_CLAUDE_CONFIG:-0}" == "1" ]]; then
  echo "skip: ${HOME}/.claude/settings.json left in place"
else
  export_user_config "claude" "claude/settings.json" "${HOME}/.claude/settings.json"
fi
link_item_clean "claude/CLAUDE.md"                    "${HOME}/.claude/CLAUDE.md"
link_item_clean "claude/MANAGED_BY_HARNESS_CONFIGS.md" "${HOME}/.claude/MANAGED_BY_HARNESS_CONFIGS.md"
link_item_clean "claude/commands"                     "${HOME}/.claude/commands"
link_item_clean "claude/hooks"                        "${HOME}/.claude/hooks"
link_item_clean "claude/skills"                       "${HOME}/.claude/skills"
remove_repo_link "${HOME}/.claude/plugins/blocklist.json"
remove_repo_link "${HOME}/.claude/plugins/known_marketplaces.json"
remove_repo_link "${HOME}/.claude/plugins/installed_plugins.json"
