# Harness Parity Todo

## Todo

1. Implement per-repo skill installer.
   - Existing plan: `docs/plans/per-repo-skill-installer.md`.
   - Goal: install repo-local skills into both Claude and Codex without losing global skill parity.

2. Decide placement for global coding conventions.
   - Candidate rule topics:
     - pure utilities use `function`
     - named exports preferred
     - helpers at file bottom
     - no procedural comments
     - constants over loose enum/status strings
     - no emoji in UI; use icons where appropriate
   - Open question: compact global rules only, expanded skill references, or both.

3. Redesign managed/adopt/update installer model.
   - Clarify top-level choices: `managed` as repo-hosted symlink logic; `adopt` as copy/replicate/merge into user-owned global config.
   - Treat `agent prompt` as an adopt sub-option, alongside replace-existing-files and keep-existing-files behavior.
   - Define archive/not-adopted folder layout, idempotency rules for repeated adopt runs, and whether repo updates use `adopt` again or a separate update command.
   - Revisit whether a layered model is possible: harness repo baseline, global config overlay, local repo overlay.

## Open Decisions

- Whether stack-specific context should be expressed as skills only, rules only, or rules that trigger skills.
- How much local repo config should override global behavior automatically versus by explicit user opt-in.
