---
name: test-harness
description: Use when choosing, adding, running, or explaining tests; debugging CI failures; validating code edits; or deciding whether scoped checks or full checks are appropriate.
---

# Test Harness

Keep verification small, native to the repo, and explicit.

## Workflow

1. Discover commands from repo files before guessing: `package.json`, `pyproject.toml`, `Makefile`, `justfile`, `taskfile`, CI config, or docs.
2. Choose the smallest check that proves touched behavior.
3. Prefer scoped format/lint/type/test commands when available.
4. Run full checks only for shared app code, build/tooling config, dependency changes, generated types, auth/payments/data migrations, CI scripts, broad refactors, cross-cutting types/config, CI risk, or explicit user request.
5. If output may be large, use `harness-run <command> ...` or redirect to `/tmp` and show only useful failure/pass lines.
6. Final response includes `Verified: <command> -> <pass|fail|blocked>`.

## Blocked Verification

Use `blocked` only when the command cannot run because of missing dependencies, network/sandbox restrictions, unavailable services, or unclear repo setup. Include the exact command attempted.
