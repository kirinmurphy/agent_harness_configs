#!/usr/bin/env bash
set -euo pipefail

# Functional smoke tests for roborepo (skill export/link/sync, rules, run, lifecycle dispatch).
# Runs subcommands against throwaway temp repos and asserts on results. The consumer-facing
# subcommands operate on a target repo dir and never touch ~/.claude / ~/.codex.
#
# Usage: scripts/test/test-roborepo.sh

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cli="${repo_root}/scripts/cli/main.mjs"
pass=0
fail=0
quiet=0

# --quiet|-q : suppress per-test "ok:" lines; still print every FAIL + the summary.
for arg in "$@"; do
  case "${arg}" in
    --quiet|-q) quiet=1 ;;
    *) echo "usage: $0 [--quiet|-q]" >&2; exit 2 ;;
  esac
done

work="$(mktemp -d "${TMPDIR:-/tmp}/roborepo-test.XXXXXX")"
trap 'rm -rf "${work}"' EXIT

assert() {
  local label="$1"; shift
  if "$@"; then
    [[ "${quiet}" -eq 0 ]] && echo "ok: ${label}"
    pass=$((pass + 1))
  else
    echo "FAIL: ${label}" >&2
    fail=$((fail + 1))
  fi
}

assert "source layout: globals shared skills exist" test -d "${repo_root}/globals/agents/skills"
assert "source layout: globals Claude source exists" test -d "${repo_root}/globals/claude"
assert "source layout: globals Codex source exists" test -d "${repo_root}/globals/codex"
assert "source layout: globals Codex commands exist" test -d "${repo_root}/globals/codex/commands"
assert "source layout: local internal skills exist" test -d "${repo_root}/local/skills"
assert "source layout: legacy agents root absent" bash -c "! test -e '${repo_root}/agents'"
assert "source layout: legacy claude root absent" bash -c "! test -e '${repo_root}/claude'"
assert "source layout: legacy codex root absent" bash -c "! test -e '${repo_root}/codex'"
assert "source layout: legacy skills-local root absent" bash -c "! test -e '${repo_root}/skills-local'"

mk_skill() {
  local dir="$1" name="$2"
  mkdir -p "${dir}/${name}"
  printf -- '---\nname: %s\ndescription: test\n---\n' "${name}" > "${dir}/${name}/SKILL.md"
}

# ---------------------------------------------------------------------------
# roborepo skill install / link
# ---------------------------------------------------------------------------
local_repo="${work}/local"
mkdir -p "${local_repo}/.claude" "${local_repo}/.codex"
mk_skill "${local_repo}/.agents/skills" "app-deploy"
mk_skill "${local_repo}/.agents/skills" "app-test"

( cd "${local_repo}" && node "${cli}" skill install >/dev/null )
assert "skill install: .claude link created" test -L "${local_repo}/.claude/skills/app-deploy"
assert "skill install: .codex link created"  test -L "${local_repo}/.codex/skills/app-test"
assert "skill install: link is relative to source" \
  test "$(readlink "${local_repo}/.claude/skills/app-deploy")" = "../../.agents/skills/app-deploy"

rerun="$( cd "${local_repo}" && node "${cli}" skill install )"
assert "skill install: idempotent re-run reports already ok" \
  bash -c "echo '${rerun}' | grep -q 'already ok'"

# Prune: delete a source skill, re-run, stale links removed.
rm -rf "${local_repo}/.agents/skills/app-test"
( cd "${local_repo}" && node "${cli}" skill install >/dev/null )
assert "skill install: orphan .claude link pruned" \
  bash -c "! test -e '${local_repo}/.claude/skills/app-test'"
assert "skill install: orphan .codex link pruned" \
  bash -c "! test -e '${local_repo}/.codex/skills/app-test'"
assert "skill install: live link kept after prune" test -L "${local_repo}/.claude/skills/app-deploy"

# Uninstall: removes only owned links.
( cd "${local_repo}" && node "${cli}" skill install --uninstall >/dev/null )
assert "skill install: uninstall removes owned links" \
  bash -c "! test -e '${local_repo}/.claude/skills/app-deploy'"

# Dry-run: reports planned links without creating harness skill dirs.
dry_repo="${work}/dry-link"
mkdir -p "${dry_repo}/.claude" "${dry_repo}/.codex"
mk_skill "${dry_repo}/.agents/skills" "app-deploy"
( cd "${dry_repo}" && node "${cli}" skill install --dry-run >/dev/null )
assert "skill install: dry-run does not create .claude link" \
  bash -c "! test -e '${dry_repo}/.claude/skills/app-deploy'"
assert "skill install: dry-run does not create .codex link" \
  bash -c "! test -e '${dry_repo}/.codex/skills/app-deploy'"

no_agent_repo="${work}/no-agent-target"
mk_skill "${no_agent_repo}/.agents/skills" "app-deploy"
( cd "${no_agent_repo}" && node "${cli}" skill install >/dev/null )
assert "skill install: skips .claude when .claude root is absent" \
  bash -c "! test -e '${no_agent_repo}/.claude/skills/app-deploy'"
assert "skill install: skips .codex when .codex root is absent" \
  bash -c "! test -e '${no_agent_repo}/.codex/skills/app-deploy'"

# Conflict: a real (non-symlink) dir at the target is never clobbered.
conflict_repo="${work}/conflict"
mk_skill "${conflict_repo}/.agents/skills" "app-deploy"
mkdir -p "${conflict_repo}/.claude/skills/app-deploy"
echo "REAL" > "${conflict_repo}/.claude/skills/app-deploy/marker"
( cd "${conflict_repo}" && node "${cli}" skill install >/dev/null 2>&1 ) || true
assert "skill install: real dir at target left intact (conflict)" \
  test -f "${conflict_repo}/.claude/skills/app-deploy/marker"

foreign_repo="${work}/foreign-link"
mk_skill "${foreign_repo}/.agents/skills" "app-deploy"
mkdir -p "${foreign_repo}/elsewhere" "${foreign_repo}/.codex/skills"
ln -s "../../elsewhere/app-deploy" "${foreign_repo}/.codex/skills/app-deploy"
( cd "${foreign_repo}" && node "${cli}" skill install --uninstall >/dev/null 2>&1 ) || true
assert "skill install: uninstall leaves foreign symlink intact" \
  test "$(readlink "${foreign_repo}/.codex/skills/app-deploy")" = "../../elsewhere/app-deploy"

# Missing .agents/skills dir: clear error, non-zero exit.
empty_repo="${work}/empty"
mkdir -p "${empty_repo}"
assert "skill install: missing .agents exits non-zero" \
  bash -c "cd '${empty_repo}' && ! node '${cli}' skill install >/dev/null 2>&1"

empty_agents_repo="${work}/empty-agents"
mkdir -p "${empty_agents_repo}/.agents"
assert "skill install: missing .agents/skills exits non-zero" \
  bash -c "cd '${empty_agents_repo}' && ! node '${cli}' skill install >/dev/null 2>&1"

assert "skill link: compatibility alias works" \
  bash -c "cd '${local_repo}' && node '${cli}' skill link >/dev/null"

assert "skill link: unknown flag rejected" \
  bash -c "cd '${local_repo}' && ! node '${cli}' skill link --nonsense >/dev/null 2>&1"

assert "skill sync: check dispatches link-skills verifier" \
  bash -c "cd '${repo_root}' && node '${cli}' skill sync --check >/dev/null"

assert "skill commands: check dispatches generated command verifier" \
  bash -c "cd '${repo_root}' && node '${cli}' skill commands --check >/dev/null"
assert "skill commands: generated Claude wrapper exists" \
  grep -q 'Use the `technical-planning-docs` skill' "${repo_root}/globals/claude/commands/technical-planning.md"
assert "skill commands: generated Codex wrapper uses agents skill path" \
  grep -q '~/.agents/skills/technical-planning-docs/SKILL.md' "${repo_root}/globals/codex/commands/technical-planning.md"
assert "skill commands: capture observer has no slash command" \
  bash -c "! test -e '${repo_root}/globals/claude/commands/capture-convention.md'"
assert "skill commands: capture observer absent from Codex commands" \
  bash -c "! test -e '${repo_root}/globals/codex/commands/capture-convention.md'"
assert "skill commands: implicit helper did not get command wrapper" \
  bash -c "! test -e '${repo_root}/globals/claude/commands/javascript-typescript.md'"

# skill new: scaffold shared skills/commands against a throwaway harness root, never this repo.
new_harness="${work}/new-harness"
mkdir -p \
  "${new_harness}/scripts/cli" \
  "${new_harness}/scripts/build" \
  "${new_harness}/manifests" \
  "${new_harness}/globals/agents/skills" \
  "${new_harness}/globals/claude/skills" \
  "${new_harness}/globals/claude/commands" \
  "${new_harness}/globals/codex/commands" \
  "${new_harness}/local/skills"
cp "${repo_root}"/scripts/cli/*.mjs "${new_harness}/scripts/cli/"
cp "${repo_root}/scripts/build/link-skills.sh" "${new_harness}/scripts/build/link-skills.sh"
cp "${repo_root}/scripts/build/skill-lib.sh" "${new_harness}/scripts/build/skill-lib.sh"
cp "${repo_root}/scripts/build/render-slash-commands.mjs" "${new_harness}/scripts/build/render-slash-commands.mjs"
printf '{"skills":[]}\n' > "${new_harness}/manifests/skill-invocation.json"
printf '{"commands":[]}\n' > "${new_harness}/manifests/slash-commands.json"
cp "${repo_root}/manifests/cli-commands.json" "${new_harness}/manifests/cli-commands.json"
cp "${repo_root}/manifests/mcp-presets.json" "${new_harness}/manifests/mcp-presets.json"
cat > "${new_harness}/README.md" <<'EOF_README'
# Test Harness

### Automatic Helpers

##### Repo

| | |
| --- | --- |

### Commands

| | | |
| --- | --- | --- |
EOF_README

( cd "${work}" && node "${new_harness}/scripts/cli/main.mjs" skill new --kind=auto --name=demo-helper --description="Demo helper workflow." --category=repo >/dev/null )
assert "skill new: auto helper creates skill" \
  test -f "${new_harness}/globals/agents/skills/demo-helper/SKILL.md"
assert "skill new: auto helper updates policy manifest" \
  grep -q '"explicit_command": false' "${new_harness}/manifests/skill-invocation.json"
assert "skill new: auto helper updates README Automatic Helpers" \
  grep -q 'demo-helper' "${new_harness}/README.md"

( cd "${work}" && node "${new_harness}/scripts/cli/main.mjs" skill new --kind=skill-command --name=demo-plan --command=demo-plan --description="Demo planning workflow." --risk=medium >/dev/null )
assert "skill new: skill-command creates command wrapper" \
  grep -q 'Use the `demo-plan` skill' "${new_harness}/globals/claude/commands/demo-plan.md"
assert "skill new: skill-command updates slash manifest" \
  grep -q '"kind": "skill-backed"' "${new_harness}/manifests/slash-commands.json"

( cd "${work}" && node "${new_harness}/scripts/cli/main.mjs" skill new --kind=standalone --name=demo-command --description="Demo command workflow." --harnesses=claude >/dev/null )
assert "skill new: standalone creates shared command source" \
  test -f "${new_harness}/globals/commands/demo-command.md"
assert "skill new: standalone renders selected harness only" \
  bash -c "test -f '${new_harness}/globals/claude/commands/demo-command.md' && ! test -e '${new_harness}/globals/codex/commands/demo-command.md'"

# ---------------------------------------------------------------------------
# roborepo skill export
# ---------------------------------------------------------------------------
export_repo="${work}/export"
mkdir -p "${export_repo}"
( cd "${export_repo}" && node "${cli}" skill export --yes >/dev/null )
assert "skill export: .claude/skills created and populated" \
  test -f "${export_repo}/.claude/skills/test-harness/SKILL.md"
assert "skill export: fresh repo creates .agents/skills for Codex" \
  test -f "${export_repo}/.agents/skills/test-harness/SKILL.md"
assert "skill export: shareable zip produced" \
  bash -c "ls '${export_repo}'/global_agent_skills_*.zip >/dev/null 2>&1"
if command -v unzip >/dev/null 2>&1; then
  assert "skill export: zip integrity (unzip -t)" \
    bash -c "unzip -tq '${export_repo}'/global_agent_skills_*.zip >/dev/null"
fi

( cd "${export_repo}" && node "${cli}" skill export --yes --on-conflict=override >/dev/null )
assert "skill export: override moves old skill to archived/" \
  bash -c "ls '${export_repo}'/.claude/skills/archived/test-harness_backup_* >/dev/null 2>&1"

skip_repo="${work}/export-skip"
mkdir -p "${skip_repo}/.claude/skills/test-harness" "${skip_repo}/.agents/skills"
echo "LOCAL" > "${skip_repo}/.claude/skills/test-harness/local.txt"
( cd "${skip_repo}" && node "${cli}" skill export --yes --on-conflict=skip >/dev/null )
assert "skill export: skip preserves existing skill content" \
  grep -q "LOCAL" "${skip_repo}/.claude/skills/test-harness/local.txt"
assert "skill export: existing .agents/skills is populated" \
  test -f "${skip_repo}/.agents/skills/test-harness/SKILL.md"
assert "skill export: invalid on-conflict rejected" \
  bash -c "cd '${skip_repo}' && ! node '${cli}' skill export --yes --on-conflict=merge >/dev/null 2>&1"

claude_only_repo="${work}/export-claude-only"
mkdir -p "${claude_only_repo}/.claude/skills"
( cd "${claude_only_repo}" && node "${cli}" skill export --yes >/dev/null )
assert "skill export: creates .agents/skills even when only .claude exists" \
  test -f "${claude_only_repo}/.agents/skills/test-harness/SKILL.md"

assert "skill export: internal skill NOT exported (firewall)" \
  bash -c "! test -e '${export_repo}/.claude/skills/harness-platform-dev'"

assert "skill export: refuses to run in source repo" \
  bash -c "cd '${repo_root}' && ! node '${cli}' skill export --yes >/dev/null 2>&1"

assert "skill export: unknown flag rejected" \
  bash -c "cd '${export_repo}' && ! node '${cli}' skill export --yes --nonsense >/dev/null 2>&1"

# ---------------------------------------------------------------------------
# roborepo run
# ---------------------------------------------------------------------------
assert "run: success exits 0" \
  bash -c "node '${cli}' run true >/dev/null"
assert "run: failure propagates non-zero exit" \
  bash -c "! node '${cli}' run false >/dev/null 2>&1"
assert "run: no command exits non-zero" \
  bash -c "! node '${cli}' run >/dev/null 2>&1"

# ---------------------------------------------------------------------------
# roborepo mcp add
# ---------------------------------------------------------------------------
mcp_jdoc="$( node "${cli}" mcp add jdocmunch --dry-run )"
assert "mcp add: jdocmunch preset maps to Claude user-scope uvx command" \
  test "${mcp_jdoc}" = $'claude mcp add --scope user jdocmunch -- uvx jdocmunch-mcp\nwould add permission: mcp__jdocmunch -> globals/claude/settings.json\ncodex MCP already present: jdocmunch'

mcp_jcode="$( node "${cli}" mcp add jcodemunch --dry-run )"
assert "mcp add: jcodemunch preset maps to Claude user-scope uvx command" \
  test "${mcp_jcode}" = $'claude mcp add --scope user jcodemunch -- uvx jcodemunch-mcp\nwould add permission: mcp__jcodemunch -> globals/claude/settings.json\ncodex MCP already present: jcodemunch'

mcp_alias="$( node "${cli}" addMCP jdocmunch --dry-run )"
assert "mcp add: addMCP alias maps to same command" \
  test "${mcp_alias}" = "${mcp_jdoc}"

mcp_pkg="$( node "${cli}" mcp add example-mcp --name=example --dry-run -- --flag value )"
assert "mcp add: generic package supports name override and passthrough args" \
  test "${mcp_pkg}" = $'claude mcp add --scope user example -- uvx example-mcp --flag value\nwould add permission: mcp__example -> globals/claude/settings.json\nwould add Codex MCP: example -> globals/codex/config.toml\n[mcp_servers.example]\ncommand = "uvx"\nargs = ["example-mcp", "--flag", "value"]'

mcp_url="$( node "${cli}" mcp add https://mcp.example.com/mcp --name=example --dry-run )"
assert "mcp add: URL defaults to http transport" \
  test "${mcp_url}" = $'claude mcp add --scope user --transport http example https://mcp.example.com/mcp\nwould add permission: mcp__example -> globals/claude/settings.json\nwould add Codex MCP: example -> globals/codex/config.toml\n[mcp_servers.example]\nurl = "https://mcp.example.com/mcp"'

mcp_skip_permission="$( node "${cli}" mcp add jdocmunch --dry-run --skip-claude-permission )"
assert "mcp add: --skip-claude-permission skips settings update" \
  test "${mcp_skip_permission}" = $'claude mcp add --scope user jdocmunch -- uvx jdocmunch-mcp\ncodex MCP already present: jdocmunch'

mcp_only_claude="$( node "${cli}" mcp add jdocmunch --dry-run --only-claude )"
assert "mcp add: --only-claude skips Codex config update" \
  test "${mcp_only_claude}" = $'claude mcp add --scope user jdocmunch -- uvx jdocmunch-mcp\nwould add permission: mcp__jdocmunch -> globals/claude/settings.json'

mcp_only_codex="$( node "${cli}" mcp add jdocmunch --dry-run --only-codex )"
assert "mcp add: --only-codex skips Claude registration and settings update" \
  test "${mcp_only_codex}" = "codex MCP already present: jdocmunch"

assert "mcp add: only flags are mutually exclusive" \
  bash -c "! node '${cli}' mcp add jdocmunch --only-claude --only-codex --dry-run >/dev/null 2>&1"

assert "mcp add: invalid scope rejected" \
  bash -c "! node '${cli}' mcp add jdocmunch --scope=team --dry-run >/dev/null 2>&1"

assert "mcp add: invalid transport rejected" \
  bash -c "! node '${cli}' mcp add https://mcp.example.com/mcp --transport=websocket --dry-run >/dev/null 2>&1"

# Real write tests run against a throwaway harness root. roborepo derives repoRoot from
# scripts/cli/paths.mjs (two levels up), so copying scripts/cli/ (which holds the entry main.mjs
# plus every module) lets us test writes without touching this repo. main.mjs imports every
# cli/ module at load time.
mcp_harness="${work}/mcp-harness"
mkdir -p "${mcp_harness}/scripts/cli" "${mcp_harness}/globals/codex" "${mcp_harness}/globals/claude" "${mcp_harness}/manifests"
cp "${repo_root}"/scripts/cli/*.mjs "${mcp_harness}/scripts/cli/"
cp "${repo_root}/manifests/mcp-presets.json" "${mcp_harness}/manifests/mcp-presets.json"
cp "${repo_root}/manifests/cli-commands.json" "${mcp_harness}/manifests/cli-commands.json"
printf '[features]\nhooks = true\n' > "${mcp_harness}/globals/codex/config.toml"
printf '{"permissions":{"allow":["Read"]}}\n' > "${mcp_harness}/globals/claude/settings.json"

( cd "${work}" && node "${mcp_harness}/scripts/cli/main.mjs" mcp add https://mcp.example.com/mcp --name=example --only-codex >/dev/null )
assert "mcp add: writes Codex HTTP url block" \
  grep -q 'url = "https://mcp.example.com/mcp"' "${mcp_harness}/globals/codex/config.toml"

( cd "${work}" && node "${mcp_harness}/scripts/cli/main.mjs" mcp add example-mcp --name=stdio-example --only-codex -- --flag value >/dev/null )
assert "mcp add: writes Codex stdio command block" \
  grep -q 'command = "uvx"' "${mcp_harness}/globals/codex/config.toml"
assert "mcp add: writes Codex stdio args block" \
  grep -q 'args = \["example-mcp", "--flag", "value"\]' "${mcp_harness}/globals/codex/config.toml"

( cd "${work}" && node "${mcp_harness}/scripts/cli/main.mjs" mcp add https://mcp.example.com/mcp --name=example --only-codex >/dev/null )
assert "mcp add: Codex write is idempotent" \
  bash -c "test \"\$(grep -c '^\\[mcp_servers.example\\]' '${mcp_harness}/globals/codex/config.toml')\" = 1"

fake_bin="${work}/fake-bin"
mkdir -p "${fake_bin}"
{
  printf '#!/usr/bin/env bash\n'
  printf 'printf "%%s\\n" "$*" > "%s"\n' "${work}/fake-claude-args.txt"
} > "${fake_bin}/claude"
chmod +x "${fake_bin}/claude"
( cd "${work}" && PATH="${fake_bin}:${PATH}" node "${mcp_harness}/scripts/cli/main.mjs" mcp add perm-mcp --name=permtest --only-claude >/dev/null )
assert "mcp add: Claude registration command invoked" \
  grep -q 'mcp add --scope user permtest -- uvx perm-mcp' "${work}/fake-claude-args.txt"
assert "mcp add: Claude permission written after successful registration" \
  grep -q '"mcp__permtest"' "${mcp_harness}/globals/claude/settings.json"

( cd "${work}" && PATH="${fake_bin}:${PATH}" node "${mcp_harness}/scripts/cli/main.mjs" mcp add all-mcp --name=alltest -- --all-flag >/dev/null )
assert "mcp add: default target invokes Claude registration" \
  grep -q 'mcp add --scope user alltest -- uvx all-mcp --all-flag' "${work}/fake-claude-args.txt"
assert "mcp add: default target writes Claude permission" \
  grep -q '"mcp__alltest"' "${mcp_harness}/globals/claude/settings.json"
assert "mcp add: default target writes Codex config" \
  grep -q 'args = \["all-mcp", "--all-flag"\]' "${mcp_harness}/globals/codex/config.toml"

{
  printf '#!/usr/bin/env bash\n'
  printf 'exit 37\n'
} > "${fake_bin}/claude"
chmod +x "${fake_bin}/claude"
assert "mcp add: Claude registration failure exits non-zero" \
  bash -c "cd '${work}' && ! env PATH='${fake_bin}':\"\${PATH}\" node '${mcp_harness}/scripts/cli/main.mjs' mcp add fail-mcp --name=failtest >/dev/null 2>&1"
assert "mcp add: Claude failure does not write permission" \
  bash -c "! grep -q '\"mcp__failtest\"' '${mcp_harness}/globals/claude/settings.json'"
assert "mcp add: Claude failure does not write Codex config" \
  bash -c "! grep -q '^\\[mcp_servers.failtest\\]' '${mcp_harness}/globals/codex/config.toml'"

# ---------------------------------------------------------------------------
# roborepo lifecycle dispatch (doctor + update --dry-run, both read-only)
# ---------------------------------------------------------------------------
update_home="${work}/update-home"
mkdir -p "${update_home}/.claude" "${update_home}/.codex" "${update_home}/.agents"
cp "${repo_root}/globals/claude/settings.json" "${update_home}/.claude/settings.json"
cp "${repo_root}/globals/codex/config.toml" "${update_home}/.codex/config.toml"
ln -s "${repo_root}/globals/claude/CLAUDE.md" "${update_home}/.claude/CLAUDE.md"
ln -s "${repo_root}/globals/claude/MANAGED_BY_ROBOREPO.md" "${update_home}/.claude/MANAGED_BY_ROBOREPO.md"
ln -s "${repo_root}/globals/claude/commands" "${update_home}/.claude/commands"
ln -s "${repo_root}/globals/claude/hooks" "${update_home}/.claude/hooks"
ln -s "${repo_root}/globals/claude/skills" "${update_home}/.claude/skills"
ln -s "${repo_root}/globals/codex/AGENTS.md" "${update_home}/.codex/AGENTS.md"
ln -s "${repo_root}/globals/codex/commands" "${update_home}/.codex/commands"
ln -s "${repo_root}/globals/codex/hooks.json" "${update_home}/.codex/hooks.json"
ln -s "${repo_root}/globals/codex/MANAGED_BY_ROBOREPO.md" "${update_home}/.codex/MANAGED_BY_ROBOREPO.md"
ln -s "${repo_root}/globals/codex/rules" "${update_home}/.codex/rules"
ln -s "${repo_root}/globals/agents/skills" "${update_home}/.agents/skills"
# ~/.codex/skills intentionally NOT pre-linked — it is no longer managed (Codex owns it).

assert "lifecycle: roborepo doctor dispatches and passes" \
  bash -c "node '${cli}' doctor >/dev/null 2>&1"
assert "lifecycle: roborepo update --dry-run dispatches (no changes)" \
  bash -c "HOME='${update_home}' node '${cli}' update --dry-run >/dev/null 2>&1"
assert "lifecycle: roborepo install verb removed (first install is the shell bootstrap)" \
  bash -c "! node '${cli}' install --dry-run >/dev/null 2>&1"
assert "lifecycle: roborepo verify dispatches and exits non-zero when not installed" \
  bash -c "! HOME='${work}/not-installed-home' node '${cli}' verify >/dev/null 2>&1"
assert "lifecycle: roborepo rules --check dispatches render verifier" \
  bash -c "cd '${repo_root}' && node '${cli}' rules --check >/dev/null"

# ---------------------------------------------------------------------------
# roborepo menu (numbered fallback via pipe)
# ---------------------------------------------------------------------------
# Capture to a file and grep the file — output contains apostrophes/parens that would break
# quoting if interpolated into `bash -c`.
menu_out="${work}/menu.txt"
printf '\n' | node "${cli}" > "${menu_out}" 2>&1 || true
assert "menu: shows Setup section header" grep -q "Setup" "${menu_out}"
assert "menu: shows Day to day section header" grep -q "Day to day" "${menu_out}"
assert "menu: numbers actions but not headers (update is 1)" grep -qE "1\) update" "${menu_out}"
assert "menu: items have descriptions" grep -q "health check" "${menu_out}"
assert "menu: numbered fallback cancels on out-of-range/blank" \
  bash -c "printf '99\n' | node '${cli}' 2>&1 | grep -q 'cancelled'"

# ---------------------------------------------------------------------------
# install-global-commands.sh PATH wiring (isolated via a fake HOME under the temp dir,
# never touching the real ~). Verifies: profile chosen by SHELL, PATH line appended once,
# and the unknown-shell branch warns instead of writing a profile the shell won't read.
# ---------------------------------------------------------------------------
igc="${repo_root}/scripts/install/install-global-commands.sh"

# zsh: writes ~/.zshrc (created if missing) with the PATH line.
zhome="${work}/home-zsh"
mkdir -p "${zhome}"
SHELL=/bin/zsh HOME="${zhome}" ROBOREPO_SHELL_PROFILE="" bash "${igc}" >/dev/null 2>&1 || true
assert "install: zsh profile gets PATH line" \
  bash -c "grep -q '.local/bin' '${zhome}/.zshrc'"

# Re-run is idempotent: the PATH line is not duplicated.
SHELL=/bin/zsh HOME="${zhome}" ROBOREPO_SHELL_PROFILE="" bash "${igc}" >/dev/null 2>&1 || true
assert "install: PATH line not duplicated on re-run" \
  bash -c "test \"\$(grep -c 'export PATH=\"\${HOME}/.local/bin' '${zhome}/.zshrc')\" = 1"

# bash: the PATH line lands in the file the current OS's login/interactive shell actually reads —
# ~/.bash_profile on macOS, ~/.bashrc on Linux. Test the OS-appropriate target.
bhome="${work}/home-bash"
mkdir -p "${bhome}"
if [[ "$(uname -s)" == "Darwin" ]]; then bash_profile="${bhome}/.bash_profile"; else bash_profile="${bhome}/.bashrc"; fi
SHELL=/bin/bash HOME="${bhome}" ROBOREPO_SHELL_PROFILE="" bash "${igc}" >/dev/null 2>&1 || true
assert "install: bash PATH line lands in the OS-correct profile" \
  grep -q ".local/bin" "${bash_profile}"

# Unknown shell (fish) with no ~/.profile: warn + don't write a profile file.
fhome="${work}/home-fish"
mkdir -p "${fhome}"
fish_out="${work}/fish.txt"
SHELL=/usr/bin/fish HOME="${fhome}" ROBOREPO_SHELL_PROFILE="" bash "${igc}" > "${fish_out}" 2>&1 || true
assert "install: unknown shell warns instead of guessing" \
  grep -qi "could not determine a shell profile" "${fish_out}"
assert "install: unknown shell does not create ~/.zshrc" \
  bash -c "! test -e '${fhome}/.zshrc'"

# ---------------------------------------------------------------------------
# Prune pass: a prior install left stale ~/.zshrc `source` lines for removed shell helpers.
# Re-running install-shell-snippets.sh should remove them and preserve the user's own content.
# Isolated via a fake HOME.
# ---------------------------------------------------------------------------
# Stale ~/.zshrc snippet source lines for removed helpers.
iss="${repo_root}/scripts/install/install-shell-snippets.sh"
shome="${work}/home-snip"
mkdir -p "${shome}"
{
  echo "# my own stuff"
  echo "alias ll='ls -la'"
  echo ""
  echo "# Harness config shell helpers"
  echo "source \"${repo_root}/shell/jcodemunch.zsh\""
  echo ""
  echo "# Harness config shell helpers"
  echo "source \"${repo_root}/shell/jdocmunch.zsh\""
} > "${shome}/.zshrc"
HOME="${shome}" bash "${iss}" >/dev/null 2>&1 || true
assert "prune: stale jcodemunch.zsh source line removed" \
  bash -c "! grep -q 'shell/jcodemunch.zsh' '${shome}/.zshrc'"
assert "prune: stale jdocmunch.zsh source line removed" \
  bash -c "! grep -q 'shell/jdocmunch.zsh' '${shome}/.zshrc'"
assert "prune: user's own .zshrc content preserved" \
  grep -q "alias ll='ls -la'" "${shome}/.zshrc"

empty_shome="${work}/home-empty-snip"
mkdir -p "${empty_shome}"
HOME="${empty_shome}" bash "${iss}" >/dev/null 2>&1 || true
assert "snippets: no configured snippets does not create ~/.zshrc" \
  bash -c "! test -e '${empty_shome}/.zshrc'"

# ---------------------------------------------------------------------------
echo ""
echo "roborepo tests: ${pass} passed, ${fail} failed"
[[ "${fail}" -eq 0 ]]
