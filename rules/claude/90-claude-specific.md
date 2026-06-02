## Claude Specifics

- Claude hooks may block broad `Grep`/`Glob` and nudge toward jcodemunch/jdocmunch. Treat that as redirect, not failure.
- For direct TypeScript compiler runs, prefer `tsc --noEmit --pretty false`.
- Summarize command results instead of pasting long logs.
