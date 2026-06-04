#!/usr/bin/env bash
set -euo pipefail

# Functional smoke tests for roborepo (skill export/link, run, lifecycle dispatch).
# Runs subcommands against throwaway temp repos and asserts on results. The consumer-facing
# subcommands operate on a target repo dir and never touch ~/.claude / ~/.codex.
#
# Usage: scripts/test-roborepo.sh

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cli="${repo_root}/scripts/roborepo.mjs"
pass=0
fail=0

work="$(mktemp -d "${TMPDIR:-/tmp}/roborepo-test.XXXXXX")"
trap 'rm -rf "${work}"' EXIT

assert() {
  local label="$1"; shift
  if "$@"; then
    echo "ok: ${label}"
    pass=$((pass + 1))
  else
    echo "FAIL: ${label}" >&2
    fail=$((fail + 1))
  fi
}

mk_skill() {
  local dir="$1" name="$2"
  mkdir -p "${dir}/${name}"
  printf -- '---\nname: %s\ndescription: test\n---\n' "${name}" > "${dir}/${name}/SKILL.md"
}

# ---------------------------------------------------------------------------
# roborepo skill link
# ---------------------------------------------------------------------------
local_repo="${work}/local"
mk_skill "${local_repo}/skills" "app-deploy"
mk_skill "${local_repo}/skills" "app-test"

( cd "${local_repo}" && node "${cli}" skill link >/dev/null )
assert "skill link: .claude link created" test -L "${local_repo}/.claude/skills/app-deploy"
assert "skill link: .codex link created"  test -L "${local_repo}/.codex/skills/app-test"
assert "skill link: link is relative to source" \
  test "$(readlink "${local_repo}/.claude/skills/app-deploy")" = "../../skills/app-deploy"

rerun="$( cd "${local_repo}" && node "${cli}" skill link )"
assert "skill link: idempotent re-run reports already ok" \
  bash -c "echo '${rerun}' | grep -q 'already ok'"

# Prune: delete a source skill, re-run, stale links removed.
rm -rf "${local_repo}/skills/app-test"
( cd "${local_repo}" && node "${cli}" skill link >/dev/null )
assert "skill link: orphan .claude link pruned" \
  bash -c "! test -e '${local_repo}/.claude/skills/app-test'"
assert "skill link: orphan .codex link pruned" \
  bash -c "! test -e '${local_repo}/.codex/skills/app-test'"
assert "skill link: live link kept after prune" test -L "${local_repo}/.claude/skills/app-deploy"

# Uninstall: removes only owned links.
( cd "${local_repo}" && node "${cli}" skill link --uninstall >/dev/null )
assert "skill link: uninstall removes owned links" \
  bash -c "! test -e '${local_repo}/.claude/skills/app-deploy'"

# Conflict: a real (non-symlink) dir at the target is never clobbered.
conflict_repo="${work}/conflict"
mk_skill "${conflict_repo}/skills" "app-deploy"
mkdir -p "${conflict_repo}/.claude/skills/app-deploy"
echo "REAL" > "${conflict_repo}/.claude/skills/app-deploy/marker"
( cd "${conflict_repo}" && node "${cli}" skill link >/dev/null 2>&1 ) || true
assert "skill link: real dir at target left intact (conflict)" \
  test -f "${conflict_repo}/.claude/skills/app-deploy/marker"

# Missing skills/ dir: clear error, non-zero exit.
empty_repo="${work}/empty"
mkdir -p "${empty_repo}"
assert "skill link: missing skills/ exits non-zero" \
  bash -c "cd '${empty_repo}' && ! node '${cli}' skill link >/dev/null 2>&1"

# ---------------------------------------------------------------------------
# roborepo skill export
# ---------------------------------------------------------------------------
export_repo="${work}/export"
mkdir -p "${export_repo}"
( cd "${export_repo}" && node "${cli}" skill export --yes >/dev/null )
assert "skill export: .claude/skills created and populated" \
  test -f "${export_repo}/.claude/skills/test-harness/SKILL.md"
assert "skill export: shareable zip produced" \
  bash -c "ls '${export_repo}'/global_agent_skills_*.zip >/dev/null 2>&1"
if command -v unzip >/dev/null 2>&1; then
  assert "skill export: zip integrity (unzip -t)" \
    bash -c "unzip -tq '${export_repo}'/global_agent_skills_*.zip >/dev/null"
fi

( cd "${export_repo}" && node "${cli}" skill export --yes --on-conflict=override >/dev/null )
assert "skill export: override moves old skill to archived/" \
  bash -c "ls '${export_repo}'/.claude/skills/archived/test-harness_backup_* >/dev/null 2>&1"

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
# roborepo lifecycle dispatch (doctor + install --dry-run, both read-only)
# ---------------------------------------------------------------------------
assert "lifecycle: roborepo doctor dispatches and passes" \
  bash -c "node '${cli}' doctor >/dev/null 2>&1"
assert "lifecycle: roborepo install --dry-run dispatches (no changes)" \
  bash -c "node '${cli}' install --dry-run >/dev/null 2>&1"

# ---------------------------------------------------------------------------
# roborepo menu (numbered fallback via pipe)
# ---------------------------------------------------------------------------
# Capture to a file and grep the file — output contains apostrophes/parens that would break
# quoting if interpolated into `bash -c`.
menu_out="${work}/menu.txt"
printf '\n' | node "${cli}" > "${menu_out}" 2>&1 || true
assert "menu: shows Setup section header" grep -q "Setup" "${menu_out}"
assert "menu: shows Day to day section header" grep -q "Day to day" "${menu_out}"
assert "menu: numbers actions but not headers (install is 1)" grep -qE "1\) install" "${menu_out}"
assert "menu: items have descriptions" grep -q "health check" "${menu_out}"
assert "menu: numbered fallback cancels on out-of-range/blank" \
  bash -c "printf '99\n' | node '${cli}' 2>&1 | grep -q 'cancelled'"

# ---------------------------------------------------------------------------
# install-global-commands.sh PATH wiring (isolated via a fake HOME under the temp dir,
# never touching the real ~). Verifies: profile chosen by SHELL, PATH line appended once,
# and the unknown-shell branch warns instead of writing a profile the shell won't read.
# ---------------------------------------------------------------------------
igc="${repo_root}/scripts/install-global-commands.sh"

# zsh: writes ~/.zshrc (created if missing) with the PATH line.
zhome="${work}/home-zsh"
mkdir -p "${zhome}"
SHELL=/bin/zsh HOME="${zhome}" HARNESS_CONFIG_SHELL_PROFILE="" bash "${igc}" >/dev/null 2>&1 || true
assert "install: zsh profile gets PATH line" \
  bash -c "grep -q '.local/bin' '${zhome}/.zshrc'"

# Re-run is idempotent: the PATH line is not duplicated.
SHELL=/bin/zsh HOME="${zhome}" HARNESS_CONFIG_SHELL_PROFILE="" bash "${igc}" >/dev/null 2>&1 || true
assert "install: PATH line not duplicated on re-run" \
  bash -c "test \"\$(grep -c 'export PATH=\"\${HOME}/.local/bin' '${zhome}/.zshrc')\" = 1"

# bash: the PATH line lands in the file the current OS's login/interactive shell actually reads —
# ~/.bash_profile on macOS, ~/.bashrc on Linux. Test the OS-appropriate target.
bhome="${work}/home-bash"
mkdir -p "${bhome}"
if [[ "$(uname -s)" == "Darwin" ]]; then bash_profile="${bhome}/.bash_profile"; else bash_profile="${bhome}/.bashrc"; fi
SHELL=/bin/bash HOME="${bhome}" HARNESS_CONFIG_SHELL_PROFILE="" bash "${igc}" >/dev/null 2>&1 || true
assert "install: bash PATH line lands in the OS-correct profile" \
  grep -q ".local/bin" "${bash_profile}"

# Unknown shell (fish) with no ~/.profile: warn + don't write a profile file.
fhome="${work}/home-fish"
mkdir -p "${fhome}"
fish_out="${work}/fish.txt"
SHELL=/usr/bin/fish HOME="${fhome}" HARNESS_CONFIG_SHELL_PROFILE="" bash "${igc}" > "${fish_out}" 2>&1 || true
assert "install: unknown shell warns instead of guessing" \
  grep -qi "could not determine a shell profile" "${fish_out}"
assert "install: unknown shell does not create ~/.zshrc" \
  bash -c "! test -e '${fhome}/.zshrc'"

# ---------------------------------------------------------------------------
# Prune passes: a prior install left stale ~/.local/bin command symlinks and stale ~/.zshrc
# `source` lines for removed helpers. Re-running the installers should remove them, and never
# touch roborepo or unrelated entries. Isolated via a fake HOME.
# ---------------------------------------------------------------------------
phome="${work}/home-prune"
mkdir -p "${phome}/.local/bin"
# Stale managed command symlinks (point into this repo's bin/, removed from managed set).
ln -s "${repo_root}/bin/jcmindex" "${phome}/.local/bin/jcmindex"
ln -s "${repo_root}/bin/jcmwatch" "${phome}/.local/bin/jcmwatch"
# An unrelated symlink that must NOT be pruned (points outside this repo).
ln -s /usr/bin/true "${phome}/.local/bin/some-other-tool"
SHELL=/bin/zsh HOME="${phome}" HARNESS_CONFIG_SHELL_PROFILE="" bash "${igc}" >/dev/null 2>&1 || true
assert "prune: stale jcmindex symlink removed" \
  bash -c "! test -e '${phome}/.local/bin/jcmindex'"
assert "prune: stale jcmwatch symlink removed" \
  bash -c "! test -e '${phome}/.local/bin/jcmwatch'"
assert "prune: roborepo symlink kept" \
  test -L "${phome}/.local/bin/roborepo"
assert "prune: unrelated symlink left intact" \
  test -L "${phome}/.local/bin/some-other-tool"

# Stale ~/.zshrc snippet source lines for removed helpers.
iss="${repo_root}/scripts/install-shell-snippets.sh"
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

# ---------------------------------------------------------------------------
echo ""
echo "roborepo tests: ${pass} passed, ${fail} failed"
[[ "${fail}" -eq 0 ]]
