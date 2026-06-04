#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failed=0
check_installed=0

case "${1:-}" in
  --installed)
    check_installed=1
    ;;
  "")
    ;;
  *)
    echo "usage: $0 [--installed]" >&2
    exit 2
    ;;
esac

ok() {
  echo "ok: $*"
}

fail() {
  echo "fail: $*" >&2
  failed=1
}

check_file() {
  [[ -e "${repo_root}/$1" ]] && ok "$1 exists" || fail "$1 missing"
}

check_json() {
  local path="${repo_root}/$1"
  if command -v node >/dev/null 2>&1; then
    node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "${path}" >/dev/null && ok "$1 parses" || fail "$1 invalid JSON"
  else
    ok "node unavailable; skipped $1 parse"
  fi
}

check_toml() {
  local path="${repo_root}/$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "${path}" <<'PY' >/dev/null && ok "$1 parses" || fail "$1 invalid TOML"
import sys
try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib
with open(sys.argv[1], "rb") as f:
    tomllib.load(f)
PY
  else
    ok "python3 unavailable; skipped $1 parse"
  fi
}

check_link() {
  local repo_rel="$1"
  local home_path="$2"
  local expected="${repo_root}/${repo_rel}"

  if [[ ! -L "${home_path}" ]]; then
    fail "${home_path} is not a symlink"
    return 0
  fi

  local actual
  actual="$(python3 - <<'PY' "${home_path}"
import os, sys
print(os.path.realpath(sys.argv[1]))
PY
)"
  [[ "${actual}" == "${expected}" ]] && ok "${home_path} -> ${expected}" || fail "${home_path} -> ${actual}; expected ${expected}"
}

check_repo_symlink() {
  local path="$1"
  local expected="$2"
  local actual="${repo_root}/${path}"

  if [[ ! -L "${actual}" ]]; then
    fail "${path} is not a symlink"
    return 0
  fi

  local target
  target="$(readlink "${actual}")"
  [[ "${target}" == "${expected}" ]] && ok "${path} -> ${expected}" || fail "${path} -> ${target}; expected ${expected}"
}

# Verify the `roborepo` command actually resolves on PATH — not just that the symlink exists.
# This catches the case (common on Windows/PowerShell, or before a new shell is opened) where
# ~/.local/bin/roborepo is installed but ~/.local/bin is not yet on PATH. Does not set `failed`
# on its own: a missing symlink is already a fail above; here we only guide the user to PATH.
check_roborepo_on_path() {
  local bin_dir="${HOME}/.local/bin"
  if command -v roborepo >/dev/null 2>&1; then
    ok "roborepo resolves on PATH ($(command -v roborepo))"
    return 0
  fi
  # Symlink present but not callable -> PATH problem, not an install problem.
  if [[ -e "${bin_dir}/roborepo" || -L "${bin_dir}/roborepo" ]]; then
    echo "warn: roborepo is installed at ${bin_dir}/roborepo but is not on PATH yet."
    echo "      Add ${bin_dir} to PATH, then open a new shell:"
    echo "        export PATH=\"\${HOME}/.local/bin:\${PATH}\"   # bash/zsh"
    echo "      (Windows PowerShell: add ${bin_dir} via System Environment Variables or"
    echo "       \$PROFILE, then restart the shell. Re-run 'roborepo doctor' to confirm.)"
  else
    fail "roborepo not found on PATH and no symlink at ${bin_dir}/roborepo — run roborepo install"
  fi
}

# The "what is a skill folder" rule is implemented twice — list_source_skills (skill-lib.sh)
# and listSourceSkills (skill-lib.mjs). Parity is the whole point of this repo, so verify the
# two agree on skills/ rather than letting them drift silently.
check_skill_lib_parity() {
  if ! command -v node >/dev/null 2>&1; then
    ok "node unavailable; skipped skill-lib parity check"
    return 0
  fi
  local bash_out node_out
  bash_out="$(
    source "${repo_root}/scripts/skill-lib.sh"
    list_source_skills "${repo_root}/skills" | sort
  )"
  node_out="$(node -e '
    const [mod, dir] = process.argv.slice(1);
    import(mod).then((m) => console.log(m.listSourceSkills(dir).sort().join("\n")));
  ' "${repo_root}/scripts/skill-lib.mjs" "${repo_root}/skills" 2>/dev/null)"
  if [[ "${bash_out}" == "${node_out}" ]]; then
    ok "skill-lib.sh and skill-lib.mjs agree on skills/"
  else
    fail "skill-lib parity: bash and node disagree on skills/ (diff below)"
    diff <(echo "${bash_out}") <(echo "${node_out}") >&2 || true
  fi
}

check_file "codex/AGENTS.md"
check_file "codex/config.toml"
check_file "codex/hooks.json"
check_file "codex/rules/default.rules"
check_file "scripts/render-rules.sh"
check_file "rules/shared/00-communication.md"
check_file "rules/shared/10-exploration.md"
check_file "rules/shared/20-verification.md"
check_file "rules/shared/30-session-capture.md"
check_file "rules/claude/90-claude-specific.md"
check_file "rules/codex/90-codex-specific.md"
# Derive the shared-skill list from skills/*/SKILL.md so this never goes stale.
# Each skill must have a per-harness symlink in claude/ and codex/.
for skill_src in "${repo_root}"/skills/*/SKILL.md; do
  [[ -e "${skill_src}" ]] || continue
  skill_name="$(basename "$(dirname "${skill_src}")")"
  check_file "skills/${skill_name}/SKILL.md"
  check_repo_symlink "claude/skills/${skill_name}" "../../skills/${skill_name}"
  check_repo_symlink "codex/skills/${skill_name}" "../../skills/${skill_name}"
done
# Internal (repo-only) skills: source in skills-local/, linked into THIS repo's project-scope
# dotdirs (.claude/skills, .codex/skills) — never global, never exported.
for skill_src in "${repo_root}"/skills-local/*/SKILL.md; do
  [[ -e "${skill_src}" ]] || continue
  skill_name="$(basename "$(dirname "${skill_src}")")"
  check_file "skills-local/${skill_name}/SKILL.md"
  check_repo_symlink ".claude/skills/${skill_name}" "../../skills-local/${skill_name}"
  check_repo_symlink ".codex/skills/${skill_name}" "../../skills-local/${skill_name}"
done
check_file "bin/roborepo"
check_file "scripts/skill-lib.sh"
check_file "scripts/skill-lib.mjs"
check_file "scripts/roborepo.mjs"
check_file "scripts/test-roborepo.sh"
check_file "scripts/normalize-claude-settings.mjs"
check_skill_lib_parity
check_json "codex/hooks.json"
check_json "claude/settings.json"
check_toml "codex/config.toml"

if command -v uvx >/dev/null 2>&1; then
  ok "uvx available"
else
  fail "uvx missing"
fi

if command -v node >/dev/null 2>&1; then
  node "${repo_root}/scripts/normalize-claude-settings.mjs" --check "${repo_root}/claude/settings.json" >/dev/null \
    && ok "claude/settings.json hook schema valid" \
    || fail "claude/settings.json hook schema invalid"
else
  ok "node unavailable; skipped Claude hook schema check"
fi

"${repo_root}/scripts/render-rules.sh" --check || failed=1

if [[ "${check_installed}" -eq 1 ]]; then
  check_link "skills/test-harness" "${HOME}/.codex/skills/test-harness"
  check_link "skills/technical-planning-docs" "${HOME}/.codex/skills/technical-planning-docs"
  check_link "skills/frontend-design" "${HOME}/.codex/skills/frontend-design"
  check_link "skills/code-style" "${HOME}/.codex/skills/code-style"
  check_link "skills/react" "${HOME}/.codex/skills/react"
  check_link "skills/javascript-typescript" "${HOME}/.codex/skills/javascript-typescript"
  check_link "skills/supabase-integration-testing" "${HOME}/.codex/skills/supabase-integration-testing"
  check_link "skills/test-harness" "${HOME}/.claude/skills/test-harness"
  check_link "skills/technical-planning-docs" "${HOME}/.claude/skills/technical-planning-docs"
  check_link "skills/frontend-design" "${HOME}/.claude/skills/frontend-design"
  check_link "skills/code-style" "${HOME}/.claude/skills/code-style"
  check_link "skills/react" "${HOME}/.claude/skills/react"
  check_link "skills/javascript-typescript" "${HOME}/.claude/skills/javascript-typescript"
  check_link "skills/supabase-integration-testing" "${HOME}/.claude/skills/supabase-integration-testing"
  check_link "codex/AGENTS.md" "${HOME}/.codex/AGENTS.md"
  check_link "codex/config.toml" "${HOME}/.codex/config.toml"
  check_link "codex/hooks.json" "${HOME}/.codex/hooks.json"
  check_link "codex/rules" "${HOME}/.codex/rules"
  check_link "codex/skills" "${HOME}/.codex/skills"
  check_link "claude/CLAUDE.md" "${HOME}/.claude/CLAUDE.md"
  check_link "claude/settings.json" "${HOME}/.claude/settings.json"
  check_link "claude/hooks" "${HOME}/.claude/hooks"
  check_link "claude/skills" "${HOME}/.claude/skills"
  check_link "bin/roborepo" "${HOME}/.local/bin/roborepo"
  check_roborepo_on_path
fi

if [[ "${failed}" -ne 0 ]]; then
  echo "doctor failed" >&2
  exit 1
fi

echo "doctor passed"
