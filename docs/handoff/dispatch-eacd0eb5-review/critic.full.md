# Adversarial review — SUPERVISOR-DELETE-01, commit 9451c0f

Worktree: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/eacd0eb5`
Base: `b9959aa` · Diff hash: `16b2dc89ed7981e6d4dcc6e0c197b3b28835ecefbdbecb0c97abec3454ac3e71`
Reviewed 2026-08-20. repowise not used (per mission). All findings below were
produced by reading the diff and running the probes named inline.

**Verdict: PASS_WITH_NITS.** Every enumerated item of the binding mission spec
(r1 rename + caller migration, r2 deletes, rename of resume, suite deletion +
coverage transplant, SUITE_DEFS, stubs) is done and green. What is left is
residue the task's *mandate* ("anything reachable only from the supervise loop
is dead code — migrate or delete") targets but the spec's write-set did not
enumerate: one live path back into the retired mode (H1, pre-existing, not a
regression) and three now-broken orphan test files (H2, caused by this commit).
Neither breaks the gate; both should be swept before this is called finished.

---

## Mission item 1 — dead readers left behind

### H1 (High) — the retired supervisor mode is still *enterable*, and the guard fleet that wedges a session is still registered

`leadv2-lanes-snapshot.sh` kept the entire `.supervise-active` sentinel-write
block verbatim from the old `leadv2-supervise.sh` (`:85-230`). Its own comment
still describes the behavior in the present tense:

> `leadv2-lanes-snapshot.sh:94-97` — "`--enter` (explicit opt-in) and the
> `LEADV2_SUPERVISE_ENTER=1` env override force a write … A bare invocation
> (interactive attach) carries none of these flags and keeps writing — **that
> path is the unchanged supervisor entry point.**"

So a *bare* `bash leadv2-lanes-snapshot.sh` (no `--json`, no `--since`, no
`--print`) still stamps `.supervise-active` with the caller's durable claude
pid. That sentinel is the live trigger for a hook fleet that this commit did
not touch and that is still registered in `plugins/leadv2/hooks/hooks.json`:

| Hook | hooks.json | Effect while sentinel is live and pid-matched |
|---|---|---|
| `leadv2-supervisor-guard.sh` | `:306`, `:362`, `:411` (3× PreToolUse) | **hard-denies** `Edit`/`Write`/`NotebookEdit` on any `.py .sh .ts .tsx .sql` or `/migrations/` path, plus Bash `git commit`, `git push`, `sed -i` on code, `>> *.sh` (`leadv2-supervisor-guard.sh:98-110, :182-190`) |
| `leadv2-supervise-fanout-guard.sh` | `:268` | Agent-spawn gate |
| `leadv2-supervisor-pump-caller.sh` | `:128` | active only for the sentinel-owning session |
| `leadv2-supervise-sentinel-cleanup.sh` | `:608` | Stop-hook cleanup |

Net: one un-flagged invocation of the *renamed, kept, live* reconciliation
script silently puts the calling session into a code-write lockout for a mode
the founder retired. This is the same shape as the recorded past failure
"stale supervisor markers block workers".

This is **pre-existing behavior, not introduced by 9451c0f** — the old
`supervise.sh` did exactly this. But the mandate is migrate-or-delete, and the
sentinel-write survived the deletion by riding along inside the renamed script.
Fix is small: drop the `PYSENTINEL` write block and the `--enter` /
`LEADV2_SUPERVISE_ENTER` flags from `leadv2-lanes-snapshot.sh`, then unregister
the four hooks above (or make each exit 0 unconditionally).

Related, lower: `hooks/leadv2-supervisor-mode-reinject.sh:155` still reinjects
a prompt naming `leadv2-supervise.sh` — a script that no longer exists — as an
allowed command. Confirmed **not registered** in `hooks.json` (grep for
`mode-reinject` returns nothing), so it is inert; it is a dead file, not a live
lie. Delete it with the rest.

### H2 (High) — three test files now reference deleted/renamed scripts and cannot run

| File | Broken reference | Was it in SUITE_DEFS at `b9959aa`? |
|---|---|---|
| `plugins/leadv2/scripts/tests/test-question-delivery-01.sh:11-12` | `leadv2-supervise-loop.sh` (**deleted**), `leadv2-supervise.sh` (renamed) | No |
| `plugins/leadv2/tests/test-supervise-sentinel-readonly.sh:10` | `../scripts/leadv2-supervise.sh` (renamed) | No |
| `plugins/leadv2/tests/test-supervise-stale-truth.sh:20` | `leadv2-supervise.sh` (renamed) | No |

None was on the core gate before or after, and there is no glob-runner over the
tests directories (verified: no `for … tests/*`, no `find … -name 'test-*'` in
`plugins/` or `scripts/`), so **the gate does not regress**. But
`test-question-delivery-01.sh` launches the deleted loop with
`bash "$LOOP" &` and then `wait "$LOOP_PID" || fail "supervisor loop failed"` —
it is now a guaranteed red if anyone ever runs it. They are dead readers of the
kind this task exists to kill: `git rm` them (question-delivery ownership is
still covered by `test-question-delivery-ownership-01.sh`, which **is** in
SUITE_DEFS).

Note the coupling to H1: `test-supervise-sentinel-readonly.sh` was the
regression guard for SENTINEL-ON-PROBE-01 ("read-only probes must never stamp
`.supervise-active`"). With H1 unfixed and this test unrunnable, that contract
is now both live and untested. Whichever way H1 is resolved, this test should
be retargeted or deliberately retired, not left broken.

### M1 (Medium) — `.supervise-loop.heartbeat` now has zero writers; `leadv2-status-surface.sh`'s S3 block is a permanently-dead reader

`git show 9451c0f^:…/leadv2-supervise-loop.sh:141,341,810` and
`leadv2-supervise-watchdog.sh:48` were the only writers of
`.supervise-loop.heartbeat`; both are deleted here. Confirmed by grep over
`plugins/**/*.sh` excluding `tests/`: after this commit the file has **read-only
references and no writer at all**.

`leadv2-status-surface.sh` still stats it at `:20, :258, :300-317, :342-347`,
still computes `SUP_BEAT`/`SUP_BEAT_AGE_SECS`/`SUP_STATE`, and still renders
it at `:1851-1854` (`sup:OFF(no beat)` in the statusline head) and
`:1876-1879` (`supervisor: OFF (no supervise loop running)`).

Degradation is graceful and the rendered value is *true* (the supervisor really
is off, forever), so this is not a lying-green. It is ~200 lines of dead
liveness arithmetic plus a founder-facing field that can now only ever print
one value. Classify: **dead reader, harmless output, delete on the sweep.** The
same applies to `test-status-surface.sh`'s ~10 fabricated heartbeat fixtures
(`:268-1095`).

### Classified as harmless fallbacks (no action needed)

- `leadv2-pulse-beat.sh:53` + `hooks/leadv2-supervisor-pump-caller.sh:86` read
  `.supervise-loop.json` to no-op when the loop owns the beat. With the loop
  gone the sentinel is never written, `_loop_is_live()` is permanently false,
  and both fail **open** — the single-lead beat/pump always drives. Correct
  post-retirement behavior. The pump-caller's comment was honestly updated to
  say so (`:76-84`, "permanently a no-op").
- `supervise-loop.log` is still written on the single-lead path by
  `leadv2-pulse-beat.sh:41-43` and `hooks/leadv2-single-lead-beat.sh:83-84`;
  read by `leadv2-broad-status.sh:33`, `leadv2-writes-overlap.sh:148-150`,
  `leadv2-status-surface.sh:2568`. Live, not dead — only the filename is a
  legacy carry-over. Renaming it is cosmetic and would need a migration; not
  worth it now.
- Prose-only mentions of `leadv2-supervise.sh` in session-runner anti-recursion
  prompts (`leadv2-{codex,glm,kimi}-session-runner.sh`) and in
  `codex-skills/source-command-leadv2/SKILL.md:15` are "never invoke a
  launcher" ban-lists. Naming a script that no longer exists is harmless there
  (the ban is a superset), though tidying them is free.

---

## Mission item 2 — was the `supervise-resume.sh` rename smuggling dead code? **No.**

`leadv2-lanes-resume.sh` has live single-lead callers inside the *kept*
reconciliation script:

- `leadv2-lanes-snapshot.sh:138` — `RESUME_SH="${SCRIPT_DIR}/leadv2-lanes-resume.sh"`
- `leadv2-lanes-snapshot.sh:1395` — `resume_script = os.path.join(script_dir, "leadv2-lanes-resume.sh")`
- `leadv2-lanes-snapshot.sh:40, :1463` — contract comments for the same path

`leadv2-lanes-snapshot.sh` itself is called on the live path by
`leadv2-status-collector.sh:118` (`--json`, lanes section). So resume is
reachable from single-lead status, not only from the deleted loop. Rename
justified. **PASS.**

### L1 (Low) — stale `[supervise-resume]` label in the renamed script

`leadv2-lanes-resume.sh:52` still prints `[supervise-resume] unknown arg: %s`.
Cosmetic; the surrounding usage strings were updated.

### L2 (Low) — `leadv2-lanes-snapshot.sh` self-identifies by its old name

`:2`, `:35`, `:78` still say `leadv2-supervise.sh`, including the **user-facing
`--help` usage line** (`:78`). A founder who runs `--help` is told to invoke a
script that no longer exists.

---

## Mission item 3 — coverage transplant

Compared `git show 9451c0f^:…/test-supervise-v2.sh` against
`test-lanes-snapshot.sh` (rename similarity 69%).

Survived, retargeted onto `leadv2-lanes-snapshot.sh`:

| Case | Old | New | Covers |
|---|---|---|---|
| Test 3a/3b | `:223-289` | `:121-185` | **adoption** triple-proof (name-only → orphan; name+task-id+live-pid → adopt) |
| Test 4a/4b | `:289-364` | `:187-260` | **tombstone-before-prune** + `observe_only` `would_prune` visibility |
| Test 5 | `:364-404` | `:262-300` | truth-probe timeout → unavailable, process-group kill |
| Test 7a/b/c | `:404-556` | `:302-452` | AND-condition death matrix |
| Test 8 | `:556-615` | `:454-511` | tombstone write failure → row kept |
| Test 9 | `:615-670` | `:513-568` | DEAD event dedup |
| Test 12a/12b | (old ≥670) | `:570-668` | pid:null funnel row survives prune; `PRUNE_V2=0` rollback |
| Test 6 | — | `:107-119` | new: `bash -n` over the 3 surviving reconciliation scripts |

Dropped, correctly: **Test 1** (loop cadence/ceiling — tested
`leadv2-supervise-loop.sh`, deleted) and **Test 2** (pick-script ranking JSON
schema — tested `leadv2-supervise-pick.sh`, deleted). No adoption, prune, or
tombstone case was lost.

Symlinked fake-claude trick **survives**: `ln -sf "$(command -v sleep)" "$repo/claude"`
moved from old `:272` to new `:170` — still `ln -sf`, not `cp`. **PASS.**

---

## Mission item 4 — SUITE_DEFS + live suite run

`run-core-offline.sh` diff:

- Removed: `"supervisor fail-closed|||… test-supervise-failclosed.sh"`,
  `"supervisor reconciliation|||… test-supervise-v2.sh"`,
  `"supervisor/lead PID isolation|||… tests/test-supervise-fanout-guard.sh"` — all 3 gone.
- Added: `"lanes snapshot reconciliation|||bash $TEST_DIR/test-lanes-snapshot.sh"` (`:190`).
- `_CORE_OFFLINE_OWNED_SUITES:93` renamed `"supervisor reconciliation"` →
  `"lanes snapshot reconciliation"`, keeping the ownership row consistent with
  the new suite name (this is the bit a careless rename usually drops).

Run in the worktree:

```
$ bash plugins/leadv2/scripts/tests/test-lanes-snapshot.sh
[TEST] === Results: PASS=13 FAIL=0 ===
[exited with code 0]
```

**PASS.**

---

## Mission item 5 — refuse-stubs

`plugins/leadv2/docs/supervisor-role.md` — reduced 216→~5 lines, states
retirement + names `leadv2-lanes-snapshot.sh` as the successor. Adequate.

`plugins/leadv2/skills/leadv2-supervise/SKILL.md` — 251 lines → stub. The
frontmatter `description` itself carries the refusal (`"[internal] Retired
2026-08-19 (founder order, SUPERVISOR-DELETE-01). Refuse to run this mode."`)
and `allowed-tools` is narrowed to `Read` alone, so the skill *cannot* act even
if loaded. Body instructs: "If invoked, refuse to run it and point the founder
at `scripts/leadv2-lanes-snapshot.sh`". This **refuses**, it does not silently
no-op. **PASS.**

`plugins/leadv2/commands/leadv2.md:72` — the `/leadv2 supervise` table row is
replaced with a retirement notice pointing at the snapshot script.

### L3 (Low) — retirement date is inconsistent

The commit message and `CLAUDE.md` say the founder order is **2026-08-17**; the
stubs (`supervisor-role.md`, `SKILL.md`, `leadv2.md:72`) all say **2026-08-19**;
`leadv2-plugin-sync.sh:519` and `leadv2-status-collector.sh:104` say
**2026-08-20**. Three dates for one decision. Pick the founder-order date
(2026-08-17) for the *decision* and leave the implementation date where it
describes the code change.

### L4 (Low) — `leadv2.md` still documents `/leadv2 fanout`

The `fanout` row (`:73`) is untouched and still live, while
`leadv2-fanout.sh` was the supervisor's dispatch arm. This is arguably in
scope of "supervisor retired" but was explicitly outside the mission spec —
flagging only so it is a decision, not an oversight. The repo CLAUDE.md says
"Do not invoke `/leadv2 supervise` / `leadv2-fanout.sh` without a founder
order", i.e. fanout is *restricted*, not deleted. Leaving it is defensible.

---

## Mission item 6 — `bash -n`

Ran `bash -n` over every `.sh` in the commit's name-only list that still exists
in the tree. **Zero syntax errors.** (`run-core-offline.sh`'s own `syntax_all`
suite covers this on the gate as well.)

---

## Summary table

| # | Sev | Finding |
|---|---|---|
| H1 | High | Retired supervisor mode is still enterable: bare `leadv2-lanes-snapshot.sh` writes `.supervise-active`, which arms 4 still-registered hooks incl. a session-wide code-write/`git commit` lockout. Pre-existing, but squarely inside the migrate-or-delete mandate. |
| H2 | High | 3 test files now reference deleted/renamed scripts and cannot run (`test-question-delivery-01.sh`, `test-supervise-sentinel-readonly.sh`, `test-supervise-stale-truth.sh`). Not on the gate → no regression, but dead readers. |
| M1 | Med | `.supervise-loop.heartbeat` has zero writers post-commit; `leadv2-status-surface.sh` S3 block (~200 lines) + the `supervisor: OFF` field are permanently dead. Output is truthful, so harmless — sweep it. |
| L1 | Low | `leadv2-lanes-resume.sh:52` still prints `[supervise-resume]`. |
| L2 | Low | `leadv2-lanes-snapshot.sh:2,35,78` self-identify as `leadv2-supervise.sh`, incl. the user-facing `--help` usage line. |
| L3 | Low | Retirement date stated three ways (08-17 / 08-19 / 08-20). |
| L4 | Low | `/leadv2 fanout` left documented and live — confirm this is intentional. |
