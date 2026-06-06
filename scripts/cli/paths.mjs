// Shared paths for roborepo command modules. repoRoot is derived from this file's location
// (scripts/cli/paths.mjs -> two levels up), so the whole CLI resolves the same harness_configs
// root regardless of cwd. The test suite copies scripts/roborepo.mjs + scripts/cli/ into a
// throwaway root to exercise writes safely.

import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));

export const repoRoot = path.resolve(here, "..", "..");
export const sharedSkillsDir = path.join(repoRoot, "agents", "skills");
