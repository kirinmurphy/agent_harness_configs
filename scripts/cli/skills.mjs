// roborepo `skill` subcommands: link this repo's .agents/skills into existing .claude/.codex, and
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

async function resolveSkillInstallTargets(repo, { dryRun = false, uninstall = false } = {}) {
  const targets = [
    { name: "Claude", root: path.join(repo, ".claude") },
    { name: "Codex", root: path.join(repo, ".codex") },
  ];
  const existing = targets.filter((target) => fs.existsSync(target.root));
  const missing = targets.filter((target) => !fs.existsSync(target.root));

  if (missing.length === 0 || uninstall) return existing.map((target) => target.root);

  const prompter = makePrompter();
  if (!prompter.ask) return existing.map((target) => target.root);

  const selected = [...existing];
  for (const target of missing) {
    const include = await confirmYesNo(prompter, `Symlink skills to ${target.name}?`, true);
    if (include) selected.push(target);
  }
  prompter.close();

  if (!dryRun) {
    for (const target of selected) fs.mkdirSync(target.root, { recursive: true });
  }
  return selected.map((target) => target.root);
}

export async function skillLink(flags) {
  for (const f of flags) {
    if (f === "--dry-run" || f === "--uninstall") continue;
    console.error(`unknown flag for "skill install": ${f}`);
    process.exit(2);
  }

  const dryRun = flags.has("--dry-run");
  const uninstall = flags.has("--uninstall");
  const repo = process.cwd();
  const agentsRoot = path.join(repo, ".agents");
  const srcDir = path.join(repo, ".agents", "skills");

  if (!fs.existsSync(agentsRoot)) {
    console.error(`no .agents directory found at ${agentsRoot}`);
    console.error(`move repo skills into .agents/skills/<skill-name>/SKILL.md first, then run:`);
    console.error(`  roborepo skill install`);
    process.exit(1);
  }

  if (!fs.existsSync(srcDir)) {
    console.error(`no .agents/skills directory found at ${srcDir}`);
    console.error(`move repo skills into .agents/skills/<skill-name>/SKILL.md first, then run:`);
    console.error(`  roborepo skill install`);
    process.exit(1);
  }

  const targetRoots = await resolveSkillInstallTargets(repo, { dryRun, uninstall });
  const t = linkLocalSkills(repo, { dryRun, uninstall, targetRoots });
  const dry = dryRun ? " (dry-run)" : "";
  console.log("");
  if (t.targetDirs === 0) {
    console.log(`0 existing agent target folder(s) found (.claude or .codex); no skill links installed${dry}.`);
    console.log(`Run interactively to choose Claude/Codex targets, or create .claude/ or .codex/ first, then re-run:`);
    console.log(`  roborepo skill install`);
    return;
  }
  if (uninstall) {
    console.log(`${t.unlinked} link(s) removed${dry}, ${t.pruned} pruned, ${t.conflicts} conflict(s).`);
  } else {
    let line =
      `${t.skills} skill(s): ${t.linked} linked${dry}, ${t.ok} already ok, ` +
      `${t.pruned} pruned, ${t.conflicts} conflict(s)`;
    if (t.denied > 0) line += `, ${t.denied} denied (OS refused symlink)`;
    console.log(`${line}.`);
    console.log("");
    console.log("Reminder: add a new skill at .agents/skills/<name>/SKILL.md? Re-run");
    console.log("  roborepo skill install");
    console.log("so existing Claude and transitional .codex/skills links pick it up.");
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

  // Guard: never run the exporter from inside the harness config source repo itself — it
  // would copy the shared skills back over their own source and drop a zip in the repo root.
  if (path.resolve(cwd) === path.resolve(repoRoot)) {
    console.error(`refusing to export into the harness config source repo (${cwd}).`);
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
