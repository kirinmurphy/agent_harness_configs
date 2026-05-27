# install-windows.ps1 — Windows symlink installer for harness-configs
#
# Requirements:
#   - Windows Developer Mode OR run PowerShell as Administrator
#     (symlink creation requires one of these)
#   - Git for Windows (https://git-scm.com) for hook scripts and bin/ commands
#     (hook scripts are bash — they will not run without Git Bash or WSL)
#
# Usage:
#   From PowerShell:  .\scripts\install-windows.ps1
#   From Git Bash:    called automatically by install-symlinks.sh
#
# Less tested than macOS/Linux. Report issues or submit PRs.

param(
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

function Link-Item {
  param($RepoRel, $HomePath)
  $src = Join-Path $repoRoot $RepoRel

  if (-not (Test-Path $src)) {
    Write-Warning "missing source: $src"
    return
  }

  $parentDir = Split-Path -Parent $HomePath
  if (-not (Test-Path $parentDir)) {
    if ($DryRun) {
      Write-Host "would mkdir: $parentDir"
    } else {
      New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }
  }

  if (Test-Path $HomePath) {
    $existing = Get-Item $HomePath -Force
    if ($existing.LinkType -eq "SymbolicLink" -and $existing.Target -eq $src) {
      Write-Host "ok: $HomePath"
      return
    }
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupRoot = Join-Path $env:USERPROFILE ".harness-configs-backups\$timestamp"
    $backupPath = Join-Path $backupRoot $HomePath.TrimStart('\').TrimStart('/')
    if (-not $DryRun) {
      New-Item -ItemType Directory -Path (Split-Path -Parent $backupPath) -Force | Out-Null
      Move-Item -Path $HomePath -Destination $backupPath
    }
    Write-Host "backup: $HomePath -> $backupPath"
  }

  if ($DryRun) {
    Write-Host "link: $HomePath -> $src"
    return
  }

  try {
    New-Item -ItemType SymbolicLink -Path $HomePath -Target $src -Force | Out-Null
    Write-Host "link: $HomePath -> $src"
  } catch {
    Write-Warning "Failed to create symlink: $HomePath"
    Write-Warning "Enable Windows Developer Mode or run PowerShell as Administrator."
    Write-Warning "  Settings > System > For Developers > Developer Mode"
  }
}

# Detect which harnesses are present
$hasClaude = Test-Path (Join-Path $env:APPDATA "Claude")
$hasCodex  = Test-Path (Join-Path $env:USERPROFILE ".codex")

if (-not $hasClaude -and -not $hasCodex) {
  Write-Warning "Neither Claude Code (~AppData\Roaming\Claude) nor Codex (~\.codex) found."
  Write-Warning "Install Claude Code or Codex first, then re-run this script."
  exit 1
}

# Claude symlinks
if ($hasClaude) {
  Write-Host ""
  Write-Host "--- Claude ---"
  $claudeHome = Join-Path $env:APPDATA "Claude"
  Link-Item "claude/CLAUDE.md"                     (Join-Path $claudeHome "CLAUDE.md")
  Link-Item "claude/settings.json"                 (Join-Path $claudeHome "settings.json")
  Link-Item "claude/MANAGED_BY_HARNESS_CONFIGS.md" (Join-Path $claudeHome "MANAGED_BY_HARNESS_CONFIGS.md")
  Link-Item "claude/commands"                      (Join-Path $claudeHome "commands")
  Link-Item "claude/hooks"                         (Join-Path $claudeHome "hooks")
  Link-Item "claude/skills"                        (Join-Path $claudeHome "skills")
} else {
  Write-Host "skip: Claude — AppData\Roaming\Claude not found"
}

# Codex symlinks
if ($hasCodex) {
  Write-Host ""
  Write-Host "--- Codex ---"
  $codexHome = Join-Path $env:USERPROFILE ".codex"
  Link-Item "codex/AGENTS.md"                     (Join-Path $codexHome "AGENTS.md")
  Link-Item "codex/config.toml"                   (Join-Path $codexHome "config.toml")
  Link-Item "codex/hooks.json"                    (Join-Path $codexHome "hooks.json")
  Link-Item "codex/MANAGED_BY_HARNESS_CONFIGS.md" (Join-Path $codexHome "MANAGED_BY_HARNESS_CONFIGS.md")
  Link-Item "codex/rules"                         (Join-Path $codexHome "rules")
  Link-Item "codex/skills"                        (Join-Path $codexHome "skills")
} else {
  Write-Host "skip: Codex — ~/.codex not found"
}

# Post-install summary
Write-Host ""
Write-Host "Install complete."
Write-Host "  Claude: $(if ($hasClaude) { 'linked' } else { 'skipped — not installed' })"
Write-Host "  Codex:  $(if ($hasCodex)  { 'linked' } else { 'skipped — not installed' })"
Write-Host ""
Write-Host "IMPORTANT: Hook scripts (jcmwatch, jcmindex, bin/ commands) require bash."
Write-Host "  Install Git for Windows: https://git-scm.com"
Write-Host "  Then add $(Join-Path $repoRoot 'bin') to your PATH or run install-global-commands.sh from Git Bash."
Write-Host ""
Write-Host "To add a harness later: install it, then re-run this script."
