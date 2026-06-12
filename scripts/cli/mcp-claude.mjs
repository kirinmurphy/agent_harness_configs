import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { repoRoot } from "./paths.mjs";
import { CLAUDE_SETTINGS_PATH } from "./mcp-config.mjs";

export function shellQuote(arg) {
  if (/^[a-zA-Z0-9_./:=@%+-]+$/.test(arg)) return arg;
  return `'${arg.replace(/'/g, `'\\''`)}'`;
}

export function claudeMcpArgs(opts, spec) {
  const args = ["mcp", "add", "--scope", opts.scope];
  if (opts.transport) args.push("--transport", opts.transport);
  args.push(spec.name);
  if (!opts.transport || opts.transport === "stdio") args.push("--");
  args.push(spec.commandOrUrl, ...spec.args);
  return args;
}

export function runClaudeMcpAdd(args) {
  const result = spawnSync("claude", args, { stdio: "inherit" });
  if (result.error) {
    console.error(`failed to run claude: ${result.error.message}`);
    process.exit(1);
  }
  if ((result.status ?? 1) !== 0) process.exit(result.status ?? 1);
}

export function ensureClaudeMcpPermission(serverName) {
  const permission = `mcp__${serverName}`;
  let settings;
  try {
    settings = JSON.parse(fs.readFileSync(CLAUDE_SETTINGS_PATH, "utf8"));
  } catch (err) {
    console.error(`failed to read ${CLAUDE_SETTINGS_PATH}: ${err.message}`);
    process.exit(1);
  }

  settings.permissions ||= {};
  settings.permissions.allow ||= [];
  if (settings.permissions.allow.includes(permission)) {
    console.log(`permission already present: ${permission}`);
    return;
  }

  const insertAt = nextMcpPermissionIndex(settings.permissions.allow);
  settings.permissions.allow.splice(insertAt, 0, permission);
  fs.writeFileSync(CLAUDE_SETTINGS_PATH, `${JSON.stringify(settings, null, 2)}\n`);
  console.log(`permission added: ${permission} -> ${path.relative(repoRoot, CLAUDE_SETTINGS_PATH)}`);
}

function nextMcpPermissionIndex(allow) {
  for (let i = allow.length - 1; i >= 0; i--) {
    if (allow[i].startsWith("mcp__")) return i + 1;
  }
  return 0;
}
