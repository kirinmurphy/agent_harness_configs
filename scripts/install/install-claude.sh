#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
backup_root="${ROBOREPO_BACKUP_ROOT:-${HOME}/.roborepo-backups/$(date +%Y%m%d-%H%M%S)}"
dry_run=0

case "${1:-}" in
  --dry-run) dry_run=1 ;;
  "") ;;
  *) echo "usage: $0 [--dry-run]" >&2; exit 2 ;;
esac

# shellcheck source=scripts/install/install-lib.sh
source "${repo_root}/scripts/install/install-lib.sh"
# shellcheck source=scripts/lib/globals-data.sh
source "${repo_root}/scripts/lib/globals-data.sh"  # provides manifest_rows

if [[ ! -d "${HOME}/.claude" ]]; then
  echo "skip: ~/.claude not found — Claude Code does not appear to be installed" >&2
  exit 0
fi

# Managed links + root config + retired-link cleanup all come from globals/manifest.tsv
# (claude rows). Preflight every link target first; abort before touching anything if any
# conflict. settings.json (root_config) is handled separately — it is mutable user state.
conflict=0
while IFS=$'\t' read -r _h kind src_rel home_abs _flags; do
  [[ "${kind}" == "link" ]] || continue
  preflight_clean_item "${src_rel}" "${home_abs}" || conflict=1
done < <(manifest_rows claude)
if [[ "${conflict}" -eq 1 ]]; then
  echo "Install has non-root Claude conflicts. No files were changed." >&2
  exit 1
fi

while IFS=$'\t' read -r _h kind src_rel home_abs _flags; do
  case "${kind}" in
    root_config)
      if [[ "${HARNESS_ADOPT_CLAUDE_CONFIG:-0}" == "1" ]]; then
        echo "skip: ${home_abs} left in place"
      else
        export_user_config "claude" "${src_rel}" "${home_abs}"
      fi
      ;;
    link)    link_item_clean "${src_rel}" "${home_abs}" ;;
    cleanup) remove_repo_link "${home_abs}" ;;
  esac
done < <(manifest_rows claude)
