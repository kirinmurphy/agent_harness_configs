#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failed=0
quiet=0
passed=0

# --quiet|-q : suppress per-check "ok:" lines; still print every failure + a summary.
for arg in "$@"; do
  case "${arg}" in
    --quiet|-q) quiet=1 ;;
    *) echo "usage: $0 [--quiet|-q]" >&2; exit 2 ;;
  esac
done

# shellcheck source=scripts/build/skill-lib.sh
source "${repo_root}/scripts/build/skill-lib.sh"
# shellcheck source=scripts/lib/manifests-data.sh
source "${repo_root}/scripts/lib/manifests-data.sh"

# Record a passing check. Honors --quiet (count always, print only when verbose).
pass_msg() {
  passed=$((passed + 1))
  [[ "${quiet}" -eq 1 ]] && return 0
  echo "ok: $*"
}

check_file_contains() {
  local path="$1"
  local pattern="$2"
  local label="$3"

  if grep -Eq "${pattern}" "${path}"; then
    pass_msg "${label}"
    return 0
  fi

  echo "fail: ${label}"
  failed=1
}

check_link() {
  local repo_rel="$1"
  local home_path="$2"
  local expected="${repo_root}/${repo_rel}"

  if [[ ! -L "${home_path}" ]]; then
    echo "fail: ${home_path} is not a symlink"
    failed=1
    return 0
  fi

  local actual
  actual="$(python3 - <<'PY' "${home_path}"
import os, sys
print(os.path.realpath(sys.argv[1]))
PY
)"
  if [[ "${actual}" != "${expected}" ]]; then
    echo "fail: ${home_path} -> ${actual}; expected ${expected}"
    failed=1
    return 0
  fi

  if [[ -f "${expected}" ]] && ! cmp -s "${home_path}" "${expected}"; then
    echo "fail: ${home_path} content differs from ${expected}"
    failed=1
    return 0
  fi

  pass_msg "${home_path} -> ${expected}"
}

check_active_file() {
  local home_path="$1"
  if [[ -f "${home_path}" && ! -L "${home_path}" ]]; then
    pass_msg "${home_path} is active local file"
  else
    echo "fail: ${home_path} is not an active local file"
    failed=1
  fi
}

# Managed links + root configs come from manifests/platform/manifest.tsv (single source of truth,
# shared with the installer/doctor/sync). link -> symlink check; root_config -> active
# local file; cleanup rows are not verified here (they only ever get pruned, not created).
while IFS=$'\t' read -r _harness kind src_rel home_abs _flags; do
  case "${kind}" in
    link)        check_link "${src_rel}" "${home_abs}" ;;
    root_config) check_active_file "${home_abs}" ;;
  esac
done < <(manifest_rows)

# Only Claude links skills per-skill (~/.claude/skills/<n> is its own symlink). Codex uses
# the whole-dir ~/.agents/skills symlink to globals/agents/skills, verified above; the <n>
# inside is the real source dir, not a link, so it is NOT checked per skill here.
while IFS= read -r skill_name; do
  [[ -n "${skill_name}" ]] || continue
  check_link "globals/agents/skills/${skill_name}" "${HOME}/.claude/skills/${skill_name}"
done < <(list_source_skills "${repo_root}/globals/agents/skills")
check_link "bin/roborepo" "${HOME}/.local/bin/roborepo"

if command -v node >/dev/null 2>&1; then
  node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "${HOME}/.codex/hooks.json"
  node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "${HOME}/.claude/settings.json"
  pass_msg "JSON config parses"
else
  echo "skip: node not found, JSON parse check not run"
fi

while IFS=$'\t' read -r home_abs pattern label; do
  check_file_contains "${home_abs}" "${pattern}" "${label}"
done < <(verify_content_rows)

doctor_args=(--installed)
[[ "${quiet}" -eq 1 ]] && doctor_args+=(--quiet)
"${repo_root}/scripts/doctor.sh" "${doctor_args[@]}"

if command -v uvx >/dev/null 2>&1; then
  pass_msg "uvx available for jcodemunch MCP"
else
  echo "fail: uvx not found; jcodemunch MCP command cannot start"
  failed=1
fi

if [[ "${failed}" -ne 0 ]]; then
  echo "verify failed (${passed} checks passed, see fail: lines above)" >&2
  exit 1
fi

echo "verify passed (${passed} checks)"
