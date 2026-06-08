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

# Codex is "installed" if either its config home (~/.codex) or its skills home (~/.agents)
# exists. AGENTS.md / config.toml / rules live under ~/.codex; skills live under ~/.agents
# (Codex scans .agents/skills exclusively). ~/.codex/skills is NOT managed: it is Codex's own
# writable skill dir (its .system skill-installer reads/writes $CODEX_HOME/skills). Any old
# repo-symlink there is pruned via the codex `cleanup` row so installs don't land in the repo.
harness_present codex || {
  echo "skip: neither ~/.codex nor ~/.agents found — Codex does not appear to be installed" >&2
  exit 0
}

# Managed rows come from globals/manifest.tsv: codex harness (AGENTS.md, hooks.json, rules,
# config.toml, plus cleanup of the retired ~/.codex/skills link) and agents harness (the
# canonical ~/.agents/skills link -> globals/agents/skills).
codex_rows() { manifest_rows codex; manifest_rows agents; }

conflict=0
while IFS=$'\t' read -r _h kind src_rel home_abs _flags; do
  [[ "${kind}" == "link" ]] || continue
  preflight_clean_item "${src_rel}" "${home_abs}" || conflict=1
done < <(codex_rows)
if [[ "${conflict}" -eq 1 ]]; then
  echo "Install has non-root Codex conflicts. No files were changed." >&2
  exit 1
fi

while IFS=$'\t' read -r _h kind src_rel home_abs _flags; do
  case "${kind}" in
    root_config)
      if [[ "${HARNESS_ADOPT_CODEX_CONFIG:-0}" == "1" ]]; then
        echo "skip: ${home_abs} left in place"
      else
        export_user_config "codex" "${src_rel}" "${home_abs}"
      fi
      ;;
    link)    link_item_clean "${src_rel}" "${home_abs}" ;;
    cleanup) remove_repo_link "${home_abs}" ;;
  esac
done < <(codex_rows)
