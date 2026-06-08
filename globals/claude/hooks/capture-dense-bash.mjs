import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

// --- Capture dense (multi-line) Bash tool calls for later pattern analysis -----------------
//
// PURPOSE: collect the super-dense, multi-line shell commands the agent emits so their
// patterns can be analyzed and engineered away (turned into scripts, CLI subcommands, or
// allowlist entries). This hook ONLY observes — it never blocks, rewrites, or prompts. It
// shares the PreToolUse:Bash chain with minimize-bash-output.mjs and must stay a silent
// passthrough so it cannot perturb that hook's decisions.
//
// FLAG RULE: a command is "dense" when it spans >= DENSE_LINE_THRESHOLD lines (newline count).
// That matches the "3+ newlines" capture rule, catching the 2-3-line-plus commands that are
// hard to read and hard to allowlist.
//
// wouldPrompt: best-effort guess at whether this command would have hit a permission prompt,
// computed by re-reading ~/.claude/settings.json and prefix-matching against allow/deny the
// way Claude's matcher does. It is approximate (does not model ask-rules, project settings,
// or session-mode overrides) and is recorded as a FIELD, not used to gate capture — so the
// log can later be filtered to "dense AND would-prompt" without this hook being fragile.

const DENSE_LINE_THRESHOLD = 3

const fail = () => process.exit(0) // any error => silent passthrough, never disturb the call

let input
try {
  input = JSON.parse(fs.readFileSync(0, 'utf8'))
} catch {
  fail()
}

const toolInput = input.tool_input || {}
const command = typeof toolInput.command === 'string' ? toolInput.command : ''
if (!command) fail()

const lineCount = command.split('\n').length
if (lineCount < DENSE_LINE_THRESHOLD) process.exit(0) // not dense — nothing to capture

// --- Best-effort allowlist match ---------------------------------------------------------
// Claude matches Bash permissions by literal prefix inside `Bash(<prefix>)`, where a trailing
// `:*` means prefix-match and no `:*` means the command must equal the prefix exactly. We
// approximate that. deny wins over allow.
const matchesRule = (cmd, rule) => {
  const m = rule.match(/^Bash\((.*)\)$/s)
  if (!m) return false
  const pat = m[1]
  if (pat.endsWith(':*')) return cmd.startsWith(pat.slice(0, -2))
  return cmd === pat
}

let wouldPrompt = null // null = could not determine
try {
  const settingsPath = path.join(os.homedir(), '.claude', 'settings.json')
  const settings = JSON.parse(fs.readFileSync(settingsPath, 'utf8'))
  const perms = settings.permissions || {}
  const allow = Array.isArray(perms.allow) ? perms.allow : []
  const deny = Array.isArray(perms.deny) ? perms.deny : []
  const trimmed = command.trim()
  const denied = deny.some(r => matchesRule(trimmed, r))
  const allowed = allow.some(r => matchesRule(trimmed, r))
  // Denied commands are auto-rejected (no prompt); allowed are auto-run (no prompt);
  // everything else prompts.
  wouldPrompt = !denied && !allowed
} catch {
  wouldPrompt = null
}

const record = {
  ts: new Date().toISOString(),
  session_id: input.session_id || null,
  cwd: input.cwd || null,
  lineCount,
  charCount: command.length,
  wouldPrompt,
  command,
}

try {
  const sid = (input.session_id || 'nosession').replace(/[^A-Za-z0-9._-]/g, '_')
  const dir = process.env.TMPDIR || os.tmpdir()
  const logPath = path.join(dir, `claude-dense-bash-${sid}.jsonl`)
  fs.appendFileSync(logPath, JSON.stringify(record) + '\n')
} catch {
  // swallow — observation must never break the tool call
}

process.exit(0)
