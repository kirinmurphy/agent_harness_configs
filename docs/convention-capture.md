# Convention Capture

Conversations with an agent surface decisions, conventions, and architectural choices that would otherwise be lost when the session ends. Without capture, the reasoning behind a pattern lives only in chat history — invisible to future sessions, future engineers, and the agent itself.

Convention capture is the mechanism for promoting those decisions into durable agent rules and project docs. When a convention or architectural decision surfaces, the agent flags it inline. The user explicitly triggers capture when ready.

## How it works

### During session

When a convention or decision is confirmed, the agent flags it inline in chat on its own line:

> 📌 **Capture candidate:** use named exports, not default exports

No file writes. No automation. Consistent format — always this exact blockquote+emoji+bold pattern, never embedded in a paragraph.

### Triggering capture

User says any of:

- `/capture-convention`
- "capture this"
- "save that convention"
- "let's document that"
- "remember this"

Agent then runs the full capture-convention workflow: scans conversation, deduplicates against existing docs, presents plan, waits for confirmation, writes.

### Routing: local vs global

Each item gets classified at capture time:

| Scope                                 | Destination                                                   |
| ------------------------------------- | ------------------------------------------------------------- |
| Applies only in this repo             | current repo's `CLAUDE.md` or `.claude/rules/`                |
| Applies to agent behavior in any repo | `harness_configs/claude/CLAUDE.md` or `harness_configs/docs/` |

Global items: caveman behavior, jcodemunch defaults, verification discipline, hook patterns.
Local items: naming conventions, component patterns, data-fetching rules, testing approach, business logic.

### Codex parity

Same inline flagging rule lives in `codex/AGENTS.md`. Codex has no slash command equivalent — user triggers capture by saying "capture this" or similar. Captured items go to same destinations via the same routing logic.

## docs/convention-capture/ directory

Not used in current design. If you want an ephemeral scratch space for capture candidates mid-session, create files here manually. Not tracked in git by default — add to `.gitignore` if created.

## Why not automatic

- Hooks can't access transcript — only shell
- Concurrent sessions would conflict on same file
- Model judgment alone over-captures noise and misses subtle decisions
- Human review at capture time produces cleaner, more durable output
