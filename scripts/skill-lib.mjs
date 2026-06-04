// Shared Node core for skill tooling (per-repo installer + harness_helper CLI).
//
// Cross-platform by design: uses only node: built-ins (fs, path, os, zlib, readline).
// No shelling out to `zip`/`unzip`/`ln`, so the same code runs on macOS, Linux, and
// Windows (Git Bash or PowerShell) wherever `node` is available.
//
// The "what is a real skill folder" rule mirrors scripts/skill-lib.sh:
//   a child directory containing a SKILL.md, that is not itself a symlink, not a dotfolder.

import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import zlib from "node:zlib";
import readline from "node:readline";

/** List real skill folder names in srcDir (folder w/ SKILL.md, not a symlink, not dotted). */
export function listSourceSkills(srcDir) {
  let entries;
  try {
    entries = fs.readdirSync(srcDir, { withFileTypes: true });
  } catch {
    return [];
  }
  const names = [];
  for (const ent of entries) {
    if (ent.name.startsWith(".")) continue;
    const full = path.join(srcDir, ent.name);
    // Reject symlinked sources outright (lstat keeps the link, not its target).
    if (fs.lstatSync(full).isSymbolicLink()) continue;
    if (!ent.isDirectory()) continue;
    if (!fs.existsSync(path.join(full, "SKILL.md"))) continue;
    names.push(ent.name);
  }
  return names.sort();
}

/** Absolute path to a harness home skills dir, e.g. ~/.claude/skills. */
export function homeSkillsDir(harness) {
  return path.join(os.homedir(), `.${harness}`, "skills");
}

/** Which global harnesses are present on this machine (have a ~/.claude / ~/.codex). */
export function detectHomeHarnesses() {
  return ["claude", "codex"].filter((h) =>
    fs.existsSync(path.join(os.homedir(), `.${h}`)),
  );
}

/**
 * Resolve client-repo skill destination dirs under repoRoot, canonical = .claude/skills
 * and .codex/skills. If neither exists, create .claude/skills (and .codex/skills only when
 * a .codex dir already exists at repo root). Returns absolute dir paths.
 */
export function resolveClientSkillDirs(repoRoot, { create = false } = {}) {
  const candidates = [
    { dir: path.join(repoRoot, ".claude", "skills"), parent: path.join(repoRoot, ".claude") },
    { dir: path.join(repoRoot, ".codex", "skills"), parent: path.join(repoRoot, ".codex") },
  ];
  const existing = candidates.filter((c) => fs.existsSync(c.dir));
  if (existing.length > 0) return existing.map((c) => c.dir);

  if (!create) return [];

  // Nothing exists yet: always seed .claude/skills; add .codex/skills if a .codex dir is there.
  const dests = [candidates[0].dir];
  if (fs.existsSync(candidates[1].parent)) dests.push(candidates[1].dir);
  for (const d of dests) fs.mkdirSync(d, { recursive: true });
  return dests;
}

/** Read a symlink target, or null if not a symlink / missing. */
export function readlinkSafe(p) {
  try {
    return fs.lstatSync(p).isSymbolicLink() ? fs.readlinkSync(p) : null;
  } catch {
    return null;
  }
}

/**
 * Ensure target is a symlink -> srcAbs. Non-destructive on conflict.
 * Returns "ok" | "linked" | "conflict" | "unlinked" | "skip".
 */
export function ensureSymlink(srcAbs, target, { dryRun = false, uninstall = false } = {}) {
  const current = readlinkSafe(target);

  if (uninstall) {
    if (current === srcAbs) {
      if (!dryRun) fs.rmSync(target);
      return "unlinked";
    }
    return "skip"; // not owned by us
  }

  if (current === srcAbs) return "ok";

  if (fs.existsSync(target) || current !== null) {
    return "conflict"; // exists and points elsewhere (or is a real file) — never clobber
  }

  if (!dryRun) {
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.symlinkSync(srcAbs, target);
  }
  return "linked";
}

/** Recursively copy a directory (dereferencing symlinks into real files). */
export function copyDir(src, dest) {
  fs.cpSync(src, dest, { recursive: true, dereference: true });
}

/** Timestamp suffix for backups/exports: YYYYMMDD-HHMMSS (local time). */
export function timestamp(d = new Date()) {
  const p = (n) => String(n).padStart(2, "0");
  return (
    `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}` +
    `-${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`
  );
}

// ---------------------------------------------------------------------------
// Interactive prompts (no-op friendly: callers pass non-interactive answers)
// ---------------------------------------------------------------------------

export function makePrompter() {
  if (!process.stdin.isTTY) {
    return { ask: null, close() {} };
  }
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  return {
    ask: (q) => new Promise((res) => rl.question(q, (a) => res(a.trim()))),
    close: () => rl.close(),
  };
}

export async function confirmYesNo(prompter, question, def = true) {
  if (!prompter.ask) return def;
  const hint = def ? "[Y/n]" : "[y/N]";
  const a = (await prompter.ask(`${question} ${hint} `)).toLowerCase();
  if (a === "") return def;
  return a === "y" || a === "yes";
}

/** Ask override / skip. Returns "override" | "skip". */
export async function askOverrideSkip(prompter, name, fallback = "skip") {
  if (!prompter.ask) return fallback;
  for (;;) {
    const a = (
      await prompter.ask(`  "${name}" already exists. (o)verride or (s)kip? [s] `)
    ).toLowerCase();
    if (a === "" || a === "s" || a === "skip") return "skip";
    if (a === "o" || a === "override") return "override";
  }
}

// ---------------------------------------------------------------------------
// Pure-Node ZIP writer (store + deflate). No external `zip` dependency.
// Produces a standard PKZIP archive readable by unzip / Finder / Explorer.
// ---------------------------------------------------------------------------

function crc32(buf) {
  let c = ~0;
  for (let i = 0; i < buf.length; i++) {
    c ^= buf[i];
    for (let k = 0; k < 8; k++) c = (c >>> 1) ^ (0xedb88320 & -(c & 1));
  }
  return (~c) >>> 0;
}

function dosDateTime(d = new Date()) {
  const time = (d.getHours() << 11) | (d.getMinutes() << 5) | (d.getSeconds() >> 1);
  const date = ((d.getFullYear() - 1980) << 9) | ((d.getMonth() + 1) << 5) | d.getDate();
  return { time: time & 0xffff, date: date & 0xffff };
}

/** Collect files under dir as { name (zip path), data } using posix separators. */
function collectFiles(dir, baseInZip) {
  const out = [];
  const walk = (cur, rel) => {
    for (const ent of fs.readdirSync(cur, { withFileTypes: true })) {
      const full = path.join(cur, ent.name);
      const zipRel = rel ? `${rel}/${ent.name}` : ent.name;
      if (ent.isDirectory()) walk(full, zipRel);
      else if (ent.isFile()) out.push({ name: `${baseInZip}/${zipRel}`, data: fs.readFileSync(full) });
    }
  };
  walk(dir, "");
  return out;
}

/**
 * Write a .zip at zipPath bundling each { srcDir, nameInZip } entry's tree.
 * Returns zipPath.
 */
export function writeZip(zipPath, entries) {
  const files = [];
  for (const e of entries) files.push(...collectFiles(e.srcDir, e.nameInZip));

  const { time, date } = dosDateTime();
  const localParts = [];
  const central = [];
  let offset = 0;

  for (const f of files) {
    const nameBuf = Buffer.from(f.name, "utf8");
    const crc = crc32(f.data);
    const deflated = zlib.deflateRawSync(f.data);
    const useDeflate = deflated.length < f.data.length;
    const stored = useDeflate ? deflated : f.data;
    const method = useDeflate ? 8 : 0;

    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(20, 4);
    local.writeUInt16LE(0, 6);
    local.writeUInt16LE(method, 8);
    local.writeUInt16LE(time, 10);
    local.writeUInt16LE(date, 12);
    local.writeUInt32LE(crc, 14);
    local.writeUInt32LE(stored.length, 18);
    local.writeUInt32LE(f.data.length, 22);
    local.writeUInt16LE(nameBuf.length, 26);
    local.writeUInt16LE(0, 28);
    localParts.push(local, nameBuf, stored);

    const cen = Buffer.alloc(46);
    cen.writeUInt32LE(0x02014b50, 0);
    cen.writeUInt16LE(20, 4);
    cen.writeUInt16LE(20, 6);
    cen.writeUInt16LE(0, 8);
    cen.writeUInt16LE(method, 10);
    cen.writeUInt16LE(time, 12);
    cen.writeUInt16LE(date, 14);
    cen.writeUInt32LE(crc, 16);
    cen.writeUInt32LE(stored.length, 20);
    cen.writeUInt32LE(f.data.length, 24);
    cen.writeUInt16LE(nameBuf.length, 28);
    cen.writeUInt32LE(offset, 42);
    central.push(cen, nameBuf);

    offset += local.length + nameBuf.length + stored.length;
  }

  const centralBuf = Buffer.concat(central);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(files.length, 8);
  end.writeUInt16LE(files.length, 10);
  end.writeUInt32LE(centralBuf.length, 12);
  end.writeUInt32LE(offset, 16);

  fs.writeFileSync(zipPath, Buffer.concat([...localParts, centralBuf, end]));
  return zipPath;
}
