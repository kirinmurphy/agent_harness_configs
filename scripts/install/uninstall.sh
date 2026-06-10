#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
dry_run=0

case "${1:-}" in
  --dry-run) dry_run=1 ;;
  "") ;;
  *) echo "usage: $0 [--dry-run]" >&2; exit 2 ;;
esac

# shellcheck source=scripts/lib/manifests-data.sh
source "${repo_root}/scripts/lib/manifests-data.sh"
# shellcheck source=scripts/install/state-lib.sh
source "${repo_root}/scripts/install/state-lib.sh"

remove_repo_symlink() {
  local path="$1"
  [[ -L "${path}" ]] || return 0

  local current
  current="$(readlink "${path}")"
  case "${current}" in
    "${repo_root}"/*)
      if [[ "${dry_run}" -eq 1 ]]; then
        echo "unlink: ${path}"
      else
        rm "${path}"
        echo "unlink: ${path}"
      fi
      ;;
  esac
}

remove_file_if_repo_symlink() {
  local path="$1"
  local expected="$2"
  [[ -L "${path}" ]] || return 0
  [[ "$(readlink "${path}")" == "${expected}" ]] || return 0

  if [[ "${dry_run}" -eq 1 ]]; then
    echo "unlink: ${path}"
  else
    rm "${path}"
    echo "unlink: ${path}"
  fi
}

remove_shell_wiring() {
  local profile line tmp
  line='export PATH="${HOME}/.local/bin:${PATH}"'

  for profile in "${HOME}/.zshrc" "${HOME}/.bashrc" "${HOME}/.bash_profile" "${HOME}/.profile"; do
    [[ -f "${profile}" ]] || continue
    if grep -Fq "${repo_root}/shell/" "${profile}" || grep -Fqx "${line}" "${profile}"; then
      if [[ "${dry_run}" -eq 1 ]]; then
        echo "prune: would remove roborepo shell wiring from ${profile}"
        continue
      fi
      tmp="$(mktemp "${TMPDIR:-/tmp}/roborepo-profile.XXXXXX")"
      awk -v repo_root="${repo_root}" -v path_line="${line}" '
        $0 == path_line { next }
        index($0, "source \"" repo_root "/shell/") == 1 { next }
        $0 == "# Harness config shell helpers" { held = $0; next }
        {
          if (held != "") { print held; held = "" }
          print
        }
        END { if (held != "") print held }
      ' "${profile}" > "${tmp}"
      mv "${tmp}" "${profile}"
      echo "prune: removed roborepo shell wiring from ${profile}"
    fi
  done
}

while IFS=$'\t' read -r _h kind _src_rel home_abs _flags; do
  case "${kind}" in
    link|cleanup) remove_repo_symlink "${home_abs}" ;;
  esac
done < <(manifest_rows)

remove_file_if_repo_symlink "${HOME}/.local/bin/roborepo" "${repo_root}/bin/roborepo"
remove_shell_wiring

state_file="$(roborepo_state_file)"
if [[ -f "${state_file}" ]]; then
  if [[ "${dry_run}" -eq 1 ]]; then
    echo "remove: ${state_file}"
  else
    rm "${state_file}"
    echo "remove: ${state_file}"
  fi
fi

echo "Uninstall complete. Local root configs and adopted copied files were left in place."
