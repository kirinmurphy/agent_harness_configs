## Code Exploration

- Use jcodemunch-mcp for code lookup whenever available.
- Prefer symbol search, outlines, references, and targeted context bundles over reading full files.
- Do not use Bash for grep/find/cat/head/tail-style source exploration when jcodemunch can answer it.
- Use native read/search tools only for non-code files or targeted editing reads.
- At session start, resolve_repo `.`.
- If the repo is not indexed, index_folder `.`.
- After meaningful file edits, re-index changed files before further analysis.

## Doc Exploration

- Use jdocmunch-mcp for documentation lookup whenever available.
- Prefer search_sections, get_toc, get_section over reading full `.md` and `.rst` files.
- At session start, call list_repos to see what docs are already indexed.
- To index local docs, call index_local with the docs folder path.
- After editing doc files, index updates passively via mtime detection.
- For new or deleted doc files, call index_local again.
