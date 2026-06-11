# Codex Hooks

Configured in `globals/codex/hooks.json`.

## SessionStart (startup|resume)

**Trigger:** session start or resume event matching `startup|resume`.

**What it does:** prints caveman mode activation instructions to stdout. Tells the model to drop articles/filler/pleasantries/hedging, use fragments, keep responses terse. Code, commits, and security output stays normal. User can say "stop caveman" or "normal mode" to deactivate.

## Notes

Codex documents support for `SessionStart`, `PreToolUse`, `PermissionRequest`,
`PostToolUse`, `PreCompact`, `PostCompact`, `UserPromptSubmit`,
`SubagentStart`, `SubagentStop`, and `Stop` events. Matchers are not honored by
every event; `UserPromptSubmit` and `Stop` ignore matcher values.

Current repo config only uses `SessionStart`. jcodemunch enforcement in Codex
still relies on rules in `globals/codex/rules/default.rules` and generated
`globals/codex/AGENTS.md` rather than tool-level hooks. See
[jcodemunch.md](jcodemunch.md) for full details.

## Skill Visibility

Codex hook payloads include useful session, prompt, tool, and stop data, but the
documented event payloads do not expose a stable list of skills implicitly loaded
for a turn. Use hooks for prompt/tool/stop guardrails, not as the source of truth
for "which skills auto-loaded" until Codex exposes explicit skill-load metadata.

## Session Permissions

Agent permission policy is authored in `manifests/agent-permissions.json` and rendered with:

```sh
roborepo permissions
roborepo permissions --check
roborepo permissions --profile readonly
roborepo permissions --profile interactive
roborepo permissions --profile workspace
```

The manifest defines named profiles used by both Claude and Codex:

| Profile | Behavior |
| --- | --- |
| `readonly` | Read-only sandbox; Codex asks before escapes. |
| `interactive` | Workspace writes, shell network disabled, ask before escapes. |
| `workspace` | Workspace writes, shell network disabled, no approval prompts; blocked actions fail. |
| `networked` | Workspace writes with sandbox network access; ask before escapes. |

The renderer writes the generated permission block in `globals/codex/config.toml`, the generated shell prefix rules in `globals/codex/rules/default.rules`, and Claude `permissions.allow` / `permissions.deny` in `globals/claude/settings.json`.

Shell command prefix policy is active through `~/.codex/rules`, which is a symlink to `globals/codex/rules`. Git remote movement is denied there with `git push` and `git pull` prefix rules.

`~/.codex/config.toml` is different: it is an active local root config file, not a symlink. Existing machines need the root config merge/export workflow before new baseline session defaults appear in active Codex sessions.
