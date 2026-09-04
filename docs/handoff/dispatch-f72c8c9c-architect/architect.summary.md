verdict: APPROVE
next_action: continue

Trace design closed: 10 spans, 9 files, 3 new files; EXIT-trap chaining is mandatory.

- `leadv2-dispatch-code.sh` has 96 `exit`s plus `trap cleanup_pending_dispatch EXIT:2494` — a naive trap clobbers it and leaks phantom lanes.
- No fork-free monotonic clock on darwin; perl CLOCK_MONOTONIC ~9ms/read, measured.
- `backlog-pump`/`codex-task` arm traps at runtime → explicit begin/end only.

Full: architect.full.md
