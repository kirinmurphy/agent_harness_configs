// roborepo `index` / `watch` / `run` subcommands. These shell out to uvx (jcodemunch-mcp,
// jdocmunch-mcp) to (live-)index the current repo, plus a generic command runner that trims
// noisy output. [path] args default to cwd and are resolved to absolute paths.

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";

/** Resolve an optional [path] arg to an absolute path; default = cwd. */
function resolveTarget(arg) {
  return arg ? path.resolve(process.cwd(), arg) : process.cwd();
}

function requireUvx() {
  const probe = spawnSync("uvx", ["--version"], { stdio: "ignore" });
  if (probe.error) {
    console.error(`this command needs "uvx" (from uv) on PATH. Install: https://docs.astral.sh/uv/`);
    process.exit(127);
  }
}

/**
 * The `watch` subcommand needs the `watchfiles` package, which isn't pulled in by a plain
 * `uv tool install jcodemunch-mcp`. jcodemunch-mcp isn't on PyPI, so `uvx --with
 * jcodemunch-mcp[watch]` can't re-resolve it — instead we add the extra dep onto the
 * already-installed tool. This is idempotent: a no-op (cache-resolve only) once satisfied.
 */
function ensureWatchDeps() {
  const r = spawnSync("uv", ["tool", "install", "jcodemunch-mcp", "--with", "watchfiles"], {
    stdio: "ignore",
  });
  if (r.error || r.status !== 0) {
    console.error(
      `warn: could not ensure "watchfiles" via "uv tool install jcodemunch-mcp --with watchfiles".\n` +
        `      watch may crash with "watchfiles is required". Install it manually, then retry.`,
    );
  }
}

export function indexCode(rest) {
  requireUvx();
  const target = resolveTarget(rest[0]);
  const sub = fs.statSync(target).isFile() ? "index-file" : "index";
  const r = spawnSync("uvx", ["jcodemunch-mcp", sub, "--no-ai-summaries", target], { stdio: "inherit" });
  process.exit(r.status ?? 1);
}

export function indexDocs(rest) {
  requireUvx();
  const target = resolveTarget(rest[0]);
  const r = spawnSync("uvx", ["jdocmunch-mcp", "index-local", "--path", target], { stdio: "inherit" });
  if (r.status === 0) {
    try {
      fs.writeFileSync(path.join(target, ".jdm-indexed"), "");
    } catch {
      /* best-effort marker */
    }
  }
  process.exit(r.status ?? 1);
}

export function watchCode(rest) {
  requireUvx();
  ensureWatchDeps();
  const target = resolveTarget(rest[0]);

  // Write the pidfile the Claude SessionStart hook reads to detect a live watcher:
  //   /tmp/jcmwatch-<md5(target)>.pid  containing "<pid> <process-start-time>".
  // The hash is keyed on the absolute target dir, matching globals/claude/settings.json.
  const hash = createHash("md5").update(target).digest("hex").slice(0, 32);
  const pidfile = path.join(os.tmpdir(), `jcmwatch-${hash}.pid`);
  const started = startTimeForPid(process.pid);
  try {
    fs.writeFileSync(pidfile, `${process.pid} ${started}`);
    const cleanup = () => {
      try {
        fs.rmSync(pidfile);
      } catch {
        /* already gone */
      }
    };
    process.on("exit", cleanup);
    process.on("SIGINT", () => process.exit(130));
    process.on("SIGTERM", () => process.exit(143));
  } catch {
    /* pidfile is best-effort; watch still runs without hook detection */
  }

  const r = spawnSync("uvx", ["jcodemunch-mcp", "watch", target], {
    stdio: "inherit",
  });
  process.exit(r.status ?? 1);
}

/** Process start time string, matching the `ps lstart`/`start` format the hook compares. */
function startTimeForPid(pid) {
  for (const flag of ["lstart=", "start="]) {
    const r = spawnSync("ps", ["-p", String(pid), "-o", flag], { encoding: "utf8" });
    if (r.status === 0 && r.stdout) return r.stdout.trim().replace(/\s+/g, " ");
  }
  return "";
}

export function runCmd(rest) {
  if (rest.length === 0) {
    console.error(`usage: roborepo run <cmd> [args...]`);
    process.exit(2);
  }
  const r = spawnSync(rest[0], rest.slice(1), { encoding: "utf8" });
  if (r.error) {
    console.error(`fail: ${rest.join(" ")} — ${r.error.message}`);
    process.exit(1);
  }
  const out = `${r.stdout ?? ""}${r.stderr ?? ""}`;
  const lines = out.split("\n");
  const status = r.status ?? 0;
  if (status === 0) {
    console.log(`ok: ${rest.join(" ")}`);
    console.log(lines.slice(-40).join("\n").trimEnd());
  } else {
    console.error(`fail(${status}): ${rest.join(" ")}`);
    console.error(lines.slice(-120).join("\n").trimEnd());
  }
  process.exit(status);
}
