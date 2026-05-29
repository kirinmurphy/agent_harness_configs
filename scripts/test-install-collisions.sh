#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pass() {
  echo "ok: $1"
}

fail() {
  echo "FAIL: $1" >&2
  if [[ $# -gt 1 && -f "$2" ]]; then
    sed -n '1,160p' "$2" >&2
  fi
  exit 1
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"
  local label="$3"

  grep -qE "$pattern" "$file" && pass "$label" || fail "$label" "$file"
}

assert_file_not_contains() {
  local file="$1"
  local pattern="$2"
  local label="$3"

  if grep -qE "$pattern" "$file"; then
    fail "$label" "$file"
  fi
  pass "$label"
}

assert_symlink_target() {
  local link_path="$1"
  local target="$2"
  local label="$3"

  [[ -L "$link_path" && "$(readlink "$link_path")" == "$target" ]] && pass "$label" || fail "$label"
}

make_home() {
  local tmp
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/.claude" "$tmp/.codex"
  echo "$tmp"
}

seed_user_configs() {
  local home_dir="$1"
  printf '{"model":"opus","permissions":{"allow":["Bash(foo)"]}}\n' > "$home_dir/.claude/settings.json"
  printf 'model = "o3"\n[profiles.personal]\nmodel = "gpt-5"\n[mcp_servers.personal]\ncommand = "foo"\n' > "$home_dir/.codex/config.toml"
}

run_expect_install() {
  local home_dir="$1"
  local output="$2"
  local script="$3"

  command -v expect >/dev/null 2>&1 || fail "expect is required for interactive installer tests"
  HC_REPO="$repo_root" HC_HOME="$home_dir" HC_EXPECT_SCRIPT="$script" expect <<'EOF' >"$output" 2>&1
set timeout 20
spawn env HOME=$env(HC_HOME) $env(HC_REPO)/scripts/install-symlinks.sh
source $env(HC_EXPECT_SCRIPT)
expect eof
set wait_result [wait]
set exit_code [lindex $wait_result 3]
exit $exit_code
EOF
}

test_fresh_managed() {
  local home_dir
  home_dir="$(make_home)"

  HOME="$home_dir" "$repo_root/scripts/install-symlinks.sh" >"$home_dir/out"

  assert_symlink_target "$home_dir/.claude/settings.json" "$repo_root/claude/settings.json" "fresh Claude config symlink"
  assert_symlink_target "$home_dir/.codex/config.toml" "$repo_root/codex/config.toml" "fresh Codex config symlink"
}

test_dry_run_collision_no_mutation() {
  local home_dir
  home_dir="$(make_home)"
  seed_user_configs "$home_dir"

  HOME="$home_dir" "$repo_root/scripts/install-symlinks.sh" --dry-run >"$home_dir/out"

  assert_file_contains "$home_dir/out" "collision: $home_dir/.claude/settings.json" "dry-run reports Claude collision"
  assert_file_contains "$home_dir/out" "adopt existing config or print agent merge prompt" "dry-run describes only safe root config choices"
  assert_file_not_contains "$home_dir/out" "managed.*backup local config" "dry-run does not offer managed replacement"
  assert_file_contains "$home_dir/out" "\[mcp_servers.personal\]" "dry-run reports personal Codex MCP"
  assert_file_contains "$home_dir/out" "\[profiles.personal\]" "dry-run reports personal Codex profile"
  [[ ! -L "$home_dir/.claude/settings.json" && ! -L "$home_dir/.codex/config.toml" ]] && pass "dry-run leaves config files untouched" || fail "dry-run leaves config files untouched"
  [[ ! -e "$home_dir/.harness-configs-backups" ]] && pass "dry-run creates no backups" || fail "dry-run creates no backups"
}

test_noninteractive_block_no_mutation() {
  local home_dir
  home_dir="$(make_home)"
  seed_user_configs "$home_dir"

  if HOME="$home_dir" "$repo_root/scripts/install-symlinks.sh" >"$home_dir/out" 2>&1; then
    fail "noninteractive collision blocks install" "$home_dir/out"
  fi

  assert_file_contains "$home_dir/out" "stdin is not interactive" "noninteractive collision explains failure"
  [[ ! -e "$home_dir/.claude/CLAUDE.md" && ! -e "$home_dir/.codex/AGENTS.md" ]] && pass "noninteractive block prevents partial install" || fail "noninteractive block prevents partial install"
}

test_non_root_conflict_blocks_before_mutation() {
  local home_dir
  home_dir="$(make_home)"
  printf 'existing agents\n' > "$home_dir/.codex/AGENTS.md"

  if HOME="$home_dir" "$repo_root/scripts/install-symlinks.sh" --dry-run >"$home_dir/out" 2>&1; then
    fail "non-root conflict blocks install" "$home_dir/out"
  fi

  assert_file_contains "$home_dir/out" "conflict: $home_dir/.codex/AGENTS.md already exists" "non-root conflict is reported"
  assert_file_contains "$home_dir/out" "Agent merge prompt:" "non-root conflict prints agent prompt"
  assert_file_contains "$home_dir/out" "Required first step: compute your own complete comparison" "non-root prompt requires full comparison"
  assert_file_contains "$home_dir/out" "Default stance: preserve the existing local path" "non-root prompt defaults to local preservation"
  [[ ! -e "$home_dir/.gitignore_global" && ! -e "$home_dir/.claude/settings.json" && ! -e "$home_dir/.codex/config.toml" ]] \
    && pass "non-root conflict prevents partial install" \
    || fail "non-root conflict prevents partial install"
}

test_global_command_conflict_blocks_before_mutation() {
  local home_dir
  home_dir="$(make_home)"
  mkdir -p "$home_dir/.local/bin"
  printf '#!/bin/sh\necho local\n' > "$home_dir/.local/bin/jcmwatch"
  chmod +x "$home_dir/.local/bin/jcmwatch"

  if HOME="$home_dir" "$repo_root/scripts/install-symlinks.sh" >"$home_dir/out" 2>&1; then
    fail "global command conflict blocks install" "$home_dir/out"
  fi

  assert_file_contains "$home_dir/out" "conflict: $home_dir/.local/bin/jcmwatch already exists" "global command conflict is reported"
  assert_file_contains "$home_dir/out" "Default stance: preserve the existing local command" "global command prompt preserves local command"
  assert_file_contains "$home_dir/.local/bin/jcmwatch" "echo local" "global command conflict leaves command untouched"
  [[ ! -e "$home_dir/.gitignore_global" && ! -e "$home_dir/.claude/settings.json" && ! -e "$home_dir/.codex/config.toml" ]] \
    && pass "global command conflict prevents config mutation" \
    || fail "global command conflict prevents config mutation"
}

test_direct_harness_conflict_blocks_before_mutation() {
  local home_dir
  home_dir="$(make_home)"
  printf 'existing agents\n' > "$home_dir/.codex/AGENTS.md"

  if HOME="$home_dir" "$repo_root/scripts/install-codex.sh" --dry-run >"$home_dir/out" 2>&1; then
    fail "direct Codex installer blocks non-root conflict" "$home_dir/out"
  fi

  assert_file_contains "$home_dir/out" "Install has non-root Codex conflicts" "direct Codex installer reports non-root conflict"
  [[ ! -e "$home_dir/.codex/config.toml" && ! -e "$home_dir/.codex/hooks.json" ]] \
    && pass "direct Codex installer prevents partial mutation" \
    || fail "direct Codex installer prevents partial mutation"
}

test_interactive_adopt_agent() {
  local home_dir expect_file
  home_dir="$(make_home)"
  seed_user_configs "$home_dir"
  expect_file="$home_dir/expect.tcl"
  cat >"$expect_file" <<'EOF'
expect "Selection*"
send "1\r"
expect "Continue by adopting existing local config?*"
send "\r"
expect "Selection*"
send "2\r"
expect "Skip this config symlink for now?*"
send "\r"
EOF

  run_expect_install "$home_dir" "$home_dir/out" "$expect_file"

  assert_file_not_contains "$home_dir/out" "managed.*backup local config" "interactive root collision does not offer managed replacement"
  assert_file_contains "$home_dir/out" "Required first step: compute your own complete comparison" "root prompt requires full comparison"
  assert_file_contains "$home_dir/out" "Default stance: adopt the local user config" "root prompt defaults to adopt"
  [[ ! -L "$home_dir/.claude/settings.json" ]] && pass "adopt leaves Claude config as regular file" || fail "adopt leaves Claude config as regular file"
  assert_file_contains "$home_dir/.claude/settings.json" '"model":"opus"' "adopt preserves Claude config content"
  [[ ! -L "$home_dir/.codex/config.toml" ]] && pass "agent leaves Codex config as regular file" || fail "agent leaves Codex config as regular file"
  assert_file_contains "$home_dir/.codex/config.toml" "\[mcp_servers.personal\]" "agent preserves Codex config content"
  ! find "$home_dir/.harness-configs-backups" -name settings.json -o -name config.toml 2>/dev/null | grep -q . \
    && pass "adopt/agent creates no root config backups" \
    || fail "adopt/agent creates no root config backups"
}

test_cancel_loop_and_agent_prompt() {
  local home_dir expect_file
  home_dir="$(make_home)"
  seed_user_configs "$home_dir"
  expect_file="$home_dir/expect.tcl"
  cat >"$expect_file" <<'EOF'
expect "Selection*"
send "1\r"
expect "Continue by adopting existing local config?*"
send "n\r"
expect "Selection*"
send "2\r"
expect "Agent merge prompt:"
expect "Skip this config symlink for now?*"
send "\r"
expect "Selection*"
send "2\r"
expect "Agent merge prompt:"
expect "Skip this config symlink for now?*"
send "\r"
EOF

  run_expect_install "$home_dir" "$home_dir/out" "$expect_file"

  assert_file_contains "$home_dir/out" "Agent merge prompt:" "agent prompt printed"
  [[ ! -L "$home_dir/.claude/settings.json" && ! -L "$home_dir/.codex/config.toml" ]] && pass "agent prompt skips config symlinks" || fail "agent prompt skips config symlinks"
}

test_abort_no_config_replacement() {
  local home_dir expect_file
  home_dir="$(make_home)"
  seed_user_configs "$home_dir"
  expect_file="$home_dir/expect.tcl"
  cat >"$expect_file" <<'EOF'
expect "Selection*"
send "q\r"
EOF

  if run_expect_install "$home_dir" "$home_dir/out" "$expect_file"; then
    fail "abort exits nonzero" "$home_dir/out"
  fi

  assert_file_contains "$home_dir/out" "install canceled by user" "abort reports cancellation"
  [[ ! -L "$home_dir/.claude/settings.json" && ! -e "$home_dir/.claude/CLAUDE.md" && ! -e "$home_dir/.gitignore_global" ]] \
    && pass "abort does not replace config or continue" \
    || fail "abort does not replace config or continue"
}

test_idempotency_no_extra_backups() {
  local home_dir
  home_dir="$(make_home)"

  HOME="$home_dir" "$repo_root/scripts/install-symlinks.sh" >"$home_dir/first.out"
  HOME="$home_dir" "$repo_root/scripts/install-symlinks.sh" >"$home_dir/second.out"

  assert_file_contains "$home_dir/second.out" "ok: $home_dir/.claude/settings.json" "idempotent Claude config ok"
  assert_file_contains "$home_dir/second.out" "ok: $home_dir/.codex/config.toml" "idempotent Codex config ok"
  ! find "$home_dir/.harness-configs-backups" -name settings.json -o -name config.toml 2>/dev/null | grep -q . \
    && pass "idempotent managed run creates no config backups" \
    || fail "idempotent managed run creates no config backups"
}

test_malformed_claude_config() {
  local home_dir
  home_dir="$(make_home)"
  printf '{bad json\n' > "$home_dir/.claude/settings.json"
  printf 'model = "o3"\n' > "$home_dir/.codex/config.toml"

  HOME="$home_dir" "$repo_root/scripts/install-symlinks.sh" --dry-run >"$home_dir/out"

  assert_file_contains "$home_dir/out" "invalid JSON" "malformed Claude config is reported"
  assert_file_contains "$home_dir/out" "collision: $home_dir/.claude/settings.json" "malformed Claude config still prompts"
}

test_sync_guard() {
  local home_dir sync_repo before_hash after_hash
  home_dir="$(make_home)"
  sync_repo="$(mktemp -d)"
  seed_user_configs "$home_dir"
  mkdir -p "$sync_repo/codex" "$sync_repo/claude"
  cp "$repo_root/codex/config.toml" "$sync_repo/codex/config.toml"
  cp "$repo_root/claude/settings.json" "$sync_repo/claude/settings.json"

  before_hash="$(shasum "$sync_repo/codex/config.toml" "$sync_repo/claude/settings.json")"
  HARNESS_CONFIG_REPO_ROOT="$sync_repo" HOME="$home_dir" "$repo_root/scripts/sync-from-home.sh" >"$home_dir/out"
  after_hash="$(shasum "$sync_repo/codex/config.toml" "$sync_repo/claude/settings.json")"

  [[ "$before_hash" == "$after_hash" ]] && pass "sync guard leaves repo config baseline unchanged" || fail "sync guard leaves repo config baseline unchanged"
  assert_file_contains "$home_dir/out" "skip user-owned config: $home_dir/.codex/config.toml" "sync guard skips Codex user config"
  assert_file_contains "$home_dir/out" "skip user-owned config: $home_dir/.claude/settings.json" "sync guard skips Claude user config"

  if HARNESS_CONFIG_REPO_ROOT="$sync_repo" HOME="$home_dir" "$repo_root/scripts/sync-from-home.sh" --include-root-config >"$home_dir/include-root.out" 2>&1; then
    fail "sync include-root-config requires interactive review" "$home_dir/include-root.out"
  fi
  assert_file_contains "$home_dir/include-root.out" "stdin is not interactive" "sync include-root-config reviews user config before promoting"
}

test_sync_interactive_choices() {
  local home_dir sync_repo expect_file
  home_dir="$(make_home)"
  sync_repo="$(mktemp -d)"
  mkdir -p "$sync_repo/codex" "$home_dir/.codex"
  printf 'repo agents\n' > "$sync_repo/codex/AGENTS.md"
  printf 'home agents\n' > "$home_dir/.codex/AGENTS.md"
  printf 'repo hooks\n' > "$sync_repo/codex/hooks.json"
  printf 'home hooks\n' > "$home_dir/.codex/hooks.json"
  printf 'repo marker\n' > "$sync_repo/codex/MANAGED_BY_HARNESS_CONFIGS.md"
  printf 'home marker\n' > "$home_dir/.codex/MANAGED_BY_HARNESS_CONFIGS.md"
  expect_file="$home_dir/expect.tcl"
  cat >"$expect_file" <<'EOF'
expect "Selection*"
send "1\r"
expect "Selection*"
send "2\r"
expect "Selection*"
send "3\r"
expect eof
EOF

  command -v expect >/dev/null 2>&1 || fail "expect is required for interactive sync tests"
  HC_REPO="$repo_root" HC_HOME="$home_dir" HC_SYNC_REPO="$sync_repo" HC_EXPECT_SCRIPT="$expect_file" expect <<'EOF' >"$home_dir/out" 2>&1
set timeout 20
spawn env HARNESS_CONFIG_REPO_ROOT=$env(HC_SYNC_REPO) HOME=$env(HC_HOME) $env(HC_REPO)/scripts/sync-from-home.sh
source $env(HC_EXPECT_SCRIPT)
set wait_result [wait]
set exit_code [lindex $wait_result 3]
exit $exit_code
EOF

  assert_file_contains "$sync_repo/codex/AGENTS.md" "repo agents" "sync keep repo leaves item unchanged"
  assert_file_contains "$sync_repo/codex/hooks.json" "home hooks" "sync overwrite copies home item"
  assert_file_contains "$sync_repo/codex/MANAGED_BY_HARNESS_CONFIGS.md" "repo marker" "sync agent prompt skips item"
  assert_file_contains "$home_dir/out" "Agent merge prompt:" "sync agent prompt printed"
  assert_file_contains "$home_dir/out" "Required first step: compute your own complete comparison" "sync prompt requires full comparison"
  assert_file_contains "$home_dir/out" "Default stance: keep the repo baseline" "sync prompt defaults to repo baseline"
}

test_sync_overwrite_rollback_on_replace_failure() {
  local home_dir sync_repo expect_file fake_bin
  home_dir="$(make_home)"
  sync_repo="$(mktemp -d)"
  fake_bin="$(mktemp -d)"
  mkdir -p "$sync_repo/codex" "$home_dir/.codex"
  printf 'repo hooks\n' > "$sync_repo/codex/hooks.json"
  printf 'home hooks\n' > "$home_dir/.codex/hooks.json"
  expect_file="$home_dir/expect.tcl"
  cat >"$expect_file" <<'EOF'
expect "Selection*"
send "2\r"
expect eof
EOF
  cat >"$fake_bin/mv" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == *".sync-from-home.tmp."*"/item" ]]; then
  exit 1
fi
exec /bin/mv "$@"
EOF
  chmod +x "$fake_bin/mv"

  command -v expect >/dev/null 2>&1 || fail "expect is required for interactive sync tests"
  if HC_REPO="$repo_root" HC_HOME="$home_dir" HC_SYNC_REPO="$sync_repo" HC_EXPECT_SCRIPT="$expect_file" HC_FAKE_BIN="$fake_bin" expect <<'EOF' >"$home_dir/out" 2>&1
set timeout 20
spawn env HARNESS_CONFIG_REPO_ROOT=$env(HC_SYNC_REPO) HOME=$env(HC_HOME) PATH=$env(HC_FAKE_BIN):$env(PATH) $env(HC_REPO)/scripts/sync-from-home.sh
source $env(HC_EXPECT_SCRIPT)
set wait_result [wait]
set exit_code [lindex $wait_result 3]
exit $exit_code
EOF
  then
    fail "sync overwrite failure exits nonzero" "$home_dir/out"
  fi

  assert_file_contains "$home_dir/out" "failed to replace" "sync overwrite reports replace failure"
  assert_file_contains "$sync_repo/codex/hooks.json" "repo hooks" "sync overwrite restores original repo file"
}

test_windows_installer_root_preflight_order() {
  local windows_script root_line claude_line
  windows_script="$repo_root/scripts/install-windows.ps1"
  root_line="$(awk '/^Invoke-RootConfigPreflight$/ { print NR; exit }' "$windows_script")"
  claude_line="$(awk '/^# Claude symlinks$/ { print NR; exit }' "$windows_script")"

  [[ -n "$root_line" && -n "$claude_line" && "$root_line" -lt "$claude_line" ]] \
    && pass "Windows installer resolves root config collisions before linking" \
    || fail "Windows installer resolves root config collisions before linking" "$windows_script"
  assert_file_contains "$windows_script" 'if \(-not \$adoptClaudeConfig\)' "Windows installer skips adopted Claude root config"
  assert_file_contains "$windows_script" 'if \(-not \$adoptCodexConfig\)' "Windows installer skips adopted Codex root config"
}

test_fresh_managed
test_dry_run_collision_no_mutation
test_noninteractive_block_no_mutation
test_non_root_conflict_blocks_before_mutation
test_global_command_conflict_blocks_before_mutation
test_direct_harness_conflict_blocks_before_mutation
test_interactive_adopt_agent
test_cancel_loop_and_agent_prompt
test_abort_no_config_replacement
test_idempotency_no_extra_backups
test_malformed_claude_config
test_sync_guard
test_sync_interactive_choices
test_sync_overwrite_rollback_on_replace_failure
test_windows_installer_root_preflight_order

echo "all install collision tests passed"
