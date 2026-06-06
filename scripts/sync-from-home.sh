#!/usr/bin/env bash
set -euo pipefail

repo_root="${HARNESS_CONFIG_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
include_user_config=0

case "${1:-}" in
  --include-root-config|--include-user-config) include_user_config=1 ;;
  "") ;;
  *) echo "usage: $0 [--include-root-config]" >&2; exit 2 ;;
esac

print_agent_sync_prompt() {
  local home_path="$1"
  local repo_rel="$2"
  local dst="${repo_root}/${repo_rel}"

  echo ""
  echo "Agent merge prompt:"
  echo "-----"
  cat <<EOF
Compare local live config at:
  ${home_path}

With repo baseline at:
  ${dst}

Default stance: keep the repo baseline as source of truth unless you can prove a local live change should be promoted.

Required first step: compute your own complete comparison of both paths. Do not rely on this prompt as an exhaustive conflict summary. For directories, inspect the full recursive file list and content diffs. For structured files, parse the format when possible and identify all changed keys/tables/arrays/sections before editing.

Merge instructions:
- Keep repo-managed defaults by default.
- Promote local live changes only when they are intentional and do not conflict with harness defaults.
- Preserve user-specific MCP servers, model preferences, permissions, hooks, profiles, trusted projects, plugin settings, and local state unless they directly conflict with harness requirements.
- If both sides set the same scalar, table, hook, permission, plugin, profile, project, rule, command, skill, or MCP/server entry differently, flag it as a conflict instead of guessing.
- Do not blindly overwrite either side.
- Report the final changed file/path and any conflicts left unresolved.
EOF
  echo "-----"
  echo ""
}

show_diff() {
  local home_path="$1"
  local dst="$2"

  if [[ -e "${dst}" ]]; then
    git diff --no-index -- "${dst}" "${home_path}" || true
  else
    echo "new repo path: ${dst}"
    if [[ -f "${home_path}" ]]; then
      sed -n '1,120p' "${home_path}"
    else
      find "${home_path}" -maxdepth 2 -type f | sed "s#^#  #"
    fi
  fi
}

paths_match() {
  local home_path="$1"
  local dst="$2"

  [[ -e "${dst}" ]] || return 1
  diff -qr "${dst}" "${home_path}" >/dev/null 2>&1
}

overwrite_from_home() {
  local home_path="$1"
  local dst="$2"
  local parent
  local tmp
  local backup_dir
  local moved_existing=0

  parent="$(dirname "${dst}")"
  mkdir -p "${parent}"
  tmp="$(mktemp -d "${parent}/.sync-from-home.tmp.XXXXXX")"
  backup_dir="$(mktemp -d "${parent}/.sync-from-home.backup.XXXXXX")"

  if ! cp -Rp "${home_path}" "${tmp}/item"; then
    rm -rf "${tmp}"
    rm -rf "${backup_dir}"
    echo "error: failed to copy ${home_path}; repo path left unchanged: ${dst}" >&2
    return 1
  fi

  if [[ -e "${dst}" || -L "${dst}" ]]; then
    if ! mv "${dst}" "${backup_dir}/item"; then
      rm -rf "${tmp}"
      rm -rf "${backup_dir}"
      echo "error: failed to stage existing repo path; repo path left unchanged: ${dst}" >&2
      return 1
    fi
    moved_existing=1
  fi

  if ! mv "${tmp}/item" "${dst}"; then
    if [[ "${moved_existing}" -eq 1 ]]; then
      mv "${backup_dir}/item" "${dst}" || true
    fi
    rm -rf "${tmp}"
    rm -rf "${backup_dir}"
    echo "error: failed to replace ${dst}; original repo path was restored" >&2
    return 1
  fi

  rm -rf "${tmp}"
  rm -rf "${backup_dir}"
}

sync_item() {
  local home_path="$1"
  local repo_rel="$2"
  local kind="${3:-standard}"
  local dst="${repo_root}/${repo_rel}"
  local choice

  if [[ ! -e "${home_path}" && ! -L "${home_path}" ]]; then
    echo "skip missing: ${home_path}"
    return 0
  fi

  if [[ "${kind}" == "user_config" ]]; then
    if [[ -L "${home_path}" && "$(readlink "${home_path}")" == "${dst}" ]]; then
      echo "ok managed config: ${home_path} -> ${repo_rel}"
      return 0
    fi

    if [[ "${include_user_config}" -ne 1 ]]; then
      echo "skip user-owned config: ${home_path}"
      echo "  use --include-root-config only when intentionally promoting local root config into the repo baseline"
      return 0
    fi
  fi

  if paths_match "${home_path}" "${dst}"; then
    echo "ok unchanged: ${home_path} -> ${repo_rel}"
    return 0
  fi

  if [[ ! -t 0 ]]; then
    echo "error: ${home_path} differs from ${dst} and stdin is not interactive." >&2
    echo "Run interactively to review the diff, or merge manually." >&2
    return 1
  fi

  while true; do
    echo ""
    echo "Home config differs from repo:"
    echo "  home: ${home_path}"
    echo "  repo: ${dst}"
    echo ""
    show_diff "${home_path}" "${dst}"
    echo ""
    echo "Choose:"
    echo "  1) keep repo      skip this item"
    echo "  2) overwrite repo copy home item into repo"
    echo "  3) agent prompt   print merge prompt and skip this item"
    echo "  q) quit"
    read -r -p "Selection [1/2/3/q]: " choice

    case "${choice}" in
      1|keep)
        echo "skip: kept repo ${repo_rel}"
        return 0
        ;;
      2|overwrite)
        overwrite_from_home "${home_path}" "${dst}"
        echo "sync: ${home_path} -> ${repo_rel}"
        return 0
        ;;
      3|agent|prompt)
        print_agent_sync_prompt "${home_path}" "${repo_rel}"
        echo "skip: ${repo_rel} left unchanged"
        return 0
        ;;
      q|Q|quit|exit)
        echo "abort: sync canceled by user" >&2
        exit 1
        ;;
      *)
        echo "Invalid selection."
        ;;
    esac
  done
}

sync_item "${HOME}/.codex/AGENTS.md" "codex/AGENTS.md"
sync_item "${HOME}/.codex/config.toml" "codex/config.toml" "user_config"
sync_item "${HOME}/.codex/hooks.json" "codex/hooks.json"
sync_item "${HOME}/.codex/MANAGED_BY_HARNESS_CONFIGS.md" "codex/MANAGED_BY_HARNESS_CONFIGS.md"
sync_item "${HOME}/.codex/rules" "codex/rules"
sync_item "${HOME}/.claude/CLAUDE.md" "claude/CLAUDE.md"
sync_item "${HOME}/.claude/settings.json" "claude/settings.json" "user_config"
sync_item "${HOME}/.claude/MANAGED_BY_HARNESS_CONFIGS.md" "claude/MANAGED_BY_HARNESS_CONFIGS.md"
sync_item "${HOME}/.claude/commands" "claude/commands"
sync_item "${HOME}/.claude/hooks" "claude/hooks"
sync_item "${HOME}/.claude/plugins/blocklist.json" "claude/plugins/blocklist.json"

echo "skip shared skills: maintained in repo/agents/skills and symlinked into both harnesses"
