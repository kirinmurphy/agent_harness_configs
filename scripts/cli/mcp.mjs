import { loadMcpPresets } from "./mcp-presets.mjs";
import { parseMcpAdd } from "./mcp-parse.mjs";
import { claudeMcpArgs, ensureClaudeMcpPermission, runClaudeMcpAdd, shellQuote } from "./mcp-claude.mjs";
import { ensureCodexMcp } from "./mcp-codex.mjs";

const mcpPresets = loadMcpPresets();

export function mcpAdd(rest) {
  const { opts, spec } = parseMcpAdd(rest, mcpPresets);
  const args = claudeMcpArgs(opts, spec);
  const display = ["claude", ...args].map(shellQuote).join(" ");

  if (opts.dryRun) {
    if (opts.target !== "only-codex") console.log(display);
    if (opts.target !== "only-codex" && opts.updateClaudePermission) {
      console.log(`would add permission: mcp__${spec.name} -> globals/claude/settings.json`);
    }
    if (opts.target !== "only-claude") ensureCodexMcp(spec, { dryRun: true });
    return;
  }

  if (opts.target !== "only-codex") {
    runClaudeMcpAdd(args);
    if (opts.updateClaudePermission) ensureClaudeMcpPermission(spec.name);
  }
  if (opts.target !== "only-claude") ensureCodexMcp(spec);
  process.exit(0);
}
