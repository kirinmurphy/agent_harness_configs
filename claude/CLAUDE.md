## Communication Style

Use caveman full mode by default. Terse, no filler, fragments OK. Off only if user says "stop caveman" or "normal mode".

## Harness Config

Stable global Claude config is version-controlled in this repo.
Prefer editing tracked repo files instead of adding ad hoc files under `~/.claude`.
If useful config is added directly under `~/.claude`, capture it in the repo or update `scripts/sync-from-home.sh` / `scripts/install-symlinks.sh`.

## Code Exploration

Use jcodemunch-mcp for code exploration whenever available.
Prefer jcodemunch symbol search, outlines, references, and targeted context over brute-force file reads.
At session start, resolve_repo ".".
If needed, index the current repo before deeper analysis.
After edits or branch changes, refresh the affected index before relying on structural analysis.
Do not use Bash for grep/find/cat/head/tail-style source exploration when jcodemunch can answer it.
Use native read/search tools only for non-code files when appropriate.

**If Glob or Grep is blocked mid-task:** treat it as a redirect, not a failure. Immediately retry the same lookup using jcodemunch (search_text, search_symbols, get_file_outline, etc.) and continue without stopping.

## Verification

Before running lint, typecheck, test, or build, inspect the available package scripts or project tooling.
Only run checks that are actually implemented in this repository.
Prefer the smallest verification command that matches the change.
Prefer file-scoped lint and targeted tests when possible.
Prefer targeted smoke tests for edited scripts over full repo checks.
Run full checks only for shared app code, build/tooling config, dependency changes, generated types, auth/payments/data migrations, CI scripts, broad refactors, cross-cutting types/config, CI risk, or explicit user request.
If a full check seems useful but likely slow, state why before running it.
Avoid watch, verbose, and debug modes unless explicitly requested.
Keep Bash output small; use `harness-run <command> ...` or commands that end with `2>&1 | tail -n 120` when a full log is unnecessary.
For direct TypeScript compiler runs, prefer `tsc --noEmit --pretty false`.
Summarize command results instead of pasting long logs.
Final response should include `Verified: <command> -> <pass|fail|blocked>` when verification was run or attempted.
