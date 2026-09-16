# A-DEGRADED-PROFILE-SELECT-EXITS-ZERO-01

Founder order 2026-09-16 (item 3 of the balancer list). Standing rules:
`docs/handoff/MAIN-RED-SUITES-CENSUS-01/lane-rules.md`.

## Why this row exists

When the live quota read fails, `leadv2-claude-profile-select.sh` stops ranking and falls back to
"run on whatever account is already active" — and it reports that with **exit 0** and
`profile=- reason=single_profile`. The caller cannot distinguish that from a real ranked selection,
so a session can sit on one account indefinitely and nothing in the system says so.

This is the mechanism behind the 2026-09-16 incident: getmany hit the degraded path at 09:33:55Z and
this repo hit it at 09:34:58Z, about a minute apart — machine-wide, not repo-specific. Across 269
profile logs on this machine: 37 fallbacks against 66 live ranked selections.

The asymmetry that makes it invisible: `--requested-profile <label>` on a mismatch is a **hard
refusal** (`NO-WAY-TO-PIN-A-DISPATCH-TO-A-NAMED-ACCOUNT-01`, exit 5), loud and unmissable. The
unpinned degraded path is a silent exit 0. The loud behaviour exists; it just is not on the path
everyone actually uses.

## Measured, with its boundary stated

```
registry: personal + work; every live probe returns {"status":"unknown","accounts":[]}
exit code : 0
stdout    : profile=- reason=single_profile
stderr    : WARN ... identity_email_unresolved ... -- fail-open   (x2, one per label)
```

**Boundary — read this before you build.** The fixture degrades the selector through
`identity_email_unresolved` (no readable `.claude.json`). The live 09:33/09:34 incident degraded
through `degradation=stale_last_known`. Both end at the same silent exit 0, but this probe exercises
**one of at least two entrances**. Your first job is to enumerate the entrances to the fallback and
say how many you found — do not assume it is two. A fix that closes one entrance and leaves the other
open would still pass this probe, which is exactly the failure mode to avoid.

## Acceptance (red at dispatch, rc=1 measured 2026-09-16)

```
bash docs/handoff/A-DEGRADED-PROFILE-SELECT-EXITS-ZERO-01/probe.sh
```

Not in your write set. Do not edit it.

## What the fix must establish

1. A degraded selection is **distinguishable by the caller** from a ranked one. A stderr WARN is not
   enough — the caller already ignores it. Decide between a non-zero exit and a machine-readable
   marker on stdout, and justify the choice against what the callers actually do. Callers to check:
   `claude-subsession.sh` (`:588-600`) and `leadv2-dispatch-code.sh`'s `claude_profile` decision line.
2. Fail-open stays fail-open. This row must NOT make a degraded read block a dispatch — the founder
   has never asked for that, and a balancer that refuses work when a probe is flaky is worse than one
   that runs on the wrong account. Make it *visible*, not *fatal*.
3. Every entrance you enumerated in the boundary section above is covered, or the report names the
   ones that are not and why.
4. The `--requested-profile` hard-refusal path must keep working unchanged; it is the one loud path
   that exists today. `test-claude-profile-requested.sh` guards it — run it before and after.

## Controls

Paired: the probe above red before, green after. Plus one control per independent claim, and
`test-claude-profile-select.sh`, `test-claude-profile-requested.sh`,
`test-profile-select-skips-exhausted.sh`, `nc-claude-profile-select.sh` run with counts reported
before and after.

## Write set — FILES, never directories

```
plugins/leadv2/scripts/leadv2-claude-profile-select.sh
plugins/leadv2/scripts/tests/test-degraded-select-is-distinguishable-01.sh
docs/handoff/A-DEGRADED-PROFILE-SELECT-EXITS-ZERO-01/report.md
```

## Ordering constraint — this lane cannot start while another holds the file

`leadv2-claude-profile-select.sh` is in the declared write set of lane `2af7d13d`
(row `7ea4fed65451`, the account-picker fix). A live lane's write set cannot be widened and a second
lane cannot take the same file. This row waits for that lane to reach terminal. Ledger:
`SD-DEGRADED-SELECT-WAITS-FOR-THE-PICKER-LANE-01`.

## ROUND 2 (lead, 2026-09-16) — the reviewer's High is CORRECT; fix it, do not argue it

Round 1 was blocked by a sonnet review at `critical=0 high=1`, and the lead verified the finding
independently rather than taking the verdict on trust. It stands:

- `DEGRADED_MARKER` resolves to a single machine-wide path
  (`leadv2-claude-profile-select.sh:164`, `${CACHE_BASE}/degraded-select.json`), and the script
  contains **no** lock of any kind — grep for `lock` in it returns only an unrelated comment.
- `plugins/leadv2/scripts/leadv2-portable-lock.sh` exists and is already used by
  `leadv2-dispatch-code.sh`, `leadv2-dispatch-ledger.sh` and `leadv2-event.sh`.
- Up to six lanes run on this machine at once, so two selections overlapping is the normal case,
  not a corner case: a healthy pick clearing the marker between a degraded write and a consumer's
  read silently destroys exactly the signal this row exists to create.

Round 1's base is sound and must not be rewritten: the byte-identical contract held, 152/152 plus
the 4/4 pinned suites passed, shellcheck was clean. Keep that and add to it.

### What round 2 must deliver

1. **Serialize every read and write of the marker through `leadv2-portable-lock.sh`.** Use the
   existing helper the way `leadv2-arm-cooldown.sh` does — do not hand-roll a lock, and do not
   invent a second lock file next to the marker.
2. **A test that fails without the lock.** This is the part that decides the round: spawn two
   concurrent selections, one degraded and one healthy, and assert the degraded marker survives to
   be read. Run it once with the lock removed and show it RED — a concurrency test that has never
   been seen to fail is not evidence of anything.
3. **Cover the six untested reason codes** the reviewer listed: `dependency_missing_probe`,
   `dependency_missing_picker`, `records_temp_unavailable`, `exhausted_filter_failed`,
   `picker_no_result`, `no_rankable_records`. One assertion each is enough; they are cheap.
4. The two Low findings: document the new env var, and say plainly in the report that no consumer
   is wired up yet and which row owns wiring one. Do not wire a consumer in this round.

### Acceptance

The row's registered probe, plus the new concurrency test shown red-then-green. Report both in
`report.md` with the commands and their output, not as a claim.

## ROUND 3 (lead, 2026-09-16) — the critical is real, and the lead's round-2 brief caused it

Round 2 did what it was told: the marker is now serialized through
`leadv2-portable-lock.sh`, the way `leadv2-arm-cooldown.sh` does it, and the suite grew to 350 lines.
The sonnet reviewer then returned `critical=1 high=0 medium=2 low=3`, and the critical stands. The
lead verified it line by line rather than trusting the verdict:

- `printf '%s\n' "$result"` — the contract output — is at `leadv2-claude-profile-select.sh:902`.
- `write_degraded_marker` / `clear_degraded_marker` are called at `:896-900`, i.e. **before** it, on
  BOTH the degraded branch and the healthy one.
- Inside those functions, `:186` and `:205` call `lv2_lock_wait "${DEGRADED_MARKER}.lock" 5`.

So every selection — including the entirely healthy path that has nothing to record — now waits on a
machine-wide lock for up to five seconds before emitting a pick it has already computed. If the
caller's kill timeout is shorter than that wait, the pick is computed and then thrown away, and a
`--requested-profile` dispatch can FATAL-abort. The fix for a lost signal must not become a way to
lose the answer itself.

**This came from the round-2 brief, which said "serialize every read and write of the marker through
`leadv2-portable-lock.sh`" and said nothing about where in the sequence that may happen.** The lane
implemented the instruction as written. Recording that here so the next reader does not read the
critical as carelessness by the worker.

### What round 3 must deliver

1. **Emit the contract line first, do the marker I/O after.** `printf '%s\n' "$result"` moves above
   the `write_degraded_marker` / `clear_degraded_marker` block. Nothing downstream reads the marker
   within the same call, so the sidecar has no claim on the critical path. Keep the exit code
   semantics exactly as they are.
2. **Never block the healthy path at all.** On a successful ranked pick, `clear_degraded_marker`
   should not cost a lock wait in the common case — check cheaply whether there is anything to
   clear before taking the lock.
3. **Medium 1 — the silent unlocked fallback.** `lv2_lock_wait ... || true` currently swallows a
   timeout and proceeds unlocked, which is the exact race round 2 existed to close, re-entered
   quietly. A lock timeout must be visible: name it in the marker payload or on stderr, and decide
   deliberately whether to proceed or skip the write. Do not leave it as `|| true`.
4. **Medium 2 — `--requested-profile` must be excluded from the new `no_rankable_records` check**,
   as the reviewer notes: a request narrows the candidate set by construction, so the absence of
   other rankable records is not a degraded condition there.
5. The three lows: address or explicitly decline each in the report, with a reason.

### Acceptance

The row's registered probe, plus the lane's own suite, plus **a new test that fails on round 2's
ordering**: assert that the contract line is emitted even when the marker lock is held by another
process for longer than the caller's patience. Hold the lock in the test, run the selection with a
short timeout, and require the pick on stdout. Show it RED against round 2's code and GREEN after.

Without that test this round is a claim, not a fix — and this is the third attempt at this row, so
the standard is higher, not lower.
