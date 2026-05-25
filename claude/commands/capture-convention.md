---
description: Capture new conventions and behaviors from this session into project docs. Trigger on /capture-convention, "capture this", "save that convention", "let's document that", "remember this", or any explicit user signal to persist something.
allowed-tools: Read, Glob, Grep, Edit, Write, Bash(git diff:*), Bash(git log:*), Bash(git status:*), Bash(mkdir:*)
---

# Capture Convention

Review the current conversation to extract **new conventions and app behaviors** established during this session. Persist them into the appropriate repo's documentation so they survive context clearing.

**Route each item to the right repo** — local project conventions go into the current repo; harness-wide behaviors go into `harness_configs`. See Step 5.

## Step 1: Confirm project root

Determine the current working directory and confirm it is a git repo. If not, ask the user which repo to write to.

## Step 2: Survey existing documentation

Read all relevant docs in the repo:
- `CLAUDE.md` (root and any nested ones)
- `.claude/rules/` files
- Any `docs/` directory markdown files
- Any other project markdown files (README, ARCHITECTURE, etc.)

Build an inventory of what is already documented.

## Step 3: Review conversation context

Scan the full conversation and sort findings into two buckets:

### Bucket A: Coding Conventions (destination: repo's `CLAUDE.md` or `.claude/rules/`)
- Naming patterns, file organization, import conventions
- Error handling approach, testing patterns
- Tool/library usage patterns
- Project-specific do/don't rules
- Architectural patterns (component structure, data flow, state management)

**These MUST be concise.** One-liners or short bullet points. Write them as direct instructions, not explanations. Examples:
- "Use named exports, not default exports"
- "Co-locate test files next to source files as `*.test.ts`"
- "Handle errors at the route level, not in individual service functions"

### Bucket B: App Behavior & Business Logic (destination: repo-specific markdown files)
- Feature behaviors and user flows
- Business logic rules and edge cases
- UI behavior specifications
- Use case descriptions
- API contract decisions

These can be more descriptive since they document *what the app does*.

### What NOT to capture
- Generic coding knowledge any developer would know
- Session-specific debugging steps or temporary fixes
- Things already documented in existing project files
- Implementation details obvious from reading the code

## Step 4: Deduplicate

Compare every item against existing docs from Step 2. Drop anything already covered. Merge related items.

## Step 5: Determine file placement

**First, classify scope:**

> Does this rule apply only in this repo? → **local**
> Does it describe how the agent should behave in *any* repo? → **global harness**

Global harness items (caveman behavior, jcodemunch defaults, verification discipline, hook patterns) go into `~/projects/live_projects/harness_configs/claude/CLAUDE.md` or a new doc under `harness_configs/docs/`. Do not invent new global rules — only promote items explicitly confirmed as cross-repo behavior.

**Bucket A (local conventions):**
- Add to the current repo's `CLAUDE.md` under a relevant section
- Or add as a rule file in `.claude/rules/` if that pattern is already in use
- Match whichever pattern the project already uses

**Bucket B (local app behavior):**
- Add to existing repo markdown docs if a relevant file exists
- Create a new file in `docs/` only if no suitable file exists and content justifies it
- Name descriptively (e.g., `docs/authentication-flow.md`)

## Step 6: Present the plan

Before making any changes, show the user:

1. **Conventions to add** (Bucket A) -- the exact lines and where they'll go
2. **App behaviors to document** (Bucket B) -- summary of content and target files
3. **Skipped items** -- anything filtered out and why

Ask the user to confirm or adjust before proceeding.

## Step 7: Apply changes

After confirmation:
- Edit existing files by appending to relevant sections
- Keep convention entries as short bullet points -- no paragraphs
- Match existing formatting and tone
- Do NOT reorganize or rewrite existing content

## Guidelines

- Be selective. 3 important items > 15 trivial ones.
- Write for a future Claude session or developer with zero context about this conversation.
- Every item should be actionable.
- If nothing new worth capturing was established, say so honestly.
