// roborepo `mcp add` subcommand: register an MCP server with Claude (via `claude mcp add`)
// and Codex (by editing codex/config.toml), plus a matching permission entry in
// claude/settings.json. Presets cover the bundled jcodemunch/jdocmunch servers; otherwise the
// input is treated as an HTTP URL or a uvx package name.

import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { repoRoot } from "./paths.mjs";

const mcpPresets = new Map([
  ["jcodemunch", { name: "jcodemunch", commandOrUrl: "uvx", args: ["jcodemunch-mcp"] }],
  ["jcodemunch-mcp", { name: "jcodemunch", commandOrUrl: "uvx", args: ["jcodemunch-mcp"] }],
  ["jdocmunch", { name: "jdocmunch", commandOrUrl: "uvx", args: ["jdocmunch-mcp"] }],
  ["jdocmunch-mcp", { name: "jdocmunch", commandOrUrl: "uvx", args: ["jdocmunch-mcp"] }],
]);

function isHttpUrl(value) {
  return /^https?:\/\//i.test(value);
}

function slugMcpName(value) {
  return value
    .replace(/^https?:\/\//i, "")
    .replace(/[?#].*$/, "")
    .replace(/\/+$/, "")
    .split("/")
    .pop()
    .replace(/\.git$/i, "")
    .replace(/-mcp$/i, "")
    .replace(/[^a-zA-Z0-9_.-]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .toLowerCase();
}

function parseMcpAdd(rest) {
  const opts = {
    scope: "user",
    name: null,
    transport: null,
    dryRun: false,
    target: "all",
    updateClaudePermission: true,
    passthrough: [],
  };
  const positional = [];
  let afterDoubleDash = false;

  for (const arg of rest) {
    if (afterDoubleDash) {
      opts.passthrough.push(arg);
      continue;
    }
    if (arg === "--") {
      afterDoubleDash = true;
      continue;
    }
    if (arg === "--dry-run") {
      opts.dryRun = true;
      continue;
    }
    if (arg === "--only-claude") {
      opts.target = opts.target === "only-codex" ? "conflict" : "only-claude";
      continue;
    }
    if (arg === "--only-codex") {
      opts.target = opts.target === "only-claude" ? "conflict" : "only-codex";
      continue;
    }
    if (arg === "--skip-claude-permission") {
      opts.updateClaudePermission = false;
      continue;
    }
    if (arg.startsWith("--scope=")) {
      opts.scope = arg.slice("--scope=".length);
      continue;
    }
    if (arg.startsWith("--name=")) {
      opts.name = arg.slice("--name=".length);
      continue;
    }
    if (arg.startsWith("--transport=")) {
      opts.transport = arg.slice("--transport=".length);
      continue;
    }
    if (arg.startsWith("--")) {
      console.error(`unknown flag for "mcp add": ${arg}`);
      process.exit(2);
    }
    positional.push(arg);
  }

  if (positional.length !== 1) {
    console.error(
      `usage: roborepo mcp add <name-or-url> [--scope=user|local|project] [--name=<name>] [--dry-run] [--only-claude|--only-codex] [--skip-claude-permission]`,
    );
    process.exit(2);
  }
  if (opts.target === "conflict") {
    console.error(`--only-claude and --only-codex are mutually exclusive`);
    process.exit(2);
  }
  if (!["user", "local", "project"].includes(opts.scope)) {
    console.error(`--scope must be user, local, or project`);
    process.exit(2);
  }
  if (opts.transport && !["stdio", "sse", "http"].includes(opts.transport)) {
    console.error(`--transport must be stdio, sse, or http`);
    process.exit(2);
  }

  const input = positional[0];
  const preset = mcpPresets.get(input.toLowerCase());
  let spec;
  if (preset) {
    spec = { ...preset, args: [...preset.args] };
  } else if (isHttpUrl(input)) {
    spec = { name: opts.name || slugMcpName(input), commandOrUrl: input, args: [] };
    opts.transport ||= "http";
  } else {
    spec = { name: opts.name || slugMcpName(input), commandOrUrl: "uvx", args: [input] };
  }

  if (!spec.name) {
    console.error(`could not derive MCP server name; pass --name=<name>`);
    process.exit(2);
  }
  if (opts.name) spec.name = opts.name;
  spec.args.push(...opts.passthrough);
  return { opts, spec };
}

function shellQuote(arg) {
  if (/^[a-zA-Z0-9_./:=@%+-]+$/.test(arg)) return arg;
  return `'${arg.replace(/'/g, `'\\''`)}'`;
}

function ensureClaudeMcpPermission(serverName) {
  const settingsPath = path.join(repoRoot, "claude", "settings.json");
  const permission = `mcp__${serverName}`;
  let settings;
  try {
    settings = JSON.parse(fs.readFileSync(settingsPath, "utf8"));
  } catch (err) {
    console.error(`failed to read ${settingsPath}: ${err.message}`);
    process.exit(1);
  }

  settings.permissions ||= {};
  settings.permissions.allow ||= [];
  if (settings.permissions.allow.includes(permission)) {
    console.log(`permission already present: ${permission}`);
    return;
  }

  const insertAt = settings.permissions.allow.findLastIndex((item) => item.startsWith("mcp__")) + 1;
  if (insertAt > 0) {
    settings.permissions.allow.splice(insertAt, 0, permission);
  } else {
    settings.permissions.allow.unshift(permission);
  }
  fs.writeFileSync(settingsPath, `${JSON.stringify(settings, null, 2)}\n`);
  console.log(`permission added: ${permission} -> ${path.relative(repoRoot, settingsPath)}`);
}

function tomlString(value) {
  return JSON.stringify(value);
}

function tomlArray(values) {
  return `[${values.map(tomlString).join(", ")}]`;
}

function tomlTableKey(key) {
  return /^[A-Za-z0-9_-]+$/.test(key) ? key : tomlString(key);
}

function codexMcpBlock(spec) {
  const lines = [`[mcp_servers.${tomlTableKey(spec.name)}]`];
  if (isHttpUrl(spec.commandOrUrl)) {
    lines.push(`url = ${tomlString(spec.commandOrUrl)}`);
  } else {
    lines.push(`command = ${tomlString(spec.commandOrUrl)}`);
    lines.push(`args = ${tomlArray(spec.args)}`);
  }
  return lines.join("\n");
}

function codexHasMcp(configText, serverName) {
  const bare = serverName.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const quoted = tomlString(serverName).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return new RegExp(`^\\[mcp_servers\\.(?:${bare}|${quoted})\\]$`, "m").test(configText);
}

function ensureCodexMcp(spec, { dryRun = false } = {}) {
  const configPath = path.join(repoRoot, "codex", "config.toml");
  let configText;
  try {
    configText = fs.readFileSync(configPath, "utf8");
  } catch (err) {
    console.error(`failed to read ${configPath}: ${err.message}`);
    process.exit(1);
  }

  if (codexHasMcp(configText, spec.name)) {
    console.log(`codex MCP already present: ${spec.name}`);
    return;
  }

  const block = codexMcpBlock(spec);
  if (dryRun) {
    console.log(`would add Codex MCP: ${spec.name} -> codex/config.toml`);
    console.log(block);
    return;
  }

  const prefix = configText.endsWith("\n") ? configText : `${configText}\n`;
  fs.writeFileSync(configPath, `${prefix}\n${block}\n`);
  console.log(`codex MCP added: ${spec.name} -> ${path.relative(repoRoot, configPath)}`);
}

export function mcpAdd(rest) {
  const { opts, spec } = parseMcpAdd(rest);
  const args = ["mcp", "add", "--scope", opts.scope];
  if (opts.transport) args.push("--transport", opts.transport);
  args.push(spec.name);
  if (!opts.transport || opts.transport === "stdio") args.push("--");
  args.push(spec.commandOrUrl, ...spec.args);

  const display = ["claude", ...args].map(shellQuote).join(" ");
  if (opts.dryRun) {
    if (opts.target !== "only-codex") console.log(display);
    if (opts.target !== "only-codex" && opts.updateClaudePermission) {
      console.log(`would add permission: mcp__${spec.name} -> claude/settings.json`);
    }
    if (opts.target !== "only-claude") ensureCodexMcp(spec, { dryRun: true });
    return;
  }

  if (opts.target !== "only-codex") {
    const r = spawnSync("claude", args, { stdio: "inherit" });
    if (r.error) {
      console.error(`failed to run claude: ${r.error.message}`);
      process.exit(1);
    }
    if ((r.status ?? 1) !== 0) process.exit(r.status ?? 1);
    if (opts.updateClaudePermission) ensureClaudeMcpPermission(spec.name);
  }
  if (opts.target !== "only-claude") ensureCodexMcp(spec);
  process.exit(0);
}
