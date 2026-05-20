import fs from 'node:fs'

const input = JSON.parse(fs.readFileSync(0, 'utf8'))
const toolInput = input.tool_input || {}
const command = toolInput.command || ''

const hasTail = s => /\|\s*tail\b/.test(s)
const addTail = s => hasTail(s) ? s : `${s} 2>&1 | tail -n 120`

const allow = nextCommand => {
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      permissionDecision: 'allow',
      permissionDecisionReason: 'Rewriting Bash command to a lower-noise form',
      updatedInput: {
        ...toolInput,
        command: nextCommand
      }
    }
  }))
}

const deny = reason => {
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      permissionDecision: 'deny',
      permissionDecisionReason: reason
    }
  }))
}

if (
  /\b(--watch|--verbose|--debug)\b/.test(command) ||
  /\b(vitest|jest|tsx|ts-node)\b.*\b(--watch|watch)\b/.test(command)
) {
  deny('Do not use watch, verbose, or debug flags unless explicitly requested.')
  process.exit(0)
}

if (
  /\bnpm\s+run\s+lint\b/.test(command) ||
  /\bpnpm\b.*\blint\b/.test(command) ||
  /\byarn\s+lint\b/.test(command) ||
  /\bbun\s+run\s+lint\b/.test(command)
) {
  allow(addTail(command))
  process.exit(0)
}

if (
  /\bnpm\s+run\s+typecheck\b/.test(command) ||
  /\bpnpm\b.*\btypecheck\b/.test(command) ||
  /\byarn\s+typecheck\b/.test(command) ||
  /\bbun\s+run\s+typecheck\b/.test(command) ||
  /\btsc\b/.test(command)
) {
  const next = /\btsc\b/.test(command) && !/--pretty\b/.test(command)
    ? command.replace(/\btsc\b/, 'tsc --pretty false')
    : command

  allow(addTail(next))
  process.exit(0)
}

if (
  /\bnpm\s+run\s+build\b/.test(command) ||
  /\bpnpm\b.*\bbuild\b/.test(command) ||
  /\byarn\s+build\b/.test(command) ||
  /\bbun\s+run\s+build\b/.test(command) ||
  /\bnext\s+build\b/.test(command) ||
  /\bvite\s+build\b/.test(command)
) {
  allow(addTail(command))
  process.exit(0)
}

process.exit(0)
