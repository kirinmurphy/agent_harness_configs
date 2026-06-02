---
name: harness-config
description: >
  Work on the harness_configs repo — the version-controlled global config that
  symlinks into ~/.claude and ~/.codex. Use when adding or editing a shared skill,
  changing global agent rules (CLAUDE.md / AGENTS.md), hooks, settings, commands,
  or keeping Claude/Codex parity. Activates only when the task touches global harness
  config or skill authoring, in any repo. Triggers: "add a skill", "edit global
  rules", "harness config", "skill authoring", editing files under harness_configs/.
---

# Harness Config & Skill Authoring

For work on the **harness_configs** repo: the version-controlled source for global
Claude + Codex configuration. Lives at `~/projects/live_projects/harness_configs`
and symlinks into `~/.claude` and `~/.codex`. This skill carries the gotchas that
are easy to get wrong; it does not duplicate the repo's own docs.

**Read these first when relevant** (they are the source of truth):
- `harness_configs/README.md` — overview of what's shared and per-harness.
- `harness_configs/docs/architecture.md` — Relationship, Symlink Map, Sync Flow.
- `harness_configs/docs/config-collision-handling.md` — conflict rules.
- `harness_configs/docs/claude-hooks.md`, `docs/codex-hooks.md` — hook behavior.

## The two-level symlink model (the #1 thing to get right)

There are **two** symlink levels. Mixing them up is the common mistake.

1. **HOME → repo (install-time).** `scripts/install-symlinks.sh` links whole dirs
   from HOME into the repo, e.g. `~/.claude/skills -> harness_configs/claude/skills`
   and `~/.codex/skills -> harness_configs/codex/skills`. Already done on a set-up
   machine. You normally do NOT touch this.

2. **Per-harness → shared source (in-repo).** Inside the repo, `claude/skills/<name>`
   and `codex/skills/<name>` are individual symlinks pointing to `../../skills/<name>`,
   the single shared source. Each shared skill needs its own per-harness symlink.

Net: a skill's source lives once in `skills/<name>/`, but is reachable by the
harnesses only through the level-2 per-skill symlinks.

## Adding a shared skill

1. Create the source: `skills/<name>/SKILL.md` (plus any support files).
2. Create the level-2 symlinks. **Always use the script** — it derives links from
   `skills/` and is idempotent, so it can't drift:
   ```bash
   scripts/link-skills.sh
   ```
   (Manual equivalent, if ever needed: `ln -s ../../skills/<name> claude/skills/<name>`
   and the same for `codex/`. Prefer the script.)
3. Add a one-line entry under **Shared Skills** in `README.md`.
4. Verify everything resolves: `scripts/link-skills.sh --check` (or `scripts/doctor.sh`,
   which derives the skill list the same way).

The source folder alone is NOT enough — without the level-2 symlinks the harnesses
won't see the skill, and the active skill list only refreshes on harness reload.
There is no auto-link-on-create; `link-skills.sh` is the mechanism that makes it
reliable, so run it after adding any skill.

A `Write|Edit` PreToolUse hook (`claude/hooks/harness-config-write-guard.mjs`,
registered in `claude/settings.json`) fires from any repo when a path under
`~/.claude` or `~/.codex` is written: it reminds that the file is symlinked into
this repo, and on a NEW path tells the agent to author in `skills/` + link rather
than dropping a plain file into HOME. It is a reminder, not a block.

## SKILL.md frontmatter

- `name`: kebab-case, matches the folder name.
- `description`: a `>` block. State plainly WHAT the skill does and WHEN to trigger
  it (include trigger phrases and clear skip conditions). The description is the only
  thing the agent sees when deciding to load the skill — make it discriminating, not
  generic. Body holds the actual instructions, loaded only on invocation.

## Editing global rules / behavior

- Claude global rules: `claude/CLAUDE.md`. Codex: `codex/AGENTS.md`. Keep behavior
  intent in parity across both unless a difference is intentional (note it).
- Hooks: `claude/hooks/` + `claude/settings.json`; `codex/hooks.json`. Automated
  "always do X" behaviors must be hooks — the harness runs them, not the model.
- Settings/permissions: `claude/settings.json`, `codex/config.toml`.
- After editing a symlinked file, the change is live immediately (no copy/sync).
- On collisions between HOME and repo, follow `docs/config-collision-handling.md` —
  flag conflicts, don't guess.

## Parity principle

This repo's whole point is Claude/Codex parity. When you add or change a capability
on one harness, ask whether the other needs the mirror, and say so explicitly if you
intentionally leave them different.
