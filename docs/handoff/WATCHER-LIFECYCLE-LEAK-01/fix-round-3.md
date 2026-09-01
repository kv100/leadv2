# Fix round 3 — last blocker is a PRE-EXISTING main test breakage, not our regression

State: watcher-lifecycle suite fully green (8/8, negative control RED, 0 residue).
The e2e gate now fails ONLY on run-core-offline.sh →
`test-t13-slice2.sh` case4a: "CLI dispatch table exposes an undocumented subcommand".

Lead verified on CANONICAL MAIN (not the lane): main's leadv2-dispatch-code.sh CLI
exposes `mission-writeset-check` and `close-gate`, and main's test-t13-slice2.sh:390
allowed list does NOT contain them — so this test fails on main too. Our lane never
touched dispatch-code.sh (commits 904cf2d, e6452b0 touch only watcher scripts).

Task:
1. Verify `mission-writeset-check` and `close-gate` are legitimate phased-path
   subcommands, not worker-spawn bypasses: confirm neither reaches spawn_worker
   without a phase record (case4b logic must still hold for them). Cite file:line.
2. If legitimate (expected): add both to the `allowed=(...)` list in
   test-t13-slice2.sh:390 with a one-line comment naming their origin. If either
   actually spawns a worker bypassing phases — STOP and report; do not whitelist.
3. Re-run run-core-offline.sh in the lane: must be fully green.
Do NOT touch the watcher scripts — they are done and green.
