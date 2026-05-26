# jdocmunch helpers.

jdmindex() {
  local target="${1:-$PWD}"
  uvx jdocmunch-mcp index-local --path "$target"
  touch "$target/.jdm-indexed"
}
