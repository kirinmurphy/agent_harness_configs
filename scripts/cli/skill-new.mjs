import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { repoRoot, sharedSkillsDir } from "./paths.mjs";
import { addSkillPolicy, addSlashCommand, readSkillPolicyManifest, readSlashCommandManifest } from "./skill-new-manifests.mjs";
import { resolveNewOptions } from "./skill-new-options.mjs";
import { updateReadmeForCommand, updateReadmeForHelper } from "./skill-new-readme.mjs";
import { skillTemplate, standaloneCommandTemplate } from "./skill-new-templates.mjs";

function runChecked(label, command, args) {
  const result = spawnSync(command, args, { cwd: repoRoot, stdio: "inherit" });
  if (result.error) throw new Error(`${label} failed to start: ${result.error.message}`);
  if (result.status !== 0) throw new Error(`${label} failed with exit ${result.status}`);
}

function writeNewFile(filePath, content) {
  if (fs.existsSync(filePath)) throw new Error(`refusing to overwrite existing file: ${path.relative(repoRoot, filePath)}`);
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, content);
}

function assertPathAvailable(filePath) {
  if (fs.existsSync(filePath)) throw new Error(`refusing to overwrite existing file: ${path.relative(repoRoot, filePath)}`);
}

function assertPathMissing(filePath) {
  if (fs.existsSync(filePath)) throw new Error(`refusing to write into existing path: ${path.relative(repoRoot, filePath)}`);
}

function preflightSkillNew(opts) {
  if (opts.kind === "auto" || opts.kind === "skill-command") {
    assertPathMissing(path.join(sharedSkillsDir, opts.name));
    if (readSkillPolicyManifest().skills.some((skill) => skill.skill === opts.name)) {
      throw new Error(`skill policy already exists: ${opts.name}`);
    }
  }

  if (opts.kind === "skill-command" || opts.kind === "standalone") {
    if (readSlashCommandManifest().commands.some((command) => command.name === opts.command)) {
      throw new Error(`slash command already exists: ${opts.command}`);
    }
  }

  if (opts.kind === "standalone") {
    assertPathAvailable(path.join(repoRoot, "globals", "commands", `${opts.command}.md`));
  }
}

export async function skillNew(args) {
  const opts = await resolveNewOptions(args);
  preflightSkillNew(opts);

  if (opts.kind === "auto" || opts.kind === "skill-command") {
    const skillDir = path.join(sharedSkillsDir, opts.name);
    writeNewFile(path.join(skillDir, "SKILL.md"), skillTemplate(opts.name, opts.description));
    addSkillPolicy({
      name: opts.name,
      risk: opts.risk,
      explicitCommand: opts.kind === "skill-command",
      description: opts.description,
    });
    if (opts.kind === "auto") {
      updateReadmeForHelper({ name: opts.name, description: opts.description, category: opts.category });
    }
  }

  if (opts.kind === "skill-command") {
    addSlashCommand({
      name: opts.command,
      kind: "skill-backed",
      description: opts.description,
      skill: opts.name,
      harnesses: opts.harnesses,
    });
    updateReadmeForCommand({ name: opts.command, harnesses: opts.harnesses, description: opts.description });
  }

  if (opts.kind === "standalone") {
    const sourceRel = path.join("globals", "commands", `${opts.command}.md`);
    writeNewFile(path.join(repoRoot, sourceRel), standaloneCommandTemplate(opts.command, opts.description));
    addSlashCommand({
      name: opts.command,
      kind: "standalone",
      description: opts.description,
      source: sourceRel,
      harnesses: opts.harnesses,
    });
    updateReadmeForCommand({ name: opts.command, harnesses: opts.harnesses, description: opts.description });
  }

  runChecked("skill symlink-globals", "bash", [path.join(repoRoot, "scripts", "build", "link-skills.sh"), "--quiet"]);
  runChecked("slash command render", process.execPath, [
    path.join(repoRoot, "scripts", "build", "render-slash-commands.mjs"),
    "--quiet",
  ]);

  console.log("");
  console.log(`created ${opts.kind}: ${opts.kind === "standalone" ? `/${opts.command}` : opts.name}`);
  console.log("next: edit the generated body, then run:");
  console.log("  scripts/doctor.sh --quiet");
}
