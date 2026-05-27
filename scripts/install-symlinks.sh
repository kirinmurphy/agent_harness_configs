#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dry_run=0

case "${1:-}" in
  --dry-run) dry_run=1 ;;
  "") ;;
  *) echo "usage: $0 [--dry-run]" >&2; exit 2 ;;
esac

# Windows: delegate to PowerShell installer, then continue for bash-specific steps
case "$(uname -s 2>/dev/null || echo unknown)" in
  MINGW*|MSYS*|CYGWIN*)
    echo "Windows + bash detected (Git Bash or similar)."
    if command -v powershell.exe &>/dev/null; then
      echo "Running PowerShell installer for symlinks..."
      powershell.exe -ExecutionPolicy Bypass \
        -File "${repo_root}/scripts/install-windows.ps1"
    else
      echo "powershell.exe not found. Run scripts/install-windows.ps1 from PowerShell manually."
    fi
    # Shell snippets and global commands still need bash — continue below
    "${repo_root}/scripts/install-gitignore-globals.sh"
    "${repo_root}/scripts/install-global-commands.sh"
    "${repo_root}/scripts/install-shell-snippets.sh"
    exit 0
    ;;
esac

# Detect which harnesses are present
has_claude=0
has_codex=0
[[ -d "${HOME}/.claude" ]] && has_claude=1
[[ -d "${HOME}/.codex" ]]  && has_codex=1

if [[ $has_claude -eq 0 && $has_codex -eq 0 ]]; then
  echo "error: neither ~/.claude nor ~/.codex found." >&2
  echo "Install Claude Code (https://claude.ai/code) or Codex before running this script." >&2
  exit 1
fi

# Harness-agnostic setup
"${repo_root}/scripts/install-gitignore-globals.sh"

# Harness-specific symlinks
dry_flag=""
[[ $dry_run -eq 1 ]] && dry_flag="--dry-run"

if [[ $has_claude -eq 1 ]]; then
  "${repo_root}/scripts/install-claude.sh" ${dry_flag}
else
  echo "skip: Claude — ~/.claude not found"
fi

if [[ $has_codex -eq 1 ]]; then
  "${repo_root}/scripts/install-codex.sh" ${dry_flag}
else
  echo "skip: Codex — ~/.codex not found"
fi

# Shell and PATH setup (harness-agnostic, bash only)
if [[ $dry_run -eq 0 ]]; then
  "${repo_root}/scripts/install-global-commands.sh"
  "${repo_root}/scripts/install-shell-snippets.sh"
fi

# Post-install summary
echo ""
echo "Install complete."
echo "  Claude: $([ $has_claude -eq 1 ] && echo 'linked' || echo 'skipped — not installed')"
echo "  Codex:  $([ $has_codex  -eq 1 ] && echo 'linked' || echo 'skipped — not installed')"
echo ""
echo "To add the other harness later: install it, then re-run this script."
