# RoboRepo

Claude Code & Codex global harness configuration with CLI support.

The repo installs shared rules, skills, hooks, MCP helpers, and maintenance commands into the local filesystem paths the harnesses already read.

Primary goals:

- keep Claude and Codex configuration aligned (where desired)
- reduce token overuse
- reproduce same harness configs across machines
- keep user-owned local config safe during updates

## Start Here

Supports macOS and Linux;
Windows support is there, but not really tested.

[Setup default configs and CLI](docs/guides/first-time-setup.md)

## Using the roborepo CLI

After [installing roborepo](docs/guides/first-time-setup.md), you have a `roborepo` command line tool.  
Install puts it on your `PATH`, so it works from any shell.

[View roborepo commands](docs/reference/services/roborepo-cli.md)

## Global Behavior

### Token Optimization / Efficiency

|                                                         |                                                                                                   |
| ------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| [jcodemunch-mcp](docs/reference/services/jcodemunch.md) | Code indexer that lets agents find relevant source through symbol search and targeted context.    |
| [jdocmunch-mcp](docs/reference/services/jdocmunch.md)   | Documentation indexer that lets agents query headings and sections instead of reading whole docs. |
| Caveman plugin                                          | Makes default agent output terse to reduce token usage.                                           |
| Minimal verification                                    | Agents run the narrowest useful check and report a `pass/fail` receipt.                           |

### Automatic Skill Helpers

|                              |                                                                                                                                         |
| ---------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| code-style                   | General cross-language coding conventions: naming, file organization, helper placement, comments, exports, readability.                 |
| javascript-typescript        | TypeScript/JavaScript utility code: ESM, lint/type errors, exports/imports, helpers, type safety, JS/TS style.                          |
| react                        | React, Next.js, Remix, and Vite React work touching JSX/TSX, components, hooks, client state, effects, routing UI, and React tests.     |
| test-harness                 | Choosing, running, and explaining tests; debugging CI failures; deciding scoped vs. full checks.                                        |
| supabase-integration-testing | Remote/real Supabase integration tests: RLS policies, RPC calls, migrations, service-role setup, anon access, unmocked DB/API behavior. |
| roborepo-support             | Working on this repo itself: shared skills, global rules, hooks, settings, and Claude/Codex parity.                                     |

### Commands

Use these when you want to intentionally start a named workflow.

|                       |                                                                                     |     |
| --------------------- | ----------------------------------------------------------------------------------- | --- |
| `/blog`               | Write a long-form architecture blog post about a real design decision.              |
| `/frontend-design`    | Apply Claude's frontend design workflow to build or review a substantial UI change. |
| `/technical-planning` | Create or revise a durable technical planning document.                             |

**Plain-Language Triggers**: Some named workflows can also be started in ordinary chat: "capture this", "write a blog post about this", or "make this a durable technical plan."

### Chat-Time Output

Lighter-weight behaviors that only generate messages in the conversation — no files written, no workflow started.

|                                                                     |                                                                                       |
| ------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| [Convention capture](docs/reference/services/convention-capture.md) | Agents surface newly confirmed conventions as inline recommendations during the chat. |

### Harness Specifics

#### Codex

- **Plugins:** GitHub
- **[Hooks](docs/reference/services/codex-hooks.md):** startup/resume activates caveman mode
- **Rules:** pre-approved safe commands for tests, builds, Docker, and local doctor checks
- **Model/features:** `gpt-5.5`, medium reasoning, hooks, JavaScript REPL, idle-sleep prevention

#### Claude

- **[Hooks](docs/reference/services/claude-hooks.md):** session hooks detect watcher status, auto-index docs, and remind agents to use
  jcodemunch/jdocmunch; tool hooks reduce broad source reads and trim noisy Bash output
- **Behavior flags:** thinking/away-summary stay quiet; dangerous-mode prompt skipped

## Maintaining the Harnesses

Harness source lives under `globals/`, with the data that drives the build/install scripts under
`manifests/`:

- `globals/agents/skills/` — shared skill source, global and exportable
- `globals/claude/` — Claude global rules, hooks, commands, settings baseline, and skill links
- `globals/codex/` — Codex global rules, hooks, settings baseline, and managed markers
- `manifests/` — `.tsv`/`.json` tables and prompts that drive install, verify, and render
- `local/skills/` — repo-only internal skills, never global or exported

Every element (rules, skills, commands, hooks, MCP, permissions, root config) is authored once and
fanned out to both harnesses. New to the setup? Start with
[How the Harnesses Work, and How We Build Parity](docs/reference/internal/harnesses-explained.md) —
it teaches what each element does natively, the defaults, and the parity pattern. For the quick
"which command changes element X" lookup, use
[Harness Anatomy and Parity](docs/reference/internal/harness-anatomy.md).

## Reference

### User Docs

- [First-Time Setup](docs/guides/first-time-setup.md)
- [Setup and Daily Use](docs/guides/setup-and-daily-use.md)
- [Install Workflow Choices](docs/guides/install-workflows.md)
- [roborepo CLI Commands](docs/reference/services/roborepo-cli.md)
- [roborepo CLI Reference](docs/reference/services/roborepo.md)
- [Documentation Index](docs/README.md)

### Under The Hood

- [How the Harnesses Work, and How We Build Parity](docs/reference/internal/harnesses-explained.md)
- [Harness Anatomy and Parity](docs/reference/internal/harness-anatomy.md)
- [How It Works](docs/reference/services/architecture.md)
- [Config Collision Handling](docs/reference/internal/config-collision-handling.md)
- [Rules Parity and Layering](docs/reference/internal/rules-parity-and-layering.md)
- [Skills And Slash Commands](docs/reference/internal/skills-and-commands.md)
- [Claude Hooks](docs/reference/services/claude-hooks.md)
- [Codex Hooks](docs/reference/services/codex-hooks.md)
