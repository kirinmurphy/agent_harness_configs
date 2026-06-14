#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, "../..");
const manifestPath = path.join(repoRoot, "manifests", "inventory", "agent-permissions.json");
const codexConfigPath = path.join(repoRoot, "globals", "codex", "config.toml");
const codexRulesPath = path.join(repoRoot, "globals", "codex", "rules", "default.rules");
const claudeSettingsPath = path.join(repoRoot, "globals", "claude", "settings.json");
const begin = "# BEGIN GENERATED AGENT PERMISSIONS";
const end = "# END GENERATED AGENT PERMISSIONS";

let check = false;
let profileName;

for (let i = 2; i < process.argv.length; i += 1) {
  const arg = process.argv[i];
  if (arg === "--check") {
    check = true;
  } else if (arg === "--profile") {
    profileName = process.argv[++i];
  } else if (arg.startsWith("--profile=")) {
    profileName = arg.slice("--profile=".length);
  } else {
    usage();
  }
}

function usage() {
  console.error("usage: render-agent-permissions.mjs [--check] [--profile <name>]");
  process.exit(2);
}

const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
profileName ??= manifest.default_profile;
const profile = manifest.profiles?.[profileName];

if (!profile) {
  const names = Object.keys(manifest.profiles ?? {}).join(", ");
  console.error(`unknown agent permission profile: ${profileName}`);
  console.error(`available profiles: ${names}`);
  process.exit(2);
}

function quoteToml(value) {
  return JSON.stringify(String(value));
}

function codexApprovalPolicy() {
  return profile.approval === "never" ? "never" : "on-request";
}

function codexSandboxMode() {
  return profile.filesystem === "read" ? "read-only" : "workspace-write";
}

function renderCodexPermissionBlock() {
  const sandboxMode = codexSandboxMode();
  const lines = [
    begin,
    `# Source: manifests/inventory/agent-permissions.json profile ${profileName}`,
    `approval_policy = ${quoteToml(codexApprovalPolicy())}`,
    `sandbox_mode = ${quoteToml(sandboxMode)}`,
  ];

  if (sandboxMode === "workspace-write") {
    lines.push("", "[sandbox_workspace_write]", `network_access = ${profile.network ? "true" : "false"}`);
  }

  lines.push(end);
  return `${lines.join("\n")}\n`;
}

function renderCodexConfig(current) {
  const block = renderCodexPermissionBlock();
  const oldBegin = "# BEGIN GENERATED CODEX PERMISSIONS";
  const oldEnd = "# END GENERATED CODEX PERMISSIONS";
  const start = current.includes(begin) ? current.indexOf(begin) : current.indexOf(oldBegin);
  const markerEnd = current.includes(begin) ? end : oldEnd;
  const finish = current.indexOf(markerEnd);

  if (start !== -1 || finish !== -1) {
    if (start === -1 || finish === -1 || finish < start) {
      throw new Error(`malformed generated permissions block in ${codexConfigPath}`);
    }
    const afterEnd = finish + markerEnd.length;
    const suffix = current.slice(afterEnd).replace(/^\n*/, "\n");
    return `${current.slice(0, start)}${block}${suffix}`;
  }

  const stripped = current
    .replace(/^approval_policy\s*=.*\n/m, "")
    .replace(/^sandbox_mode\s*=.*\n/m, "")
    .replace(/\n?\[sandbox_workspace_write\]\nnetwork_access\s*=.*\n/m, "\n");

  const marker = /^model_reasoning_effort\s*=.*\n/m;
  const match = marker.exec(stripped);
  if (!match) {
    return `${block}\n${stripped}`;
  }

  const insertAt = match.index + match[0].length;
  return `${stripped.slice(0, insertAt)}${block}\n${stripped.slice(insertAt).replace(/^\n+/, "")}`;
}

function renderCodexRule(pattern, decision) {
  const formattedPattern = `[${pattern.map((item) => JSON.stringify(String(item))).join(", ")}]`;
  return `prefix_rule(pattern=${formattedPattern}, decision=${JSON.stringify(decision)})`;
}

function renderCodexRules() {
  const deny = manifest.commands?.deny ?? [];
  const allow = manifest.commands?.allow ?? [];
  return `${[
    ...deny.map((pattern) => renderCodexRule(pattern, "forbidden")),
    ...allow.map((pattern) => renderCodexRule(pattern, "allow")),
  ].join("\n")}\n`;
}

function commandToClaude(pattern) {
  const joined = pattern.map(String).join(" ");
  return `Bash(${joined}:*)`;
}

function claudePermissions() {
  const allow = [...(manifest.tools?.read ?? [])];
  if (profile.filesystem !== "read") {
    allow.push(...(manifest.tools?.write ?? []));
  }

  for (const [server, tools] of Object.entries(manifest.mcp ?? {})) {
    for (const tool of tools) {
      allow.push(`mcp__${server}__${tool}`);
    }
  }

  for (const pattern of manifest.commands?.allow ?? []) {
    allow.push(commandToClaude(pattern));
  }

  const deny = (manifest.commands?.deny ?? []).map(commandToClaude);
  return {
    allow: [...new Set(allow)],
    deny: [...new Set(deny)],
  };
}

function renderClaudeSettings(current) {
  const settings = JSON.parse(current);
  settings.permissions = claudePermissions();
  return `${JSON.stringify(settings, null, 2)}\n`;
}

function checkOrWrite(target, rendered, label) {
  const current = fs.existsSync(target) ? fs.readFileSync(target, "utf8") : "";
  if (current === rendered) {
    if (check) console.log(`ok: ${label} generated permissions current`);
    return true;
  }

  if (check) {
    console.error(`fail: ${label} generated permissions drifted`);
    return false;
  }

  fs.writeFileSync(target, rendered);
  console.log(`render: ${path.relative(repoRoot, target)}`);
  return true;
}

let ok = true;
try {
  ok = checkOrWrite(codexConfigPath, renderCodexConfig(fs.readFileSync(codexConfigPath, "utf8")), "globals/codex/config.toml") && ok;
  ok = checkOrWrite(codexRulesPath, renderCodexRules(), "globals/codex/rules/default.rules") && ok;
  ok = checkOrWrite(claudeSettingsPath, renderClaudeSettings(fs.readFileSync(claudeSettingsPath, "utf8")), "globals/claude/settings.json") && ok;
} catch (error) {
  console.error(error?.message || String(error));
  process.exit(1);
}

process.exit(ok ? 0 : 1);
