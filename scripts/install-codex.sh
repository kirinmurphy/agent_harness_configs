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

if [[ ! -d "${HOME}/.codex" ]]; then
  echo "skip: ~/.codex not found — Codex does not appear to be installed" >&2
  exit 0
fi

conflict=0
preflight_clean_item "codex/AGENTS.md" "${HOME}/.codex/AGENTS.md" || conflict=1
preflight_clean_item "codex/hooks.json" "${HOME}/.codex/hooks.json" || conflict=1
preflight_clean_item "codex/MANAGED_BY_HARNESS_CONFIGS.md" "${HOME}/.codex/MANAGED_BY_HARNESS_CONFIGS.md" || conflict=1
preflight_clean_item "codex/rules" "${HOME}/.codex/rules" || conflict=1
preflight_clean_item "codex/skills" "${HOME}/.codex/skills" || conflict=1
if [[ "${conflict}" -eq 1 ]]; then
  echo "Install has non-root Codex conflicts. No files were changed." >&2
  exit 1
fi

if [[ "${HARNESS_ADOPT_CODEX_CONFIG:-0}" == "1" ]]; then
  echo "skip: ${HOME}/.codex/config.toml left in place"
else
  link_user_config "codex" "codex/config.toml" "${HOME}/.codex/config.toml"
fi
link_item_clean "codex/AGENTS.md"                     "${HOME}/.codex/AGENTS.md"
link_item_clean "codex/hooks.json"                    "${HOME}/.codex/hooks.json"
link_item_clean "codex/MANAGED_BY_HARNESS_CONFIGS.md" "${HOME}/.codex/MANAGED_BY_HARNESS_CONFIGS.md"
link_item_clean "codex/rules"                         "${HOME}/.codex/rules"
link_item_clean "codex/skills"                        "${HOME}/.codex/skills"
