# Claude Hooks

Configured in `claude/settings.json` under `"hooks"`.

## SessionStart

**Trigger:** every new session or resume.

**What it does:** checks whether `jcmwatch` is running for the current directory by looking for a pidfile at `/tmp/jcmwatch-<md5-of-pwd>.pid` and verifying the pid is alive. Injects a system message telling the model either:
- index is current (watch is running) — no manual reindex needed
- watch is not running — suggests running `jcmindex` if index may be stale

Also reminds the model to use jcodemunch tools (`resolve_repo`, `search_symbols`, etc.) for code exploration instead of `Grep`/`Read`.

## PreToolUse: Grep|Glob

**Trigger:** model attempts to call `Grep` or `Glob`.

**What it does:** hard blocks the call with `"continue": false`. The stop reason instructs the model to retry using jcodemunch (`search_symbols`, `get_file_outline`, `find_references`, `get_context_bundle`). Treated as a redirect, not an error — model should immediately retry via jcodemunch.

## PreToolUse: Read

**Trigger:** model attempts to call `Read`.

**What it does:** soft nudge — allows the call but injects a reminder to prefer jcodemunch for exploration. `Read` is still permitted for targeted reads (known file paths, editing workflows, non-code files).

## PreToolUse: Bash

**Trigger:** model attempts to call `Bash`.

**What it does:** pipes the command through `minimize-bash-output.mjs`, which trims noisy stdout to a useful tail. Keeps Bash output small so it doesn't flood context.
