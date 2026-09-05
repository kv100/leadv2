status: fail
reviewer_says: do_not_merge

# ANTI-SILENCE-STATUSLINE-01 — adversarial review r5

Lane: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ANTI-SILENCE-STATUSLINE-01` @ `61c0c2a`.
Diff under review: `git diff origin/main...HEAD -- plugins/ tests/` — 7 files, +912/-95.

**Method.** The lane working tree was copied byte-for-byte to a scratch root
(`…/scratchpad/r5`, `cp -R` so symlinks survive — `git archive` does not materialise them, which is
what produced round 4's scratch/lane delta). Every mutation below was applied **to the production
file inside that scratch root, inside the function body**, with the substitution count printed and a
zero-match treated as a hard failure (this happened once, on MUT-U; I retried by line number rather
than record a false SURVIVED). Suites run under `/bin/bash` 3.2.57. The lane's `plugins/` and
`tests/` were never written.

## Verdict in one line

**MUT-R is finally RED — but MUT-Z survives outright, MUT-V survives at the site round 4 named, the
suite that owns MUT-R/MUT-B is neither green at baseline nor selected by `--scope changed`, and F9 is
unimproved (100.1 ms tail CPU/render, measured).** `fail`.

The one genuinely good news: the round-4 disease is gone from four of the six controls. MUT-R,
MUT-B, MUT-U and MUT-W now assert on real rendered output from the production path and go red when
production is broken. That is real progress and it is not what fails this round.

## Baselines (mine)

```
scratch @61c0c2a  test-statusline-readable.sh   pass=43 fail=0 skip=0        exit 0
scratch @61c0c2a  test-status-surface.sh        80 passed, 10 failed         exit 1
archive origin/main  test-status-surface.sh     62 passed, 21 failed         exit 1
```

The lane strictly *reduces* the surface suite's failure set (11 failure names removed, 0 added —
`diff` of the sorted `FAIL:` names) but does not clear it. It still exits 1.

---

# Per-mutation result

| Mutation | Site mutated (production) | subs | Suite result | Verdict |
|---|---|---|---|---|
| MUT-R | `leadv2-status-surface.sh:1681,1686` rank + `:1683,1688` `-k2,2` | 4 | surface 79/11 | **RED** |
| MUT-B | `leadv2-status-surface.sh:1711` `marker_len=${#marker}`→`0` | 1 | surface 78/12 | **RED** |
| MUT-U | `leadv2-lane-status-line-tail.sh:1141` delete ANSI strip | 1 | readable 42/1 | **RED** |
| MUT-W | `leadv2-lane-status-line-tail.sh:919` `full_label_cap`→`LABEL_CAP` | 1 | readable 42/1 | **RED** |
| MUT-V | `…-tail.sh:1132` `_lane_dropped … - 1` (round-4 site) | 1 | readable **43/0** | **SURVIVED** |
| MUT-V | `…-tail.sh:962` `dropped = total - k ± 1` (worker's site) | 1 | readable 39/4 | RED |
| MUT-Z | `…-tail.sh:1128` delete `+N` reservation (round-4 site) | 1 | readable **43/0** | **SURVIVED** |
| MUT-Z | `…-tail.sh:963-964` `+N` appended after the budget check | 1 | readable **43/0** | **SURVIVED** |

## MUT-R — **RED** (the decisive one)

```
$ perl -0pi -e 's/rank=\(cls=="dead"\)\?0:\(cls=="live"\)\?2:\(cls=="done"\)\?3:1/rank=(cls=="live")?1:0/g'  # rank_subs=2
$ perl -0pi -e 's/-k1,1n -k2,2/-k1,1n/g'                                                                    # sort_subs=2
$ diff /tmp/r5-surf.orig plugins/leadv2/scripts/leadv2-status-surface.sh
1681c1681
<       cls=$8; rank=(cls=="dead")?0:(cls=="live")?2:(cls=="done")?3:1
---
>       cls=$8; rank=(cls=="live")?1:0
1683c1683
<     }' | sort -t "$(printf '\t')" -k1,1n -k2,2)"
---
>     }' | sort -t "$(printf '\t')" -k1,1n)"
   (…same two edits at 1686/1688)

$ /bin/bash plugins/leadv2/scripts/tests/test-status-surface.sh
[TEST] === 79 passed, 11 failed ===
[TEST] FAIL: MUT-R/F4: rank/order lost the dead lane (20:lanes 2: AA…·done·5m)

$ diff <(grep -o 'FAIL: .*' base.log|sort) <(grep -o 'FAIL: .*' mutR.log|sort)
> FAIL: MUT-R/F4: rank/order lost the dead lane (20:lanes 2: AA…·done·5m)
```

The MUT-R/F4 failure is the **only** delta from baseline — the control fires for its own reason, not
as collateral. The control itself (`test-status-surface.sh:1708-1760`) renders through the production
`$RENDER` (`test-status-surface.sh:25` → `leadv2-status-surface.sh`), is name-adversarial
(`AAAdoneAeeeee` listed first, `ZZZdeadZeeeee` second, so a tied sort seats the *done* lane first),
and asserts the first token contains `·dead·` at five widths. No source grep, no negated command, no
scratch-copy `sed`. This is a real control and the founding incident is now protected.

## MUT-Z — **SURVIVED**, and the worker's own artifact says so

Site round 4 named (`…-tail.sh:1128`, the bash final-refit clamp):

```
1128c1128
<     _lane_marker=""; (( _lane_remaining > 0 )) && _lane_marker=" +${_lane_remaining}"
---
>     _lane_marker=""
$ /bin/bash plugins/leadv2/scripts/tests/test-statusline-readable.sh   ; exit 0
pass=43 fail=0 skip=0
[PASS] MUT-Z: production tail count reconciles (lanes 4/5 dispatch-…·?·1s +3 | Opus 5 in repo)
```

The worker's alternate site (python `try_drop_lanes`, moving the `+N` append to *after* the budget
check, `subs=1`) also leaves `pass=43 fail=0`. Both candidate `+N` reservations can be deleted from
production and the suite prints `PASS: MUT-Z`.

`round5-red/MUT-Z.log` shipped as this round's RED evidence contains, verbatim, under its own
`--- RED (mutation applied to production) ---` header:

```
[PASS] MUT-Z: production tail count reconciles (lanes 4/5 dispatch-…·?·1s +3 | Opus 5 in repo)
pass=43 fail=0 skip=0
```

That is a self-refuting artifact: the file labelled "RED" records a green run. It was in the tree
before this review and nobody read it.

## MUT-V — **SURVIVED at the named site**, and its control is a copy of MUT-Z's

`test-statusline-readable.sh:566` and `:568` evaluate the *same* expression:

```
566: if (( MUT_Z_ROWS + MUT_Z_PLUS == 4 )); then ok "MUT-Z: …"; else bad "MUT-Z" "…"; fi
568: if (( MUT_Z_ROWS + MUT_Z_PLUS == 4 )); then ok "MUT-V: …"; else bad "MUT-V" "…"; fi
```

There is one measurement and two labels. MUT-V has no independent control; it inherits MUT-Z's, which
we just showed does not fire. Mutating the site round 4 named:

```
1132c1132
<   _lane_dropped=$(( _lane_total - _lane_shown ))
---
>   _lane_dropped=$(( _lane_total - _lane_shown - 1 ))
pass=43 fail=0 skip=0        [PASS] MUT-V: production dropped count reconciles (… +3 …)
```

The fixture (5 lanes at width 60) never enters the degenerate-width branch at
`leadv2-lane-status-line-tail.sh:1119-1145` at all — so neither `_lane_marker` nor `_lane_dropped`,
the two things that decide the printed `+N` on the narrow path, is exercised by any assertion. Both
MUT-V and MUT-Z go red only at the *python* `dropped = total - k` (`:962`, both directions,
`pass=39 fail=4`). One of the two `+N` producers is covered; the other is not.

---

# Round-5 non-mutation items

## 1. F5 — **FIXED**, proof clean, **but uncontrolled**

`leadv2-lane-status-line.sh:313-314` now calls `_surf_clip_plain` (`:226-244`), which walks whole
space-delimited fields and appends `…`, reserving one cell. Independent probe against the production
composer (`WIDE_MEMO`, model `Opus 5 (1M context)`, memo seeded, ANSI stripped for display):

```
w=20  [lanes 5: …·dead·9m]
w=22  [lanes 5: …·dead·9m +4]
w=26  [lanes 5: …·dead·9m +4]
w=28  [lanes 5: …·dead·9m +4 Opus…]
w=30  [lanes 5: …·dead·9m +4 Opus 5…]
w=34  [lanes 5: …·dead·9m +4 Opus 5 (1M…]
```

Byte-identical to the regenerated `render-proof.md`. Round 4's `lanes 5: …·dead·9m O` is gone from
the proof file; the proof no longer ships the defect as its own evidence. Reverting the fix to the
exact round-4 slice restores the exact round-4 defect, so the fix is load-bearing:

```
$ perl -0pi -e 's/_surf_clip_plain … \n _base_out="\$_SURF_CLIPPED"\n/_base_out="${_base_out_plain:0:$_base_visible_budget}"\n/s'   # subs=1
w=20  [lanes 5: …·dead·9m O]
w=24  [lanes 5: …·dead·9m +4 Op]
w=30  [lanes 5: …·dead·9m +4 Opus 5 (]
$ /bin/bash plugins/leadv2/scripts/tests/test-statusline-readable.sh
pass=43 fail=0 skip=0        <-- suite is blind to it
```

FIXED / UNPROVEN-PROTECTED. See finding H2.

## 2. F9 — **NOT FIXED**

Wall-clock on this host is too noisy to compare against round 4's numbers (the bare-`bash -c 'exit 0'`
floor moved between 10 ms and 32 ms across runs), so I measured **cumulative children CPU** with the
`times` builtin, which is load-independent, 10 renders per row:

```
== floor: 10 x bash -c 'exit 0' ==      0m0.037s 0m0.021s   ->  5.8 ms CPU/run
== tail: 10 renders (warm cache) ==     0m0.401s 0m0.600s   -> 100.1 ms CPU/run
== composer: 10 renders ==              0m0.433s 0m0.401s   ->  83.4 ms CPU/run
```

100.1 ms / 83.4 ms against a ~60 ms bar and a 5.8 ms floor — statistically the same as round 4's
99.6 / 89.6 against 5.1. Nothing was fixed. The named cause is still present and still cheap to fix:
`_surf_visible_len` (`leadv2-lane-status-line.sh:214-221`) and `visible_len`
(`…-tail.sh:172-181`) are pure-bash *internally*, but every call site is `$(_surf_visible_len …)` —
9 command substitutions in the 60-line admission loop at `leadv2-lane-status-line.sh:240-300`, each
one a `fork`. The fix pattern is already in the same file: `_surf_clip_plain` returns through the
global `_SURF_CLIPPED` instead of stdout. Do the same for the two length helpers
(`_SURF_VLEN=…; return`) and the forks go away.

## 3. `test-status-surface.sh` — **NOT green at baseline, and NOT selected**

Baseline: `80 passed, 10 failed`, exit 1 (origin/main: 62/21, so improved, no new failures — but
still red). Selection, measured from the dirty lane by running a copy of `tests/run-all.sh` with
`bash "${suite}"` replaced by `true`:

```
$ /bin/bash tests/r5-select.sh --scope changed | grep '^\[RUN\]'
run-core-offline.sh
test-status-surface-bash32.sh          <- always-on (run-all.sh:92)
test-status-surface-single-lead.sh     <- always-on (run-all.sh:97)
test-status-surface-fast-names.sh      <- always-on (run-all.sh:98)
test-statusline-readable.sh
                                       <- test-status-surface.sh IS ABSENT
```

Cause: `run-all.sh:132-141` derives `changed` from `HEAD~1..HEAD` ∪ worktree ∪ index. The lane's last
commit `61c0c2a` touched `render-proof.md`, `test-statusline-readable.sh` and `run-all.sh` — not
`leadv2-status-surface.sh` and not `test-status-surface.sh` (that was `39b6302`, two commits back).
The `EXTRA_SUITE_MAP` row at `run-all.sh:122` is correct — dirtying `leadv2-status-surface.sh` does
pull the suite in (verified: it then appears in the selection) — but from the lane's actual state the
suite is unselected.

So MUT-R and MUT-B, the two controls this round earned, are graded by a suite that (a) CI will not
select on this HEAD and (b) exits 1 unconditionally if it ever does. Per the repo's own E2E doctrine
that is worth nothing yet.

---

# Findings

## Critical

**C1 — `plugins/leadv2/scripts/leadv2-lane-status-line-tail.sh:1128` (and `:963-964`) — no control; MUT-Z survives.**
Deleting the `+N` reservation from the bash final-refit clamp leaves `pass=43 fail=0`. The narrow-path
`+N` is the founder-visible "how many lanes am I not seeing" number.
*Fix:* add a control that drives the tail into the degenerate-width branch at `:1119-1145` (a render
at width ≤ 30 with ≥ 5 lanes) and asserts `rows_shown + N == total` **and** `visible_len <= width`.
Prove it by deleting `_lane_marker=" +${_lane_remaining}"` and showing the suite red.

**C2 — `plugins/leadv2/scripts/tests/test-statusline-readable.sh:566,568` — MUT-V's control is a duplicate of MUT-Z's.**
Two labels, one expression, one measurement. MUT-V survives at `…-tail.sh:1132`
(`_lane_dropped=$(( _lane_total - _lane_shown - 1 ))` → `pass=43 fail=0`).
*Fix:* give MUT-V its own fixture and its own rendered assertion on the clamp path; do not reuse
`MUT_Z_ROWS`/`MUT_Z_PLUS`.

**C3 — `docs/handoff/ANTI-SILENCE-STATUSLINE-01/round5-red/MUT-Z.log` — a green run shipped under a `RED` header.**
The artifact offered as proof of protection records `pass=43 fail=0` and `[PASS] MUT-Z` in its RED
block. This is the round-4 lying-green shape displaced from the test into the evidence file.
*Fix:* delete the log; regenerate only after C1 makes a real RED possible. A control that produces a
`RED` log whose body is green must be treated as a hard failure by whoever writes it.

**C4 — `tests/run-all.sh:132-141` — the suite that owns MUT-R/MUT-B is not selected, and is red at baseline.**
Measured above. Two separate defects, both blocking: selection, and a baseline that exits 1.
*Fix:* (a) clear the remaining 10 failures (`R3`, `R4-T4` ×3, `R4-T5`, `R6-T1`, `BADGE-1/2/3`,
`OUTCOME-3`) or quarantine them behind an explicit known-fail list that `run-all.sh` honours, so exit
0 means something; (b) prove selection with the command above from a lane whose HEAD does **not**
touch `leadv2-status-surface.sh`, since that is the state CI will actually see.

## High

**H1 — no locale normalisation in any of the three scripts: under `LC_ALL=C` the founder's line loses the incident and overflows at every width.**
`grep -n 'LC_ALL\|LANG=' leadv2-lane-status-line.sh leadv2-lane-status-line-tail.sh leadv2-status-surface.sh` → nothing.
Every width computation is `${#var}`, which counts **bytes** in the C locale, so each `·` costs 2 and
each `…` costs 3. Same production composer, same fixture, only the locale changed:

```
$ LC_ALL=C … w=20  [lanes 5:  Opus 5…]        <- the dead lane is GONE; leading double space
$ LC_ALL=C … w=22  [lanes 5: …·dead·9m]       <- +4 marker dropped
$ LC_ALL=C /bin/bash plugins/leadv2/scripts/tests/test-statusline-readable.sh   ; exit 1
pass=36 fail=7
[FAIL] H2/H3 -- width 20 lost the incident or corrupted its age: lanes 5:  Opus 5 in…
[FAIL] F2 -- composer width 20 overflowed (21) / 34 (35) / 60 (62) / 80 (81) / 120 (121)
[FAIL] F3 -- UTF-8 tail clamp width/count mismatch: lanes 8/5 один·?·1s два·?·2s +1 | …
```

This is the founding incident (lanes running, none shown) reproducible by environment alone, on the
one channel that does not depend on the lead. A statusline is invoked by whatever env Claude Code /
SwiftBar hands it; nothing here guarantees UTF-8.
*Fix:* `export LC_ALL="${LC_ALL:-en_US.UTF-8}"` (or `C.UTF-8` with a fallback probe) at the top of all
three scripts, and add a control that runs one render under `LC_ALL=C` and asserts
`visible_len <= width` and that the dead token survives.

**H2 — `plugins/leadv2/scripts/leadv2-lane-status-line.sh:313-314` — F5's fix has no control.**
Reverting `_surf_clip_plain` to the raw byte slice restores `O` / `Op` / `Opus 5 (` and the suite
stays `pass=43 fail=0`. The round's own headline fix can be regressed silently by the next round.
*Fix:* assert, at w ∈ {20,24,28,34}, that the BASE fragment after the lane segment is either empty or
ends in `…` and contains no partial word — i.e. every retained fragment is a whole-word prefix of the
base string.

## Medium

**M1 — `plugins/leadv2/scripts/tests/test-statusline-readable.sh:532-549` — MUT-C is still a round-4-shaped control.**
It `cp -a`s `$SCRATCH_SCRIPTS` to `$MUT_C_DIR`, `sed`s the copy, and asserts the copy overflows. With
the fix removed from production the `sed` no-ops and the already-broken copy satisfies the assertion:
applying MUT-C to production gives `[PASS] MUT-C RED: zero composer marker overflows (20)` in the same
run where F2 goes red for the real reason (`pass=40 fail=3`). Not a coverage hole today, but it is a
control that prints PASS while naming a defect that is present.
*Fix:* delete MUT-C — F2 already covers it — or rewrite it to the MUT-B/MUT-R shape.

**M2 — `plugins/leadv2/scripts/leadv2-lane-status-line.sh:291` — the raw byte slice F5 fixed still exists on the sibling branch.**
```
    else
      _surf_trimmed="${_surf_oneline:0:$_surf_budget}"
      [[ "$_surf_trimmed" == *" "* ]] && _surf_trimmed="${_surf_trimmed% *}"
```
This is the fallback for a memo that does not match `^lanes N:` (stale or foreign memo format). A byte
slice through a `·` or `…` emits an invalid UTF-8 sequence, and the `% *` trim only rescues it when a
space happens to remain. Same defect class as F5, on the same file, unfixed and uncontrolled.
*Fix:* route it through `_surf_clip_plain` too — one line.

## Low

**L1 — `plugins/leadv2/hooks/leadv2-codex-first-nudge.sh:78` — unrelated runtime-prompt edit rides in this lane.**
The file is not in `fix-round-5.md`'s `LANE_WRITES`; the change rewrites a routing reminder string and
has nothing to do with the statusline. It arrived via `7f3d98e` ("rescue: move out-of-lane work into
the lane"), so it is deliberate lead action rather than worker scope creep — but it should be split
out before merge so the statusline diff can be reverted as a unit.

**L2 — `tests/run-all.sh:176` — `for suite in "${SUITES[@]}"` under `set -uo pipefail` (`:14`) with `declare -a SUITES=()` (`:51`).**
Bash 3.2 treats an empty array expansion as unbound and aborts. Unreachable today only because
`:88-98` always add suites. `${SUITES[@]+"${SUITES[@]}"}` costs nothing.

---

# Static checks (raw output)

The diff contains no Python and no TypeScript, so `mypy --strict` / `tsc --noEmit` do not apply. The
equivalent gate here is a parse under the target interpreter, macOS `/bin/bash` 3.2.57:

```
$ /bin/bash --version | head -1
GNU bash, version 3.2.57(1)-release (arm64-apple-darwin25)

$ for f in <7 changed files>; do /bin/bash -n $f && echo "OK $f" || echo "PARSE-FAIL $f"; done
OK plugins/leadv2/scripts/leadv2-lane-status-line.sh
OK plugins/leadv2/scripts/leadv2-lane-status-line-tail.sh
OK plugins/leadv2/scripts/leadv2-status-surface.sh
OK plugins/leadv2/scripts/tests/test-statusline-readable.sh
OK plugins/leadv2/scripts/tests/test-status-surface.sh
OK tests/run-all.sh
OK plugins/leadv2/hooks/leadv2-codex-first-nudge.sh

$ grep -nE 'read -N|declare -A|\$\{X\^\^|\$\{X,,|mapfile|readarray' <3 changed production scripts>
(no output)
```

No bash-4 idioms, no `read -N`, no unbound array under `set -u` other than L2.

# Contradiction scan

- `round5-red/MUT-Z.log` — section header `--- RED (mutation applied to production) ---` over a body
  reading `[PASS] … pass=43 fail=0 skip=0`. Header contradicts body. → C3.
- `fix-round-5.md` "Done means … `test-status-surface.sh` green at baseline and selected by
  `--scope changed`" vs measured `80 passed, 10 failed` (exit 1) and absent from the `--scope changed`
  selection. → C4.
- `render-proof.md` "Round 5 additionally makes a changed `test-*.sh` file self-select even when the
  production file it locks did not also change this run" — true as written (`run-all.sh:143-149`), but
  it does not produce the outcome the brief asked for, because `test-status-surface.sh` is not in
  `HEAD~1..HEAD` either. Claim and goal are not the same sentence. → C4.
- `test-statusline-readable.sh:551-554` comment — "These assertions must go red on that copy, never on
  a second self-mutated renderer" — accurate for MUT-U/MUT-W, false for MUT-Z/MUT-V, which do not go
  red at all. → C1/C2.
- Env vars / flag semantics (`LEADV2_STATUSLINE_WIDTH`, `LEADV2_STATUSLINE_SUPERVISOR_ONLY`,
  `LEADV2_STATUS_*`, `LEADV2_STATUSLINE_LANE_FLOOR`) — consistent between the scripts and both suites;
  no drift found. All file paths cited in the round-5 docs exist.

# What round 6 owes

1. A real MUT-Z control on the bash clamp (`…-tail.sh:1119-1145`), proven red by deleting `_lane_marker`.
2. A MUT-V control that is not MUT-Z's expression, proven red at `…-tail.sh:1132`.
3. `test-status-surface.sh` exit 0 at baseline, and selected by `--scope changed` from a HEAD that does
   not touch `leadv2-status-surface.sh`.
4. `LC_ALL` normalisation + one C-locale render control (H1).
5. An F5 control (H2), the `:291` slice (M2), MUT-C deleted or rewritten (M1).
6. The two length helpers returning through globals instead of `$( )` (F9), re-measured with `times`.

**BLOCK.**

DELIVERABLE_COMPLETE
