#!/usr/bin/env bash
# Shared helpers for install scripts. Source this file, do not execute directly.

unique_backup_path() {
  local home_path="$1"
  local backup_path="${backup_root}${home_path}"

  if [[ ! -e "${backup_path}" && ! -L "${backup_path}" ]]; then
    echo "${backup_path}"
    return 0
  fi

  local i=1
  while [[ -e "${backup_path}.${i}" || -L "${backup_path}.${i}" ]]; do
    i=$((i + 1))
  done
  echo "${backup_path}.${i}"
}

timestamped_path() {
  local path="$1"
  local tag="$2"
  local ts="${ROBOREPO_INSTALL_TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}"
  local dir base name ext

  dir="$(dirname "${path}")"
  base="$(basename "${path}")"
  if [[ -d "${path}" && ! -L "${path}" ]]; then
    echo "${dir}/${base}_${tag}_${ts}"
    return 0
  fi

  case "${base}" in
    *.*)
      name="${base%.*}"
      ext=".${base##*.}"
      echo "${dir}/${name}_${tag}_${ts}${ext}"
      ;;
    *)
      echo "${dir}/${base}_${tag}_${ts}"
      ;;
  esac
}

copy_tree() {
  local src="$1"
  local dest="$2"

  if [[ -d "${src}" && ! -L "${src}" ]]; then
    mkdir -p "$(dirname "${dest}")"
    cp -R "${src}" "${dest}"
  else
    mkdir -p "$(dirname "${dest}")"
    cp -p "${src}" "${dest}"
  fi
}

stdin_is_interactive() {
  [[ -t 0 || "${ROBOREPO_ASSUME_INTERACTIVE:-0}" == "1" ]]
}

paths_equivalent_for_copy() {
  local src="$1"
  local dest="$2"

  [[ -e "${dest}" || -L "${dest}" ]] || return 1
  if [[ -f "${src}" && -f "${dest}" && ! -L "${dest}" ]]; then
    cmp -s "${src}" "${dest}"
    return $?
  fi
  return 1
}

choose_path_conflict_action() {
  local repo_rel="$1"
  local home_path="$2"
  local src="${repo_root}/${repo_rel}"
  local choice

  if [[ -n "${ROBOREPO_ON_CONFLICT:-}" ]]; then
    CONFIG_COLLISION_ACTION="${ROBOREPO_ON_CONFLICT}"
    return 0
  fi

  if [[ "${dry_run}" -eq 1 ]]; then
    echo "collision: ${home_path}"
    echo "dry-run: would ask overwrite, keep originals, or agent prompt"
    return 0
  fi

  if ! stdin_is_interactive; then
    echo "error: ${home_path} exists and stdin is not interactive." >&2
    echo "Run interactively, pass --on-conflict overwrite|keep|agent, or use --dry-run to inspect collisions." >&2
    return 1
  fi

  while true; do
    echo ""
    echo "Existing harness target:"
    echo "  local:   ${home_path}"
    echo "  harness: ${src}"
    echo ""
    echo "Choose:"
    echo "  1) overwrite     backup local as *_original_TIMESTAMP; install repo item"
    echo "  2) keep originals leave local active; stage repo item as *_update_TIMESTAMP"
    echo "  3) agent prompt  stage repo item and print merge prompt"
    echo "  q) quit"
    printf "Selection [1/2/3/q]: "
    if ! read -r choice; then
      CONFIG_COLLISION_ACTION="abort"
      return 0
    fi

    case "${choice}" in
      1|overwrite)
        CONFIG_COLLISION_ACTION="overwrite"
        return 0
        ;;
      2|keep|original|originals)
        CONFIG_COLLISION_ACTION="keep"
        return 0
        ;;
      3|agent|prompt)
        CONFIG_COLLISION_ACTION="agent"
        return 0
        ;;
      q|Q|quit|exit)
        CONFIG_COLLISION_ACTION="abort"
        return 0
        ;;
      *)
        echo "Invalid selection."
        ;;
    esac
  done
}

stage_update_item() {
  local repo_rel="$1"
  local home_path="$2"
  local src="${repo_root}/${repo_rel}"
  local update_path
  update_path="$(timestamped_path "${home_path}" update)"

  if [[ "${dry_run}" -eq 0 ]]; then
    copy_tree "${src}" "${update_path}"
  fi
  echo "stage: ${update_path} <- ${src}"
}

install_copy_item() {
  local repo_rel="$1"
  local home_path="$2"
  local harness="${3:-}"
  local src="${repo_root}/${repo_rel}"

  if [[ ! -e "${src}" ]]; then
    echo "missing source: ${src}" >&2
    return 1
  fi

  if [[ ! -e "${home_path}" && ! -L "${home_path}" ]]; then
    if [[ "${dry_run}" -eq 0 ]]; then
      copy_tree "${src}" "${home_path}"
    fi
    echo "copy: ${home_path} <- ${src}"
    return 0
  fi

  if paths_equivalent_for_copy "${src}" "${home_path}"; then
    echo "ok: ${home_path}"
    return 0
  fi

  CONFIG_COLLISION_ACTION=""
  choose_path_conflict_action "${repo_rel}" "${home_path}"
  if [[ "${dry_run}" -eq 1 && -n "${harness}" ]]; then
    describe_user_config "${harness}" "${home_path}"
  fi
  case "${CONFIG_COLLISION_ACTION}" in
    overwrite)
      local original_path
      original_path="$(timestamped_path "${home_path}" original)"
      if [[ "${dry_run}" -eq 0 ]]; then
        mkdir -p "$(dirname "${original_path}")"
        mv "${home_path}" "${original_path}"
        copy_tree "${src}" "${home_path}"
      fi
      echo "backup: ${home_path} -> ${original_path}"
      echo "copy: ${home_path} <- ${src}"
      ;;
    keep)
      stage_update_item "${repo_rel}" "${home_path}"
      ;;
    agent)
      stage_update_item "${repo_rel}" "${home_path}"
      print_install_conflict_prompt "${repo_rel}" "${home_path}"
      ;;
    abort)
      echo "abort: install canceled by user" >&2
      exit 1
      ;;
  esac
}

install_link_item() {
  local repo_rel="$1"
  local home_path="$2"
  local src="${repo_root}/${repo_rel}"

  if [[ ! -e "${src}" ]]; then
    echo "missing source: ${src}" >&2
    return 1
  fi

  if [[ -L "${home_path}" ]]; then
    local current
    current="$(readlink "${home_path}")"
    if [[ "${current}" == "${src}" ]]; then
      echo "ok: ${home_path}"
      return 0
    fi
    case "${current}" in
      "${repo_root}"/*)
        if [[ "${dry_run}" -eq 0 ]]; then
          ln -sfn "${src}" "${home_path}"
        fi
        echo "relink: ${home_path} -> ${src}"
        return 0
        ;;
    esac
  fi

  if [[ ! -e "${home_path}" && ! -L "${home_path}" ]]; then
    if [[ "${dry_run}" -eq 0 ]]; then
      mkdir -p "$(dirname "${home_path}")"
      ln -s "${src}" "${home_path}"
    fi
    echo "link: ${home_path} -> ${src}"
    return 0
  fi

  CONFIG_COLLISION_ACTION=""
  choose_path_conflict_action "${repo_rel}" "${home_path}"
  case "${CONFIG_COLLISION_ACTION}" in
    overwrite)
      local original_path
      original_path="$(timestamped_path "${home_path}" original)"
      if [[ "${dry_run}" -eq 0 ]]; then
        mkdir -p "$(dirname "${original_path}")" "$(dirname "${home_path}")"
        mv "${home_path}" "${original_path}"
        ln -s "${src}" "${home_path}"
      fi
      echo "backup: ${home_path} -> ${original_path}"
      echo "link: ${home_path} -> ${src}"
      ;;
    keep)
      stage_update_item "${repo_rel}" "${home_path}"
      ;;
    agent)
      stage_update_item "${repo_rel}" "${home_path}"
      print_install_conflict_prompt "${repo_rel}" "${home_path}"
      ;;
    abort)
      echo "abort: install canceled by user" >&2
      exit 1
      ;;
  esac
}

link_item() {
  local repo_rel="$1"
  local home_path="$2"
  local src="${repo_root}/${repo_rel}"

  if [[ ! -e "${src}" ]]; then
    echo "missing source: ${src}" >&2
    return 1
  fi

  if [[ "${dry_run}" -eq 0 ]]; then
    mkdir -p "$(dirname "${home_path}")"
  fi

  if [[ -L "${home_path}" ]]; then
    local current
    current="$(readlink "${home_path}")"
    if [[ "${current}" == "${src}" ]]; then
      echo "ok: ${home_path}"
      return 0
    fi
    case "${current}" in
      "${repo_root}"/*)
        if [[ "${dry_run}" -eq 0 ]]; then
          ln -sfn "${src}" "${home_path}"
        fi
        echo "relink: ${home_path} -> ${src}"
        return 0
        ;;
    esac
  fi

  if [[ -e "${home_path}" || -L "${home_path}" ]]; then
    local backup_path
    backup_path="$(unique_backup_path "${home_path}")"
    if [[ "${dry_run}" -eq 0 ]]; then
      mkdir -p "$(dirname "${backup_path}")"
      mv "${home_path}" "${backup_path}"
    fi
    echo "backup: ${home_path} -> ${backup_path}"
  fi

  if [[ "${dry_run}" -eq 0 ]]; then
    ln -s "${src}" "${home_path}"
  fi
  echo "link: ${home_path} -> ${src}"
}

print_install_conflict_prompt() {
  local repo_rel="$1"
  local home_path="$2"
  local src="${repo_root}/${repo_rel}"

  echo ""
  echo "Agent merge prompt:"
  echo "-----"
  cat <<EOF
Resolve this harness install conflict.

Repo harness path:
  ${src}

Existing local path:
  ${home_path}

Default stance: preserve the existing local path as source of truth unless you can prove a repo change can be added without breaking local behavior.

Required first step: compute your own complete comparison of both paths. Do not rely on this prompt as an exhaustive conflict summary. For directories, inspect the full recursive file list and content diffs. For structured files, parse the format when possible instead of using only text matching.

Goal: preserve the user's existing local behavior while installing useful harness behavior from the repo.

Merge instructions:
- Keep local-only behavior by default.
- Add repo-only harness behavior only when it does not conflict with local behavior.
- If both sides edit the same setting, hook, rule, command, skill, or MCP/server entry, explain the conflict and stop for user choice.
- Do not delete, replace, or move the local path unless the user explicitly approves that exact action.
- Report the files changed and the conflicts left unresolved.
EOF
  echo "-----"
  echo ""
}

link_item_clean() {
  local repo_rel="$1"
  local home_path="$2"
  local src="${repo_root}/${repo_rel}"

  if [[ ! -e "${src}" ]]; then
    echo "missing source: ${src}" >&2
    return 1
  fi

  if [[ "${dry_run}" -eq 0 ]]; then
    mkdir -p "$(dirname "${home_path}")"
  fi

  if [[ -L "${home_path}" ]]; then
    local current
    current="$(readlink "${home_path}")"
    if [[ "${current}" == "${src}" ]]; then
      echo "ok: ${home_path}"
      return 0
    fi
    case "${current}" in
      "${repo_root}"/*)
        if [[ "${dry_run}" -eq 0 ]]; then
          ln -sfn "${src}" "${home_path}"
        fi
        echo "relink: ${home_path} -> ${src}"
        return 0
        ;;
    esac
  fi

  if [[ -e "${home_path}" || -L "${home_path}" ]]; then
    echo "conflict: ${home_path} already exists; not replacing it"
    print_install_conflict_prompt "${repo_rel}" "${home_path}"
    return 1
  fi

  if [[ "${dry_run}" -eq 0 ]]; then
    ln -s "${src}" "${home_path}"
  fi
  echo "link: ${home_path} -> ${src}"
}

export_user_config() {
  local harness="$1"
  local repo_rel="$2"
  local home_path="$3"
  local src="${repo_root}/${repo_rel}"

  if [[ -L "${home_path}" ]]; then
    local current
    current="$(readlink "${home_path}")"
    case "${current}" in
      "${src}"|"${repo_root}"/*)
      if [[ "${dry_run}" -eq 0 ]]; then
        rm "${home_path}"
        cp "${src}" "${home_path}"
      fi
      echo "copy: ${home_path} <- ${src} (converted from repo symlink)"
      return 0
      ;;
    esac
  fi

  install_copy_item "${repo_rel}" "${home_path}" "${harness}"
}

preflight_clean_item() {
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

  echo "conflict: ${home_path} already exists; not replacing it" >&2
  print_install_conflict_prompt "${repo_rel}" "${home_path}" >&2
  return 1
}

remove_repo_link() {
  local home_path="$1"

  if [[ ! -L "${home_path}" ]]; then
    return 0
  fi

  local current
  current="$(readlink "${home_path}")"
  case "${current}" in
    "${repo_root}"/*)
      local backup_path
      backup_path="$(unique_backup_path "${home_path}")"
      if [[ "${dry_run}" -eq 0 ]]; then
        mkdir -p "$(dirname "${backup_path}")"
        mv "${home_path}" "${backup_path}"
      fi
      echo "cleanup: ${home_path} -> ${backup_path}"
      ;;
  esac
}

describe_user_config() {
  local harness="$1"
  local home_path="$2"

  if [[ "${harness}" == "claude" ]]; then
    if command -v node >/dev/null 2>&1; then
      if node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "${home_path}" >/dev/null 2>&1; then
        echo "  parse: valid JSON"
      else
        echo "  parse: invalid JSON or non-JSON content"
      fi
    fi
    grep -E '"(permissions|hooks|mcpServers|enabledPlugins|extraKnownMarketplaces|model|statusLine)"[[:space:]]*:' "${home_path}" 2>/dev/null \
      | sed 's/^/  has: /' \
      | head -n 12 || true
    return 0
  fi

  echo "  parse: TOML not fully parsed by installer"
  grep -E '^[[:space:]]*(model|model_provider|approval_policy|sandbox_mode)[[:space:]]*=|^[[:space:]]*\[(mcp_servers|model_providers|profiles|features|hooks|projects|plugins)(\.|\])' "${home_path}" 2>/dev/null \
    | sed 's/^/  has: /' \
    | head -n 20 || true
}

print_agent_merge_prompt() {
  local harness="$1"
  local mode="$2"
  local repo_rel="$3"
  local home_path="$4"
  local src="${repo_root}/${repo_rel}"

  echo ""
  echo "Agent merge prompt:"
  echo "-----"
  sed \
    -e "s#{{SRC}}#${src}#g" \
    -e "s#{{HOME_PATH}}#${home_path}#g" \
    -e "s#{{MODE}}#${mode}#g" \
    -e "s#{{HARNESS}}#${harness}#g" \
    "${repo_root}/manifests/platform/prompts/install-root-config-merge.md"
  echo "-----"
  echo ""
}

confirm_choice() {
  local prompt="$1"
  local answer

  read -r -p "${prompt} [Y/n] " answer
  case "${answer}" in
    ""|y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

config_collision_action() {
  local harness="$1"
  local repo_rel="$2"
  local home_path="$3"
  local src="${repo_root}/${repo_rel}"
  local choice

  while true; do
    echo ""
    echo "User-owned ${harness} config exists:"
    echo "  local:   ${home_path}"
    echo "  harness: ${src}"
    echo ""
    describe_user_config "${harness}" "${home_path}"
    echo ""
    echo "Choose:"
    echo "  1) adopt         keep local root config; install only clean harness links"
    echo "  2) agent prompt  print merge prompt; leave root config unchanged"
    echo "  q) quit"
    read -r -p "Selection [1/2/q]: " choice

    case "${choice}" in
      1|adopt)
        echo ""
        echo "Keeping local ${home_path}. Harness defaults will not be installed for this file."
        print_agent_merge_prompt "${harness}" "adopt existing" "${repo_rel}" "${home_path}"
        if confirm_choice "Continue by adopting existing local config?"; then
          CONFIG_COLLISION_ACTION="adopt"
          return 0
        fi
        ;;
      2|agent|prompt)
        print_agent_merge_prompt "${harness}" "manual agent merge before install" "${repo_rel}" "${home_path}"
        if confirm_choice "Skip this root config export for now?"; then
          CONFIG_COLLISION_ACTION="agent"
          return 0
        fi
        ;;
      q|Q|quit|exit)
        CONFIG_COLLISION_ACTION="abort"
        return 0
        ;;
      *)
        echo "Invalid selection."
        ;;
    esac
  done
}

choose_config_collision_action() {
  local harness="$1"
  local repo_rel="$2"
  local home_path="$3"

  config_collision_action "${harness}" "${repo_rel}" "${home_path}"
}

choose_profile() {
  if [[ -n "${ROBOREPO_SHELL_PROFILE:-}" ]]; then
    echo "${ROBOREPO_SHELL_PROFILE}"
    return 0
  fi

  case "${SHELL:-}" in
    */zsh)
      echo "${HOME}/.zshrc"
      ;;
    */bash)
      if [[ -f "${HOME}/.bashrc" ]]; then
        echo "${HOME}/.bashrc"
      elif [[ -f "${HOME}/.bash_profile" ]]; then
        echo "${HOME}/.bash_profile"
      else
        echo "${HOME}/.bashrc"
      fi
      ;;
    *)
      if [[ -f "${HOME}/.profile" ]]; then
        echo "${HOME}/.profile"
      else
        echo "${HOME}/.zshrc"
      fi
      ;;
  esac
}
