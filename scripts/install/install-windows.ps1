# install-windows.ps1 — Windows symlink installer for harness-configs
#
# Requirements:
#   - Windows Developer Mode OR run PowerShell as Administrator
#     (symlink creation requires one of these)
#   - Git for Windows (https://git-scm.com) for hook scripts and bin/ commands
#     (hook scripts are bash — they will not run without Git Bash or WSL)
#
# Usage:
#   From PowerShell:  .\scripts\install\install-windows.ps1
#   From Git Bash:    called automatically by roborepo-install.sh
#
# Less tested than macOS/Linux. Report issues or submit PRs.

param(
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

function Link-Item {
  param($RepoRel, $HomePath, [switch]$AllowReplace)
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
    if (-not $AllowReplace) {
      Write-Warning "conflict: $HomePath already exists; not replacing it"
      Write-AgentMergePrompt "install" "resolve local path conflict" $RepoRel $HomePath
      throw "install has non-root config conflicts; no replacement was made for $HomePath"
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

function Write-AgentMergePrompt {
  param($Harness, $Mode, $RepoRel, $HomePath)
  $src = Join-Path $repoRoot $RepoRel
  Write-Host ""
  Write-Host "Agent merge prompt:"
  Write-Host "-----"
  Write-Host @"
Compare harness config at:
  $src

With local user config at:
  $HomePath

Default stance: adopt the local user config as source of truth. Preserve existing local behavior unless you can prove a harness change can be added safely.

Selected install direction: $Mode.

Required first step: compute your own complete comparison of both paths. Do not rely on this prompt as an exhaustive conflict summary. For directories, inspect the full recursive file list and content diffs. For structured files, parse the format when possible and identify all changed keys/tables/arrays/sections before editing.

Merge instructions:
- Keep local-only behavior by default.
- Add repo-only harness behavior only when it does not conflict with local behavior.
- If both sides edit the same setting, hook, rule, command, skill, or MCP/server entry, explain the conflict and stop for user choice.
- Do not delete, replace, or move the local path unless the user explicitly approves that exact action.
- Report the files changed and the conflicts left unresolved.
Harness: $Harness
"@
  Write-Host "-----"
  Write-Host ""
}

function Confirm-Choice {
  param($Prompt)
  $answer = Read-Host "$Prompt [Y/n]"
  return ($answer -eq "" -or $answer -eq "y" -or $answer -eq "Y" -or $answer -eq "yes" -or $answer -eq "YES")
}

function Link-UserConfig {
  param($Harness, $RepoRel, $HomePath)
  $src = Join-Path $repoRoot $RepoRel

  if (-not (Test-Path $src)) {
    Write-Warning "missing source: $src"
    return
  }

  if (Test-Path $HomePath) {
    $existing = Get-Item $HomePath -Force
    if ($existing.LinkType -eq "SymbolicLink" -and $existing.Target -eq $src) {
      Write-Host "ok: $HomePath"
      return
    }
  } else {
    Link-Item $RepoRel $HomePath
    return
  }

  if ($DryRun) {
    Write-Host "collision: $HomePath"
    Write-Host "dry-run: would ask whether to adopt existing config or print agent merge prompt"
    return
  }

  if (-not [Environment]::UserInteractive) {
    throw "$HomePath exists and PowerShell is not interactive. Run interactively or use -DryRun to inspect collisions."
  }

  while ($true) {
    Write-Host ""
    Write-Host "User-owned $Harness config exists:"
    Write-Host "  local:   $HomePath"
    Write-Host "  harness: $src"
    Write-Host ""
    Write-Host "Choose:"
    Write-Host "  1) adopt         keep local root config; install only clean harness links"
    Write-Host "  2) agent prompt  print merge prompt; leave root config unchanged"
    Write-Host "  q) quit"
    $choice = Read-Host "Selection [1/2/q]"

    switch ($choice) {
      { $_ -in @("1", "adopt") } {
        Write-Host ""
        Write-Host "Keeping local $HomePath. Harness defaults will not be installed for this file."
        Write-AgentMergePrompt $Harness "adopt existing" $RepoRel $HomePath
        if (Confirm-Choice "Continue by adopting existing local config?") {
          Write-Host "skip: $HomePath left in place"
          return
        }
      }
      { $_ -in @("2", "agent", "prompt") } {
        Write-AgentMergePrompt $Harness "manual agent merge before install" $RepoRel $HomePath
        if (Confirm-Choice "Skip this config symlink for now?") {
          Write-Host "skip: $HomePath left in place"
          return
        }
      }
      { $_ -in @("q", "Q", "quit", "exit") } {
        throw "install canceled by user"
      }
      default {
        Write-Host "Invalid selection."
      }
    }
  }
}

function Resolve-UserConfigCollision {
  param($Harness, $RepoRel, $HomePath)
  $src = Join-Path $repoRoot $RepoRel

  if (-not (Test-Path $src)) {
    Write-Warning "missing source: $src"
    return $false
  }

  if (Test-Path $HomePath) {
    $existing = Get-Item $HomePath -Force
    if ($existing.LinkType -eq "SymbolicLink" -and $existing.Target -eq $src) {
      return $false
    }
  } else {
    return $false
  }

  if ($DryRun) {
    Write-Host "collision: $HomePath"
    Write-Host "dry-run: would ask whether to adopt existing config or print agent merge prompt"
    return $false
  }

  if (-not [Environment]::UserInteractive) {
    throw "$HomePath exists and PowerShell is not interactive. Run interactively or use -DryRun to inspect collisions."
  }

  while ($true) {
    Write-Host ""
    Write-Host "User-owned $Harness config exists:"
    Write-Host "  local:   $HomePath"
    Write-Host "  harness: $src"
    Write-Host ""
    Write-Host "Choose:"
    Write-Host "  1) adopt         keep local root config; install only clean harness links"
    Write-Host "  2) agent prompt  print merge prompt; leave root config unchanged"
    Write-Host "  q) quit"
    $choice = Read-Host "Selection [1/2/q]"

    switch ($choice) {
      { $_ -in @("1", "adopt") } {
        Write-Host ""
        Write-Host "Keeping local $HomePath. Harness defaults will not be installed for this file."
        Write-AgentMergePrompt $Harness "adopt existing" $RepoRel $HomePath
        if (Confirm-Choice "Continue by adopting existing local config?") {
          Write-Host "skip: $HomePath left in place"
          return $true
        }
      }
      { $_ -in @("2", "agent", "prompt") } {
        Write-AgentMergePrompt $Harness "manual agent merge before install" $RepoRel $HomePath
        if (Confirm-Choice "Skip this config symlink for now?") {
          Write-Host "skip: $HomePath left in place"
          return $true
        }
      }
      { $_ -in @("q", "Q", "quit", "exit") } {
        throw "install canceled by user"
      }
      default {
        Write-Host "Invalid selection."
      }
    }
  }
}

function Test-CleanTarget {
  param($RepoRel, $HomePath)
  $src = Join-Path $repoRoot $RepoRel

  if (-not (Test-Path $HomePath)) {
    return $true
  }

  $existing = Get-Item $HomePath -Force
  if ($existing.LinkType -eq "SymbolicLink" -and $existing.Target -eq $src) {
    return $true
  }

  Write-Warning "conflict: $HomePath already exists and is not managed by this repo."
  Write-AgentMergePrompt "install" "resolve local path conflict" $RepoRel $HomePath
  return $false
}

function Invoke-CleanTargetPreflight {
  $conflict = $false

  if ($hasClaude) {
    $claudeHome = Join-Path $env:APPDATA "Claude"
    if (-not (Test-CleanTarget "claude/CLAUDE.md" (Join-Path $claudeHome "CLAUDE.md"))) { $conflict = $true }
    if (-not (Test-CleanTarget "claude/MANAGED_BY_HARNESS_CONFIGS.md" (Join-Path $claudeHome "MANAGED_BY_HARNESS_CONFIGS.md"))) { $conflict = $true }
    if (-not (Test-CleanTarget "claude/commands" (Join-Path $claudeHome "commands"))) { $conflict = $true }
    if (-not (Test-CleanTarget "claude/hooks" (Join-Path $claudeHome "hooks"))) { $conflict = $true }
    if (-not (Test-CleanTarget "claude/skills" (Join-Path $claudeHome "skills"))) { $conflict = $true }
  }

  if ($hasCodex) {
    $codexHome = Join-Path $env:USERPROFILE ".codex"
    $agentsHome = Join-Path $env:USERPROFILE ".agents"
    if (-not (Test-CleanTarget "codex/AGENTS.md" (Join-Path $codexHome "AGENTS.md"))) { $conflict = $true }
    if (-not (Test-CleanTarget "codex/hooks.json" (Join-Path $codexHome "hooks.json"))) { $conflict = $true }
    if (-not (Test-CleanTarget "codex/MANAGED_BY_HARNESS_CONFIGS.md" (Join-Path $codexHome "MANAGED_BY_HARNESS_CONFIGS.md"))) { $conflict = $true }
    if (-not (Test-CleanTarget "codex/rules" (Join-Path $codexHome "rules"))) { $conflict = $true }
    if (-not (Test-CleanTarget "agents/skills" (Join-Path $agentsHome "skills"))) { $conflict = $true }
    if (-not (Test-CleanTarget "agents/skills" (Join-Path $codexHome "skills"))) { $conflict = $true }
  }

  if ($conflict) {
    throw "install has non-root config conflicts; no files were changed"
  }
}

function Invoke-RootConfigPreflight {
  $script:adoptClaudeConfig = $false
  $script:adoptCodexConfig = $false

  if ($hasClaude) {
    $claudeHome = Join-Path $env:APPDATA "Claude"
    if (Resolve-UserConfigCollision "claude" "claude/settings.json" (Join-Path $claudeHome "settings.json")) {
      $script:adoptClaudeConfig = $true
    }
  }

  if ($hasCodex) {
    $codexHome = Join-Path $env:USERPROFILE ".codex"
    if (Resolve-UserConfigCollision "codex" "codex/config.toml" (Join-Path $codexHome "config.toml")) {
      $script:adoptCodexConfig = $true
    }
  }
}

# Detect which harnesses are present
$hasClaude = Test-Path (Join-Path $env:APPDATA "Claude")
$hasCodex  = (Test-Path (Join-Path $env:USERPROFILE ".codex")) -or (Test-Path (Join-Path $env:USERPROFILE ".agents"))

if (-not $hasClaude -and -not $hasCodex) {
  Write-Warning "Neither Claude Code (~AppData\Roaming\Claude) nor Codex (~\.codex/~\.agents) found."
  Write-Warning "Install Claude Code or Codex first, then re-run this script."
  exit 1
}

Invoke-CleanTargetPreflight
Invoke-RootConfigPreflight

# Claude symlinks
if ($hasClaude) {
  Write-Host ""
  Write-Host "--- Claude ---"
  $claudeHome = Join-Path $env:APPDATA "Claude"
  if (-not $adoptClaudeConfig) {
    Link-UserConfig "claude" "claude/settings.json"  (Join-Path $claudeHome "settings.json")
  }
  Link-Item "claude/CLAUDE.md"                     (Join-Path $claudeHome "CLAUDE.md")
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
  $agentsHome = Join-Path $env:USERPROFILE ".agents"
  if (-not $adoptCodexConfig) {
    Link-UserConfig "codex" "codex/config.toml"     (Join-Path $codexHome "config.toml")
  }
  Link-Item "codex/AGENTS.md"                     (Join-Path $codexHome "AGENTS.md")
  Link-Item "codex/hooks.json"                    (Join-Path $codexHome "hooks.json")
  Link-Item "codex/MANAGED_BY_HARNESS_CONFIGS.md" (Join-Path $codexHome "MANAGED_BY_HARNESS_CONFIGS.md")
  Link-Item "codex/rules"                         (Join-Path $codexHome "rules")
  Link-Item "agents/skills"                       (Join-Path $agentsHome "skills")
  Link-Item "agents/skills"                       (Join-Path $codexHome "skills")
} else {
  Write-Host "skip: Codex — ~/.codex/~/.agents not found"
}

# Post-install summary
Write-Host ""
Write-Host "Install complete."
Write-Host "  Claude: $(if ($hasClaude) { 'linked' } else { 'skipped — not installed' })"
Write-Host "  Codex:  $(if ($hasCodex)  { 'linked' } else { 'skipped — not installed' })"
Write-Host ""
Write-Host "IMPORTANT: Hook scripts and bin/ commands require bash."
Write-Host "  Install Git for Windows: https://git-scm.com"
Write-Host "  Then add $(Join-Path $repoRoot 'bin') to your PATH or run install-global-commands.sh from Git Bash."
Write-Host ""
Write-Host "To add a harness later: install it, then re-run this script."
