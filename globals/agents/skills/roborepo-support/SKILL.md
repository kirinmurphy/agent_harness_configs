---
name: roborepo-support
description: >
  Work on this repo — the version-controlled global config that
  symlinks into ~/.claude and ~/.codex. Use when adding or editing a shared skill,
  changing global agent rules (CLAUDE.md / AGENTS.md), hooks, settings, commands,
  or keeping Claude/Codex parity. Activates only when the task touches global harness
  config or skill authoring, in any repo. Triggers: "add a skill", "edit global
  rules", "roborepo support", "harness config", "skill authoring", editing files in this repo.
---

# Roborepo Support & Skill Authoring

For work on this repo: the version-controlled source for global
Claude + Codex configuration. The local checkout path is user-specific; install
scripts link the relevant HOME config paths back to this repo. This skill carries
the gotchas that are easy to get wrong; it does not duplicate the repo's own docs.

**Read these first when relevant** (they are the source of truth):
- `README.md` — overview of what's shared and per-harness.
- `docs/architecture.md` — Relationship, Symlink Map, Sync Flow.
- `docs/config-collision-handling.md` — conflict rules.
- `docs/claude-hooks.md`, `docs/codex-hooks.md` — hook behavior.

## The skill symlink model (the #1 thing to get right)

The canonical shared source is **`globals/agents/skills/<name>/`**. The two harnesses reach it
differently because Codex and Claude scan different paths:

1. **HOME → repo (install-time).** `scripts/install/main.sh` links HOME dirs into the
   repo. Codex scans `~/.agents/skills` **exclusively** (no `~/.codex/skills` fallback), so
   the canonical link is `~/.agents/skills -> <repo>/globals/agents/skills`. Claude
   scans `~/.claude/skills -> <repo>/globals/claude/skills`. Already done on a set-up machine;
   you normally do NOT touch this.

2. **Claude per-skill → shared source (in-repo).** Inside the repo, `globals/claude/skills/<name>` is
   an individual symlink pointing to `../../agents/skills/<name>`. Codex needs NO per-skill
   intermediate — it reads `globals/agents/skills/` directly via `~/.agents/skills`.

Net: a skill's source lives once in `globals/agents/skills/<name>/`. Codex sees it directly; Claude
sees it through its per-skill symlink.

## Adding a shared skill

1. Create the source: `globals/agents/skills/<name>/SKILL.md` (plus any support files).
2. Create the Claude per-skill symlink. **Always use the script** — it derives links from
   `globals/agents/skills/` and is idempotent, so it can't drift:
   ```bash
   scripts/build/link-skills.sh
   ```
   (Manual equivalent, if ever needed: `ln -s ../../agents/skills/<name> globals/claude/skills/<name>`.
   Prefer the script.)
3. Add a one-line entry under **Shared Skills** in `README.md`.
4. Verify everything resolves: `scripts/build/link-skills.sh --check` (or `scripts/doctor.sh`,
   which derives the skill list the same way).

The source folder alone is NOT enough for Claude — without its per-skill symlink Claude
won't see the skill, and the active skill list only refreshes on harness reload.
There is no auto-link-on-create; `link-skills.sh` is the mechanism that makes it
reliable, so run it after adding any skill.

A `Write|Edit` PreToolUse hook (`globals/claude/hooks/roborepo-write-guard.mjs`,
registered in `globals/claude/settings.json`) fires from any repo when a path under
`~/.claude` or `~/.codex` is written. For read-mostly assets, it reminds that the
file is symlinked into this repo. For mutable root config (`~/.claude/settings.json`,
`~/.codex/config.toml`), it reminds that the active file is local and only portable
defaults should be merged back into the repo baseline. It is a reminder, not a block.

## SKILL.md frontmatter

- `name`: kebab-case, matches the folder name.
- `description`: a `>` block. State plainly WHAT the skill does and WHEN to trigger
  it (include trigger phrases and clear skip conditions). The description is the only
  thing the agent sees when deciding to load the skill — make it discriminating, not
  generic. Body holds the actual instructions, loaded only on invocation.

## Editing global rules / behavior

- Claude global rules: `globals/claude/CLAUDE.md`. Codex: `globals/codex/AGENTS.md`. Keep behavior
  intent in parity across both unless a difference is intentional (note it).
- Hooks: `globals/claude/hooks/` + `globals/claude/settings.json`; `globals/codex/hooks.json`. Automated
  "always do X" behaviors must be hooks — the harness runs them, not the model.
- Settings/permissions: `globals/claude/settings.json`, `globals/codex/config.toml`.
- After editing a symlinked read-mostly asset, the change is live immediately (no copy/sync).
  Mutable root config (`globals/claude/settings.json`, `globals/codex/config.toml`) is exported into HOME as
  active local files, not symlinked.
- On collisions between HOME and repo, follow `docs/config-collision-handling.md` —
  flag conflicts, don't guess.

## Parity principle

This repo's whole point is Claude/Codex parity. When you add or change a capability
on one harness, ask whether the other needs the mirror, and say so explicitly if you
intentionally leave them different.
