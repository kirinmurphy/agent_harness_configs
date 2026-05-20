# jcodemunch helpers.

jcmwatch() {
  uvx --with "jcodemunch-mcp[watch]" jcodemunch-mcp watch "${1:-$PWD}"
}
