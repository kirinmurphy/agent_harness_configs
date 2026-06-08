#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const args = process.argv.slice(2);
const checkOnly = args.includes("--check");
const paths = args.filter((arg) => arg !== "--check");
const targets = paths.length > 0 ? paths : [path.join(process.cwd(), ".claude", "settings.json")];

let failed = false;

function normalizeHookEntry(entry) {
  if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
    return entry;
  }

  const matcher = typeof entry.matcher === "string" ? entry.matcher : "";

  if (Array.isArray(entry.hooks)) {
    return { ...entry, matcher };
  }

  const { matcher: _matcher, hooks: _hooks, ...hook } = entry;
  return {
    matcher,
    hooks: [hook],
  };
}

function normalizeSettings(settings) {
  if (!settings || typeof settings !== "object" || !settings.hooks) {
    return settings;
  }

  const hooks = {};
  for (const [eventName, entries] of Object.entries(settings.hooks)) {
    hooks[eventName] = Array.isArray(entries) ? entries.map(normalizeHookEntry) : entries;
  }

  return { ...settings, hooks };
}

function validate(settings, filePath) {
  for (const [eventName, entries] of Object.entries(settings.hooks || {})) {
    if (!Array.isArray(entries)) {
      throw new Error(`${filePath}: hooks.${eventName} must be an array`);
    }

    entries.forEach((entry, index) => {
      if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
        throw new Error(`${filePath}: hooks.${eventName}[${index}] must be an object`);
      }
      if (typeof entry.matcher !== "string") {
        throw new Error(`${filePath}: hooks.${eventName}[${index}].matcher must be a string`);
      }
      if (!Array.isArray(entry.hooks)) {
        throw new Error(`${filePath}: hooks.${eventName}[${index}].hooks must be an array`);
      }
    });
  }
}

for (const target of targets) {
  try {
    const before = fs.readFileSync(target, "utf8");
    const settings = JSON.parse(before);
    const normalized = normalizeSettings(settings);
    validate(normalized, target);

    const after = `${JSON.stringify(normalized, null, 2)}\n`;
    if (before === after) {
      console.log(`ok: ${target}`);
      continue;
    }

    if (checkOnly) {
      console.error(`fail: ${target} needs Claude hook schema normalization`);
      failed = true;
      continue;
    }

    fs.writeFileSync(target, after);
    console.log(`fixed: ${target}`);
  } catch (error) {
    console.error(`fail: ${error.message}`);
    failed = true;
  }
}

if (failed) {
  process.exit(1);
}
