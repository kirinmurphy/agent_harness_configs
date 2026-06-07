// Shared Node core for skill tooling, used by the roborepo CLI (scripts/roborepo.mjs).
//
// Cross-platform by design: uses only node: built-ins (fs, path, zlib, readline).
// No shelling out to `zip`/`unzip`/`ln`, so the same code runs on macOS, Linux, and
// Windows (Git Bash or PowerShell) wherever `node` is available. Note: symlink creation on
// Windows requires Developer Mode or an elevated shell; ensureSymlink() degrades gracefully
// (returns "denied" instead of throwing) when the OS refuses.
//
// The "what is a real skill folder" rule mirrors scripts/skill-lib.sh:
//   a child directory containing a SKILL.md, that is not itself a symlink, not a dotfolder.

import fs from "node:fs";
import path from "node:path";
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

/**
 * Resolve client-repo skill destination dirs under repoRoot, canonical = .claude/skills
 * (Claude reads it) and .agents/skills (Codex scans it exclusively). If neither exists,
 * create both so a fresh export works for both harnesses. Returns absolute dir paths.
 */
export function resolveClientSkillDirs(repoRoot, { create = false } = {}) {
  const candidates = [
    { dir: path.join(repoRoot, ".claude", "skills"), parent: path.join(repoRoot, ".claude") },
    { dir: path.join(repoRoot, ".agents", "skills"), parent: path.join(repoRoot, ".agents") },
  ];
  if (!create) {
    const existing = candidates.filter((c) => fs.existsSync(c.dir));
    return existing.map((c) => c.dir);
  }

  // Nothing exists yet: seed both harness homes so fresh exports are visible to Claude and Codex.
  const dests = candidates.map((c) => c.dir);
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
 * Returns "ok" | "linked" | "conflict" | "unlinked" | "skip" | "denied".
 * "denied" means the OS refused symlink creation (e.g. Windows without Developer Mode/admin);
 * the caller reports it and continues rather than aborting the whole run.
 */
export function ensureSymlink(srcAbs, target, { dryRun = false, uninstall = false } = {}) {
  const current = readlinkSafe(target);

  if (uninstall) {
    if (current === srcAbs) {
      if (!dryRun) fs.unlinkSync(target);
      return "unlinked";
    }
    return "skip"; // not owned by us
  }

  if (current === srcAbs) return "ok";

  if (fs.existsSync(target) || current !== null) {
    return "conflict"; // exists and points elsewhere (or is a real file) — never clobber
  }

  if (!dryRun) {
    try {
      fs.mkdirSync(path.dirname(target), { recursive: true });
      fs.symlinkSync(srcAbs, target);
    } catch (err) {
      if (err?.code === "EPERM" || err?.code === "EACCES") return "denied";
      throw err;
    }
  }
  return "linked";
}

/** Recursively copy a directory (dereferencing symlinks into real files). */
export function copyDir(src, dest) {
  fs.cpSync(src, dest, { recursive: true, dereference: true });
}

// The symlink target prefix used for in-repo client skill links: ../../.agents/skills/<name>.
// .agents/skills is the canonical client source AND what Codex scans for project skills.
const LOCAL_LINK_PREFIX = path.join("..", "..", ".agents", "skills");

/**
 * In-repo skill linking for a CLIENT repo: source <repoRoot>/.agents/skills/<name> becomes a
 * per-harness symlink in <repoRoot>/.claude/skills and/or <repoRoot>/.codex/skills, each
 * pointing at ../../.agents/skills/<name>. Purely local — never touches ~/.claude or ~/.codex.
 * A harness destination participates when its root folder already exists, or when the CLI
 * explicitly selected it after prompting the user.
 *
 * .agents/skills is the single canonical source (Codex reads it directly as project-scope
 * skills; the per-harness links let Claude and the transitional .codex path see it too).
 * Built on the shared ensureSymlink primitive so there is no duplicated link/conflict logic.
 * Like link-skills.sh, it also PRUNES orphaned links — symlinks this tool owns whose source
 * skill no longer exists — so deleting a skill and re-running cleans up the dead link.
 *
 * Returns a tally { linked, ok, conflicts, unlinked, denied, pruned, skills }.
 */
export function linkLocalSkills(repoRoot, { dryRun = false, uninstall = false, targetRoots = null } = {}) {
  const srcDir = path.join(repoRoot, ".agents", "skills");
  const harnessRoots =
    targetRoots ?? [path.join(repoRoot, ".claude"), path.join(repoRoot, ".codex")].filter((root) => fs.existsSync(root));
  const harnessDirs = harnessRoots.map((root) => path.join(root, "skills"));
  const names = listSourceSkills(srcDir);
  const tally = {
    linked: 0,
    ok: 0,
    conflicts: 0,
    unlinked: 0,
    denied: 0,
    pruned: 0,
    skills: names.length,
    targetDirs: harnessDirs.length,
  };

  for (const name of names) {
    // Relative target keeps the client repo portable: ../../.agents/skills/<name>.
    const relTarget = path.join(LOCAL_LINK_PREFIX, name);
    for (const hdir of harnessDirs) {
      const target = path.join(hdir, name);
      const result = ensureSymlink(relTarget, target, { dryRun, uninstall });
      tally[
        { linked: "linked", unlinked: "unlinked", conflict: "conflicts", denied: "denied" }[result] ?? "ok"
      ]++;
      if (result === "linked") console.log(`link: ${target} -> ${relTarget}`);
      else if (result === "unlinked") console.log(`unlink: ${target}`);
      else if (result === "conflict") console.warn(`conflict: ${target} exists and points elsewhere — skipped`);
      else if (result === "denied")
        console.warn(`denied: ${target} — OS refused symlink (Windows: enable Developer Mode or run elevated)`);
    }
  }

  // Prune pass (skip during uninstall — that already removes our links by ownership).
  if (!uninstall) {
    const live = new Set(names);
    for (const hdir of harnessDirs) {
      let entries;
      try {
        entries = fs.readdirSync(hdir, { withFileTypes: true });
      } catch {
        continue; // dir doesn't exist — nothing to prune
      }
      for (const ent of entries) {
        const link = path.join(hdir, ent.name);
        const tgt = readlinkSafe(link);
        if (tgt === null) continue; // only symlinks; never touch real files/dirs
        // Only links we own: target shaped like ../../.agents/skills/<name>.
        if (path.dirname(tgt) !== LOCAL_LINK_PREFIX) continue;
        if (live.has(ent.name)) continue; // source still exists — keep
        if (!dryRun) fs.unlinkSync(link);
        console.log(`prune: ${link} (source gone)`);
        tally.pruned++;
      }
    }
  }

  return tally;
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

/**
 * Interactive single-choice menu with optional section headers and per-item descriptions.
 * items: a flat list of either
 *   { header: "SECTION NAME" }                         non-selectable section divider, or
 *   { label, value, desc? }                            a selectable action.
 * On an interactive TTY: arrow up/down (skipping headers), Enter to select, Esc/q/Ctrl-C cancel.
 * Otherwise (pipe, dumb terminal): a numbered list (headers shown, only actions numbered).
 * Returns the chosen item's `value`, or null if cancelled.
 */
export async function selectMenu(title, items) {
  const isHeader = (it) => Object.prototype.hasOwnProperty.call(it, "header");
  const selectable = items.map((it, i) => (isHeader(it) ? -1 : i)).filter((i) => i >= 0);
  const labelWidth = Math.max(...items.filter((it) => !isHeader(it)).map((it) => it.label.length));

  const tty = process.stdin.isTTY && process.stdout.isTTY;
  if (!tty) return numberedFallback(title, items, isHeader);

  return new Promise((resolve) => {
    let pos = 0; // index into `selectable`
    const out = process.stdout;

    const line = (it, sel) => {
      if (isHeader(it)) return `\x1b[2K\x1b[2m${it.header}\x1b[0m\n`; // dim header
      const pad = it.label.padEnd(labelWidth);
      const desc = it.desc ? `  \x1b[2m${it.desc}\x1b[0m` : "";
      return sel
        ? `\x1b[2K\x1b[36m> ${pad}\x1b[0m${desc}\n`
        : `\x1b[2K  ${pad}${desc}\n`;
    };

    const render = (first) => {
      if (!first) out.write(`\x1b[${items.length + 1}A`);
      out.write(`\x1b[2K${title}\n`);
      items.forEach((it, i) => out.write(line(it, i === selectable[pos])));
    };

    readline.emitKeypressEvents(process.stdin);
    process.stdin.setRawMode(true);
    process.stdin.resume();
    render(true);

    const cleanup = () => {
      process.stdin.setRawMode(false);
      process.stdin.pause();
      process.stdin.removeListener("keypress", onKey);
    };

    const onKey = (_str, key) => {
      if (!key) return;
      if (key.name === "up" || key.name === "k") {
        pos = (pos - 1 + selectable.length) % selectable.length;
        render(false);
      } else if (key.name === "down" || key.name === "j") {
        pos = (pos + 1) % selectable.length;
        render(false);
      } else if (key.name === "return" || key.name === "enter") {
        cleanup();
        out.write("\n");
        resolve(items[selectable[pos]].value);
      } else if (key.name === "escape" || key.name === "q" || (key.ctrl && key.name === "c")) {
        cleanup();
        out.write("\n");
        resolve(null);
      }
    };

    process.stdin.on("keypress", onKey);
  });
}

function numberedFallback(title, items, isHeader) {
  console.log(title);
  // Number only selectable actions; render headers as plain dividers. Map the printed number
  // back to the item via `order`.
  const order = [];
  for (const it of items) {
    if (isHeader(it)) {
      console.log(`\n  ${it.header}`);
    } else {
      order.push(it);
      const desc = it.desc ? `  — ${it.desc}` : "";
      console.log(`  ${order.length}) ${it.label}${desc}`);
    }
  }
  process.stdout.write("Select a number (or blank to cancel): ");

  // Read from stdin directly — works for both a piped stream and an interactive terminal,
  // unlike makePrompter() which requires an attached TTY. We capture the first line and
  // resolve a TTY immediately; for a piped stream (no TTY) we resolve on "close" using the
  // captured line, because readline may deliver "close" in the same tick as "line".
  const interactive = process.stdin.isTTY;
  const rl = readline.createInterface({ input: process.stdin });
  return new Promise((resolve) => {
    let captured = null;
    let settled = false;
    const toValue = (l) => {
      const n = Number.parseInt(l, 10);
      return Number.isInteger(n) && n >= 1 && n <= order.length ? order[n - 1].value : null;
    };
    const finish = (val) => {
      if (settled) return;
      settled = true;
      rl.close();
      resolve(val);
    };
    rl.once("line", (l) => {
      captured = l;
      if (interactive) finish(toValue(l));
    });
    rl.once("close", () => finish(captured === null ? null : toValue(captured)));
  });
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
