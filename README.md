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

## Global Behavior

### Token Optimization / Efficiency

|                                                                     |                                                                                                   |
| ------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| [jcodemunch-mcp](docs/reference/services/jcodemunch.md)             | Code indexer that lets agents find relevant source through symbol search and targeted context.    |
| [jdocmunch-mcp](docs/reference/services/jdocmunch.md)               | Documentation indexer that lets agents query headings and sections instead of reading whole docs. |
| Caveman plugin                                                      | Makes default agent output terse to reduce token usage.                                           |
| Minimal verification                                                | Agents run the narrowest useful check and report a `pass/fail` receipt.                           |
| [Convention capture](docs/reference/services/convention-capture.md) | Agents flag newly confirmed conventions so the user can decide whether to save them.              |

### Automatic Helpers

These have no slash command. They load when the task, files, or repo context makes them relevant.

##### Code & Frontend

|                           |                                                                                                                                     |
| ------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| code-style                | General cross-language coding conventions: naming, file organization, helper placement, comments, exports, readability.             |
| javascript-typescript     | TypeScript/JavaScript utility code: ESM, lint/type errors, exports/imports, helpers, type safety, JS/TS style.                      |
| react                     | React, Next.js, Remix, and Vite React work touching JSX/TSX, components, hooks, client state, effects, routing UI, and React tests. |

##### Testing

|                                  |                                                                                                                                         |
| -------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| test-harness                     | Choosing, running, and explaining tests; debugging CI failures; deciding scoped vs. full checks.                                        |
| supabase-integration-testing     | Remote/real Supabase integration tests: RLS policies, RPC calls, migrations, service-role setup, anon access, unmocked DB/API behavior. |

##### Repo

|                      |                                                                                                     |
| -------------------- | --------------------------------------------------------------------------------------------------- |
| roborepo-support     | Working on this repo itself: shared skills, global rules, hooks, settings, and Claude/Codex parity. |

### Commands

Use these when you want to intentionally start a named workflow.

|                       |               |                                                                                                                                                  |
| --------------------- | ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `/blog`               | Claude, Codex | Write a long-form architecture blog post about a real design decision.                                                                           |
| `/design-review`      | Claude, Codex | Apply the frontend design workflow to build or review a substantial UI change.                                                                   |
| `/technical-planning` | Claude, Codex | Create or revise a durable technical planning document.                                                                                          |

#### Plain-Language Triggers

Some named workflows can also be started in ordinary chat: "capture this", "write a blog post about this", or "make this a durable technical plan."

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

## Using the `roborepo` CLI

`roborepo` is the single front door. Install puts it on your `PATH`, so it works from any shell.

> If `roborepo` is not found, run `roborepo doctor` (or `./bin/roborepo doctor` before the first
> install) — it reports whether the command is installed and on `PATH`, with the exact fix.

### Setup and Maintenance

|                            |                                                                                                                                                             |
| -------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `roborepo update`          | Re-applies the harness config on this machine: managed links, root config export, global command install, and shell wiring. Use after pulling repo changes. |
| `roborepo sync`            | Reviews live config under `~/.claude` and `~/.codex` and pulls intentional changes back into this repo.                                                     |
| `roborepo doctor`          | Runs harness health checks for config files, links, helper commands, dependencies, and generated outputs.                                                   |
| `roborepo verify`          | Runs post-install verification that the installed harness paths resolve correctly.                                                                          |
| `roborepo rules [--check]` | Renders generated Claude/Codex global instruction files, or verifies them with `--check`.                                                                   |

### Indexing

|                              |                                                                                      |
| ---------------------------- | ------------------------------------------------------------------------------------ |
| `roborepo index code [path]` | Runs a one-shot jcodemunch code index for the current directory or `[path]`.         |
| `roborepo index docs [path]` | Runs a one-shot jdocmunch documentation index for the current directory or `[path]`. |
| `roborepo watch code [path]` | Keeps the jcodemunch code index live while files change.                             |

### Skills

|                                     |                                                                                                         |
| ----------------------------------- | ------------------------------------------------------------------------------------------------------- |
| `roborepo skill new`                | Scaffolds a shared skill or slash command and updates manifests, generated links, commands, and README. |
| `roborepo skill export`             | Copies this repo's shared skills into the current target repo and leaves a shareable zip bundle.        |
| `roborepo skill install`            | Links a target repo's `.agents/skills` into existing `.claude/skills` and/or `.codex/skills` folders.   |
| `roborepo skill link`               | Compatibility alias for `roborepo skill install`.                                                       |
| `roborepo skill sync [--check]`     | Syncs this repo's shared skill links after adding or removing `globals/agents/skills/<name>`.           |
| `roborepo skill commands [--check]` | Renders generated slash commands from `manifests/slash-commands.json`, or verifies them with `--check`. |

### MCP Setup

|                                  |                                                                                                      |
| -------------------------------- | ---------------------------------------------------------------------------------------------------- |
| `roborepo mcp add <name-or-url>` | Registers an MCP server with Claude and Codex, including matching Claude permissions unless skipped. |

### Command Output

|                                |                                                                                |
| ------------------------------ | ------------------------------------------------------------------------------ |
| `roborepo run <cmd> [args...]` | Runs a command and prints a trimmed output tail so noisy checks stay readable. |

Run:

```sh
roborepo --help
```

Full flags and examples live in [roborepo CLI Reference](docs/reference/services/roborepo.md).

### Index Code and Docs

Code indexing powers `jcodemunch-mcp`, so agents can search symbols and targeted source context
instead of reading broad file dumps:

```sh
roborepo index code
roborepo watch code
```

Documentation indexing powers `jdocmunch-mcp`, so agents can search sections and headings:

```sh
roborepo index docs
```

## Maintainer Workflows

These change the harness source repo itself.

### Repository Layout

Global harness source lives under `globals/`:

- `globals/agents/skills/` — shared skill source, global and exportable
- `globals/claude/` — Claude global rules, hooks, commands, settings baseline, and skill links
- `globals/codex/` — Codex global rules, hooks, settings baseline, and managed markers

`manifests/` holds the data that drives the install/verify/sync scripts — the `.tsv` tables
(managed paths, source-file checklist, rule targets, etc.), `.json` config, and prompt
templates under `manifests/prompts/`.

Repo-only internal skills live under `local/skills/` and link only into this repo's
project-scope `.claude/skills/` and `.agents/skills/` folders.

### Add or Edit Shared Skills

Shared skills live under:

```text
globals/agents/skills/<name>/SKILL.md
```

For new skills or commands, prefer the scaffold:

```sh
roborepo skill new
```

It asks whether to create an automatic helper skill, a skill-backed slash
command, or a standalone slash command, then updates the relevant manifests,
README rows, generated links, and generated command files.

After manually adding or removing a shared skill, update and verify harness
links:

```sh
roborepo skill sync
roborepo skill sync --check
```

Add the user-facing skill description to this README's `Automatic Helpers` or
`Commands` section, depending on whether it has a slash command.
For the mechanics of how Claude and Codex see shared skills, see
[How It Works](docs/reference/services/architecture.md#shared-skills-canonical-source--per-harness-fan-out).

If the skill should also have an explicit slash command, add that command to
`manifests/slash-commands.json`, then render and check:

```sh
roborepo skill commands
roborepo skill commands --check
```

### Edit Global Rules

Generated global instruction files:

- `globals/claude/CLAUDE.md`
- `globals/codex/AGENTS.md`

Edit source fragments instead:

- `globals/rules/shared/` for shared behavior
- `globals/rules/claude/` for Claude-only behavior
- `globals/rules/codex/` for Codex-only behavior

Then render and check:

```sh
roborepo rules
roborepo rules --check
```

## Reference

### User Docs

- [First-Time Setup](docs/guides/first-time-setup.md)
- [Setup and Daily Use](docs/guides/setup-and-daily-use.md)
- [Install Workflow Choices](docs/guides/install-workflows.md)
- [roborepo CLI Reference](docs/reference/services/roborepo.md)
- [Documentation Index](docs/README.md)

### Under The Hood

- [How It Works](docs/reference/services/architecture.md)
- [Config Collision Handling](docs/reference/internal/config-collision-handling.md)
- [Rules Parity and Layering](docs/reference/internal/rules-parity-and-layering.md)
- [Skills And Slash Commands](docs/reference/internal/skills-and-commands.md)
- [Claude Hooks](docs/reference/services/claude-hooks.md)
- [Codex Hooks](docs/reference/services/codex-hooks.md)
