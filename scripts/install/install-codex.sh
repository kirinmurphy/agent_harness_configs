#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
backup_root="${HARNESS_CONFIG_BACKUP_ROOT:-${HOME}/.harness-configs-backups/$(date +%Y%m%d-%H%M%S)}"
dry_run=0

case "${1:-}" in
  --dry-run) dry_run=1 ;;
  "") ;;
  *) echo "usage: $0 [--dry-run]" >&2; exit 2 ;;
esac

# shellcheck source=scripts/install/install-lib.sh
source "${repo_root}/scripts/install/install-lib.sh"

# Codex is "installed" if either its config home (~/.codex) or its skills home (~/.agents)
# exists. AGENTS.md / config.toml / rules live under ~/.codex; skills live under ~/.agents
# (Codex scans .agents/skills exclusively). ~/.codex/skills is kept as a transitional
# cross-compat link only.
if [[ ! -d "${HOME}/.codex" && ! -d "${HOME}/.agents" ]]; then
  echo "skip: neither ~/.codex nor ~/.agents found — Codex does not appear to be installed" >&2
  exit 0
fi

conflict=0
preflight_clean_item "codex/AGENTS.md" "${HOME}/.codex/AGENTS.md" || conflict=1
preflight_clean_item "codex/hooks.json" "${HOME}/.codex/hooks.json" || conflict=1
preflight_clean_item "codex/MANAGED_BY_HARNESS_CONFIGS.md" "${HOME}/.codex/MANAGED_BY_HARNESS_CONFIGS.md" || conflict=1
preflight_clean_item "codex/rules" "${HOME}/.codex/rules" || conflict=1
# Canonical skills home + transitional cross-compat copy, both -> repo agents/skills.
preflight_clean_item "agents/skills" "${HOME}/.agents/skills" || conflict=1
preflight_clean_item "agents/skills" "${HOME}/.codex/skills" || conflict=1
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
# Skills: ~/.agents/skills is canonical (Codex reads this); ~/.codex/skills is transitional.
link_item_clean "agents/skills"                       "${HOME}/.agents/skills"
link_item_clean "agents/skills"                       "${HOME}/.codex/skills"
