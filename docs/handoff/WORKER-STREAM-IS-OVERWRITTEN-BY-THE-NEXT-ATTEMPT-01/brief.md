# WORKER-STREAM-IS-OVERWRITTEN-BY-THE-NEXT-ATTEMPT-01 — attempt-scope the worker stream path

LANE_WRITES: plugins/leadv2/scripts/claude-subsession.sh,plugins/leadv2/scripts/leadv2-budget-check.sh,plugins/leadv2/scripts/tests/test-stream-attempt-isolation.sh,tests/run-all.sh,docs/handoff/WORKER-STREAM-IS-OVERWRITTEN-BY-THE-NEXT-ATTEMPT-01/

Read-only reference (do NOT edit): `plugins/leadv2/scripts/leadv2-dispatch-code.sh` — held by another
session. Every design decision below is chosen specifically so this lane needs **zero** edits to it.

## 0. The defect (given, not re-derived)

A lane's stream file is keyed by the dispatch **signature** (a content hash of the mission text),
not by the **attempt**. Re-dispatching the same lane reuses the same signature, hence the same
directory, hence the same filename, and the second `claude` process's stdout redirect truncates
the first attempt's transcript. Measured 2026-09-03: 463 lines/923,548 bytes/0 result events →
449 lines/671,008 bytes/1 result event on one lane. Consequence already lived once: five workers
believed dead, four re-dispatches, four of five streams destroyed before the investigation could
read them.

## 1. Root cause chain (file:line, verified against the live tree)

| # | File:line | What happens |
|---|---|---|
| 1 | `plugins/leadv2/scripts/leadv2-dispatch-code.sh:2016` `compute_sig()` | `sha256sum` of the **normalized mission text** (whitespace-collapsed, CR-stripped). Deterministic by design — comment: "two missions that differ only in indentation... collapse to the same sig (one task = one model)". This determinism is *correct* for its actual job (duplicate-dispatch dedup, `_dispatch_sig_blocked`) and *wrong* when reused as a filesystem key. |
| 2 | `leadv2-dispatch-code.sh:3303` | `sig8="${sig:0:8}"` |
| 3 | `leadv2-dispatch-code.sh:~5502` (sonnet arm) | `bash "$SUBSESSION_BIN" --task-id "dispatch-${sig8}" ...` |
| 4 | `plugins/leadv2/scripts/claude-subsession.sh:193` | `HANDOFF_DIR="$PROJECT_ROOT/docs/handoff/$TASK_ID"` |
| 5 | `claude-subsession.sh:421` | `STREAM_OUT="$HANDOFF_DIR/${ROLE}.stream.jsonl"` — **no attempt component anywhere in this path.** |
| 6 | `claude-subsession.sh:568` (`--wait` path) and `:1239` (detached/setsid path — the one `leadv2-dispatch-code.sh`'s sonnet arm actually uses) | `claude "${CLAUDE_ARGS[@]}" > "$STREAM_OUT" 2>&1` — **truncating** redirect. This is the actual overwrite mechanism. |

A sibling artifact has the identical disease and should be fixed in the same edit:
`claude-subsession.sh:1252` `MARKER_FILE="$HANDOFF_DIR/${ROLE}.cost-pending.yaml"` — a second
attempt overwrites the first attempt's pending-cost marker before `leadv2-cost-flush.sh` can
process it, silently losing that attempt's cost record. Same file, same root cause, near-zero
marginal cost to fix alongside — see §4 Do-list.

**Existing precedent for the fix**: `leadv2-dispatch-code.sh:614-621` already defines
`_dl_attempt_token() { printf '%s-%s-%s' "$sig8" "$ATTEMPT_EPOCH" "$$"; }`, used by the terminal
ledger (`_dl_note` / `leadv2-dispatch-ledger.sh`) for exactly "this specific attempt, not the
lane." It was never applied to the stream path. The naming decision below reuses this shape.

## 2. Census — writers, path-builders, readers (measured)

**Writers of stream content: 1.** `claude-subsession.sh` (the sole process that opens/redirects
into `STREAM_OUT`). `leadv2-fanout.sh` and `leadv2-fanout-lane-launcher.sh` never write content —
verified by reading both call sites (`leadv2-fanout.sh:1921`, `leadv2-fanout-lane-launcher.sh:442`):
both re-parse `sig8` out of `dispatch-code.sh`'s own stdout (`task=<sig8>`) and reconstruct the
identical path string purely to stamp it into `active.yaml` as `log_path`. Three independent
call sites reconstruct the same formula by hand — a drift risk noted in §5, not fixed here (no
shared resolver exists to change without touching the locked file).

**Readers/consumers, 14 files, with what each needs:**

| File | What it does with the stream | Needs |
|---|---|---|
| `leadv2-lane-liveness.sh` (:336 `WORKER_STREAM_NAMES`, :712-821, :1034) | Liveness verdict (alive/silent/dead) from mtime+content | **Newest** attempt |
| `lib/leadv2-worker-reason.sh` (:16-218) | Terminal reason/result, last `{"type":"result"}` | **Newest** attempt |
| `leadv2-dispatch-product-close.sh` (:555-582, :1591-1904, :2633, :3280, :3335) | Close-time silent-worker + review-body verdicts | **Newest** attempt |
| `leadv2-review-run.sh` (:224-250; :1142 comment already flags this exact shared-key trap) | Review body extraction from `critic.stream.jsonl` | **Newest** attempt |
| `leadv2-cache-truth.sh` (:17-133, literal name check at :94) | Cache-hit-rate truth for one run | **Newest**, or an explicit run-dir arg |
| `leadv2-cost-flush.sh` (:53-128) | Cost recompute from the path recorded in a spawn-time marker | **The specific attempt** the marker was written for |
| `leadv2-budget-check.sh` (:109-130, `os.listdir`+`endswith('.stream.jsonl')`, non-recursive) | Fallback token sum | **All** attempts (currently silently sees only the survivor) |
| `leadv2-broad-status.sh` (:675-719) | Pulse row "пишет сейчас (N байт)" | **Newest** attempt |
| `leadv2-lanes-snapshot.sh` (:424-459, `glob.glob(hdir/"*.stream.jsonl")`, non-recursive) | Freshness/bytes for the snapshot | **Newest** attempt |
| `leadv2-lane-detail.sh` (:271 `stat_stream`, :389-390; :111 "HARD RULE 1: never read `*.stream.jsonl` content here") | `os.stat()` on `log_path` for bytes/age only, never content | **Newest** attempt |
| `leadv2-dispatch-ledger.sh` (:719-727) | Ties ledger rows (already attempt-tokened via `_dl_attempt_token`) to file existence | Ideally **the matching attempt**; today only ever sees the sig8-keyed survivor |
| `leadv2-context-diet-probe.sh` (:58-109) | Ad-hoc token-usage diagnostic | Whichever attempt is being probed (usually newest) |
| `leadv2-lane-heartbeat.sh` (:6) / `leadv2-lane-watch.sh` (:104-183) | mtime-based heartbeat | **Newest** attempt |
| `leadv2-active-registry.sh` (:698-699, :950-952) | Stamps `log_path` into `active.yaml`, re-stamped on every attempt already | Whatever value it's given — no change needed to its own logic |

`leadv2-lane-watch-v2.sh:219,269-270` explicitly documents it does **not** depend on
`*.stream.jsonl` (uses `.stream_state` and other runner-written dotfiles instead) — already immune,
out of scope.

## 3. The naming decision

**Chosen shape:**
```
docs/handoff/dispatch-<sig8>/attempts/<epoch>-<pid>/<role>.stream.jsonl   # real, immutable per attempt
docs/handoff/dispatch-<sig8>/<role>.stream.jsonl                          # pointer: symlink -> latest attempt's real file
docs/handoff/dispatch-<sig8>/<role>.cost-pending.<epoch>-<pid>.yaml       # companion: same fix, cost marker
```
`<epoch>-<pid>` mirrors the existing `_dl_attempt_token()` shape (minus the redundant `sig8`,
already the parent directory) — greppable alongside the ledger's own attempt tokens, not an
invented convention.

The pointer is repointed **atomically** on every attempt, first or not, via `ln -s ... tmp-name &&
mv -f tmp-name <role>.stream.jsonl` (same-filesystem `mv` is an atomic rename; a bare `ln -sfn`
over an existing name is unlink-then-link on some platforms and is not). Repoint happens
immediately when the attempt starts (before any content is written) — a fresh, empty target under
a "starting:Ns" liveness verdict is already a modeled state (`leadv2-lane-liveness.sh` has this
verdict shape today); it must never lag and point at the previous, now-finished attempt while a
new one is live.

**Options considered and rejected:**

| Option | Readers it breaks | Why rejected |
|---|---|---|
| (a) Attempt counter in the flat filename, no pointer (`developer.attempt2.stream.jsonl`) | Every **hardcoded-literal** reader: `leadv2-dispatch-code.sh` itself (:3113, :5555, :7106 — locked, cannot be edited to look elsewhere), `leadv2-lane-liveness.sh`'s `WORKER_STREAM_NAMES` tuple, `leadv2-cache-truth.sh:94`, `leadv2-dispatch-product-close.sh:1614,1903`, `lib/leadv2-worker-reason.sh:74` | These never look for `developer.attempt2.stream.jsonl`; every one of them goes blind on the second attempt. Since the worst-hit reader (`dispatch-code.sh`) is the one file we are forbidden to edit, this option is not viable at all. |
| (b) Flat numbered file **plus** a flat pointer in the same directory | None directly — but `leadv2-budget-check.sh`, `leadv2-lanes-snapshot.sh`, `lib/leadv2-worker-reason.sh`'s glob (`*.stream.jsonl`, non-recursive) would match **both** the numbered real file and the pointer that aliases it, double-counting/double-processing the latest attempt | Silent double-count in a token-cost aggregator is a correctness regression, not an improvement |
| (c) **Chosen**: per-attempt subdirectory + top-level pointer | None. Verified: `os.stat`/`open`/`os.path.exists` all follow symlinks (confirmed by reading `stat_stream()` in `leadv2-lane-detail.sh` — plain `os.stat`), and the three non-recursive top-level globs (`leadv2-budget-check.sh`, `leadv2-lanes-snapshot.sh`, `lib/leadv2-worker-reason.sh:198`) see exactly one `*.stream.jsonl` match at the top level — the pointer — identical cardinality to today. No `find -type f` pattern exists anywhere in the scripts tree (checked) that would exclude a symlink. | Every existing reader, including the three inside the locked file, keeps working unmodified. |

**The one reader that must change on purpose, not by accident:** `leadv2-budget-check.sh`'s
fallback token sum (§2) still only sees the top-level pointer (one file) under option (c) — same
as today, i.e. still undercounts history. Widen it explicitly to also walk
`attempts/*/*.stream.jsonl` and exclude symlinks from the walk (`os.path.islink`) to avoid
double-counting the pointer against its own target. This is the only reader in the "needs all"
row of §2 whose fix is mandatory for this lane to be a complete answer to the defect, and it is
not in the locked file.

`leadv2-cost-flush.sh` needs no code change: it reads the exact path recorded in `MARKER_FILE` at
spawn time, which after the fix is already the real per-attempt path — it becomes *more* correct
as a side effect, not less.

## 4. Do / Don't

**Do (in `claude-subsession.sh`, not locked):**
1. New function computing the attempt id, e.g. `_lv2_attempt_id() { printf '%s-%s' "$(date +%s)" "$$"; }`.
2. New function performing the atomic pointer repoint (symlink-to-tmp + `mv -f`), called unconditionally on every attempt (first included).
3. Route `STREAM_OUT` through `HANDOFF_DIR/attempts/<attempt-id>/${ROLE}.stream.jsonl`; `mkdir -p` that subdirectory before use.
4. Apply the same attempt-id to `MARKER_FILE` (§1 sibling defect).

**Do (in `leadv2-budget-check.sh`, not locked):** widen the fallback sum per §3.

**Do NOT touch:** `leadv2-dispatch-code.sh` (locked by another session — every one of its own
literal/glob reads of `developer.stream.jsonl`/`architect.stream.jsonl` keeps working unmodified
under option (c), verified in §3). If any future finding requires an edit there, stop and escalate
— do not route around it by duplicating its logic elsewhere.

**Verified unaffected, do not edit (symlink-transparent or non-recursive-glob-transparent, per §2/§3):**
`leadv2-lane-liveness.sh`, `lib/leadv2-worker-reason.sh`, `leadv2-dispatch-product-close.sh`,
`leadv2-review-run.sh`, `leadv2-cache-truth.sh`, `leadv2-active-registry.sh`, `leadv2-fanout.sh`,
`leadv2-fanout-lane-launcher.sh`, `leadv2-broad-status.sh`, `leadv2-lanes-snapshot.sh`,
`leadv2-lane-detail.sh`, `leadv2-dispatch-ledger.sh`, `leadv2-context-diet-probe.sh`,
`leadv2-lane-heartbeat.sh`, `leadv2-lane-watch.sh`, `leadv2-cost-flush.sh`.

## 5. Retention

**No retention mechanism currently exists** — checked (`grep` across `plugins/leadv2/scripts` for
mtime-based pruning of `docs/handoff/`: zero hits). Today 830 `dispatch-*` dirs exist on disk,
397 still carry a survivor stream (measured). This lane does not need to ship a pruner — it needs
to not make the eventual one dangerous. Specify, don't build:

- **Keep**: every attempt directory of every dispatch dir whose task has **no confirmed terminal
  verdict** in `leadv2-dispatch-ledger.sh` (state ∉ {landed, dead, refused}) — unconditionally,
  regardless of age.
- **Prune candidate**: attempts beyond the most recent N (propose N=3) inside a dispatch dir
  **only after** its task is terminal **and** a grace window (propose 14 days) has passed since
  the terminal state landed.
- **Named failure mode** (the one the task asked for by name): a rule keyed on mtime-age alone is
  exactly wrong here, because investigation timing is anti-correlated with freshness — nobody
  opens an investigation into a stream that changed 10 minutes ago. "Delete anything untouched for
  7 days" would delete a silent/dead lane's evidence at precisely the moment someone goes looking
  for why it went silent — this is the 2026-09-03 incident again, wearing a retention hat instead
  of a re-dispatch hat. Any future pruner must key on **terminal ledger state**, never on mtime
  alone, and must cross-check `active.yaml` before deleting anything a currently-registered live
  lane's `log_path` still resolves through.

## 6. Backfill

69 `developer.full.md` reports and 397 surviving `*.stream.jsonl` files exist today under the old,
flat, non-attempt-scoped shape (measured). **Decision: leave in place, do not migrate, no special
indexing.** Reasoning: every reader audited in §2/§3 treats "regular file at `<role>.stream.jsonl`"
and "symlink at `<role>.stream.jsonl`" identically — none of them calls `os.path.islink()` or
otherwise distinguishes the two. An old-shape dispatch dir's flat file continues to satisfy every
one of those readers unmodified, forever; there is nothing to gain and real churn-risk to lose by
moving 830 directories into the new shape for content that, for the ones missing a survivor, no
longer exists to move. **What a future reader does on an old-shape path**: add one code comment at
the point the new attempt-id/pointer logic lands in `claude-subsession.sh`, stating plainly — *"a
dispatch dir with no `attempts/` subdirectory predates attempt-scoping; if `<role>.stream.jsonl`
exists there it is definitionally the last (and only recoverable) attempt for that lane."* That
sentence is the entire backfill: it stops a future investigator from assuming a missing
`attempts/` dir is itself a bug.

## 7. Negative controls

Per repo standard: count changed function bodies, not lanes. This lane changes **4 function
bodies** — 4 named mutations, plus the 1 mandatory end-to-end control below (5 controls total).
Run every one through `plugins/leadv2/scripts/leadv2-mutation-control.sh <suite> <file>
<sed-or-patch> [task_dir]`, which requires `baseline_rc=0` (suite green pre-mutation) and
`mutated_rc=1` (suite red post-mutation) — exit code 0 from the tool itself means both held.

| # | Function (file) | Mutation | Assertion it must break |
|---|---|---|---|
| 1 | `_lv2_attempt_id()` (`claude-subsession.sh`) | Return a constant string instead of `<epoch>-<pid>` | Unit check: two calls in the same test process return equal values → collision restored |
| 2 | Pointer-repoint function (`claude-subsession.sh`) | No-op the repoint call | Pointer after a 2nd attempt still resolves (`readlink`) to attempt #1's real file, not #2's |
| 3 | `MARKER_FILE` attempt-scoping (`claude-subsession.sh`) | Revert to flat `${ROLE}.cost-pending.yaml` | Two dispatches produce 1 marker file, not 2 |
| 4 | Fallback token-sum widen (`leadv2-budget-check.sh`) | Revert to non-recursive `os.listdir(hdir)` only | Summed tokens across a 2-attempt fixture equal only the latest attempt's count, not both |
| **5 (mandatory, named explicitly by the task)** | The integration of #1+#2 | Revert `STREAM_OUT` to the flat pre-fix `$HANDOFF_DIR/${ROLE}.stream.jsonl` (no `attempts/`, no pointer) | **Dispatch the same `--task-id` twice; assert both attempts' real stream files exist AND differ.** This is the whole defect — its absence is why the 2026-09-03 incident went undetected for four re-dispatches. |

**Fixture construction (mandatory control #5), required shape:**
- Fake **only** the `claude` binary (one level below the function under claim), placed first on
  `PATH`: a tiny script that echoes one JSON line embedding its own `$$`/timestamp, so two
  invocations are trivially distinguishable. Do not fake `claude-subsession.sh` itself — its real
  attempt-id, `mkdir`, and pointer-repoint logic must execute for real.
- Invoke `claude-subsession.sh` **with `--wait`** (the synchronous `run_subsession` path,
  `claude-subsession.sh:568`), not the detached/setsid path — determinism over realism here; the
  detached-launch mechanics already have their own coverage (`test-claude-subsession-sentinel.sh`)
  and are not what this control is proving.
- Call it twice with the **identical** `--task-id`. Capture and check the launcher's own exit code
  from each call explicitly (`bash claude-subsession.sh ...; rc=$?; [[ $rc -eq 0 ]] || fail ...`)
  **before** touching the filesystem assertions — do not background the launch inside `( … )` with
  its status discarded. That exact pattern produced a false red in this repo tonight; a fixture
  that cannot tell "the launcher failed" from "the mutation worked" proves nothing either way.
- Assert **filesystem post-state only**, never a return code standing in for it:
  `[[ -f attempts/<id1>/developer.stream.jsonl ]]`, `[[ -f attempts/<id2>/developer.stream.jsonl ]]`,
  `! diff -q <file1> <file2> >/dev/null` (they must differ), `[[ -L developer.stream.jsonl ]]` and
  `readlink` resolves to attempt #2's real path.
- The fixture must verify its own setup: confirm the fake `claude` is actually the one that ran
  (e.g. grep its known marker string out of the produced file) before trusting any assertion built
  on top of it — a setup that silently fell through to a real `claude` binary or produced an empty
  file must fail loudly as a setup error, not as a passed or failed mutation check.

## 8. Suite registration (constraint carried forward)

New suite: `plugins/leadv2/scripts/tests/test-stream-attempt-isolation.sh`. Register in
`tests/run-all.sh`: an `add_suite` line, **and** two `EXTRA_SUITE_MAP` rows (`tests/run-all.sh:134`
block) —
```
claude-subsession.sh:plugins/leadv2/scripts/tests/test-stream-attempt-isolation.sh
leadv2-dispatch-code.sh:plugins/leadv2/scripts/tests/test-stream-attempt-isolation.sh
```
The second row costs nothing today (this lane never touches `leadv2-dispatch-code.sh`) but means
a *future* change to the locked file re-runs this suite via `--scope changed`, since that file is
the one that hands the sig8-keyed task-id to the writer. Prove the registration with a **real**
edit (this lane's actual `claude-subsession.sh` diff satisfies that — `touch` does not, git does
not see it):
```
LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed
```
Nothing goes into `tests/known-red-suites.txt`; no existing assertion is weakened. Never
`reset --hard`/`clean`/`stash` in this shared tree; never prune worktrees.

DELIVERABLE_COMPLETE
