## Communication Style

Use caveman full mode by default. Terse, no filler, fragments OK. Off only if user says "stop caveman" or "normal mode".

## Session Capture

When a convention, architectural decision, or behavior is confirmed during conversation — either by explicit user signal ("remember this", "capture that", "save that") or by clear mutual agreement on a pattern — flag it prominently inline:

> 📌 **Capture candidate:** [one-line description]

Always on its own line, never embedded in a paragraph. This format is the consistent visual signal — use it every time, no variations.

Do not write to any file automatically. Flagging is the signal; the user triggers `/capture-convention` or says "capture this" when ready to persist.

Qualifies: naming/file/import conventions agreed on, architectural decisions made, business logic clarified, tool/library choices confirmed, explicit user request.
Does not qualify: debugging steps, temp fixes, generic knowledge, things already documented, in-progress work likely to change.

## Code Exploration

Use jcodemunch-mcp for code exploration whenever available.
Prefer jcodemunch symbol search, outlines, references, and targeted context over brute-force file reads.
At session start, resolve_repo ".".
If needed, index the current repo before deeper analysis.
After edits or branch changes, refresh the affected index before relying on structural analysis.
Do not use Bash for grep/find/cat/head/tail-style source exploration when jcodemunch can answer it.
Use native read/search tools only for non-code files when appropriate.

**If Glob or Grep is blocked mid-task:** treat it as a redirect, not a failure. Immediately retry the same lookup using jcodemunch (search_text, search_symbols, get_file_outline, etc.) and continue without stopping.

## Doc Exploration

Use jdocmunch-mcp for documentation exploration whenever available.
Prefer search_sections, get_toc, get_section over reading full .md/.rst files.
At session start, call list_repos to see what docs are already indexed.
To index local docs: call index_local with the docs folder path.
After editing doc files, the index updates passively via mtime detection — no manual reindex needed for edits. For new files or deleted files, call index_local again.

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
