#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=scripts/skill-lib.sh
source "${repo_root}/scripts/skill-lib.sh"  # provides list_source_skills (used below)

failed=0
check_installed=0
quiet=0
passed=0

# Flags may appear in any order:
#   --installed  also check the global ~/.claude and ~/.codex install links
#   --quiet|-q   suppress per-check "ok:" lines; still print every failure + a summary
for arg in "$@"; do
  case "${arg}" in
    --installed) check_installed=1 ;;
    --quiet|-q)  quiet=1 ;;
    *)
      echo "usage: $0 [--installed] [--quiet|-q]" >&2
      exit 2
      ;;
  esac
done

ok() {
  passed=$((passed + 1))
  [[ "${quiet}" -eq 1 ]] && return 0
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

check_active_file() {
  local home_path="$1"
  if [[ -f "${home_path}" && ! -L "${home_path}" ]]; then
    ok "${home_path} is active local file"
  else
    fail "${home_path} is not an active local file"
  fi
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
    fail "roborepo not found on PATH and no symlink at ${bin_dir}/roborepo — run scripts/install/main.sh"
  fi
}

# The "what is a skill folder" rule is implemented twice — list_source_skills (skill-lib.sh)
# and listSourceSkills (skill-lib.mjs). Parity is the whole point of this repo, so verify the
# two agree on agents/skills/ rather than letting them drift silently.
check_skill_lib_parity() {
  if ! command -v node >/dev/null 2>&1; then
    ok "node unavailable; skipped skill-lib parity check"
    return 0
  fi
  local bash_out node_out
  bash_out="$(
    source "${repo_root}/scripts/skill-lib.sh"
    list_source_skills "${repo_root}/agents/skills" | sort
  )"
  node_out="$(node -e '
    const [mod, dir] = process.argv.slice(1);
    import(mod).then((m) => console.log(m.listSourceSkills(dir).sort().join("\n")));
  ' "${repo_root}/scripts/cli/skill-lib.mjs" "${repo_root}/agents/skills" 2>/dev/null)"
  if [[ "${bash_out}" == "${node_out}" ]]; then
    ok "skill-lib.sh and skill-lib.mjs agree on agents/skills/"
  else
    fail "skill-lib parity: bash and node disagree on agents/skills/ (diff below)"
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
# Derive the shared-skill list from agents/skills/*/SKILL.md so this never goes stale.
# Claude gets a per-skill symlink (claude/skills/<n> -> ../../agents/skills/<n>). Codex has
# NO per-skill intermediate: it reads ~/.agents/skills -> agents/skills directly.
for skill_src in "${repo_root}"/agents/skills/*/SKILL.md; do
  [[ -e "${skill_src}" ]] || continue
  skill_name="$(basename "$(dirname "${skill_src}")")"
  check_file "agents/skills/${skill_name}/SKILL.md"
  check_repo_symlink "claude/skills/${skill_name}" "../../agents/skills/${skill_name}"
done
# Internal (repo-only) skills: source in skills-local/, linked into THIS repo's project-scope
# dotdirs (.claude/skills, .agents/skills) — never global, never exported.
for skill_src in "${repo_root}"/skills-local/*/SKILL.md; do
  [[ -e "${skill_src}" ]] || continue
  skill_name="$(basename "$(dirname "${skill_src}")")"
  check_file "skills-local/${skill_name}/SKILL.md"
  check_repo_symlink ".claude/skills/${skill_name}" "../../skills-local/${skill_name}"
  check_repo_symlink ".agents/skills/${skill_name}" "../../skills-local/${skill_name}"
done
check_file "bin/roborepo"
check_file "scripts/skill-lib.sh"
check_file "scripts/cli/skill-lib.mjs"
check_file "scripts/cli/main.mjs"
check_file "scripts/test/test-roborepo.sh"
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

# Sub-script checks. In quiet mode swallow their normal stdout but keep failures (stderr)
# and the non-zero exit. link-skills.sh --check is the source of truth for per-skill link
# integrity; calling it here keeps doctor from drifting against the linker.
if [[ "${quiet}" -eq 1 ]]; then
  "${repo_root}/scripts/render-rules.sh" --check >/dev/null || failed=1
  "${repo_root}/scripts/link-skills.sh" --check >/dev/null || failed=1
else
  "${repo_root}/scripts/render-rules.sh" --check || failed=1
  "${repo_root}/scripts/link-skills.sh" --check || failed=1
fi

if [[ "${check_installed}" -eq 1 ]]; then
  # Claude links each skill individually (claude/skills/<n> -> agents/skills/<n>), so each
  # ~/.claude/skills/<n> is its own symlink and is checked per skill. Codex has NO per-skill
  # links — ~/.agents/skills and ~/.codex/skills are whole-dir symlinks to agents/skills, and
  # <n> inside them is the real source dir. Those are verified at the dir level below.
  while IFS= read -r skill_name; do
    [[ -n "${skill_name}" ]] || continue
    check_link "agents/skills/${skill_name}" "${HOME}/.claude/skills/${skill_name}"
  done < <(list_source_skills "${repo_root}/agents/skills")
  check_link "codex/AGENTS.md" "${HOME}/.codex/AGENTS.md"
  check_active_file "${HOME}/.codex/config.toml"
  check_link "codex/hooks.json" "${HOME}/.codex/hooks.json"
  check_link "codex/rules" "${HOME}/.codex/rules"
  check_link "agents/skills" "${HOME}/.agents/skills"
  check_link "agents/skills" "${HOME}/.codex/skills"
  check_link "claude/CLAUDE.md" "${HOME}/.claude/CLAUDE.md"
  check_active_file "${HOME}/.claude/settings.json"
  check_link "claude/hooks" "${HOME}/.claude/hooks"
  check_link "claude/skills" "${HOME}/.claude/skills"
  check_link "bin/roborepo" "${HOME}/.local/bin/roborepo"
  check_roborepo_on_path
fi

if [[ "${failed}" -ne 0 ]]; then
  echo "doctor failed (${passed} checks passed, see fail: lines above)" >&2
  exit 1
fi

echo "doctor passed (${passed} checks)"
