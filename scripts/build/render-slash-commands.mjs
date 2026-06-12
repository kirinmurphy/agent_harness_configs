#!/usr/bin/env node
import { renderSlashCommands } from "../cli/slash-commands.mjs";

const args = new Set(process.argv.slice(2));
for (const arg of args) {
  if (arg !== "--check" && arg !== "--quiet" && arg !== "-q") {
    console.error("usage: scripts/build/render-slash-commands.mjs [--check] [--quiet|-q]");
    process.exit(2);
  }
}

const checkOnly = args.has("--check");
const quiet = args.has("--quiet") || args.has("-q");

try {
  const result = renderSlashCommands({ checkOnly, quiet });
  if (result.failed > 0) {
    console.error(`slash command render ${checkOnly ? "check " : ""}failed (${result.failed} issue(s))`);
    process.exit(1);
  }
  if (!quiet) {
    const mode = checkOnly ? "checked" : "rendered";
    console.log(`${result.commands} slash command(s) ${mode}, ${result.changed} file(s) changed`);
  }
} catch (err) {
  console.error(err?.stack || String(err));
  process.exit(1);
}
