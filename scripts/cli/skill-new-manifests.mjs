import fs from "node:fs";
import {
  SKILL_INVOCATION_MANIFEST,
  SLASH_COMMANDS_MANIFEST,
} from "./skill-command-config.mjs";

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function writeJson(filePath, data) {
  fs.writeFileSync(filePath, `${JSON.stringify(data, null, 2)}\n`);
}

export function addSkillPolicy({ name, risk, explicitCommand, description }) {
  const manifest = readSkillPolicyManifest();
  if (manifest.skills.some((skill) => skill.skill === name)) throw new Error(`skill policy already exists: ${name}`);
  manifest.skills.push({
    skill: name,
    risk,
    invocation: explicitCommand ? "manual" : "auto",
    explicit_command: explicitCommand,
    notes: explicitCommand ? `Explicit command workflow: ${description}` : `Automatic helper: ${description}`,
  });
  manifest.skills.sort((a, b) => a.skill.localeCompare(b.skill));
  writeJson(SKILL_INVOCATION_MANIFEST, manifest);
}

export function addSlashCommand({ name, kind, description, skill, source, harnesses }) {
  const manifest = readSlashCommandManifest();
  if (manifest.commands.some((command) => command.name === name)) throw new Error(`slash command already exists: ${name}`);
  const entry = { name, kind, description, harnesses };
  if (kind === "skill-backed") entry.skill = skill;
  else entry.source = source;
  manifest.commands.push(entry);
  manifest.commands.sort((a, b) => a.name.localeCompare(b.name));
  writeJson(SLASH_COMMANDS_MANIFEST, manifest);
}

export function readSkillPolicyManifest() {
  return readJson(SKILL_INVOCATION_MANIFEST);
}

export function readSlashCommandManifest() {
  return readJson(SLASH_COMMANDS_MANIFEST);
}
