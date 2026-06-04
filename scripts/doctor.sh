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
check_file "bin/harness-run"
check_file "bin/jcmwatch"
check_file "bin/jcmindex"
check_file "bin/harness_helper"
check_file "bin/harness-install-local-skills"
check_file "scripts/skill-lib.sh"
check_file "scripts/skill-lib.mjs"
check_file "scripts/harness_helper.mjs"
check_file "scripts/install-local-skills.mjs"
check_file "scripts/normalize-claude-settings.mjs"
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
  check_link "bin/jcmwatch" "${HOME}/.local/bin/jcmwatch"
  check_link "bin/jcmindex" "${HOME}/.local/bin/jcmindex"
  check_link "bin/harness-run" "${HOME}/.local/bin/harness-run"
  check_link "bin/harness_helper" "${HOME}/.local/bin/harness_helper"
  check_link "bin/harness-install-local-skills" "${HOME}/.local/bin/harness-install-local-skills"
fi

if [[ "${failed}" -ne 0 ]]; then
  echo "doctor failed" >&2
  exit 1
fi

echo "doctor passed"
