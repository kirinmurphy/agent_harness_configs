#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bin_dir="${HOME}/.local/bin"
path_line='export PATH="${HOME}/.local/bin:${PATH}"'
backup_root="${HOME}/.harness-configs-backups/$(date +%Y%m%d-%H%M%S)"

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    echo "Windows shell detected. This installer manages POSIX shells only." >&2
    echo "Use WSL, Git Bash, or add this repo's bin directory to PATH manually:" >&2
    echo "  ${repo_root}/bin" >&2
    exit 1
    ;;
esac

choose_profile() {
  if [[ -n "${HARNESS_CONFIG_SHELL_PROFILE:-}" ]]; then
    echo "${HARNESS_CONFIG_SHELL_PROFILE}"
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

mkdir -p "${bin_dir}"

link_command() {
  local name="$1"
  local target="${bin_dir}/${name}"
  local source_path="${repo_root}/bin/${name}"

  if [[ -e "${target}" || -L "${target}" ]]; then
    current="$(readlink "${target}" 2>/dev/null || true)"
    if [[ "${current}" != "${source_path}" ]]; then
      mkdir -p "${backup_root}${bin_dir}"
      mv "${target}" "${backup_root}${target}"
      echo "backup: ${target} -> ${backup_root}${target}"
    else
      echo "ok: ${target}"
    fi
  fi

  if [[ ! -L "${target}" ]]; then
    ln -s "${source_path}" "${target}"
    echo "link: ${target} -> ${source_path}"
  fi
}

link_command "jcmwatch"
link_command "jcmindex"
link_command "jdmindex"
link_command "harness-run"

profile_path="$(choose_profile)"
touch "${profile_path}"

if ! grep -Fqx "${path_line}" "${profile_path}"; then
  mkdir -p "${backup_root}$(dirname "${profile_path}")"
  cp -p "${profile_path}" "${backup_root}${profile_path}"
  printf '\n# Harness config global commands\n%s\n' "${path_line}" >> "${profile_path}"
  echo "backup: ${profile_path} -> ${backup_root}${profile_path}"
  echo "path: ${path_line}"
else
  echo "ok: ${profile_path} already includes ${bin_dir}"
fi
