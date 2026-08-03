# SWIFTBAR-ACTIVE-SOURCE-02 — fix round 1 (critic BLOCK; fix exactly these)

Target: the existing working-tree diff in THIS worktree (leadv2-status-surface.sh census block ~2609-2766, leadv2-status-surface.10s.sh, tests/test-status-surface-single-lead.sh). Keep everything the critic verified correct (single ps pass, POSIX .10s, untouched other blocks, real-wrapper tests).

1. CRITICAL — reservation state filter missing: only rows with state pending|confirmed count as active (mission 1b). Real writer values are ONLY "pending"/"confirmed" (leadv2-dispatch-code.sh _dispatch_append_pending_locked / dispatch_confirm). Fix the code AND the fixtures — tests currently use "state":"running" which never exists in prod; change fixtures to pending/confirmed and add one case with a bogus-state row that must NOT count.

2. CRITICAL — GLM/Kimi census rows never carry sig8 → double-count vs their own reservation + "closing" unreachable. The sig8 is ALREADY IN the run-id in argv: glm-runs/YYMMDD-HHMMSS-<sig8>-<rand>. Change patterns 2/3 to capture it: glm-runs/\d{6}-\d{6}-([a-f0-9]{8})- (same for kimi-runs). Use that sig8 as the census key so (a) the reservation dedup loop recognizes the lane (menubar count correct — one entry per task), (b) has_terminal works → "closing" reachable for glm/kimi.

3. CRITICAL+HIGH — codex census pattern matches nothing real (runner argv is `codex exec ... -C <shared-root>`, no worktree ref). Replace pattern 4: enumerate $PROJECT_ROOT/docs/handoff/*/.session-runner.pid files, pid alive (python os.kill(pid,0) — no subprocess spawns) → active codex lane with task_id = the handoff dir name; correlate to reservations by task_id/sig8 where possible. Drop the dead argv pattern.

4. MEDIUM — test (c): with dedup fixed, pin the assertion to ONE exact expected count (craft the fixture so the expectation is unambiguous: 2 live workers whose sigs match their own reservations + 1 unrelated pending reservation-only lane = exactly 3 entries, count asserted as 3 — reservation-only lanes ARE shown as spawned-but-not-yet-visible). No ranges in assertions.

5. Fix test (d) to actually cover "closing" for a NON-sonnet arm: PS stub = a real glm-shaped argv (glm-runs run-id containing the sig8) + terminal row for that sig8 → expect "closing".

6. LOW — derive "glm-runs"/"kimi-runs" path segments from $GLM_RUNS_DIR/$KIMI_RUNS_DIR basenames when set (default unchanged).

ACCEPTANCE: bash -n (bash5 + /bin/bash 3.2); tests/test-status-surface-single-lead.sh green with corrected fixtures; run-core-offline.sh green vs baseline; live probe: run the .10s surface while a process matching the glm shape exists (spawn a sleep stub with the exact argv if no real one) → ONE entry with sig8, not two. Report per-finding status. Do NOT commit.
