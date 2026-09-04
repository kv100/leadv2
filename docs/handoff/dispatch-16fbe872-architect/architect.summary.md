verdict: REVISE
next_action: continue

Two mission premises refuted; design rebuilt on what the CLI actually honors.

- Task 1 is a no-op: 8d00999 + 747c1ad already ancestors of main (b5ea9f8). No cherry-pick.
- `CLAUDE_CODE_CREDENTIALS_SERVICE`: 0 occurrences in claude 2.1.245 — exporting it is a no-op. Only `CLAUDE_CONFIG_DIR` pins a profile.
- Real fix: thread `cred=` through, export `LEADV2_ANTHROPIC_ACTIVE_SERVICE`, add config_dir↔credential mismatch guard.

Full: full.md
