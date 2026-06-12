import readline from "node:readline";

export function makePrompter() {
  if (!process.stdin.isTTY) return { ask: null, close() {} };
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

export async function selectMenu(title, items) {
  const isHeader = (it) => Object.prototype.hasOwnProperty.call(it, "header");
  const selectable = items.map((it, i) => (isHeader(it) ? -1 : i)).filter((i) => i >= 0);
  const labelWidth = Math.max(...items.filter((it) => !isHeader(it)).map((it) => it.label.length));

  const tty = process.stdin.isTTY && process.stdout.isTTY;
  if (!tty) return numberedFallback(title, items, isHeader);

  return new Promise((resolve) => {
    let pos = 0;
    const out = process.stdout;

    const line = (it, sel) => {
      if (isHeader(it)) return `\x1b[2K\x1b[2m${it.header}\x1b[0m\n`;
      const pad = it.label.padEnd(labelWidth);
      const desc = it.desc ? `  \x1b[2m${it.desc}\x1b[0m` : "";
      return sel ? `\x1b[2K\x1b[36m> ${pad}\x1b[0m${desc}\n` : `\x1b[2K  ${pad}${desc}\n`;
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
