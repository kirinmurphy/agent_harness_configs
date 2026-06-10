#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
dry_run=0
agent_permission_profile="${ROBOREPO_AGENT_PERMISSION_PROFILE:-${ROBOREPO_CODEX_PERMISSION_PROFILE:-}}"
install_mode="${ROBOREPO_INSTALL_MODE:-}"
on_conflict="${ROBOREPO_ON_CONFLICT:-}"
backup_root="${ROBOREPO_BACKUP_ROOT:-${HOME}/.roborepo-backups/$(date +%Y%m%d-%H%M%S)}"
export ROBOREPO_BACKUP_ROOT="${backup_root}"
export ROBOREPO_INSTALL_TIMESTAMP="${ROBOREPO_INSTALL_TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      dry_run=1
      shift
      ;;
    --permissions|--agent-permissions|--codex-permissions)
      [[ $# -ge 2 ]] || { echo "usage: $0 [--dry-run] [--mode managed|adopt] [--on-conflict overwrite|keep|agent] [--permissions <profile>]" >&2; exit 2; }
      agent_permission_profile="$2"
      shift 2
      ;;
    --permissions=*|--agent-permissions=*)
      agent_permission_profile="${1#*=}"
      shift
      ;;
    --codex-permissions=*)
      agent_permission_profile="${1#*=}"
      shift
      ;;
    --mode)
      [[ $# -ge 2 ]] || { echo "usage: $0 [--dry-run] [--mode managed|adopt] [--on-conflict overwrite|keep|agent] [--permissions <profile>]" >&2; exit 2; }
      install_mode="$2"
      shift 2
      ;;
    --mode=*)
      install_mode="${1#*=}"
      shift
      ;;
    --on-conflict)
      [[ $# -ge 2 ]] || { echo "usage: $0 [--dry-run] [--mode managed|adopt] [--on-conflict overwrite|keep|agent] [--permissions <profile>]" >&2; exit 2; }
      on_conflict="$2"
      shift 2
      ;;
    --on-conflict=*)
      on_conflict="${1#*=}"
      shift
      ;;
    *)
      echo "usage: $0 [--dry-run] [--mode managed|adopt] [--on-conflict overwrite|keep|agent] [--permissions <profile>]" >&2
      exit 2
      ;;
  esac
done

case "${install_mode}" in
  "" ) ;;
  managed|adopt) ;;
  *) echo "usage: $0 [--dry-run] [--mode managed|adopt] [--on-conflict overwrite|keep|agent] [--permissions <profile>]" >&2; exit 2 ;;
esac

case "${on_conflict}" in
  "" ) ;;
  overwrite|keep|agent|prompt|abort) ;;
  *) echo "usage: $0 [--dry-run] [--mode managed|adopt] [--on-conflict overwrite|keep|agent] [--permissions <profile>]" >&2; exit 2 ;;
esac
[[ "${on_conflict}" == "prompt" ]] && on_conflict="agent"
export ROBOREPO_ON_CONFLICT="${on_conflict}"

dry_args=()
[[ $dry_run -eq 1 ]] && dry_args=(--dry-run)

# shellcheck source=scripts/install/install-lib.sh
source "${repo_root}/scripts/install/install-lib.sh"
# shellcheck source=scripts/install/state-lib.sh
source "${repo_root}/scripts/install/state-lib.sh"
# shellcheck source=scripts/lib/manifests-data.sh
source "${repo_root}/scripts/lib/manifests-data.sh"  # provides manifest_rows

if [[ -z "${install_mode}" ]]; then
  install_mode="$(read_install_mode 2>/dev/null || true)"
fi
install_mode="${install_mode:-managed}"
export ROBOREPO_INSTALL_MODE="${install_mode}"

run_with_dry_args() {
  if [[ $dry_run -eq 1 ]]; then
    "$1" --dry-run
  else
    "$1"
  fi
}

# Windows: delegate to PowerShell installer, then continue for bash-specific steps
case "$(uname -s 2>/dev/null || echo unknown)" in
  MINGW*|MSYS*|CYGWIN*)
    echo "Windows + bash detected (Git Bash or similar)."
    if command -v powershell.exe &>/dev/null; then
      echo "Running PowerShell installer..."
      ps_args=(-ExecutionPolicy Bypass -File "${repo_root}/scripts/install/install-windows.ps1")
      [[ $dry_run -eq 1 ]] && ps_args+=(-DryRun)
      powershell.exe "${ps_args[@]}"
    else
      echo "powershell.exe not found. Run scripts/install/install-windows.ps1 from PowerShell manually."
    fi
    # Shell snippets and global commands still need bash — continue below
    run_with_dry_args "${repo_root}/scripts/install/install-gitignore-globals.sh"
    if [[ $dry_run -eq 0 ]]; then
      "${repo_root}/scripts/install/install-global-commands.sh"
      "${repo_root}/scripts/install/install-shell-snippets.sh"
    fi
    exit 0
    ;;
esac

# Detect which harnesses are present.
has_claude=0
has_codex=0
harness_present claude && has_claude=1
harness_present codex && has_codex=1

if [[ $has_claude -eq 0 && $has_codex -eq 0 ]]; then
  echo "error: neither ~/.claude nor ~/.codex/~/.agents found." >&2
  echo "Install Claude Code (https://claude.ai/code) or Codex before running this script." >&2
  exit 1
fi

if [[ -n "${agent_permission_profile}" ]]; then
  if [[ $dry_run -eq 1 ]]; then
    if node "${repo_root}/scripts/build/render-agent-permissions.mjs" --check --profile "${agent_permission_profile}" >/dev/null; then
      echo "ok: agent permission profile ${agent_permission_profile} already rendered"
    else
      echo "dry-run: would render agent permission profile ${agent_permission_profile}"
    fi
  else
    node "${repo_root}/scripts/build/render-agent-permissions.mjs" --profile "${agent_permission_profile}"
  fi
fi

preflight_shell_setup() {
  "${repo_root}/scripts/install/install-global-commands.sh" --dry-run
  "${repo_root}/scripts/install/install-shell-snippets.sh" --dry-run
}

check_clean_target() {
  local repo_rel="$1"
  local home_path="$2"
  local src="${repo_root}/${repo_rel}"

  if [[ ! -e "${home_path}" && ! -L "${home_path}" ]]; then
    return 0
  fi

  if [[ -L "${home_path}" ]]; then
    case "$(readlink "${home_path}")" in
      "${src}"|"${repo_root}"/*) return 0 ;;
    esac
  fi

  echo "conflict: ${home_path} already exists and is not managed by this repo." >&2
  echo "  repo source: ${src}" >&2
  echo "Agent merge prompt:" >&2
  echo "  Default stance: preserve the existing local path as source of truth unless you can prove a repo change can be added without breaking local behavior." >&2
  echo "  Required first step: compute your own complete comparison of both paths. Do not rely on this prompt as an exhaustive conflict summary." >&2
  echo "  For directories, inspect the full recursive file list and content diffs. For structured files, parse the format when possible." >&2
  echo "  Add repo-only harness behavior only when it does not conflict with local behavior. Flag conflicts instead of guessing." >&2
  return 1
}

# Preflight every managed link target (from manifests/manifest.tsv) for the present harnesses.
# Claude uses the claude rows; Codex uses codex + agents rows (skills live under ~/.agents).
# root_config and cleanup rows are not preflighted here — root config is mutable user state
# handled by preflight_root_config below.
preflight_clean_targets() {
  local conflict=0
  local _h kind src_rel home_abs _flags

  preflight_harness() {
    while IFS=$'\t' read -r _h kind src_rel home_abs _flags; do
      [[ "${kind}" == "link" ]] || continue
      check_clean_target "${src_rel}" "${home_abs}" || conflict=1
    done < <(manifest_rows "$1")
  }

  [[ $has_claude -eq 1 ]] && preflight_harness claude
  if [[ $has_codex -eq 1 ]]; then
    preflight_harness codex
    preflight_harness agents
  fi

  if [[ $conflict -eq 1 ]]; then
    echo "Install has non-root config conflicts. No files were changed." >&2
    echo "Use the agent prompt above, or merge/move these paths before re-running." >&2
    exit 1
  fi
}

preflight_unattended_conflicts() {
  [[ "${dry_run}" -eq 0 ]] || return 0
  [[ -z "${ROBOREPO_ON_CONFLICT:-}" ]] || return 0
  stdin_is_interactive && return 0

  local conflict=0
  local _h kind src_rel home_abs _flags src current
  preflight_harness_conflicts() {
    while IFS=$'\t' read -r _h kind src_rel home_abs _flags; do
      case "${kind}" in
        root_config|link) ;;
        *) continue ;;
      esac
      src="${repo_root}/${src_rel}"
      [[ ! -e "${home_abs}" && ! -L "${home_abs}" ]] && continue
      if [[ "${kind}" == "link" && "${install_mode}" == "managed" && -L "${home_abs}" ]]; then
        current="$(readlink "${home_abs}")"
        [[ "${current}" == "${src}" || "${current}" == "${repo_root}"/* ]] && continue
      fi
      if [[ "${kind}" == "root_config" && -L "${home_abs}" ]]; then
        current="$(readlink "${home_abs}")"
        [[ "${current}" == "${src}" || "${current}" == "${repo_root}"/* ]] && continue
      fi
      if paths_equivalent_for_copy "${src}" "${home_abs}"; then
        continue
      fi
      echo "error: ${home_abs} exists and stdin is not interactive." >&2
      conflict=1
    done < <(manifest_rows "$1")
  }

  [[ $has_claude -eq 1 ]] && preflight_harness_conflicts claude
  if [[ $has_codex -eq 1 ]]; then
    preflight_harness_conflicts codex
    preflight_harness_conflicts agents
  fi
  if [[ "${conflict}" -eq 1 ]]; then
    echo "Run interactively, pass --on-conflict overwrite|keep|agent, or use --dry-run to inspect collisions." >&2
    exit 1
  fi
}

preflight_unattended_conflicts
preflight_shell_setup

# Harness-specific managed links and root config export
if [[ $has_claude -eq 1 ]]; then
  run_with_dry_args "${repo_root}/scripts/install/install-claude.sh"
else
  echo "skip: Claude — ~/.claude not found"
fi

if [[ $has_codex -eq 1 ]]; then
  run_with_dry_args "${repo_root}/scripts/install/install-codex.sh"
else
  echo "skip: Codex — ~/.codex not found"
fi

# Harness-agnostic setup
run_with_dry_args "${repo_root}/scripts/install/install-gitignore-globals.sh"

# Shell and PATH setup (harness-agnostic, bash only)
if [[ $dry_run -eq 0 ]]; then
  "${repo_root}/scripts/install/install-global-commands.sh"
  "${repo_root}/scripts/install/install-shell-snippets.sh"
fi

write_install_state "${install_mode}"

# Post-install summary
echo ""
echo "Install complete."
echo "  Mode:   ${install_mode}"
echo "  Claude: $([ $has_claude -eq 1 ] && echo 'installed' || echo 'skipped — not installed')"
echo "  Codex:  $([ $has_codex  -eq 1 ] && echo 'installed' || echo 'skipped — not installed')"
if [[ $has_claude -eq 0 || $has_codex -eq 0 ]]; then
  echo ""
  echo "To add the other harness later: install it, then re-run this script."
fi
