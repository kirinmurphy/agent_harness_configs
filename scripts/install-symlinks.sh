#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dry_run=0
backup_root="${HARNESS_CONFIG_BACKUP_ROOT:-${HOME}/.harness-configs-backups/$(date +%Y%m%d-%H%M%S)}"
export HARNESS_CONFIG_BACKUP_ROOT="${backup_root}"

case "${1:-}" in
  --dry-run) dry_run=1 ;;
  "") ;;
  *) echo "usage: $0 [--dry-run]" >&2; exit 2 ;;
esac

dry_args=()
[[ $dry_run -eq 1 ]] && dry_args=(--dry-run)

# shellcheck source=scripts/install-lib.sh
source "${repo_root}/scripts/install-lib.sh"

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
      echo "Running PowerShell installer for symlinks..."
      ps_args=(-ExecutionPolicy Bypass -File "${repo_root}/scripts/install-windows.ps1")
      [[ $dry_run -eq 1 ]] && ps_args+=(-DryRun)
      powershell.exe "${ps_args[@]}"
    else
      echo "powershell.exe not found. Run scripts/install-windows.ps1 from PowerShell manually."
    fi
    # Shell snippets and global commands still need bash — continue below
    run_with_dry_args "${repo_root}/scripts/install-gitignore-globals.sh"
    if [[ $dry_run -eq 0 ]]; then
      "${repo_root}/scripts/install-global-commands.sh"
      "${repo_root}/scripts/install-shell-snippets.sh"
    fi
    exit 0
    ;;
esac

# Detect which harnesses are present
has_claude=0
has_codex=0
[[ -d "${HOME}/.claude" ]] && has_claude=1
[[ -d "${HOME}/.codex" ]]  && has_codex=1

if [[ $has_claude -eq 0 && $has_codex -eq 0 ]]; then
  echo "error: neither ~/.claude nor ~/.codex found." >&2
  echo "Install Claude Code (https://claude.ai/code) or Codex before running this script." >&2
  exit 1
fi

preflight_shell_setup() {
  "${repo_root}/scripts/install-global-commands.sh" --dry-run
  "${repo_root}/scripts/install-shell-snippets.sh" --dry-run
}

check_clean_target() {
  local repo_rel="$1"
  local home_path="$2"
  local src="${repo_root}/${repo_rel}"

  if [[ ! -e "${home_path}" && ! -L "${home_path}" ]]; then
    return 0
  fi

  if [[ -L "${home_path}" && "$(readlink "${home_path}")" == "${src}" ]]; then
    return 0
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

preflight_clean_targets() {
  local conflict=0

  if [[ $has_claude -eq 1 ]]; then
    check_clean_target "claude/CLAUDE.md" "${HOME}/.claude/CLAUDE.md" || conflict=1
    check_clean_target "claude/MANAGED_BY_HARNESS_CONFIGS.md" "${HOME}/.claude/MANAGED_BY_HARNESS_CONFIGS.md" || conflict=1
    check_clean_target "claude/commands" "${HOME}/.claude/commands" || conflict=1
    check_clean_target "claude/hooks" "${HOME}/.claude/hooks" || conflict=1
    check_clean_target "claude/skills" "${HOME}/.claude/skills" || conflict=1
  fi

  if [[ $has_codex -eq 1 ]]; then
    check_clean_target "codex/AGENTS.md" "${HOME}/.codex/AGENTS.md" || conflict=1
    check_clean_target "codex/hooks.json" "${HOME}/.codex/hooks.json" || conflict=1
    check_clean_target "codex/MANAGED_BY_HARNESS_CONFIGS.md" "${HOME}/.codex/MANAGED_BY_HARNESS_CONFIGS.md" || conflict=1
    check_clean_target "codex/rules" "${HOME}/.codex/rules" || conflict=1
    check_clean_target "codex/skills" "${HOME}/.codex/skills" || conflict=1
  fi

  if [[ $conflict -eq 1 ]]; then
    echo "Install has non-root config conflicts. No files were changed." >&2
    echo "Use the agent prompt above, or merge/move these paths before re-running." >&2
    exit 1
  fi
}

preflight_clean_targets
preflight_shell_setup

preflight_root_config() {
  local harness="$1"
  local repo_rel="$2"
  local home_path="$3"
  local src="${repo_root}/${repo_rel}"
  local current

  if [[ -L "${home_path}" ]]; then
    current="$(readlink "${home_path}")"
    if [[ "${current}" == "${src}" ]]; then
      return 0
    fi
  fi

  if [[ ! -e "${home_path}" && ! -L "${home_path}" ]]; then
    return 0
  fi

  if [[ $dry_run -eq 1 ]]; then
    echo "collision: ${home_path}"
    echo "dry-run: would ask whether to adopt existing config or print agent merge prompt"
    describe_user_config "${harness}" "${home_path}"
    return 0
  fi

  if [[ ! -t 0 ]]; then
    echo "error: ${home_path} exists and stdin is not interactive." >&2
    echo "Run interactively, move the file aside, or use --dry-run to inspect collisions." >&2
    return 1
  fi

  CONFIG_COLLISION_ACTION=""
  config_collision_action "${harness}" "${repo_rel}" "${home_path}"
  case "${CONFIG_COLLISION_ACTION}" in
    adopt|agent)
      echo "skip: ${home_path} left in place"
      case "${harness}" in
        claude) export HARNESS_ADOPT_CLAUDE_CONFIG=1 ;;
        codex) export HARNESS_ADOPT_CODEX_CONFIG=1 ;;
      esac
      ;;
    abort)
      echo "abort: install canceled by user" >&2
      exit 1
      ;;
  esac
}

if [[ $has_claude -eq 1 ]]; then
  preflight_root_config "claude" "claude/settings.json" "${HOME}/.claude/settings.json"
fi

if [[ $has_codex -eq 1 ]]; then
  preflight_root_config "codex" "codex/config.toml" "${HOME}/.codex/config.toml"
fi

# Harness-agnostic setup
run_with_dry_args "${repo_root}/scripts/install-gitignore-globals.sh"

# Harness-specific symlinks
if [[ $has_claude -eq 1 ]]; then
  run_with_dry_args "${repo_root}/scripts/install-claude.sh"
else
  echo "skip: Claude — ~/.claude not found"
fi

if [[ $has_codex -eq 1 ]]; then
  run_with_dry_args "${repo_root}/scripts/install-codex.sh"
else
  echo "skip: Codex — ~/.codex not found"
fi

# Shell and PATH setup (harness-agnostic, bash only)
if [[ $dry_run -eq 0 ]]; then
  "${repo_root}/scripts/install-global-commands.sh"
  "${repo_root}/scripts/install-shell-snippets.sh"
fi

# Post-install summary
echo ""
echo "Install complete."
echo "  Claude: $([ $has_claude -eq 1 ] && echo 'linked' || echo 'skipped — not installed')"
echo "  Codex:  $([ $has_codex  -eq 1 ] && echo 'linked' || echo 'skipped — not installed')"
echo ""
echo "To add the other harness later: install it, then re-run this script."
