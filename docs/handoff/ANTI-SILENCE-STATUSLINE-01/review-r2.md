status: fail
reviewer_says: do_not_merge

# ANTI-SILENCE-STATUSLINE-01 — adversarial review r2

Lane: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ANTI-SILENCE-STATUSLINE-01` @ `fe203b3`
Round 2 is **one commit** (`fe203b3`, 4 files, +161/-30) on top of the r1 anchor `8ad022f`.

All mutations were applied to a `git archive fe203b3` extraction under the scratchpad. The lane's
`plugins/` and `tests/` are byte-clean (`git status --porcelain -- plugins tests` empty) and each
scratch script diffs IDENTICAL against `fe203b3` after my reverts.

## Suites, as run by me (not taken on trust)

```
plugins/leadv2/scripts/tests/test-statusline-readable.sh  (in the lane)      pass=17 fail=0 skip=0
plugins/leadv2/scripts/tests/test-status-surface.sh       (in the lane)      68 passed, 21 failed
plugins/leadv2/scripts/tests/test-statusline-readable.sh  (clean checkout)   pass=15 fail=0 skip=1
```

The lead's `pass=17 fail=0 skip=0` is real **in the lane worktree only**. In a checkout without
reachable history it is `pass=15 fail=0 skip=1` — F8 is not fixed (see table).
The 21 `test-status-surface.sh` failures remain pre-existing (r1 measured 21 at the anchor
`91c9919` too); `leadv2-status-surface.10s.sh`, whose `bash -n` fails, does not exist in this tree.
They are not charged against the diff — but see **N6**, because this diff newly puts them on the
CI blocking path.

---

# Prior findings — verdict table

| # | Finding | Verdict | Evidence |
|---|---|---|---|
| **F1** | field-boundary cut has no control | **FIXED** | **ran** — MUT-1 (`leadv2-lane-status-line-tail.sh:1098` backoff → `: # MUTATED`) now goes **RED**: `[FAIL] R12 -- mid-word-truncated token found (80='', 112='LANDING')`, `pass=14 fail=1 skip=1`; revert → `pass=15 fail=0 skip=1`. MUT-3 (composer refit branch disabled) → **RED**, 3 fails. Residual: composer `:252` mutation still green (N10). |
| **F2** | budget exceeded by its own `+N` marker | **PARTIAL** | **ran** — 30/34/60/80/120/200 all render at **exactly** the budget (see renders). But at **W=22 the render is 23 visible chars** (N4), and the fix has **no control**: MUT-C makes W=60 render **64 chars** while the suite stays `pass=15 fail=0` (N2). |
| **F3** | dropped-count lies (counts upstream `+M` as one lane) | **PARTIAL** | **ran** — composer path now exact (1+4, 2+3, 4+1, 5+0 against `lanes 5`). **Tail path unfixed and proven wrong**: instrumented, `TAILCLAMP W=80 LANES_IN=[lanes 12/5 1·?·1s … 7·?·7s +5] REST=[ 6·?·6s 7·?·7s +5] DROPPED_N=3` — **7 lanes hidden, `+3` printed**. `leadv2-lane-status-line-tail.sh:1100` still `tr -s ' ' \| grep -c`. |
| **F4** | silent lane dropped in favour of a live one | **PARTIAL** | **ran** — `continue`→`break` + first-row preservation landed and are mutation-controlled (MUT-A → RED 2 fails; MUT-E → RED). A non-live lane is present at every width I tested. **But** the rank function only separates `live`; within rank 0 the sort falls back to lexicographic on the lane *name*, so a **`done` lane takes the only narrow slot from a `dead` lane** — see **N1**, the founding incident survives one class-name away. |
| **F5** | base half cut mid-word, no marker, colour dropped | **NOT FIXED** | **ran + read** — `leadv2-lane-status-line.sh:272` is byte-identical: `_base_out="${_base_out_plain:0:$_base_visible_budget}"`. All six of my renders cut mid-word (`Opus 5 `, `in ~`, `~/Projects/`, `~/Proj`, `Opus 5 i`, `· g`) and every truncating render loses all ANSI colour. |
| **F6** | `emit_oneline` overflows its budget by `+N` | **FIXED, UNCONTROLLED** | **ran** — every emit_oneline render ≤ W (see renders). But MUT-B (`marker_len=${#marker}` → `marker_len=0`) **survives**: suite stays `68 passed, 21 failed` while W=34 renders **35 chars**. See N2. |
| **F7** | `width` assertion has 22 chars slack, measures ANSI bytes | **NOT FIXED** | **read** — `test-statusline-readable.sh:480` unchanged: `if (( ${#NARROW_LINE} <= 40 + ${#DEAD_ONLY_LINE} ))`. Still 22 chars of slack on a 40-column budget, still counting raw ANSI bytes. Confirmed by MUT-C: a 64-char render at W=60 does not trip it. |
| **F8** | R1/R2 baseline is git-dependent, reverts to SKIP | **NOT FIXED** | **ran** — clean `git archive` checkout: `[SKIP] R1/R2 pre-fix baseline -- git archive of prior revision unavailable in this checkout (first commit / shallow clone)`, `pass=15 fail=0 skip=1`. The author added a fallback *ref* chain instead of inlining the two literal fixture strings the brief asked for. |
| **F9** | new synchronous subprocess spawns on a ≤100 ms contract path | **PARTIAL** | **ran + read** — `tr`+`grep` removed from the main path (good). A **second** `sed -E` was added at `:290` in the no-user-command branch. Main path still spawns `stat`, `jq`, `timeout bash`, `sed`. Measured with a no-op user command: `115ms 112ms 115ms 114ms 117ms` (r1: ~100 ms). The file header's "ZERO synchronous subprocess spawns" contract is still violated. |

Prior Mediums/Lows, for completeness: **F10 NOT FIXED** (`plugins/leadv2/hooks/leadv2-codex-first-nudge.sh:78` string rewrite still in the diff, still outside `LANE_WRITES`); **F11 WORSE** — `render-proof.md` is now absent from the lane worktree entirely and `git ls-files` in the main root returns nothing for the whole handoff dir, so the acceptance artifact the round-2 brief demanded ("re-run render at 30/34/60/80/120/200") does not exist on disk; **F12 NOT FIXED**, root cause now identified as N3; **F13 FIXED** — the new `silence:` assertions in `test-status-surface.sh:1900-1922` drive the real `sort`+fitter and are mutation-proven by MUT-A; **F14 NOT FIXED** — no `LC_ALL`/`LANG` in any of the three scripts, and N3 proves the byte/char confusion is live on this host; **F15 NOT FIXED** and now load-bearing — the unconditional trailing space is what causes N4.

---

# New findings

## CRITICAL

### N1 — A cleanly-finished lane outranks a crashed one for the only narrow slot
`plugins/leadv2/scripts/leadv2-status-surface.sh:1682-1688`

```awk
cls=$7; rank=(cls=="live")?1:0
```
`dead`, `done` and `queued` all get rank 0. `sort -t TAB -k1,1n` is not stable and has no secondary
key, so equal ranks fall back to whole-line lexicographic order — i.e. **the lane name**. Proven:

```
$ printf 'AAA-FINISHED-CLEAN\t…\tdone\nZZZ-CRASHED-LANE\t…\tdead\nliveA\t…\tlive\n' | awk … | sort -t TAB -k1,1n
0	AAA-FINISHED-CLEAN	done	9m
0	ZZZ-CRASHED-LANE	dead	14m
1	liveA	live	1s
```

Driven through the real `emit_oneline` with those three rows:

```
W=26  len=21  |lanes 3: …·done·9m +2|
W=30  len=21  |lanes 3: …·done·9m +2|
W=34  len=21  |lanes 3: …·done·9m +2|
W=40  len=36  |lanes 3: AAA-FINISHED-CL…·done·9m +2|
W=50  len=36  |lanes 3: AAA-FINISHED-CL…·done·9m +2|
W=60  len=36  |lanes 3: AAA-FINISHED-CL…·done·9m +2|
```

**Failure scenario, and it is the founding incident:** three lanes; one finished cleanly
(`AAA-FINISHED-CLEAN·done`), one crashed (`ZZZ-CRASHED-LANE·dead`), one live. At every width from 26
to 60 the founder sees `…·done·9m +2`. The lane that died is invisible and the lane he is shown is
the one that is *fine*. The r1 fix changed which healthy lane wins, not that one does.

**Required fix:** rank must order `dead > queued > done > live`, with a deterministic secondary key
(age descending), not `live vs not-live` plus lexicographic luck.

### N2 — Two assertions added this round survive their own mutation
`plugins/leadv2/scripts/leadv2-status-surface.sh:1711` and `plugins/leadv2/scripts/leadv2-lane-status-line.sh:226`

The round-2 brief's explicit rule: *"An assertion that survives its own mutation is not a control.
F1 is exactly that; do not add a second."* Two were added.

**MUT-B** — surface-side marker reservation, mutated inside `emit_oneline`:
```
marker=" +${remaining}"; marker_len=${#marker}   →   marker=" +${remaining}"; marker_len=0
[TEST] PASS: width: 12-lane oneline at WIDTH=40 stayed within the exact budget (len=35)
[TEST] === 68 passed, 21 failed ===        <-- STILL GREEN
```
Same mutation, real render: `W=34 len=35` — **over budget by 1**, invisible to the suite. The new
`width: … stayed within the exact budget` assertion measures a render that has 5 columns of slack,
so tightening its bound from 60 to 40 did nothing.

**MUT-C** — composer-side marker reservation, mutated inside the refit loop:
```
_surf_marker=""; (( _surf_remaining > 0 )) && _surf_marker=" +${_surf_remaining}"   →   _surf_marker=""
pass=15 fail=0 skip=1                      <-- STILL GREEN
```
Same mutation, real composer render on the founder's live path:
```
W=60   vis=64   |lanes 5: ANTI-SILENCE-STA…·dead·14m BROAD-STATUS-RO…·dead·9m +3 |  <<< OVER BUDGET
```
**That is r1's F2 verbatim (63 > 60 then, 64 > 60 now), reintroducible by deleting one assignment,
with no test in the repo able to see it.** R13 cannot: its fixture is 5 short tokens at W=30, where
the marker never straddles the boundary. F7's `width` assertion cannot: 22 chars of slack.

**Required fix:** R13 needs a companion case whose token lengths put the `+N` marker exactly on the
budget boundary (a memo whose second token ends at `budget - 2`), asserted at several widths; and
`test-status-surface.sh` needs a WIDTH sweep asserting `len <= W` for every W in 26..60, not one
width with slack.

## HIGH

### N3 — The tail measures visible width in BYTES and cuts in CHARACTERS
`plugins/leadv2/scripts/leadv2-lane-status-line-tail.sh:1089` vs `:1095`

```bash
FINAL_VISIBLE_LEN="$(printf '%s' "$FINAL_LINE" | sed … | awk '{print length}')"   # BYTES
OVERFLOW=$(( FINAL_VISIBLE_LEN - STATUSLINE_WIDTH ))
KEEP=$(( ${#LANES} - OVERFLOW ))                                                  # CHARACTERS
```
Measured on this host (`LANG=C.UTF-8`):
```
$ printf 'a·b…c' | awk '{print length}'   → 8
$ S='a·b…c'; echo ${#S}                   → 5
```
Every `·` counts 2 and every `…` counts 3 in the measure, and 1 in the cut. For the suite's own
fixture `LANES` this is **151 bytes vs 137 characters — a 14-character phantom overflow**, so the
tail trims roughly one whole lane token more than it needs to, at every width. **This is the
mechanism behind r1's F12** ("a lane hidden at 200 columns with columns free"), which round 2 did
not diagnose.

What makes this blocking rather than merely wrong: **the author fixed this exact bug in the test
helper in this same commit** —
```
-visible_len() { printf '%s' "$1" | strip_ansi | awk '{print length}'; }
+# Bash's character length follows the terminal locale; awk's length can count
+# UTF-8 bytes, turning each visible `·` into two columns on this host.
+visible_len() { local plain; plain="$(printf '%s' "$1" | strip_ansi)"; printf '%s' "${#plain}"; }
```
— named it in a comment, and left it in the production script. The test was made to agree with the
shipped behaviour instead of the shipped behaviour being fixed.

**Required fix:** replace `awk '{print length}'` at `:1089` (and `:182`) with the same `${#plain}`
form, and set `LC_ALL` to a UTF-8 locale at the top of both scripts so `${#}` is codepoint-based
regardless of the inherited environment (F14).

### N4 — Off-by-one overflow whenever the lane segment exactly fills the budget
`plugins/leadv2/scripts/leadv2-lane-status-line.sh:256, 268-271`

`_surf_trimmed` is fitted to `<= _surf_budget`, then `_surf_tail="$_surf_trimmed "` appends an
unconditional space (F15) making it `budget + 1`, then
`_base_visible_budget=$(( _surf_budget - ${#_surf_tail} ))` goes negative and is clamped to `0`.
The negative slack is discarded instead of being charged back:

```
W=22  vis=23  |lanes 5: …·dead·14m +4 |   <-- 1 over budget, ends in a space
W=24  vis=24  |lanes 5: …·dead·14m +4 O|
W=26  vis=26  |lanes 5: …·dead·14m +4 Opu|
W=28  vis=28  |lanes 5: …·dead·14m +4 Opus |
```

**Failure scenario:** a narrow IDE panel or a split terminal at exactly the width where the lanes
fill the line — the statusline soft-wraps to two rows, which is the original complaint. No assertion
covers any width below 30.

**Required fix:** fit `_surf_trimmed` to `_surf_budget - 1` when a base will follow, or make the
separator space conditional on `_base_visible_budget > 0`.

### N5 — The first-row shrink starts at the minimum and never grows: 10-14 columns of lane identity thrown away
`plugins/leadv2/scripts/leadv2-status-surface.sh:1719-1725`

```bash
name_cap="…"
while [ $(( ${#name_cap} + suffix_len + marker_len )) -gt "$budget" ] && [ ${#name_cap} -gt 0 ]; do
  name_cap="${name_cap:0:${#name_cap}-1}"
done
```
The loop is seeded at the **shortest possible** label and can only shrink further. It never attempts
the real label, so the moment the full 16-char cap does not fit, the lane name is discarded
wholesale. Measured, 2 dead + 3 live lanes:

```
W=30   len=20   |lanes 5: …·dead·- +4|      budget 21, used 11 — 10 columns unused
W=34   len=20   |lanes 5: …·dead·- +4|      budget 25, used 11 — 14 columns unused
```
`ANTI-SILEN…·dead·- +4` would have fitted at W=30 and `ANTI-SILENCE-…·dead·- +4` at W=34.

**Failure scenario:** the founder's narrow panel shows `lanes 5: …·dead·- +4`. He knows *a* lane
died and cannot tell *which*, on the one surface whose job is to name the lane that died — while a
third of the line sits empty. This is the brief's "exact-budget calculation that now under-fills"
and the inverse of F4 at the same time (four live lanes vanish to buy nine blank columns).

**Required fix:** seed `name_cap` at the full capped label and shrink downward until it fits, never
seed at `…`.

### N6 — This diff newly selects a RED suite into the CI blocking path
`tests/run-all.sh:135` (`leadv2-status-surface.sh:plugins/leadv2/scripts/tests/test-status-surface.sh`)

The three `EXTRA_SUITE_MAP` rows **do** select — run-verified, which r1 could not complete:

```
$ git diff --name-only HEAD
plugins/leadv2/scripts/leadv2-lane-status-line-tail.sh
plugins/leadv2/scripts/leadv2-lane-status-line.sh
plugins/leadv2/scripts/leadv2-status-surface.sh
$ bash tests/run-all.sh --scope changed
[RUN]  …/plugins/leadv2/scripts/tests/run-core-offline.sh
[FAIL] …/plugins/leadv2/scripts/tests/run-core-offline.sh
[RUN]  …/tests/test-status-surface-bash32.sh
[RUN]  …/tests/test-status-surface-single-lead.sh
[RUN]  …/tests/test-status-surface-fast-names.sh
[RUN]  …/plugins/leadv2/scripts/tests/test-statusline-readable.sh
[RUN]  …/plugins/leadv2/scripts/tests/test-status-surface.sh
[FAIL] …/plugins/leadv2/scripts/tests/test-status-surface.sh
run-all: 4 passed, 2 failed, scope=changed
```

`test-status-surface.sh` was **not** reachable from `--scope changed` before this diff (stem
`leadv2-status-surface` has no `test-leadv2-status-surface.sh`), and it carries 21 pre-existing
failures. The row is correct in principle and wrong to land now: **every future change to any of
these three files will fail the gate for reasons unrelated to that change.** Land the row in the same
commit that fixes (or quarantines) the 21, or the next author's first act will be to delete it.

## MEDIUM

### N7 — R12's class whitelist omits classes the code actually emits
`plugins/leadv2/scripts/tests/test-statusline-readable.sh:259`

```bash
[[ ! "$R12_REST" =~ ^(alive|dead|done|queued|\?)·[0-9]+[smh]?$ ]]
```
`emit_oneline` emits `live` (`leadv2-status-surface.sh:1683`), which is not in the list, and the tail
emits four-field tokens at wide widths — instrumented directly:
`dispatch-c98a1414-archi…·?·1s·sw`, `GATE-FOREIGN-FAILURE-01·?·2s·full`. Both forms would be reported
as mid-word cuts. R12 only escapes false-RED because it is applied at widths 80 and 112 where the
fixture happens to render `·?·<age>` and drop the arm suffix. Widen the grammar, or R12 becomes a
false alarm the first time someone extends it to width 200.

### N8 — The composer does not validate `COLUMNS`; `emit_oneline` does
`leadv2-lane-status-line.sh:213` vs `leadv2-status-surface.sh:1671`

`emit_oneline` has `case "$width" in ''|*[!0-9]*) width=80 ;; esac`. The composer takes
`_surf_budget="${LEADV2_STATUSLINE_WIDTH:-${COLUMNS:-80}}"` raw. A non-numeric `COLUMNS` makes every
`(( … > _surf_budget ))` compare against an unset variable name → 0, so **every lane collapses to
`lanes N: +N`** and the base is blanked. Mirror the surface's guard.

### N9 — The tail's dropped-count has no assertion at all
Mutation **MUT-F** (`DROPPED_N=$(( DROPPED_N - 1 ))` inserted inside the clamp body) leaves the suite
at `pass=15 fail=0 skip=1`. R5 only inspects `LABELS_80`, where the `+3` is produced by
`render_step12`, not by the overflow clamp; the clamp fires at 112 and 200, where nothing counts.
This is why F3's tail half shipped through round 2 untouched.

## LOW

### N10 — The composer's else-branch backoff still survives its mutation
`leadv2-lane-status-line.sh:252`. MUT-2 (`_surf_trimmed="${_surf_trimmed% *}"` → `: # MUTATED`)
leaves `pass=15 fail=0 skip=1`. That branch is now the fallback for a memo that does not match
`^lanes N:`, so it is unreachable from today's `emit_oneline` — but it is the path that runs if the
memo format ever drifts, which is precisely when nobody will be looking.

---

# My width renders, verbatim

**A. The founder's live path** — real `plugins/leadv2/scripts/leadv2-lane-status-line.sh`,
`LEADV2_STATUSLINE_SUPERVISOR_ONLY=1`, `statusLine.command` printing
`Opus 5 in ~/Projects/leadv2 | cc 87%·7d/5d17h · cx 93%·wk/6d17h · glm 19%·wk/20h53m`, seeded memo
`lanes 5: ANTI-SILENCE-STA…·dead·14m BROAD-STATUS-RO…·dead·9m dispatch-c98a1b·live·1s dispatch-5bfce2·live·3s GATE-FOREIGN-01·live·2s`.
ANSI stripped; `vis` = Python `len()` of the stripped string (codepoints, `·` and `…` = 1 each).

```
W=30   vis=30   |lanes 5: …·dead·14m +4 Opus 5 |
W=34   vis=34   |lanes 5: …·dead·14m +4 Opus 5 in ~|
W=60   vis=60   |lanes 5: ANTI-SILENCE-STA…·dead·14m +4 Opus 5 in ~/Projects/|
W=80   vis=80   |lanes 5: ANTI-SILENCE-STA…·dead·14m BROAD-STATUS-RO…·dead·9m +3 Opus 5 in ~/Proj|
W=120  vis=120  |lanes 5: ANTI-SILENCE-STA…·dead·14m BROAD-STATUS-RO…·dead·9m dispatch-c98a1b·live·1s dispatch-5bfce2·live·3s +1 Opus 5 i|
W=200  vis=200  |lanes 5: ANTI-SILENCE-STA…·dead·14m BROAD-STATUS-RO…·dead·9m dispatch-c98a1b·live·1s dispatch-5bfce2·live·3s GATE-FOREIGN-01·live·2s Opus 5 in ~/Projects/leadv2 | cc 87%·7d/5d17h · cx 93%·wk/6d17h · g|
```

Good: `vis == W` at every width — F2's overflow is gone in this range; `+N` is exact at every width
(1+4, 1+4, 1+4, 2+3, 4+1, 5+0 against `lanes 5`) — F3 fixed on this path; a `dead` lane is present at
every width — F4's headline claim holds *for a `dead`-vs-`live` mix*.

Bad, all six renders: the base is cut mid-word every time (`Opus 5 `, `in ~`, `~/Projects/`,
`~/Proj`, `Opus 5 i`, `· g`) with no dropped marker and no colour — **F5 unfixed**. At 30 and 34 the
lane identity is `…` — **N5**. Below 30 the line goes over budget — **N4**.

**B. The upstream `emit_oneline`** — real `leadv2-status-surface.sh --oneline`, fully sandboxed
fixture, 2 `dead` + 3 `live` lanes, `LEADV2_STATUSLINE_WIDTH` swept:

```
W=30   len=20   |lanes 5: …·dead·- +4|
W=34   len=20   |lanes 5: …·dead·- +4|
W=40   len=35   |lanes 5: ANTI-SILENCE-ST…·dead·- +4|
W=60   len=59   |lanes 5: ANTI-SILENCE-ST…·dead·- BROAD-STATUS-RO…·dead·- +3|
W=80   len=72   |lanes 5: ANTI-SILENCE-ST…·dead·- BROAD-STATUS-RO…·dead·- liveA·live·- +2|
W=120  len=95   |lanes 5: ANTI-SILENCE-ST…·dead·- BROAD-STATUS-RO…·dead·- liveA·live·- liveB·live·- liveC·live·-|
W=200  len=95   |lanes 5: ANTI-SILENCE-ST…·dead·- BROAD-STATUS-RO…·dead·- liveA·live·- liveB·live·- liveC·live·-|
```

No render exceeds its width (F6 fixed). W=30 wastes 10 columns and W=34 wastes 14 (N5).

**C. Same `emit_oneline`, one `done` + one `dead` + one `live` lane (N1):**

```
W=26  len=21  |lanes 3: …·done·9m +2|
W=30  len=21  |lanes 3: …·done·9m +2|
W=34  len=21  |lanes 3: …·done·9m +2|
W=40  len=36  |lanes 3: AAA-FINISHED-CL…·done·9m +2|
W=50  len=36  |lanes 3: AAA-FINISHED-CL…·done·9m +2|
W=60  len=36  |lanes 3: AAA-FINISHED-CL…·done·9m +2|
```

A lane crashed. At six widths the founder is shown the one that finished.

---

# Mutation pairs I ran

```
MUT-1  tail:1098   [[ "$TRIMMED" == *" "* ]] && TRIMMED="${TRIMMED% *}"   -> : # MUTATED
  RED   [FAIL] R12 -- mid-word-truncated token found (80='', 112='LANDING')   pass=14 fail=1 skip=1
  GREEN (revert)                                                              pass=15 fail=0 skip=1

MUT-2  composer:252  _surf_trimmed="${_surf_trimmed% *}"                  -> : # MUTATED
  GREEN pass=15 fail=0 skip=1   <-- mutation SURVIVED (else-branch, N10)

MUT-3  composer:219  =~ ^lanes                                            -> =~ ^ZZZNEVERlanes
  RED   [FAIL] silence / [FAIL] order / [FAIL] R13                            pass=12 fail=3 skip=1
  GREEN (revert)                                                              pass=15 fail=0 skip=1

MUT-A  surface:1729 (inside emit_oneline)  break                          -> continue
  RED   [FAIL] silence: width-30 dropped dead lane … (lanes 2: …·dead·- live·live·- +1)
        [FAIL] silence: width-30 admitted healthy lane after unfittable dead lane
        === 66 passed, 23 failed ===
  GREEN (revert)                                                              === 68 passed, 21 failed ===

MUT-B  surface:1711 (inside emit_oneline)  marker_len=${#marker}          -> marker_len=0
  GREEN === 68 passed, 21 failed ===   <-- mutation SURVIVED; real render W=34 len=35 (N2)

MUT-C  composer:226 (inside refit loop)    _surf_marker=" +${_surf_remaining}" -> ""
  GREEN pass=15 fail=0 skip=1          <-- mutation SURVIVED; real render W=60 vis=64 (N2)

MUT-D  composer:248  _surf_dropped_n=$(( _surf_total - _surf_shown ))     -> ( … - 1 )
  RED   [FAIL] R13 -- … lied about +N … (lanes 5: …·dead·9m +3 …)             pass=14 fail=1 skip=1

MUT-E  composer:232  (( _surf_shown == 0 ))                               -> (( _surf_shown == 999 ))
  RED   [FAIL] R13 -- memo clamp lost silent lane … (lanes 5: +5 Opus 5 …)    pass=14 fail=1 skip=1

MUT-F  tail:1101 (inside clamp body)  DROPPED_N=$(( DROPPED_N - 1 ))      (inserted)
  GREEN pass=15 fail=0 skip=1          <-- mutation SURVIVED (N9)
```

---

# Static checks (raw output)

No Python or TypeScript in this diff; the equivalent gates are `bash -n` and `shellcheck`.

```
$ for f in $(git diff --name-only 91c9919..fe203b3); do bash -n "$f"; done
plugins/leadv2/hooks/leadv2-codex-first-nudge.sh               OK
plugins/leadv2/scripts/leadv2-lane-status-line-tail.sh         OK
plugins/leadv2/scripts/leadv2-lane-status-line.sh              OK
plugins/leadv2/scripts/leadv2-status-surface.sh                OK
plugins/leadv2/scripts/tests/test-status-surface.sh            OK
plugins/leadv2/scripts/tests/test-statusline-readable.sh       OK
tests/run-all.sh                                               OK

$ shellcheck -S warning -e SC1090,SC1091,SC2034 \
    plugins/leadv2/scripts/leadv2-lane-status-line.sh \
    plugins/leadv2/scripts/leadv2-status-surface.sh
(no output — clean)
```

---

# Contradiction scan

- **Test helper vs production measurement — CONTRADICTION (N3).** This commit changes `visible_len()`
  away from `awk '{print length}'` with a comment stating awk counts UTF-8 bytes, while
  `leadv2-lane-status-line-tail.sh:1089` and `:182` keep using exactly that to size the production
  cut. The test was aligned to the bug rather than the bug fixed.
- **`COLUMNS` validation — CONTRADICTION (N8).** `emit_oneline` sanitises a non-numeric width to 80;
  the composer, reading the same two env vars, does not.
- **Prefix format — consistent.** `emit_oneline` emits `lanes N: …`; the tail emits `lanes n/cap …`.
  The composer's refit regex `^lanes[[:space:]]+([0-9]+):?…` only ever sees the memo (emit_oneline
  form). Verified: no cross-feeding. Note this is load-bearing and undocumented — if the memo ever
  carried the `n/cap` form, `_surf_total` would silently become `n` and `/cap` would be treated as a
  lane token.
- **`LEADV2_STATUSLINE_WIDTH` vs `COLUMNS`** — consistent, and the detached refresher still exports
  `LEADV2_STATUSLINE_WIDTH` explicitly because `$COLUMNS` does not survive `setsid`. Correct.
- **Path existence** — the three `EXTRA_SUITE_MAP` suite paths all exist and all select
  (run-verified, N6). `plugins/leadv2/scripts/tests/run-all.sh` (named in the original brief) still
  does not exist; the author's `tests/run-all.sh` is correct.
- **`render-proof.md`** — the review request and the round-2 "Done means" both point at
  `docs/handoff/ANTI-SILENCE-STATUSLINE-01/render-proof.md`. It exists in **neither** the lane
  worktree nor git. F11's prediction landed: the artifact was swept.
- **Flag semantics** — `LEADV2_STATUSLINE_SUPERVISOR_ONLY` defaults to `1`; with the supervisor
  retired the founder always takes the non-supervisor branch, which is the branch this diff changes.
  Consistent with the single-lead rule. No hook, loop, notifier or send door was added.

---

# Verdict

**BLOCK.** 2 Critical + 4 High + 3 Medium + 1 Low.

Round 2 is real work and it moved three of the four Criticals materially: the field-boundary control
now goes red under its own mutation (F1), the composer's `+N` no longer pushes the line past the
budget in the 30-200 range and its count is exact (F2/F3 on that path), and `break` + first-row
preservation are mutation-proven (F4).

It does not merge, for three reasons the round's own rules name:

1. **The founding incident is still reproducible.** N1: `rank=(cls=="live")?1:0` plus an unkeyed sort
   means a lane that finished cleanly takes the only narrow slot from a lane that crashed. At six
   widths the founder is shown `…·done·9m +2` while a `dead` lane hides behind the marker. The r1 fix
   changed which healthy lane wins, not that one does.
2. **Two of the new assertions survive their own mutation** (N2), one of them on the founder's live
   path where deleting a single assignment restores r1's F2 as a 64-character line at COLUMNS=60,
   green. The brief's rule was explicit and this is its second occurrence in two rounds.
3. **F3, F5, F7, F8 are untouched**, and F3's tail half is now *measured* rather than argued:
   `DROPPED_N=3` printed against 7 hidden lanes, with no assertion anywhere that can see it (N9).

Minimum to unblock: N1, N2, F3-tail (with N3's byte/char fix, which is the same code region), F5,
F7. N6 must be resolved before the `EXTRA_SUITE_MAP` rows land, or the gate blocks its own writeset.

DELIVERABLE_COMPLETE
