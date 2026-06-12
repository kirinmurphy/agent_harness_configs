import fs from "node:fs";
import { MCP_PRESETS_PATH } from "./mcp-config.mjs";

export function loadMcpPresets() {
  let payload;
  try {
    payload = JSON.parse(fs.readFileSync(MCP_PRESETS_PATH, "utf8"));
  } catch (err) {
    console.error(`failed to read ${MCP_PRESETS_PATH}: ${err.message}`);
    process.exit(1);
  }

  const presets = new Map();
  for (const preset of payload.presets || []) {
    for (const alias of preset.aliases || []) {
      presets.set(alias.toLowerCase(), {
        name: preset.name,
        commandOrUrl: preset.commandOrUrl,
        args: [...(preset.args || [])],
      });
    }
  }
  return presets;
}
