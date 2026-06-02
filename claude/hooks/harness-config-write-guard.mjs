import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

// Fires on Write/Edit. When the target path lives under a symlinked harness
// config dir (~/.claude or ~/.codex), inject a non-blocking reminder that the
// real file is version-controlled in the harness_configs repo. Edits to an
// existing file resolve through the symlink to the root and are safe; the trap
// is creating a NEW plain file here instead of in harness_configs + linking.
// Visible from any repo because settings.json is itself symlinked globally.

const input = JSON.parse(fs.readFileSync(0, 'utf8'))
const toolInput = input.tool_input || {}
const filePath = toolInput.file_path || ''

const noop = () => process.exit(0)

if (!filePath) noop()

const abs = path.resolve(filePath)
const home = os.homedir()
const guarded = [path.join(home, '.claude'), path.join(home, '.codex')]

const underGuarded = guarded.some(
  dir => abs === dir || abs.startsWith(dir + path.sep),
)
if (!underGuarded) noop()

// settings.local.json is intentionally machine-local, not in the repo.
if (path.basename(abs) === 'settings.local.json') noop()

const isNewFile = !fs.existsSync(abs)

const reminder = isNewFile
  ? `This path symlinks into the version-controlled harness_configs repo (~/projects/live_projects/harness_configs). Do NOT create a new file directly here. Create it in harness_configs/ (for a skill: skills/<name>/SKILL.md), then run scripts/link-skills.sh to create the symlinks. See the harness-config skill.`
  : `This file is a symlink into the version-controlled harness_configs repo (~/projects/live_projects/harness_configs). Editing here is fine — it resolves to the root file — but commit the change in that repo, not from the current working dir.`

process.stdout.write(
  JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      additionalContext: `[harness-config] ${reminder}`,
    },
  }),
)
