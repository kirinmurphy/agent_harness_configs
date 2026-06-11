// roborepo `skill` subcommands: link this repo's .agents/skills into existing .claude/.codex, and
// export the shared harness skills into a consumer repo (+ a shareable zip).

import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
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
import { repoRoot, sharedSkillsDir } from "./paths.mjs";

const SKILL_INVOCATION_MANIFEST = path.join(repoRoot, "manifests", "skill-invocation.json");
const SLASH_COMMANDS_MANIFEST = path.join(repoRoot, "manifests", "slash-commands.json");
const README_PATH = path.join(repoRoot, "README.md");

const NEW_KIND_ITEMS = [
  {
    label: "auto",
    value: "auto",
    desc: "automatic helper skill, no slash command",
  },
  {
    label: "skill-command",
    value: "skill-command",
    desc: "skill plus explicit slash command",
  },
  {
    label: "standalone",
    value: "standalone",
    desc: "slash command only, no skill",
  },
];

const README_CATEGORY_HEADINGS = {
  documentation: "Documentation",
  code: "Code & Frontend",
  testing: "Testing",
  repo: "Repo",
};

const README_CATEGORY_ORDER = ["documentation", "code", "testing", "repo"];

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

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function writeJson(filePath, data) {
  fs.writeFileSync(filePath, `${JSON.stringify(data, null, 2)}\n`);
}

function slugify(value, label) {
  const slug = String(value ?? "")
    .trim()
    .replace(/^\//, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
  if (!/^[a-z0-9][a-z0-9-]*$/.test(slug)) {
    throw new Error(`${label} must contain letters or numbers and may use hyphens`);
  }
  return slug;
}

function parseList(value) {
  return String(value ?? "")
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
}

function parseNewArgs(args) {
  const opts = {
    kind: null,
    name: null,
    command: null,
    description: null,
    risk: "low",
    category: "code",
    harnesses: ["claude", "codex"],
    yes: false,
  };

  for (const arg of args) {
    if (arg === "--yes" || arg === "-y") {
      opts.yes = true;
    } else if (arg.startsWith("--kind=")) {
      opts.kind = arg.slice("--kind=".length);
    } else if (arg.startsWith("--name=")) {
      opts.name = arg.slice("--name=".length);
    } else if (arg.startsWith("--command=")) {
      opts.command = arg.slice("--command=".length);
    } else if (arg.startsWith("--description=")) {
      opts.description = arg.slice("--description=".length);
    } else if (arg.startsWith("--risk=")) {
      opts.risk = arg.slice("--risk=".length);
    } else if (arg.startsWith("--category=")) {
      opts.category = arg.slice("--category=".length);
    } else if (arg.startsWith("--harnesses=")) {
      opts.harnesses = parseList(arg.slice("--harnesses=".length));
    } else {
      console.error(`unknown flag for "skill new": ${arg}`);
      process.exit(2);
    }
  }

  return opts;
}

async function askRequired(prompter, current, question) {
  if (current !== null && current !== undefined && String(current).trim() !== "") return current;
  if (!prompter.ask) {
    console.error(`missing required value: ${question}`);
    process.exit(2);
  }
  for (;;) {
    const answer = await prompter.ask(`${question}: `);
    if (answer.trim() !== "") return answer.trim();
  }
}

async function resolveNewOptions(args) {
  const opts = parseNewArgs(args);
  const prompter = makePrompter();

  if (!opts.kind) {
    opts.kind = await selectMenu("What are you adding?", NEW_KIND_ITEMS);
    if (opts.kind === null) {
      console.log("cancelled.");
      process.exit(0);
    }
  }
  if (!["auto", "skill-command", "standalone"].includes(opts.kind)) {
    console.error(`--kind must be auto, skill-command, or standalone`);
    process.exit(2);
  }

  opts.name = slugify(await askRequired(prompter, opts.name, opts.kind === "standalone" ? "Command name" : "Skill name"), "name");
  if (opts.kind === "skill-command") {
    opts.command = slugify(await askRequired(prompter, opts.command ?? opts.name, "Slash command name"), "command");
  } else if (opts.kind === "standalone") {
    opts.command = opts.name;
  }
  opts.description = String(await askRequired(prompter, opts.description, "One-line description")).trim();
  if (opts.description.includes("\n")) {
    console.error("description must be one line");
    process.exit(2);
  }

  if (!["low", "medium", "high"].includes(opts.risk)) {
    console.error(`--risk must be low, medium, or high`);
    process.exit(2);
  }
  if (!README_CATEGORY_HEADINGS[opts.category]) {
    console.error(`--category must be one of: ${Object.keys(README_CATEGORY_HEADINGS).join(", ")}`);
    process.exit(2);
  }
  for (const harness of opts.harnesses) {
    if (!["claude", "codex"].includes(harness)) {
      console.error(`--harnesses values must be claude and/or codex`);
      process.exit(2);
    }
  }

  prompter.close();
  return opts;
}

function skillTemplate(name, description) {
  return `---
name: ${name}
description: ${description}
---

# ${name}

Use this skill when ${description.charAt(0).toLowerCase()}${description.slice(1)}

## Workflow

1. Confirm the request matches this skill.
2. Inspect the repo for existing patterns.
3. Apply the smallest useful workflow.
4. Report what changed or what should happen next.
`;
}

function standaloneCommandTemplate(name, description) {
  return `---
description: ${description}
---

# /${name}

${description}

## Workflow

1. Confirm the command intent.
2. Run the command-specific workflow.
3. Report the result and any required follow-up.
`;
}

function addSkillPolicy({ name, risk, explicitCommand, description }) {
  const manifest = readJson(SKILL_INVOCATION_MANIFEST);
  if (manifest.skills.some((skill) => skill.skill === name)) {
    throw new Error(`skill policy already exists: ${name}`);
  }
  manifest.skills.push({
    skill: name,
    risk,
    invocation: explicitCommand ? "manual" : "auto",
    explicit_command: explicitCommand,
    notes: explicitCommand
      ? `Explicit command workflow: ${description}`
      : `Automatic helper: ${description}`,
  });
  manifest.skills.sort((a, b) => a.skill.localeCompare(b.skill));
  writeJson(SKILL_INVOCATION_MANIFEST, manifest);
}

function addSlashCommand({ name, kind, description, skill, source, harnesses }) {
  const manifest = readJson(SLASH_COMMANDS_MANIFEST);
  if (manifest.commands.some((command) => command.name === name)) {
    throw new Error(`slash command already exists: ${name}`);
  }
  const entry = { name, kind, description, harnesses };
  if (kind === "skill-backed") entry.skill = skill;
  else entry.source = source;
  manifest.commands.push(entry);
  manifest.commands.sort((a, b) => a.name.localeCompare(b.name));
  writeJson(SLASH_COMMANDS_MANIFEST, manifest);
}

function markdownCell(value) {
  return String(value).replaceAll("|", "\\|").replace(/\s+/g, " ").trim();
}

function ensureReadmeHelperSection(readme, category) {
  const heading = README_CATEGORY_HEADINGS[category];
  const marker = `##### ${heading}`;
  if (readme.includes(marker)) return readme;

  const commandsIndex = readme.indexOf("\n### Commands");
  if (commandsIndex < 0) throw new Error("README.md missing ### Commands section");

  const section = `##### ${heading}

| | |
| --- | --- |

`;
  return `${readme.slice(0, commandsIndex)}\n${section}${readme.slice(commandsIndex + 1)}`;
}

function nextReadmeHeadingIndex(readme, start) {
  const matches = [...readme.slice(start).matchAll(/\n#{3,5} /g)];
  if (matches.length === 0) return readme.length;
  return start + matches[0].index;
}

function insertReadmeTableRow(readme, sectionHeading, row) {
  const headingIndex = readme.indexOf(sectionHeading);
  if (headingIndex < 0) throw new Error(`README.md missing ${sectionHeading}`);
  const sectionEnd = nextReadmeHeadingIndex(readme, headingIndex + sectionHeading.length);
  const section = readme.slice(headingIndex, sectionEnd);
  if (section.includes(row.split("|")[1].trim())) return readme;

  const lines = section.split("\n");
  let insertAt = -1;
  for (let i = lines.length - 1; i >= 0; i--) {
    if (lines[i].startsWith("|")) {
      insertAt = i + 1;
      break;
    }
  }
  if (insertAt < 0) throw new Error(`README.md section ${sectionHeading} has no table`);
  lines.splice(insertAt, 0, row);
  return `${readme.slice(0, headingIndex)}${lines.join("\n")}${readme.slice(sectionEnd)}`;
}

function updateReadmeForHelper({ name, description, category }) {
  let readme = fs.readFileSync(README_PATH, "utf8");
  readme = ensureReadmeHelperSection(readme, category);
  const row = `| ${markdownCell(name)} | ${markdownCell(description)} |`;
  readme = insertReadmeTableRow(readme, `##### ${README_CATEGORY_HEADINGS[category]}`, row);
  fs.writeFileSync(README_PATH, readme);
}

function updateReadmeForCommand({ name, harnesses, description }) {
  let readme = fs.readFileSync(README_PATH, "utf8");
  const row = `| \`/${markdownCell(name)}\` | ${markdownCell(harnesses.map((h) => h[0].toUpperCase() + h.slice(1)).join(", "))} | ${markdownCell(description)} |`;
  readme = insertReadmeTableRow(readme, "### Commands", row);
  fs.writeFileSync(README_PATH, readme);
}

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

export async function skillNew(args) {
  const opts = await resolveNewOptions(args);

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

  runChecked("skill sync", "bash", [path.join(repoRoot, "scripts", "build", "link-skills.sh"), "--quiet"]);
  runChecked("slash command render", process.execPath, [path.join(repoRoot, "scripts", "build", "render-slash-commands.mjs"), "--quiet"]);

  console.log("");
  console.log(`created ${opts.kind}: ${opts.kind === "standalone" ? `/${opts.command}` : opts.name}`);
  console.log("next: edit the generated body, then run:");
  console.log("  scripts/doctor.sh --quiet");
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

  // Guard: never run the exporter from inside the roborepo source repo itself — it
  // would copy the shared skills back over their own source and drop a zip in the repo root.
  if (path.resolve(cwd) === path.resolve(repoRoot)) {
    console.error(`refusing to export into the roborepo source repo (${cwd}).`);
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
