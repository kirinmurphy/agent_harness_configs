# First-Time Setup

Use this guide to install the repo-managed configs and put `roborepo` on your `PATH`.

Works with Claude Code, Codex, or both. Supports macOS and Linux; Windows support is available but
less tested.

## Install Configs And CLI

Preview install changes:

```sh
./bin/roborepo update --dry-run
```

Install on a new machine:

```sh
./bin/roborepo update
```

After the first install, use `roborepo` from anywhere:

```sh
roborepo
roborepo update
roborepo doctor
roborepo verify
```

## Choose an Install Type

The installer has two ownership models:

| Workflow | Use when | Result |
| --- | --- | --- |
| `managed` | This repo owns the global defaults. | Global config paths point into this repo through symlinks. |
| `adopt` | You already have local Claude/Codex config you want to keep. | Local config remains user-owned while repo defaults are copied, staged, or merged intentionally. |

No install workflow deletes existing user config. When the installer finds a collision it preserves
the existing file and either asks what to do or stops before changing that path.

For the full decision model, see [Install Workflow Choices](install-workflows.md). For exact
collision behavior, see [Config Collision Handling](../reference/internal/config-collision-handling.md).
