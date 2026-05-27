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

link_item "codex/AGENTS.md"                     "${HOME}/.codex/AGENTS.md"
link_item "codex/config.toml"                   "${HOME}/.codex/config.toml"
link_item "codex/hooks.json"                    "${HOME}/.codex/hooks.json"
link_item "codex/MANAGED_BY_HARNESS_CONFIGS.md" "${HOME}/.codex/MANAGED_BY_HARNESS_CONFIGS.md"
link_item "codex/rules"                         "${HOME}/.codex/rules"
link_item "codex/skills"                        "${HOME}/.codex/skills"
