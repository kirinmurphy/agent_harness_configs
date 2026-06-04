#!/usr/bin/env node
// roborepo — one CLI for everything a consumer of harness_configs does in their own repo.
//
// Nested subcommands, grouped by category so the surface is scannable:
//
//   roborepo                       no args -> interactive menu (arrow keys + numbered fallback)
//
//   skill   work with skills in the current repo
//     roborepo skill export        bundle shared skills into a .zip + copy into this repo
//     roborepo skill link          symlink this repo's skills/ into .claude/skills + .codex/skills
//
//   index   index the current repo for the MCP servers
//     roborepo index code [path]   jcodemunch  (code index)
//     roborepo index docs [path]   jdocmunch   (docs index)
//
//   watch   keep an index live
//     roborepo watch code [path]   jcodemunch watch
//
//   run     run a command, capturing + truncating noisy output
//     roborepo run <cmd> [args...]
//
//   lifecycle  set up / maintain the harness_configs install on this machine
//     roborepo install [--dry-run]   install repo-managed config (symlinks, commands, shell)
//     roborepo update  [--dry-run]   re-apply the install (same operation today; stable verb)
//     roborepo sync                  review/pull live config back into the repo
//     roborepo doctor  [--installed] health check
//     roborepo verify                post-install verification
//
// [path] is optional everywhere it appears; it defaults to the current directory and may be
// relative or absolute — roborepo always resolves it to an absolute path before use.
//
// MAINTAINER-only scripts (render-rules.sh, link-skills.sh, test-*.sh) are deliberately NOT
// exposed here — they edit the harness_configs source itself, not anything a consumer touches.
// The lifecycle verbs above dispatch to the existing bash scripts (install-symlinks.sh, etc.);
// those filenames are an internal detail and are not renamed.

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { fileURLToPath } from "node:url";
import {
  listSourceSkills,
  resolveClientSkillDirs,
  copyDir,
  timestamp,
  makePrompter,
  confirmYesNo,
  askOverrideSkip,
  writeZip,
  linkLocalSkills,
  selectMenu,
} from "./skill-lib.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, "..");
const sharedSkillsDir = path.join(repoRoot, "skills");

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
  roborepo watch code  [path]

  roborepo run <cmd> [args...]

  roborepo install [--dry-run]   set up harness config on this machine
  roborepo update  [--dry-run]   re-apply the install
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

// --------------------------------------------------------------------------- skill link

function skillLink(flags) {
  const dryRun = flags.has("--dry-run");
  const uninstall = flags.has("--uninstall");
  const repo = process.cwd();
  const srcDir = path.join(repo, "skills");

  if (!fs.existsSync(srcDir)) {
    console.error(`no skills/ directory found at ${srcDir}`);
    console.error(`create skills/<skill-name>/SKILL.md in this repo first, then re-run.`);
    process.exit(1);
  }

  const t = linkLocalSkills(repo, { dryRun, uninstall });
  const dry = dryRun ? " (dry-run)" : "";
  console.log("");
  if (uninstall) {
    console.log(`${t.unlinked} link(s) removed${dry}, ${t.pruned} pruned, ${t.conflicts} conflict(s).`);
  } else {
    let line =
      `${t.skills} skill(s): ${t.linked} linked${dry}, ${t.ok} already ok, ` +
      `${t.pruned} pruned, ${t.conflicts} conflict(s)`;
    if (t.denied > 0) line += `, ${t.denied} denied (OS refused symlink)`;
    console.log(`${line}.`);
    console.log("");
    console.log("Reminder: add a new skill at skills/<name>/SKILL.md ? Re-run");
    console.log("  roborepo skill link");
    console.log("so .claude/skills and .codex/skills pick it up — the source folder alone is not enough.");
  }
}

// --------------------------------------------------------------------------- skill export

async function skillExport(flags) {
  const assumeYes = flags.has("--yes");
  let onConflict = "skip";
  for (const f of flags) {
    if (f === "--yes") continue;
    if (f.startsWith("--on-conflict=")) {
      onConflict = f.slice("--on-conflict=".length);
      continue;
    }
    console.error(`unknown flag for "skill export": ${f}`);
    process.exit(2);
  }
  if (!["skip", "override"].includes(onConflict)) {
    console.error(`--on-conflict must be skip or override`);
    process.exit(2);
  }

  const cwd = process.cwd();

  // Guard: never run the exporter from inside the harness_configs source repo itself — it
  // would copy the shared skills back over their own source and drop a zip in the repo root.
  if (path.resolve(cwd) === path.resolve(repoRoot)) {
    console.error(`refusing to export into the harness_configs source repo (${cwd}).`);
    console.error(`cd into the TARGET repo first, then run: roborepo skill export`);
    process.exit(1);
  }

  const prompter = makePrompter();
  const interactive = Boolean(prompter.ask);
  if (!interactive && !assumeYes) {
    console.error(`non-interactive: pass --yes and optionally --on-conflict=skip|override`);
    prompter.close();
    process.exit(2);
  }

  const proceed = assumeYes
    ? true
    : await confirmYesNo(prompter, `Download skills into the current folder (${cwd})?`, true);
  if (!proceed) {
    console.log("");
    console.log("Re-run this command from the ROOT of the target repo:");
    console.log("  cd /path/to/your/repo && roborepo skill export");
    prompter.close();
    return;
  }

  const dests = resolveClientSkillDirs(cwd, { create: true });
  console.log(`destinations: ${dests.map((d) => path.relative(cwd, d) || d).join(", ")}`);

  const skills = listSourceSkills(sharedSkillsDir);
  if (skills.length === 0) {
    console.error(`no shared skills found under ${sharedSkillsDir}`);
    prompter.close();
    process.exit(1);
  }
  const ts = timestamp();
  const bundleName = `global_agent_skills_${ts}`;
  const zipPath = path.join(cwd, `${bundleName}.zip`);
  writeZip(
    zipPath,
    skills.map((name) => ({ srcDir: path.join(sharedSkillsDir, name), nameInZip: `${bundleName}/${name}` })),
  );
  console.log(`bundled ${skills.length} skill(s) -> ${path.basename(zipPath)} (shareable artifact)`);

  let copied = 0;
  let skipped = 0;
  let overridden = 0;

  for (const dest of dests) {
    fs.mkdirSync(dest, { recursive: true });
    for (const name of skills) {
      const src = path.join(sharedSkillsDir, name);
      const target = path.join(dest, name);

      if (!fs.existsSync(target)) {
        copyDir(src, target);
        console.log(`copy: ${path.relative(cwd, target)}`);
        copied++;
        continue;
      }

      const choice = interactive ? await askOverrideSkip(prompter, name) : onConflict;
      if (choice === "override") {
        const archiveDir = path.join(dest, "archived");
        fs.mkdirSync(archiveDir, { recursive: true });
        const backup = path.join(archiveDir, `${name}_backup_${ts}`);
        fs.renameSync(target, backup);
        copyDir(src, target);
        console.log(`override: ${path.relative(cwd, target)} (old -> ${path.relative(cwd, backup)})`);
        overridden++;
      } else {
        console.log(`skip: ${path.relative(cwd, target)} (kept existing)`);
        skipped++;
      }
    }
  }

  prompter.close();
  console.log("");
  console.log(`done: ${copied} copied, ${overridden} overridden, ${skipped} skipped.`);
  console.log(`shareable bundle left at: ${path.basename(zipPath)}`);
}

// --------------------------------------------------------------------------- index / watch / run

/** Resolve an optional [path] arg to an absolute path; default = cwd. */
function resolveTarget(arg) {
  return arg ? path.resolve(process.cwd(), arg) : process.cwd();
}

function requireUvx() {
  const probe = spawnSync("uvx", ["--version"], { stdio: "ignore" });
  if (probe.error) {
    console.error(`this command needs "uvx" (from uv) on PATH. Install: https://docs.astral.sh/uv/`);
    process.exit(127);
  }
}

function indexCode(rest) {
  requireUvx();
  const target = resolveTarget(rest[0]);
  const sub = fs.statSync(target).isFile() ? "index-file" : "index";
  const r = spawnSync("uvx", ["jcodemunch-mcp", sub, "--no-ai-summaries", target], { stdio: "inherit" });
  process.exit(r.status ?? 1);
}

function indexDocs(rest) {
  requireUvx();
  const target = resolveTarget(rest[0]);
  const r = spawnSync("uvx", ["jdocmunch-mcp", "index-local", "--path", target], { stdio: "inherit" });
  if (r.status === 0) {
    try {
      fs.writeFileSync(path.join(target, ".jdm-indexed"), "");
    } catch {
      /* best-effort marker */
    }
  }
  process.exit(r.status ?? 1);
}

function watchCode(rest) {
  requireUvx();
  const target = resolveTarget(rest[0]);

  // Write the pidfile the Claude SessionStart hook reads to detect a live watcher:
  //   /tmp/jcmwatch-<md5(target)>.pid  containing "<pid> <process-start-time>".
  // The hash is keyed on the absolute target dir, matching claude/settings.json.
  const hash = createHash("md5").update(target).digest("hex").slice(0, 32);
  const pidfile = path.join(os.tmpdir(), `jcmwatch-${hash}.pid`);
  const started = startTimeForPid(process.pid);
  try {
    fs.writeFileSync(pidfile, `${process.pid} ${started}`);
    const cleanup = () => {
      try {
        fs.rmSync(pidfile);
      } catch {
        /* already gone */
      }
    };
    process.on("exit", cleanup);
    process.on("SIGINT", () => process.exit(130));
    process.on("SIGTERM", () => process.exit(143));
  } catch {
    /* pidfile is best-effort; watch still runs without hook detection */
  }

  const r = spawnSync("uvx", ["--with", "jcodemunch-mcp[watch]", "jcodemunch-mcp", "watch", target], {
    stdio: "inherit",
  });
  process.exit(r.status ?? 1);
}

/** Process start time string, matching the `ps lstart`/`start` format the hook compares. */
function startTimeForPid(pid) {
  for (const flag of ["lstart=", "start="]) {
    const r = spawnSync("ps", ["-p", String(pid), "-o", flag], { encoding: "utf8" });
    if (r.status === 0 && r.stdout) return r.stdout.trim().replace(/\s+/g, " ");
  }
  return "";
}

function runCmd(rest) {
  if (rest.length === 0) {
    console.error(`usage: roborepo run <cmd> [args...]`);
    process.exit(2);
  }
  const r = spawnSync(rest[0], rest.slice(1), { encoding: "utf8" });
  if (r.error) {
    console.error(`fail: ${rest.join(" ")} — ${r.error.message}`);
    process.exit(1);
  }
  const out = `${r.stdout ?? ""}${r.stderr ?? ""}`;
  const lines = out.split("\n");
  const status = r.status ?? 0;
  if (status === 0) {
    console.log(`ok: ${rest.join(" ")}`);
    console.log(lines.slice(-40).join("\n").trimEnd());
  } else {
    console.error(`fail(${status}): ${rest.join(" ")}`);
    console.error(lines.slice(-120).join("\n").trimEnd());
  }
  process.exit(status);
}

// --------------------------------------------------------------------------- menu

async function interactiveMenu() {
  // Ordered by significance: setup first, then day-to-day, then skills, then maintenance.
  const items = [
    { header: "Setup" },
    { label: "install", value: ["install"], desc: "set up harness config on this machine" },
    { label: "update", value: ["update"], desc: "re-apply the install (pick up new config)" },

    { header: "Day to day" },
    { label: "index code", value: ["index", "code"], desc: "index this repo's code for jcodemunch" },
    { label: "index docs", value: ["index", "docs"], desc: "index this repo's docs for jdocmunch" },
    { label: "watch code", value: ["watch", "code"], desc: "live-index code as files change" },
    { label: "run", value: ["run"], desc: "run a command with trimmed output" },

    { header: "Skills" },
    { label: "skill export", value: ["skill", "export"], desc: "copy shared skills into this repo" },
    { label: "skill link", value: ["skill", "link"], desc: "link this repo's skills/ into .claude + .codex" },

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

    case "watch":
      if (sub === "code") return watchCode(rest);
      console.error(`unknown: roborepo watch ${sub ?? ""}`.trim());
      return usage();

    case "run":
      return runCmd(sub === undefined ? [] : [sub, ...rest]);

    // Lifecycle verbs -> existing bash scripts. install + update map to the same script today;
    // the separate verb keeps the CLI contract stable if update diverges later.
    case "install":
    case "update":
      return runRepoScript("scripts/install-symlinks.sh", [sub, ...rest].filter(Boolean));
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
