Compare local live config at:
  {{HOME_PATH}}

With repo baseline at:
  {{DST}}

Default stance: keep the repo baseline as source of truth unless you can prove a local live change should be promoted.

Required first step: compute your own complete comparison of both paths. Do not rely on this prompt as an exhaustive conflict summary. For directories, inspect the full recursive file list and content diffs. For structured files, parse the format when possible and identify all changed keys/tables/arrays/sections before editing.

Merge instructions:
- Keep repo-managed defaults by default.
- Promote local live changes only when they are intentional and do not conflict with harness defaults.
- Preserve user-specific MCP servers, model preferences, permissions, hooks, profiles, trusted projects, plugin settings, and local state unless they directly conflict with harness requirements.
- If both sides set the same scalar, table, hook, permission, plugin, profile, project, rule, command, skill, or MCP/server entry differently, flag it as a conflict instead of guessing.
- Do not blindly overwrite either side.
- Report the final changed file/path and any conflicts left unresolved.
