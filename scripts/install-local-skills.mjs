#!/usr/bin/env node
// harness-install-local-skills — give a CLIENT repo the same dual-harness skill linking
// that harness_configs does for itself.
//
// Run from the root of a client repo. Source of local skills = <cwd>/.claude/skills/<name>/
// (canonical, matching the export tool). Each local skill is symlinked into whichever global
// harness skill dirs exist (~/.claude/skills, ~/.codex/skills), and — so the client repo
// itself has the two-level layout — mirrored into <cwd>/.codex/skills as well.
//
// Cross-platform: pure node built-ins via scripts/skill-lib.mjs. On Windows, symlink creation
// may require Developer Mode or admin; the tool reports and continues per-skill on failure.
//
//   harness-install-local-skills [--dry-run] [--uninstall] [--no-mirror-codex]

import fs from "node:fs";
import path from "node:path";
import {
  listSourceSkills,
  detectHomeHarnesses,
  homeSkillsDir,
  ensureSymlink,
} from "./skill-lib.mjs";

const args = new Set(process.argv.slice(2));
const dryRun = args.has("--dry-run");
const uninstall = args.has("--uninstall");
const mirrorCodex = !args.has("--no-mirror-codex");
for (const a of args) {
  if (!["--dry-run", "--uninstall", "--no-mirror-codex"].includes(a)) {
    console.error(`usage: harness-install-local-skills [--dry-run] [--uninstall] [--no-mirror-codex]`);
    process.exit(2);
  }
}

const repoRoot = process.cwd();
const srcDir = path.join(repoRoot, ".claude", "skills");

if (!fs.existsSync(srcDir)) {
  console.error(`no skills found at ${srcDir}`);
  console.error(`create .claude/skills/<skill-name>/ in this repo first, then re-run.`);
  process.exit(1);
}

const skills = listSourceSkills(srcDir);
if (skills.length === 0) {
  console.error(`no skill folders (with SKILL.md) under ${srcDir}`);
  process.exit(1);
}

// Targets: present global harness skill dirs, plus the repo's own .codex/skills mirror.
const homeHarnesses = detectHomeHarnesses();
if (homeHarnesses.length === 0) {
  console.error(`neither ~/.claude nor ~/.codex found; install a harness first.`);
  process.exit(1);
}

let linked = 0;
let conflicts = 0;
let unlinked = 0;

for (const name of skills) {
  const srcAbs = path.join(srcDir, name);

  // 1) Global harness skill dirs.
  for (const h of homeHarnesses) {
    const target = path.join(homeSkillsDir(h), name);
    report(ensureSymlink(srcAbs, target, { dryRun, uninstall }), target, srcAbs);
  }

  // 2) Mirror into the client repo's own .codex/skills (relative link, two-level layout).
  if (mirrorCodex) {
    const codexDir = path.join(repoRoot, ".codex", "skills");
    const target = path.join(codexDir, name);
    const rel = path.join("..", "..", ".claude", "skills", name);
    // Relative target so the client repo stays portable; we compare exact link strings.
    const current = safeReadlink(target);
    if (uninstall) {
      if (current === rel) {
        if (!dryRun) fs.rmSync(target);
        console.log(`unlink: ${target}`);
        unlinked++;
      }
    } else if (current === rel) {
      // ok
    } else if (current !== null || fs.existsSync(target)) {
      console.warn(`conflict: ${target} -> ${current ?? "(real path)"} (wanted ${rel}) — skipped`);
      conflicts++;
    } else {
      if (!dryRun) {
        fs.mkdirSync(codexDir, { recursive: true });
        fs.symlinkSync(rel, target);
      }
      console.log(`link: ${target} -> ${rel}`);
      linked++;
    }
  }
}

function safeReadlink(p) {
  try {
    return fs.lstatSync(p).isSymbolicLink() ? fs.readlinkSync(p) : null;
  } catch {
    return null;
  }
}

function report(result, target, srcAbs) {
  switch (result) {
    case "linked":
      console.log(`link: ${target} -> ${srcAbs}`);
      linked++;
      break;
    case "unlinked":
      console.log(`unlink: ${target}`);
      unlinked++;
      break;
    case "conflict":
      console.warn(`conflict: ${target} exists and points elsewhere — skipped (resolve manually)`);
      conflicts++;
      break;
    case "ok":
    case "skip":
    default:
      break;
  }
}

console.log("");
if (uninstall) {
  console.log(`${unlinked} link(s) removed${dryRun ? " (dry-run)" : ""}, ${conflicts} conflict(s).`);
} else {
  console.log(`${linked} link(s) created${dryRun ? " (dry-run)" : ""}, ${conflicts} conflict(s).`);
  console.log("");
  console.log("Reminder: create a NEW local skill at .claude/skills/<name>/ ? Re-run");
  console.log("  harness-install-local-skills");
  console.log("so both harnesses pick it up — the source folder alone is not enough.");
}
