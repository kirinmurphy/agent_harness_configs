import fs from "node:fs";
import path from "node:path";
import { repoRoot } from "./paths.mjs";
import { CODEX_CONFIG_PATH } from "./mcp-config.mjs";
import { isHttpUrl } from "./mcp-parse.mjs";

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

export function ensureCodexMcp(spec, { dryRun = false } = {}) {
  let configText;
  try {
    configText = fs.readFileSync(CODEX_CONFIG_PATH, "utf8");
  } catch (err) {
    console.error(`failed to read ${CODEX_CONFIG_PATH}: ${err.message}`);
    process.exit(1);
  }

  if (codexHasMcp(configText, spec.name)) {
    console.log(`codex MCP already present: ${spec.name}`);
    return;
  }

  const block = codexMcpBlock(spec);
  if (dryRun) {
    console.log(`would add Codex MCP: ${spec.name} -> globals/codex/config.toml`);
    console.log(block);
    return;
  }

  const prefix = configText.endsWith("\n") ? configText : `${configText}\n`;
  fs.writeFileSync(CODEX_CONFIG_PATH, `${prefix}\n${block}\n`);
  console.log(`codex MCP added: ${spec.name} -> ${path.relative(repoRoot, CODEX_CONFIG_PATH)}`);
}
