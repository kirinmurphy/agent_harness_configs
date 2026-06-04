#!/usr/bin/env node
// harness_helper — CLI for tasks in the harness_configs ecosystem.
//
// Subcommands:
//   --export-skill   Bundle this repo's SHARED skills (harness_configs/skills/) into a
//                    shareable .zip and copy them into a target repo's harness skill dirs,
//                    with per-skill override/skip/backup handling.
//
// Cross-platform: pure node built-ins (see scripts/skill-lib.mjs). Runs on macOS/Linux/Windows.
//
// NOTE: only the SHARED layer (skills/) is ever exported. The INTERNAL layer (skills-local/)
// has no code path here — that firewall is structural, not a flag.

import fs from "node:fs";
import path from "node:path";
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
} from "./skill-lib.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, "..");
const sharedSkillsDir = path.join(repoRoot, "skills");

const argv = process.argv.slice(2);

function usage() {
  console.log(`harness_helper — harness_configs ecosystem CLI

usage:
  harness_helper --export-skill [--yes] [--on-conflict=skip|override]

commands:
  --export-skill   Bundle shared skills into a .zip and copy into the current repo's
                   .claude/skills (+ .codex/skills) with override/skip per skill.

flags:
  --yes                 non-interactive: assume "yes" to the destination prompt
  --on-conflict=MODE    non-interactive conflict mode: skip (default) or override
  -h, --help            show this help`);
}

async function exportSkill(flags) {
  const assumeYes = flags.has("--yes");
  let onConflict = "skip";
  for (const f of flags) {
    if (f.startsWith("--on-conflict=")) onConflict = f.split("=")[1];
  }
  if (!["skip", "override"].includes(onConflict)) {
    console.error(`--on-conflict must be skip or override`);
    process.exit(2);
  }

  const cwd = process.cwd();
  const prompter = makePrompter();
  const interactive = Boolean(prompter.ask);

  if (!interactive && !assumeYes) {
    console.error(`non-interactive: pass --yes and optionally --on-conflict=skip|override`);
    prompter.close();
    process.exit(2);
  }

  // 1) Confirm destination = current folder.
  const proceed = assumeYes ? true : await confirmYesNo(prompter, `Download skills into the current folder (${cwd})?`, true);
  if (!proceed) {
    console.log("");
    console.log("Re-run this command from the ROOT of the target repo:");
    console.log("  cd /path/to/your/repo && harness_helper --export-skill");
    prompter.close();
    return;
  }

  // 2) Resolve destination dirs (canonical .claude/skills + .codex/skills, create if absent).
  const dests = resolveClientSkillDirs(cwd, { create: true });
  console.log(`destinations: ${dests.map((d) => path.relative(cwd, d) || d).join(", ")}`);

  // 3) Bundle the shareable artifact: one .zip of all shared skills.
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

  // 4) Per-skill copy into each destination, driven from the source tree.
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

      const choice = interactive
        ? await askOverrideSkip(prompter, name)
        : onConflict;

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

async function main() {
  if (argv.length === 0 || argv.includes("-h") || argv.includes("--help")) {
    usage();
    process.exit(argv.length === 0 ? 2 : 0);
  }

  const flags = new Set(argv);
  if (flags.has("--export-skill") || flags.has("export-skill")) {
    await exportSkill(flags);
    return;
  }

  console.error(`unknown command: ${argv.join(" ")}`);
  usage();
  process.exit(2);
}

main().catch((err) => {
  console.error(err?.stack || String(err));
  process.exit(1);
});
