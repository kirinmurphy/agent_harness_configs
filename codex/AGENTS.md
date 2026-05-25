Code exploration:
- use jcodemunch-mcp for code lookup whenever available
- prefer symbol search, outlines, references, and targeted context bundles over reading full files
- do not use Bash for grep/find/cat/head/tail-style source exploration when jcodemunch can answer it
- use native read/search tools only for non-code files or targeted editing reads
At session start, resolve_repo ".".
If the repo is not indexed, index_folder ".".
After meaningful file edits, re-index changed files before further analysis.

Harness config:
- stable global Codex config is version-controlled in this repo
- prefer editing tracked repo files instead of adding ad hoc files under `~/.codex`
- if useful config is added directly under `~/.codex`, capture it in the repo or update `scripts/sync-from-home.sh` / `scripts/install-symlinks.sh`

Verification:
- default to smallest check that proves touched behavior
- before testing, discover repo-native commands from package.json, pyproject.toml, Makefile, justfile, taskfile, or docs; do not invent commands when a repo advertises its own
- only run checks that are implemented in the current repository
- prefer formatting/lint/type checks scoped to touched files when tool supports it
- prefer targeted smoke tests for edited scripts over full repo checks
- run full repo checks only for shared app code, build/tooling config, dependency changes, generated types, auth/payments/data migrations, CI scripts, broad refactors, cross-cutting types/config, CI risk, or explicit user request
- if a full check seems useful but likely slow, state why before running it
- do not run slow whole-repo tooling just because it exists
- avoid watch, verbose, and debug modes unless explicitly requested
- keep command output small; use `harness-run <command> ...` when a command may print a large log
- final response should include `Verified: <command> -> <pass|fail|blocked>` when verification was run or attempted

Session capture:
- when convention, architectural decision, or behavior confirmed — by explicit user signal or clear mutual agreement — flag prominently on its own line: `> 📌 **Capture candidate:** [one-line description]`
- always own line, never embedded in paragraph; same format every time, no variations
- do not write to any file automatically; flagging only; user triggers capture when ready
- qualifies: naming/file/import conventions, architectural decisions, business logic, tool choices, explicit user request
- does not qualify: debugging steps, temp fixes, generic knowledge, already-documented things, in-progress work

Communication:
- always use caveman full by default
- default to maximum brevity
- keep technical accuracy, exact commands, and exact file paths
- do not restate solved context unless needed for the next action
- do not repeat points already made
- do not narrate intermediary thinking unless it changes the action, decision, or user-visible result
- keep status updates as short as possible
- switch to normal mode only when I explicitly say normal mode or stop caveman
