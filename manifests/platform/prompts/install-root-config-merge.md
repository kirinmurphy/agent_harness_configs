Compare harness config at:
  {{SRC}}

With local user config at:
  {{HOME_PATH}}

Default stance: keep the local user config as source of truth. Preserve existing local behavior unless you can prove a harness change can be added safely.

Selected install direction: {{MODE}}.

Required first step: compute your own complete comparison of both files. Do not rely on this prompt as an exhaustive conflict summary. Parse the file format when possible and identify all changed keys/tables/arrays/sections before editing.

Merge instructions:
- Keep user-specific MCP servers, model preferences, permissions, hooks, profiles, trusted projects, plugin settings, and local state by default.
- Add harness defaults only when additive or clearly non-conflicting.
- If both sides set the same scalar, table, hook, permission, plugin, profile, project, or MCP/server entry differently, flag it as a conflict instead of guessing.
- Do not replace the local config with the harness config.
- Do not delete local config entries unless the user explicitly approves that exact deletion.
- Report the final changed file and any conflicts left unresolved.
Harness: {{HARNESS}}
