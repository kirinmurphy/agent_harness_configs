# RoboRepo

Version-controlled Claude Code and Codex global harness configuration and CLI helper.

The repo installs shared rules, skills, hooks, MCP helpers, and maintenance commands into the local filesystem paths the harnesses already read.

Primary goals:

- keep Claude and Codex behavior aligned
- reduce token waste through code and documentation indexing
- make global harness setup repeatable across machines
- keep user-owned local config safe during install and update

## Start Here

Works with Claude Code, Codex, or both.
Supports macOS and Linux; Windows support is available but less tested.

Setup both default configs and CLI [here](docs/guides/first-time-setup.md).

## Global Behavior

### General Behavior

Implemented across both Codex and Claude:

| Behavior                                                                | Description                                                                                              |
| ----------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| **[jcodemunch-mcp](docs/reference/services/jcodemunch.md)**             | Code indexer that lets agents find relevant source through symbol search and targeted context.           |
| **[jdocmunch-mcp](docs/reference/services/jdocmunch.md)**               | Documentation indexer that lets agents query headings and sections instead of reading whole docs.        |
| **Caveman plugin**                                                      | Makes default agent output terse to reduce token usage.                                                  |
| **Minimal verification**                                                | Agents run the narrowest useful check and report a `Verified: <command> -> <pass/fail/blocked>` receipt. |
| **[Convention capture](docs/reference/services/convention-capture.md)** | Agents flag newly confirmed conventions so the user can decide whether to save them.                     |

### Shared Skills

| Skill                       | Description                                                                                                                                  |
| --------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| **test-harness**            | Choosing, running, and explaining tests; debugging CI failures; deciding scoped vs. full checks.                                             |
| **technical-planning-docs** | Writing architecture notes, migration docs, runbooks, and design proposals with facts, recommendations, risks, and open questions separated. |
| **blog**                    | Long-form architecture blog posts with a fixed 6-beat storyline arc.                                                                         |
| **roborepo-support**       | Working on this repo itself: shared skills, global rules, hooks, settings, and Claude/Codex parity.                                       |
| **frontend-design**         | Production-grade UI components and pages; avoids generic AI aesthetics.                                                                      |

### Harness Notes

#### Codex

- **Plugins:** GitHub
- **Hooks:** startup/resume activates caveman mode
- **Rules:** pre-approved safe commands for tests, builds, Docker/Colima, and local doctor checks
- **Model/features:** `gpt-5.5`, medium reasoning, hooks, JavaScript REPL, idle-sleep prevention

#### Claude

- **Hooks:** session hooks detect watcher status, auto-index docs, and remind agents to use
  jcodemunch/jdocmunch; tool hooks reduce broad source reads and trim noisy Bash output
- **Convention capture:** `/capture-convention` slash command
- **Behavior flags:** thinking/away-summary stay quiet; dangerous-mode prompt skipped

## Using the `roborepo` CLI

`roborepo` is the single front door. Before it is installed on `PATH`, use the checked-out shim:
`./bin/roborepo`.

### Setup and Maintenance

| Command                    | What it does                                                                                                                                                |
| -------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `roborepo update`          | Re-applies the harness config on this machine: managed links, root config export, global command install, and shell wiring. Use after pulling repo changes. |
| `roborepo sync`            | Reviews live config under `~/.claude` and `~/.codex` and pulls intentional changes back into this repo.                                                     |
| `roborepo doctor`          | Runs harness health checks for config files, links, helper commands, dependencies, and generated outputs.                                                   |
| `roborepo verify`          | Runs post-install verification that the installed harness paths resolve correctly.                                                                          |
| `roborepo rules [--check]` | Renders generated Claude/Codex global instruction files, or verifies them with `--check`.                                                                   |

### Indexing

| Command                      | What it does                                                                         |
| ---------------------------- | ------------------------------------------------------------------------------------ |
| `roborepo index code [path]` | Runs a one-shot jcodemunch code index for the current directory or `[path]`.         |
| `roborepo index docs [path]` | Runs a one-shot jdocmunch documentation index for the current directory or `[path]`. |
| `roborepo watch code [path]` | Keeps the jcodemunch code index live while files change.                             |

### Skills

| Command                         | What it does                                                                                          |
| ------------------------------- | ----------------------------------------------------------------------------------------------------- |
| `roborepo skill export`         | Copies this repo's shared skills into the current target repo and leaves a shareable zip bundle.      |
| `roborepo skill install`        | Links a target repo's `.agents/skills` into existing `.claude/skills` and/or `.codex/skills` folders. |
| `roborepo skill link`           | Compatibility alias for `roborepo skill install`.                                                     |
| `roborepo skill sync [--check]` | Syncs this repo's shared skill links after adding or removing `agents/skills/<name>`.                 |

### MCP Setup

| Command                          | What it does                                                                                         |
| -------------------------------- | ---------------------------------------------------------------------------------------------------- |
| `roborepo mcp add <name-or-url>` | Registers an MCP server with Claude and Codex, including matching Claude permissions unless skipped. |

### Command Output

| Command                        | What it does                                                                   |
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

### Add or Edit Shared Skills

Shared skills live under:

```text
agents/skills/<name>/SKILL.md
```

After adding or removing a shared skill, update and verify harness links:

```sh
roborepo skill sync
roborepo skill sync --check
```

Add the user-facing skill description to this README's [Shared Skills](#shared-skills) table.
For the mechanics of how Claude and Codex see shared skills, see
[How It Works](docs/reference/services/architecture.md#shared-skills-canonical-source--per-harness-fan-out).

### Edit Global Rules

Generated global instruction files:

- `claude/CLAUDE.md`
- `codex/AGENTS.md`

Edit source fragments instead:

- `rules/shared/` for shared behavior
- `rules/claude/` for Claude-only behavior
- `rules/codex/` for Codex-only behavior

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
- [Claude Hooks](docs/reference/services/claude-hooks.md)
- [Codex Hooks](docs/reference/services/codex-hooks.md)
