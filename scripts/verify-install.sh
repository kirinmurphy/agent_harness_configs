#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failed=0

check_file_contains() {
  local path="$1"
  local pattern="$2"
  local label="$3"

  if grep -Eq "${pattern}" "${path}"; then
    echo "ok: ${label}"
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

  echo "ok: ${home_path} -> ${expected}"
}

check_link "codex/AGENTS.md" "${HOME}/.codex/AGENTS.md"
check_link "codex/config.toml" "${HOME}/.codex/config.toml"
check_link "codex/hooks.json" "${HOME}/.codex/hooks.json"
check_link "codex/MANAGED_BY_HARNESS_CONFIGS.md" "${HOME}/.codex/MANAGED_BY_HARNESS_CONFIGS.md"
check_link "codex/rules" "${HOME}/.codex/rules"
check_link "codex/skills" "${HOME}/.codex/skills"

check_link "claude/CLAUDE.md" "${HOME}/.claude/CLAUDE.md"
check_link "claude/settings.json" "${HOME}/.claude/settings.json"
check_link "claude/MANAGED_BY_HARNESS_CONFIGS.md" "${HOME}/.claude/MANAGED_BY_HARNESS_CONFIGS.md"
check_link "claude/commands" "${HOME}/.claude/commands"
check_link "claude/hooks" "${HOME}/.claude/hooks"
check_link "claude/skills" "${HOME}/.claude/skills"
check_link "claude/plugins/blocklist.json" "${HOME}/.claude/plugins/blocklist.json"

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
check_link "bin/jcmwatch" "${HOME}/.local/bin/jcmwatch"
check_link "bin/jcmindex" "${HOME}/.local/bin/jcmindex"
check_link "bin/harness-run" "${HOME}/.local/bin/harness-run"
check_link "bin/harness_helper" "${HOME}/.local/bin/harness_helper"
check_link "bin/harness-install-local-skills" "${HOME}/.local/bin/harness-install-local-skills"

if command -v node >/dev/null 2>&1; then
  node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "${HOME}/.codex/hooks.json"
  node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "${HOME}/.claude/settings.json"
  echo "ok: JSON config parses"
else
  echo "skip: node not found, JSON parse check not run"
fi

check_file_contains "${HOME}/.codex/config.toml" '^[[:space:]]*hooks[[:space:]]*=[[:space:]]*true[[:space:]]*$' "Codex hooks feature enabled"
check_file_contains "${HOME}/.codex/hooks.json" 'CAVEMAN MODE ACTIVE' "Codex caveman startup hook configured"
check_file_contains "${HOME}/.codex/AGENTS.md" 'Use caveman full by default' "Codex AGENTS caveman default configured"
check_file_contains "${HOME}/.codex/config.toml" '^\[mcp_servers\.jcodemunch\]$' "Codex jcodemunch MCP configured"
check_file_contains "${HOME}/.codex/config.toml" '^[[:space:]]*args[[:space:]]*=[[:space:]]*\["jcodemunch-mcp"\][[:space:]]*$' "Codex jcodemunch MCP args configured"
check_file_contains "${HOME}/.codex/AGENTS.md" 'Verified: <command> -> <pass\|fail\|blocked>' "Codex verification receipt configured"

"${repo_root}/scripts/doctor.sh" --installed

if command -v uvx >/dev/null 2>&1; then
  echo "ok: uvx available for jcodemunch MCP"
else
  echo "fail: uvx not found; jcodemunch MCP command cannot start"
  failed=1
fi

if [[ "${failed}" -ne 0 ]]; then
  echo "verify failed"
  exit 1
fi

echo "verify passed"
