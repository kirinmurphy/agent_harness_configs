# Codex Hooks

Configured in `globals/codex/hooks.json`.

## SessionStart (startup|resume)

**Trigger:** session start or resume event matching `startup|resume`.

**What it does:** prints caveman mode activation instructions to stdout. Tells the model to drop articles/filler/pleasantries/hedging, use fragments, keep responses terse. Code, commits, and security output stays normal. User can say "stop caveman" or "normal mode" to deactivate.

## Notes

Codex `PreToolUse` hook support is not confirmed stable. jcodemunch enforcement in Codex relies on rules in `globals/codex/rules/default.rules` and generated `globals/codex/AGENTS.md` rather than tool-level hooks. See [jcodemunch.md](jcodemunch.md) for full details.
