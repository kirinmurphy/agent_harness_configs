#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
backup_root="${HARNESS_CONFIG_BACKUP_ROOT:-${HOME}/.harness-configs-backups/$(date +%Y%m%d-%H%M%S)}"
dry_run=0

case "${1:-}" in
  --dry-run) dry_run=1 ;;
  "") ;;
  *) echo "usage: $0 [--dry-run]" >&2; exit 2 ;;
esac

# shellcheck source=scripts/install-lib.sh
source "${repo_root}/scripts/install-lib.sh"

if [[ ! -d "${HOME}/.claude" ]]; then
  echo "skip: ~/.claude not found — Claude Code does not appear to be installed" >&2
  exit 0
fi

link_item "claude/CLAUDE.md"                    "${HOME}/.claude/CLAUDE.md"
link_item "claude/settings.json"                "${HOME}/.claude/settings.json"
link_item "claude/MANAGED_BY_HARNESS_CONFIGS.md" "${HOME}/.claude/MANAGED_BY_HARNESS_CONFIGS.md"
link_item "claude/commands"                     "${HOME}/.claude/commands"
link_item "claude/hooks"                        "${HOME}/.claude/hooks"
link_item "claude/skills"                       "${HOME}/.claude/skills"
remove_repo_link "${HOME}/.claude/plugins/known_marketplaces.json"
remove_repo_link "${HOME}/.claude/plugins/installed_plugins.json"
