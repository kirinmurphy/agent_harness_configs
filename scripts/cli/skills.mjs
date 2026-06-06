// roborepo `skill` subcommands: link this repo's .agents/skills into .claude/.codex, and
// export the shared harness skills into a consumer repo (+ a shareable zip).

import fs from "node:fs";
import path from "node:path";
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
} from "./skill-lib.mjs";
import { repoRoot, sharedSkillsDir } from "./paths.mjs";

export function skillLink(flags) {
  for (const f of flags) {
    if (f === "--dry-run" || f === "--uninstall") continue;
    console.error(`unknown flag for "skill link": ${f}`);
    process.exit(2);
  }

  const dryRun = flags.has("--dry-run");
  const uninstall = flags.has("--uninstall");
  const repo = process.cwd();
  const srcDir = path.join(repo, ".agents", "skills");

  if (!fs.existsSync(srcDir)) {
    console.error(`no .agents/skills directory found at ${srcDir}`);
    console.error(`create .agents/skills/<skill-name>/SKILL.md in this repo first, then re-run.`);
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
    console.log("Reminder: add a new skill at .agents/skills/<name>/SKILL.md ? Re-run");
    console.log("  roborepo skill link");
    console.log("so .claude/skills and .codex/skills pick it up — the source folder alone is not enough.");
  }
}

export async function skillExport(flags) {
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
