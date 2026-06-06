#!/usr/bin/env node
// roborepo — one CLI for everything a consumer of harness_configs does in their own repo.
//
// This file is the orchestrator: usage text, the interactive menu, and the dispatch table.
// The actual subcommand implementations live under scripts/cli/, grouped by category:
//
//   cli/skills.mjs   skill export / skill link
//   cli/index.mjs    index code|docs, watch code, run
//   cli/mcp.mjs      mcp add (Claude + Codex registration)
//   cli/paths.mjs    shared repoRoot / sharedSkillsDir
//   cli/skill-lib.mjs  shared Node core (zip, prompts, symlink helpers)
//
// Nested subcommands, grouped by category so the surface is scannable:
//
//   roborepo                       no args -> interactive menu (arrow keys + numbered fallback)
//
//   skill   work with skills in the current repo
//     roborepo skill export        bundle shared skills into a .zip + copy into this repo
//     roborepo skill link          symlink this repo's .agents/skills into .claude/skills + .codex/skills
//
//   index   index the current repo for the MCP servers
//     roborepo index code [path]   jcodemunch  (code index)
//     roborepo index docs [path]   jdocmunch   (docs index)
//
//   mcp     register MCP servers with Claude + Codex
//     roborepo mcp add <name-or-url> [--scope=user|local|project] [--name=<name>] [--dry-run] [--only-claude|--only-codex] [--skip-claude-permission]
//     roborepo addMCP <name-or-url>  alias for mcp add
//
//   watch   keep an index live
//     roborepo watch code [path]   jcodemunch watch
//
//   run     run a command, capturing + truncating noisy output
//     roborepo run <cmd> [args...]
//
//   lifecycle  maintain the harness_configs install on this machine
//     roborepo update  [--dry-run]   re-apply repo-managed config (symlinks, commands, shell)
//       (the FIRST install is the shell bootstrap scripts/roborepo-install.sh — that is what
//        puts roborepo on PATH; from then on you only ever `update`)
//     roborepo sync                  review/pull live config back into the repo
//     roborepo doctor  [--installed] health check
//     roborepo verify                post-install verification
//
// [path] is optional everywhere it appears; it defaults to the current directory and may be
// relative or absolute — roborepo always resolves it to an absolute path before use.
//
// MAINTAINER-only scripts (render-rules.sh, link-skills.sh, test-*.sh) are deliberately NOT
// exposed here — they edit the harness_configs source itself, not anything a consumer touches.
// The lifecycle verbs above dispatch to the existing bash scripts (roborepo-install.sh, etc.);
// those filenames are an internal detail.

import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { selectMenu } from "./cli/skill-lib.mjs";
import { repoRoot } from "./cli/paths.mjs";
import { skillLink, skillExport } from "./cli/skills.mjs";
import { indexCode, indexDocs, watchCode, runCmd } from "./cli/index.mjs";
import { mcpAdd } from "./cli/mcp.mjs";

const argv = process.argv.slice(2);

// --------------------------------------------------------------------------- help

function usage() {
  console.log(`roborepo — harness_configs CLI

usage:
  roborepo                       interactive menu

  roborepo skill export [--yes] [--on-conflict=skip|override]
  roborepo skill link  [--dry-run] [--uninstall]

  roborepo index code  [path]
  roborepo index docs  [path]
  roborepo mcp add <name-or-url> [--scope=user|local|project] [--name=<name>] [--dry-run] [--only-claude|--only-codex] [--skip-claude-permission]
  roborepo addMCP <name-or-url>  alias for "mcp add"
  roborepo watch code  [path]

  roborepo run <cmd> [args...]

  roborepo update  [--dry-run]   re-apply harness config (first install: scripts/roborepo-install.sh)
  roborepo sync                  pull live config back into the repo
  roborepo doctor  [--installed] health check
  roborepo verify                post-install verification

  roborepo --help | -h

[path] is optional (defaults to the current directory) and may be relative or absolute.`);
}

// Dispatch to a maintainer/lifecycle bash script in this repo, passing through args and
// the exit code. These scripts resolve their own repo root, so cwd does not matter.
function runRepoScript(relScript, args) {
  const script = path.join(repoRoot, relScript);
  if (!fs.existsSync(script)) {
    console.error(`missing script: ${script}`);
    process.exit(1);
  }
  const r = spawnSync("bash", [script, ...args], { stdio: "inherit" });
  if (r.error) {
    console.error(`failed to run ${relScript}: ${r.error.message}`);
    process.exit(1);
  }
  process.exit(r.status ?? 1);
}

// --------------------------------------------------------------------------- menu

async function interactiveMenu() {
  // Ordered by significance: setup first, then day-to-day, then skills, then maintenance.
  const items = [
    { header: "Setup" },
    { label: "update", value: ["update"], desc: "re-apply harness config on this machine (pick up new config)" },

    { header: "Day to day" },
    { label: "index code", value: ["index", "code"], desc: "index this repo's code for jcodemunch" },
    { label: "index docs", value: ["index", "docs"], desc: "index this repo's docs for jdocmunch" },
    { label: "mcp add", value: ["mcp", "add"], desc: "register an MCP server with Claude + Codex" },
    { label: "watch code", value: ["watch", "code"], desc: "live-index code as files change" },
    { label: "run", value: ["run"], desc: "run a command with trimmed output" },

    { header: "Skills" },
    { label: "skill export", value: ["skill", "export"], desc: "copy shared skills into this repo" },
    { label: "skill link", value: ["skill", "link"], desc: "link this repo's .agents/skills into .claude + .codex" },

    { header: "Maintenance" },
    { label: "sync", value: ["sync"], desc: "pull live config back into the repo" },
    { label: "doctor", value: ["doctor"], desc: "health check" },
    { label: "verify", value: ["verify"], desc: "post-install verification" },

    { header: "Other" },
    { label: "help", value: ["--help"], desc: "show full usage" },
    { label: "exit", value: null, desc: "quit" },
  ];
  const choice = await selectMenu("roborepo — choose an action:", items);
  if (choice === null) {
    console.log("cancelled.");
    return;
  }
  // "run" from the menu has no command to run; guide the user instead of erroring.
  if (Array.isArray(choice) && choice.length === 1 && choice[0] === "run") {
    console.log("usage: roborepo run <cmd> [args...]");
    return;
  }
  if (Array.isArray(choice) && choice.length === 2 && choice[0] === "mcp" && choice[1] === "add") {
    console.log("usage: roborepo mcp add <name-or-url> [--scope=user|local|project] [--name=<name>]");
    return;
  }
  await dispatch(choice);
}

// --------------------------------------------------------------------------- dispatch

async function dispatch(args) {
  const [cat, sub, ...rest] = args;
  const flags = new Set(rest);

  switch (cat) {
    case undefined:
      return interactiveMenu();

    case "-h":
    case "--help":
      return usage();

    case "skill":
      if (sub === "export") return skillExport(new Set(rest));
      if (sub === "link") return skillLink(flags);
      console.error(`unknown: roborepo skill ${sub ?? ""}`.trim());
      return usage();

    case "index":
      if (sub === "code") return indexCode(rest);
      if (sub === "docs") return indexDocs(rest);
      console.error(`unknown: roborepo index ${sub ?? ""}`.trim());
      return usage();

    case "mcp":
      if (sub === "add") return mcpAdd(rest);
      console.error(`unknown: roborepo mcp ${sub ?? ""}`.trim());
      return usage();

    case "addMCP":
      return mcpAdd(sub === undefined ? [] : [sub, ...rest]);

    case "watch":
      if (sub === "code") return watchCode(rest);
      console.error(`unknown: roborepo watch ${sub ?? ""}`.trim());
      return usage();

    case "run":
      return runCmd(sub === undefined ? [] : [sub, ...rest]);

    // Lifecycle verbs -> existing bash scripts. The first install always happens via the shell
    // bootstrap (scripts/roborepo-install.sh) — that's how roborepo lands on PATH — so the CLI
    // only ever re-applies: `update` re-runs that same script to pick up new config.
    case "update":
      return runRepoScript("scripts/roborepo-install.sh", [sub, ...rest].filter(Boolean));
    case "sync":
      return runRepoScript("scripts/sync-from-home.sh", [sub, ...rest].filter(Boolean));
    case "doctor":
      return runRepoScript("scripts/doctor.sh", [sub, ...rest].filter(Boolean));
    case "verify":
      return runRepoScript("scripts/verify-install.sh", [sub, ...rest].filter(Boolean));

    default:
      console.error(`unknown command: ${args.join(" ")}`);
      usage();
      process.exit(2);
  }
}

dispatch(argv).catch((err) => {
  console.error(err?.stack || String(err));
  process.exit(1);
});
