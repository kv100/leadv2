status: fail
reviewer_says: do_not_merge

# ANTI-SILENCE-STATUSLINE-01 — adversarial review r3

Lane: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ANTI-SILENCE-STATUSLINE-01` @ `981ca1b`
Round 3 is **one commit** (`981ca1b`, 5 files, +169/-24) on top of the r2 head `fe203b3`.

All mutations were applied to a `git archive 981ca1b` extraction under the scratchpad. The lane's
`plugins/` and `tests/` are byte-clean; each mutated scratch file was diffed IDENTICAL against
`981ca1b` after every revert (three integrity checks, all `IDENTICAL`).

## Suites, as run by me (not taken on trust)

```
plugins/leadv2/scripts/tests/test-statusline-readable.sh  (lane)             pass=37 fail=0 skip=0   [13.1s]
plugins/leadv2/scripts/tests/test-status-surface.sh       (lane)             70 passed, 21 failed    [21.3s]
plugins/leadv2/scripts/tests/test-statusline-readable.sh  (clean checkout)   pass=35 fail=0 skip=1
tests/run-all.sh --scope changed                          (lane)             3 passed, 1 failed
```

The lead's `pass=37 fail=0 skip=0` is real. It is also **+20 assertions of which 18 are two
length-only sweep loops**, and five of the nine round-3 fixes have no assertion that fails when the
fix is removed — including the Critical one.

---

# Prior findings — verdict table

| # | Finding | Verdict | Evidence |
|---|---|---|---|
| **F2** | budget exceeded by its own `+N` marker | **PARTIAL** | **ran** — composer is now exact at every required width (20→20, 22→22, 26→26, 30→30, 34→34, 60→60, 80→80, 120→120, 200→149). r2's `W=22 vis=23` is gone, and the fix **is controlled**: MUT-X (revert the conditional trailing space) → `[FAIL] F2 -- composer width 20 overflowed (21)`, `pass=34 fail=1`. **But** at W=20 the render is `lanes 5: …·dead·9 +4` — the age `9m` is cut to `9` (H3 below). |
| **F3** | dropped-count lies on the tail path | **PARTIAL** | **ran** — 35 distinct-Cyrillic tail renders (N=4/6/8/10/12 × W=40..120): `shown + N == total` in **35 of 35**. r2's `7 hidden, +3 printed` is dead. The *measure* is controlled (MUT-Y → RED). The *count* is **not**: MUT-V (`_lane_dropped = total - shown - 1`) leaves `pass=35 fail=0` (H1 below). |
| **F4** | silent lane dropped in favour of a live one | **PARTIAL** | **ran** — behaviourally fixed: rank is now `dead=0 · other=1 · live=2 · done=3` with `-k1,1n -k2,2`, and the name-adversarial fixture (`AAAFINISHEDCLEAN·done`, `ZZZCRASHEDLANE·dead`, `mmLIVELANEzz·live`) puts **dead first and present at W=22..200 in three different input orders**, byte-identical output each time. **But the only control is decorative** (C1) and **at W=20 no lane is shown at all** (H2). |
| **F5** | base cut mid-word, no marker, colour dropped | **NOT FIXED** | **ran + read** — `leadv2-lane-status-line.sh:275` is still `_base_out="${_base_out_plain:0:$_base_visible_budget}"`; measured cuts `Opus`, `Opus 5 i`, `Opus 5 in ~/`, `~/pr`, `Opu`. Worse, `:288-291` (the no-user-command branch) strips ANSI **unconditionally** whenever a lane digest exists — measured `ansi=no` at **W=200 with vis=149**, i.e. colour destroyed with 51 columns to spare. |
| **F7** | `width` assertion has 22 chars slack, measures ANSI | **NOT FIXED** | **read** — `test-statusline-readable.sh:480` byte-identical: `if (( ${#NARROW_LINE} <= 40 + ${#DEAD_ONLY_LINE} ))` → a 63-char ceiling on a 40-column budget. |
| **F8** | R1/R2 baseline is git-dependent, reverts to SKIP | **NOT FIXED** | **ran** — clean `git archive` checkout: `[SKIP] R1/R2 pre-fix baseline -- git archive of prior revision unavailable`, `pass=35 fail=0 skip=1`. Untouched this round. |
| **F9** | new subprocess spawns on a ≤100 ms path | **WORSE** | **ran** — 10 warm renders each: **tail 139.0 ms/render, composer 122.4 ms/render** (r2: 112-117 ms). This round *added* forks: `_surf_visible_len` (2 forks) is now called **once per removed character** in the shrink loop at `:236-238`, and `visible_len` **once per lane token** in the tail refit at `:1124`. |
| **N2** | fixes shipped with no control | **PARTIAL** | **ran** — MUT-C is fixed *and* controlled: applying it to the production composer gives `[FAIL] F2 -- composer width 20 overflowed (21)` + `[FAIL] F2 -- composer width 80 overflowed (82)`, `pass=33 fail=2`. MUT-B's "control" is a **source grep** and survives a behaviour-only mutation (C2). |
| **N3** | tail measures bytes, cuts characters | **PARTIAL** | **ran** — `visible_len()` is now bash `${#plain}` at `:172-176` and is controlled (MUT-Y → `[FAIL] F3 -- UTF-8 tail clamp width/count mismatch: lanes 8/5 один·?·1s два·?·2s +1`). **But no `LC_ALL`/`LANG` is set in any of the three scripts** and six `${var:0:N}` slices remain locale-dependent; measured silent truncation of multi-byte labels without an ellipsis (H5). |
| **N5** | shrink loop seeds at `…`, never grows | **PARTIAL — not fixed where it matters** | **ran + read** — the *tail's python* seed was fixed (`full_label_cap`), uncontrolled (MUT-W → green). The *surface's* `emit_oneline` seed at `leadv2-status-surface.sh:1722` is **unchanged** (`name_cap="…"`), measured: W=34, budget 25, render `…·dead·14m +2` = 13 chars — **12 columns unused and the lane name destroyed** (M1). |
| **N6** | RED suite newly on the CI blocking path | **NOT FIXED** | **ran** — `test-status-surface.sh` is still `70 passed, 21 failed`; the `EXTRA_SUITE_MAP` rows are still in `tests/run-all.sh:137-139`; the commit message is a bare one-line subject with an empty body, and no handoff note explains the 21. Additionally the row now **fails to select at all** after a commit (M3). |

---

# New assertions — which I mutation-tested, and whether each held

Nine mutations, each applied to the scratch **production** file (never to the test), suite re-run,
file restored and diffed IDENTICAL.

| Assertion under test | Mutation | Result |
|---|---|---|
| `F4: width-26 oneline shows dead lane before done lane` | **MUT-R**: `rank=(cls=="dead")?0:(cls=="live")?2:(cls=="done")?3:1` → `rank=(cls=="live")?1:0`, and `-k1,1n -k2,2` → `-k1,1n` (a full revert of the round's Critical fix) | **SURVIVED — still `[TEST] PASS: F4 …`, `70 passed, 21 failed`** |
| `MUT-B RED: production marker reservation is non-zero` | **MUT-B2**: `marker_len=${#marker}` → `marker_len=0`, with the literal string re-added on the next line as a comment | **SURVIVED — `70 passed, 21 failed`**, identical to unmutated |
| `F2: composer width 20..200 is exact/smaller` (9) | **MUT-X**: revert `_surf_tail` conditional space to the unconditional `"$_surf_trimmed "` | **HELD** — `[FAIL] F2 -- composer width 20 overflowed (21)`, `pass=34 fail=1` |
| `MUT-C RED: zero composer marker overflows` | **MUT-C** applied to the production composer | **HELD** — `pass=33 fail=2` (F2@20 and F2@80) |
| `F3: UTF-8 tail clamp fits 60 with exact +5` | **MUT-Y**: `visible_len()` body → `sed … \| awk '{print length}'` (bytes) | **HELD** — `pass=34 fail=1` |
| `F2/F5: tail width 20..200` (9) | **MUT-Z**: delete the `+N` reservation from the tail refit admission test (`_lane_marker=""`) | **SURVIVED — `pass=35 fail=0`** |
| `F2/F5: tail width 20..200` (9) | **MUT-U**: delete the ANSI strip before the degenerate-width base clip (slice the raw coloured string) | **SURVIVED — `pass=35 fail=0`** |
| `F3` + `F2/F5` sweeps | **MUT-V**: `_lane_dropped=$(( _lane_total - _lane_shown - 1 ))` at `:1127` | **SURVIVED — `pass=35 fail=0`** |
| (tail label seed) | **MUT-W**: `full_label_cap = max([...])` → `full_label_cap = LABEL_CAP` | **SURVIVED — `pass=35 fail=0`** |

**4 held, 5 survived.** The two that survived on the *test* side (MUT-R, MUT-B2) are the two
assertions this round added specifically to satisfy the brief's Critical and High items.

---

# New findings

## CRITICAL

### C1 — The control for the round's Critical fix survives a full revert of that fix
`plugins/leadv2/scripts/tests/test-status-surface.sh:1687-1694`

```bash
F4_ONELINE="$(LEADV2_STATUSLINE_WIDTH=26 run_render --oneline)"
if [[ "$F4_ONELINE" == *'·dead·'* ]] && [[ "$F4_ONELINE" != *'·done·'* ]]; then
```

The fixture it runs against is the pre-existing OUTCOME-3 pair: `oc3doneeeeeee` (done) and
`oc3deadeeee` (dead). `oc3deadeeee` sorts **before** `oc3doneeeeeee` lexicographically, so r2's code
— `rank=(cls=="live")?1:0` with an unkeyed `sort`, where both rows are rank 0 and fall back to
whole-line lexicographic order — already puts the dead lane first. Measured:

```
$ perl -0pi -e 's/rank=\(cls=="dead"\)\?0:\(cls=="live"\)\?2:\(cls=="done"\)\?3:1/rank=(cls=="live")?1:0/g;
                s/-k1,1n -k2,2/-k1,1n/g'  leadv2-status-surface.sh          # full revert to r2
$ bash plugins/leadv2/scripts/tests/test-status-surface.sh
[TEST] PASS: F4: width-26 oneline shows dead lane before done lane (lanes 2: …·dead·5m +1)
[TEST] === 70 passed, 21 failed ===
```

**Failure scenario:** the next author simplifies the rank expression, or a refactor drops `-k2,2`,
and the founding incident returns green. The fix itself is real — my name-adversarial harness
(`AAAFINISHEDCLEAN·done` vs `ZZZCRASHEDLANE·dead`) confirms dead-first at W=22..200 across three
input orders — but **nothing in the repo can tell the fix apart from its absence.** The brief's rule
was literal: *"Every fix gets an assertion that fails when the fix is removed, and you RUN it."* This
is the third round in which the Critical fix ships uncontrolled.

**Required fix:** make the fixture name-adversarial — the `done` lane's id must sort *before* the
`dead` lane's id — and assert the *first* token's class is `dead`, not merely that no `done` token
appears. Add `queued` and `live` arms to the same fixture.

### C2 — The new "MUT-B" assertion is a source grep, and its runtime half is dead code
`plugins/leadv2/scripts/tests/test-status-surface.sh:1951-1979`

The block copies the renderer, mutates it, sweeps `seq 20 80` looking for an over-budget render,
assigns the result to `MUT_B_RED` — and then **never reads `MUT_B_RED`**. The pass/fail condition is:

```bash
if grep -q 'marker_len=${#marker}' "$RENDER"; then
  pass "MUT-B RED: production marker reservation is non-zero"
```

with a comment that pre-emptively defends this ("deliberately source-level … even in a fixture whose
next token happens not to fit"), i.e. the author observed the runtime half not firing and shipped
the grep instead. Proven:

```
# MUT-B2: behaviour broken, the literal string preserved as a comment
      marker=" +${remaining}"; marker_len=0
      # invariant: marker_len=${#marker}

[TEST] PASS: MUT-B RED: production marker reservation is non-zero
[TEST] === 70 passed, 21 failed ===        <-- identical to unmutated
```

and the same mutated production renderer, driven through the real `emit_oneline`:

```
W=20   len=22   |lanes 3: …·dead·14m +2|     over budget by 2
W=21   len=22   |lanes 3: …·dead·14m +2|     over budget by 1
W=34   len=35   |lanes 3: ZZZCRASHEDLANE·dead·14m +2|   over budget by 1
```

**Failure scenario:** anyone who rewrites the reservation in an equivalent but differently-spelled
form (`marker_len=$(( ${#remaining} + 2 ))`) turns this assertion RED for no reason; anyone who
breaks the reservation while leaving the literal anywhere in the file — including a comment — keeps
it GREEN while the statusline soft-wraps. A false control in both directions.

**Required fix:** use `MUT_B_RED`. If the 12-identical-lane fixture cannot produce an overflow, the
fixture is wrong: build one whose next token ends at `budget - 2` so the marker straddles the
boundary, and assert `[ -n "$MUT_B_RED" ]`. Delete the grep.

## HIGH

### H1 — Four round-3 fixes have no control at all
`leadv2-lane-status-line-tail.sh:1121-1123` (`+N` reservation in the refit loop),
`:1127` (`_lane_dropped`), `:1135-1137` (ANSI strip before the base clip), `:912` (`full_label_cap`).

MUT-Z, MUT-V, MUT-U and MUT-W each leave `pass=35 fail=0 skip=1`. Two of these are the exact
properties the round-3 brief named: *"make its dropped-count exact. **Control on both halves**"* and
*"Never cut inside an ANSI escape sequence."* MUT-V is r2's **N9** verbatim, still open.

**Failure scenario for MUT-V specifically:** the tail's `+N` under-reports by one on every render
where any lane is hidden — the founder sees `+3` with four lanes hidden, which is the exact bug F3
was filed for — and the suite is green.

**Required fix:** one assertion per fix. For the count: a fixture with a known lane total asserting
`visible_tokens + N == total` at several widths (my probe does this in 8 lines and catches MUT-V
immediately). For the ANSI strip: assert `$'\033'` is absent from the base once it has been clipped.
For the reservation: a fixture whose next token straddles the budget boundary.

### H2 — At COLUMNS=20 the surface answers "did a lane die?" with silence
`plugins/leadv2/scripts/leadv2-status-surface.sh:1718-1731`

Measured through the real `emit_oneline`, fixture = 1 dead + 1 done + 1 live:

```
W=20   len=11   |lanes 3: +3|            <<< no lane, no class, no name
W=22   len=22   |lanes 3: …·dead·14m +2|
```

`budget = 20 - 7 - 2 = 11`; `suffix_len = 4 + 3 + 2 = 9`; `marker_len = 3`. The first-row branch
shrinks `name_cap` to the empty string, `9 + 3 = 12 > 11` still holds, `toks` stays empty and the
digest collapses to `+3`. A 3-character marker crowds out the 10-character token `…·dead·14m` that
*would* have fitted in the 11-column budget.

**Failure scenario:** a narrow IDE panel or split pane at 20 columns. Three lanes, one crashed, and
the statusline says `lanes 3: +3`. The brief's acceptance criterion is "a **dead** lane present and
**first** at every width" over the list `20/22/26/…`; at 20 it is neither.

**Required fix:** when `n_shown` would end at 0, drop the marker before dropping the row — the row is
the payload, the marker is the annotation.

### H3 — The composer corrupts the age field at narrow widths
`plugins/leadv2/scripts/leadv2-lane-status-line.sh:235-238`

```bash
_surf_suffix="·${_surf_tok#*·}"          # e.g. "·dead·9m"
_surf_tok="…${_surf_suffix}"
while (( $(_surf_visible_len "…") > _surf_budget && ${#_surf_tok} > ${#_surf_suffix} )); do
  _surf_tok="${_surf_tok:0:${#_surf_tok}-1}"        # cuts from the RIGHT
done
```

Once the label is already `…` (1 char), the loop keeps shrinking — and it shrinks the **right-hand
end**, i.e. the suffix, not the label. Measured on the founder's live path:

```
W=20   vis=20   |lanes 5: …·dead·9 +4|
```

`9m` has become `9`. A nine-**minute**-old dead lane renders as `9`, which in this grammar reads as
nine seconds. That is a value corruption, not a cosmetic cut, and it is exactly the mid-token
truncation R12 exists to forbid — but R12 runs only against the tail at widths 80 and 112.

**Failure scenario:** the founder glances at a 20-column pane, reads `dead·9`, assumes the lane died
seconds ago and is mid-restart, and does not intervene on a lane dead for nine minutes.

**Required fix:** stop the loop before the first suffix character is removed (the guard
`${#_surf_tok} > ${#_surf_suffix}` is off by one because `…`+suffix is `1 + len(suffix)`), or drop
the row entirely when even `…·cls·age` does not fit.

### H4 — F5: colour is destroyed at every width, and cuts still land mid-word
`plugins/leadv2/scripts/leadv2-lane-status-line.sh:275` and `:288-291`

The user-command branch (`:274-276`) now strips+slices only when over budget — an improvement — but
the slice is still a raw `${plain:0:N}` with no boundary back-off and no marker.

The **no-user-command branch** (`:288-291`) is worse: it strips ANSI **unconditionally** whenever
`_surf_tail` is non-empty, then slices, with no over-budget test at all. Measured, and this is the
branch the suite's own composer fixture exercises:

```
W=200  vis=149  ansi=no   |lanes 5: SILENT-LANE-THAT-MUST-REMAIN·dead·9m … Opus 5 in ~/proj [style] 50% ctx|
```

51 columns of headroom, nothing truncated, every colour code removed. Mid-word cuts at
20/26/30/34/80/120: `9`, `Opus`, `Opus 5 i`, `Opus 5 in ~/`, `~/pr`, `Opu`.

**Required fix:** guard `:288-291` with the same `if (( ${#plain} > budget ))` its sibling has, and
back both slices off to the last whitespace boundary with an explicit `…`.

### H5 — Multi-byte lane labels are truncated silently, and no locale is pinned
`leadv2-lane-status-line-tail.sh` (no `LC_ALL`), `leadv2-lane-status-line.sh:238,253,275,291`,
`leadv2-status-surface.sh:1706,1723`

`grep -n 'LC_ALL\|LANG=' ` over all three scripts returns **nothing**. Every `${var:0:N}` in the diff
is character-based only if the inherited locale is UTF-8. Measured on this host with distinct
Cyrillic lane names:

```
N=4  W=40   lanes 4/5 альф·?·1s +3
N=4  W=50   lanes 4/5 альф·?·1s бет·?·2s +2
N=4  W=70   lanes 4/5 альф·?·1s бет·?·2s гамм·?·3s дельт·?·4s
```

`альфа`→`альф`, `бета`→`бет`, `гамма`→`гамм`, `дельта`→`дельт` — each loses its last character **with
no `…`**, while the same code path emits `ал…` for the 10-lane fixture. A silently shortened label is
indistinguishable from a real lane of that name.

**Failure scenario, and it is the live one:** the composer's memo refresher is detached with
`setsid`, which is why `LEADV2_STATUSLINE_WIDTH` has to be exported explicitly (`:296-298` comment).
A detached process inherits a stripped environment; under `LC_ALL=C` every one of those six slices
becomes a **byte** slice and will cut a two-byte Cyrillic codepoint in half, emitting a replacement
glyph into the founder's statusline. r2 filed this as F14; round 3 named byte-vs-char in three
commit comments and still did not set the locale.

**Required fix:** `export LC_ALL="${LC_ALL:-C.UTF-8}"` at the top of all three scripts, and make the
label capper emit `…` whenever it shortened.

### H6 — F7 and F8 are untouched
`test-statusline-readable.sh:480` and `:115-130`. Read + ran; see the table. Both were named
explicitly in the round-3 brief under "[High] F5 / F7 / F8 — not fixed" and neither line changed.

## MEDIUM

### M1 — `emit_oneline` still throws away 8-12 columns of lane identity
`leadv2-status-surface.sh:1722` — `name_cap="…"` seed, unchanged from r2. Measured:

```
W=30   len=22   |lanes 3: …·dead·14m +2|    budget 21, used 13 —  8 columns unused
W=34   len=22   |lanes 3: …·dead·14m +2|    budget 25, used 13 — 12 columns unused
```

`ZZZCRASHEDL…·dead·14m +2` (24 chars) fits the 25-column budget at W=34. The round-3 commit fixed the
analogous seed in the *tail's* python (`full_label_cap`) and left the surface's alone. The founder's
narrow pane names no lane while a third of the field is blank.

### M2 — The tail under-fills badly between 45 and 106 columns
Measured with the suite's own 4-lane fixture:

```
W=60   vis=45   |lanes 4/5 dispatch-…·?·1s +3 | Opus 5 in repo|
W=80   vis=45   |lanes 4/5 dispatch-…·?·1s +3 | Opus 5 in repo|
W=120  vis=106  |lanes 4/5 dispatch-c9…·?·1s dispatch-5b…·?·1s GATE-FOREIG…·?·2s LANDING-PAG…·?·8s | …|
```

At 80 columns three of four lanes are hidden and **35 columns sit empty**. This is r1's F12 shape,
now measured at the width the founder actually runs. Nothing asserts a lower bound on fill, so the
length-only sweeps cannot see it.

### M3 — `--scope changed` selects the statusline suites only while the edit is uncommitted
`tests/run-all.sh:133-135`

```bash
changed="$(git -C "${ROOT}" diff --name-only HEAD 2>/dev/null)"
if [[ -z "${changed}" ]] && git … rev-parse HEAD~1 …; then
  changed="$(git … diff --name-only HEAD~1..HEAD)"
fi
```

The `HEAD~1..HEAD` fallback fires only when the working tree is **entirely** clean. In any real lane
worktree the leadv2 control plane is permanently dirty — measured here, `git diff --name-only HEAD |
wc -l` = **21** files (`docs/leadv2/bus.jsonl`, `active.yaml`, journals…), none matching
`plugins/leadv2/scripts/*.sh`. So after the author commits, the map rows go inert:

```
$ bash tests/run-all.sh --scope changed
run-all: 3 passed, 1 failed, scope=changed
  Failures (blocking):
    - plugins/leadv2/scripts/tests/run-core-offline.sh
```

Neither `test-statusline-readable.sh` nor `test-status-surface.sh` was selected. N6's premise ("CI
now selects the suite") holds only pre-commit; post-commit it selects neither, and CI is red anyway
for the pre-existing `run-core-offline.sh` failure (also red at r2).

### M4 — The 9 `F2/F5: tail width N` assertions pass on empty output and do not test F5
`test-statusline-readable.sh:562-570`

```bash
if (( $(visible_len "$_tail_out") <= _tail_w )); then ok "F2/F5: tail width $_tail_w …"
```

`visible_len ""` is `0`, and `0 <= W` for all W — a tail that fails to launch is green. I hit this
accidentally: when `$SCRATCH_SCRIPTS` resolved empty, all nine printed `[PASS]` while stderr carried
`bash: /scripts/leadv2-lane-status-line-tail.sh: No such file or directory`. They are also named for
**F5** and test neither of F5's properties (no ANSI-presence check, no mid-word check).

**Required fix:** add `[ -n "$_tail_out" ]` and a lower bound; rename them, or make them assert what
F5 is about.

### M5 — The MUT-B block leaves the shared fixture mutated and burns ~10 s per suite run
`test-status-surface.sh:1955-1967` overwrites `${STATE_DIR}/active.yaml` with 12 `mutb*` sessions and
never restores it, then runs **61** full renders (`seq 20 80`) whose only output is a variable that
is never read. Every later assertion in that file inherits the fixture.

### M6 — F9: per-render cost grew, and now scales with lane count
139.0 ms (tail) / 122.4 ms (composer), measured over 10 warm renders each, against r2's 112-117 ms.
`leadv2-lane-status-line.sh:236-238` calls `_surf_visible_len` — a command substitution wrapping
`printf | sed`, i.e. **2 forks** — once per *removed character*, in a loop that shrinks one character
at a time; `leadv2-lane-status-line-tail.sh:1124` calls `visible_len` once per lane token. r2 used
`${#...}` there, which forks nothing. A pure-bash ANSI strip or one precomputed length restores it.

## LOW

### L1 — The round's own required artifacts are missing or stale
`docs/handoff/ANTI-SILENCE-STATUSLINE-01/round3-red/` does **not exist** (the brief: "RED logs under
…/round3-red/"). `render-proof.md` exists but is **untracked** (`git ls-files` on the handoff dir
returns nothing) and **stale**: it reports `pass=16 fail=0 skip=0` against a suite that now reports
37, covers only widths 80/120/200, and predates the rank change it is supposed to evidence.

### L2 — The tiebreaker is the lane name, not urgency
`leadv2-status-surface.sh:1683,1688` — `-k2,2` makes the sort total and order-independent (verified:
identical output for three input permutations), but among several `dead` lanes it shows the
alphabetically-first, not the longest-dead. Two crashed lanes, the founder sees `AAA-…` and never
`ZZZ-…`.

### L3 — r2's N7 / N8 / N10 are untouched
R12's class whitelist still omits `live` (`test-statusline-readable.sh:259`); the composer still
takes `_surf_budget="${LEADV2_STATUSLINE_WIDTH:-${COLUMNS:-80}}"` raw at `:211` while `emit_oneline`
sanitises the same pair at `:1670`; the composer's else-branch backoff at `:253` is still
uncontrolled.

---

# Renders at the required widths, verbatim

`vis` = visible characters after ANSI stripping (Python `len`, so `·` and `…` count 1).

**A. Composer — the founder's live path.** Real `leadv2-lane-status-line.sh`,
`LEADV2_STATUSLINE_SUPERVISOR_ONLY=1`, memo
`lanes 5: SILENT-LANE-THAT-MUST-REMAIN·dead·9m live-one·live·1s live-two·live·2s live-three·live·3s live-four·live·4s`.

```
W=20   vis=20   ansi=no   |lanes 5: …·dead·9 +4|                      <<< age corrupted (H3)
W=22   vis=22   ansi=no   |lanes 5: …·dead·9m +4 |
W=26   vis=26   ansi=no   |lanes 5: …·dead·9m +4 Opus|
W=30   vis=30   ansi=no   |lanes 5: …·dead·9m +4 Opus 5 i|
W=34   vis=34   ansi=no   |lanes 5: …·dead·9m +4 Opus 5 in ~/|
W=60   vis=60   ansi=no   |lanes 5: SILENT-LANE-THAT-MUST-REMAIN·dead·9m +4 Opus 5 in ~|
W=80   vis=80   ansi=no   |lanes 5: SILENT-LANE-THAT-MUST-REMAIN·dead·9m live-one·live·1s +3 Opus 5 in ~/pr|
W=120  vis=120  ansi=no   |lanes 5: SILENT-LANE-THAT-MUST-REMAIN·dead·9m live-one·live·1s live-two·live·2s live-three·live·3s live-four·live·4s Opu|
W=200  vis=149  ansi=no   |lanes 5: SILENT-LANE-THAT-MUST-REMAIN·dead·9m live-one·live·1s live-two·live·2s live-three·live·3s live-four·live·4s Opus 5 in ~/proj [style] 50% ctx|
```

Never over budget (F2 fixed, controlled). `+N` exact at every width (1+4 ×6, 2+3, 5+0, 5+0). A `dead`
lane present and first at every width. Colour gone at **every** width including 200 (H4); base cut
mid-word at 26/30/34/80/120 (H4); age corrupted at 20 (H3).

**B. `emit_oneline` — name-adversarial 3-lane fixture** (`AAAFINISHEDCLEAN·done`,
`ZZZCRASHEDLANE·dead`, `mmLIVELANEzz·live`), the r2 N1 reproduction:

```
W=20   len=11   |lanes 3: +3|                                          <<< no dead lane at all (H2)
W=22   len=22   |lanes 3: …·dead·14m +2|
W=26   len=22   |lanes 3: …·dead·14m +2|
W=30   len=22   |lanes 3: …·dead·14m +2|
W=34   len=22   |lanes 3: …·dead·14m +2|
W=60   len=55   |lanes 3: ZZZCRASHEDLANE·dead·14m mmLIVELANEzz·live·- +1|
W=80   len=77   |lanes 3: ZZZCRASHEDLANE·dead·14m mmLIVELANEzz·live·- AAAFINISHEDCLEAN·done·9m|
W=120  len=77   |same as 80|
W=200  len=77   |same as 80|
```

Identical output for input orders `done,dead,live` / `live,done,dead` / `dead,live,done` — the sort
is total. r2's `lanes 3: …·done·9m +2` is gone at every width ≥ 22.

**C. Production tail**, the suite's 4-lane fixture:

```
W=20   vis=20   ansi=yes  |lanes 4/5 +4 | Opus |
W=22   vis=22   ansi=yes  |lanes 4/5 +4 | Opus 5 |
W=26   vis=26   ansi=yes  |lanes 4/5 +4 | Opus 5 in r|
W=30   vis=29   ansi=yes  |lanes 4/5 +4 | Opus 5 in repo|
W=34   vis=29   ansi=yes  |lanes 4/5 +4 | Opus 5 in repo|
W=60   vis=45   ansi=yes  |lanes 4/5 dispatch-…·?·1s +3 | Opus 5 in repo|
W=80   vis=45   ansi=yes  |lanes 4/5 dispatch-…·?·1s +3 | Opus 5 in repo|
W=120  vis=106  ansi=yes  |lanes 4/5 dispatch-c9…·?·1s dispatch-5b…·?·1s GATE-FOREIG…·?·2s LANDING-PAG…·?·8s | Opus 5 in repo 79% ctx|
W=200  vis=196  ansi=yes  |lanes 4/5 dispatch-c9…·?·1s dispatch-5b…·?·1s GATE-FOREIG…·?·2s LANDING-PAG…·?·8s | Opus 5 (1M context) in /var/…/repo 79% ctx|
```

Never over budget. Under-fills at 60/80 (M2); base cut mid-word at 20/22/26 (H4).

**D. Tail dropped-count, distinct Cyrillic labels** — 35 renders, `shown + N == total` in 35/35.
Excerpt:

```
N=8   W=60   vis=50   shown=2  +6   OK   lanes 8/5 альфа·?·1s бета·?·2s +6
N=10  W=80   vis=74   shown=4  +6   OK   lanes 10/5 альфа·?·1s бета·?·2s гамма·?·3s дельта·?·4s +6
N=12  W=100  vis=98   shown=6  +6   OK   lanes 12/5 альфа·?·1s … дзета·?·6s +6
N=12  W=120  vis=117  shown=8  +4   OK   lanes 12/5 альфа·?·1s … тета·?·8s +4
```

r2's `TAILCLAMP W=80 … DROPPED_N=3` against 7 hidden lanes is fixed. Labels silently shortened
without `…` at N=4 (H5).

---

# Static checks (raw output)

No Python or TypeScript in this diff; `bash -n` and `shellcheck` are the equivalent gates.

```
$ for f in $(git diff --name-only 91c9919..981ca1b); do printf '%-58s ' "$f"; bash -n "$f" && echo OK; done
plugins/leadv2/hooks/leadv2-codex-first-nudge.sh             OK
plugins/leadv2/scripts/leadv2-lane-status-line-tail.sh       OK
plugins/leadv2/scripts/leadv2-lane-status-line.sh            OK
plugins/leadv2/scripts/leadv2-status-surface.sh              OK
plugins/leadv2/scripts/tests/test-status-surface.sh          OK
plugins/leadv2/scripts/tests/test-statusline-readable.sh     OK
tests/run-all.sh                                             OK

$ shellcheck -S warning -e SC1090,SC1091,SC2034 \
    plugins/leadv2/scripts/leadv2-lane-status-line.sh \
    plugins/leadv2/scripts/leadv2-status-surface.sh \
    plugins/leadv2/scripts/leadv2-lane-status-line-tail.sh
leadv2-lane-status-line.sh      (no output — clean)
leadv2-status-surface.sh        (no output — clean)
leadv2-lane-status-line-tail.sh:676  SC2140 ×2 / SC1078  — inside the embedded python heredoc
leadv2-lane-status-line-tail.sh:939  SC2140              — inside a comment
leadv2-lane-status-line-tail.sh:940  SC2140 ×2           — inside a comment
```

The three tail hits are shellcheck mis-parsing an embedded python block and two comments; not
charged against the diff.

---

# Contradiction scan

- **Comment vs code, tail `:1107`** — *"Character accounting matches visible_len above, including
  UTF-8 labels; **no raw slice can land in a word** or ANSI escape."* Twenty-nine lines later,
  `:1136`: `FINAL_BASE="${FINAL_BASE:0:_base_budget}"` — a raw slice that lands in a word at
  W=20/22/26 (`Opus `, `Opus 5 `, `Opus 5 in r`). **CONTRADICTION.**
- **Comment vs code, `test-status-surface.sh:1971`** — *"This invariant is deliberately source-level
  **as well as runtime**"*, but the runtime half (`MUT_B_RED`) is never read. **CONTRADICTION (C2).**
- **Commit subject vs code** — "prioritize dead lanes and **character** budgets", while no `LC_ALL`
  is set and six `${var:0:N}` slices remain byte-based under a C locale. **CONTRADICTION (H5).**
- **Assertion name vs content** — nine assertions named `F2/F5` test neither F5 property. **MISLABEL
  (M4).**
- **Test helper vs production — RESOLVED.** r2's contradiction (helper counts chars, production
  counts bytes) is gone: `visible_len` in the tail is now the same `${#plain}` form as the helper,
  and MUT-Y proves it.
- **`render-proof.md` vs the suite** — the artifact reports `pass=16 fail=0 skip=0`; the suite
  reports 37. **STALE (L1).**
- **Path existence** — `round3-red/` **absent**. The three `EXTRA_SUITE_MAP` paths all exist. The
  handoff dir contains only `channel-verdict.md`, `lane-mission-2.md`, `render-proof.md`, all
  untracked.
- **Flag semantics** — `LEADV2_STATUSLINE_SUPERVISOR_ONLY` still defaults to `1`, and the
  non-supervisor branch is still the one this diff changes; `LEADV2_STATUSLINE_WIDTH` vs `COLUMNS`
  precedence is consistent between composer and surface, except that only the surface validates it
  (L3). No hook, loop, notifier or send door was added.
- **Rank semantics** — `dead(0) < other(1) < live(2) < done(3)`, so `queued`/`stale`/`?` now outrank
  `live`. I could not synthesise a `queued` row (my no-ledger sessions classified as `dead`), so this
  is **UNVERIFIED**: if `queued` lanes are common on the board, several of them will push running
  lanes off a narrow line. Worth one fixture before merge.

---

# Verdict

**BLOCK.** 2 Critical + 6 High + 6 Medium + 3 Low.

Round 3 is the strongest of the three rounds on *behaviour*. Four things are genuinely fixed and
genuinely measured: the urgency rank puts a dead lane first at every width ≥22 and the sort is total
across input permutations; the composer is exact at 20-200 with an exact `+N`; the tail's
dropped-count reconciles in 35 of 35 Cyrillic renders; and three fixes (MUT-X, MUT-C, MUT-Y) are
mutation-proven RED.

It does not merge, for the reason the round was sent back the last two times:

1. **The Critical fix's only control is decorative.** Reverting the rank expression *and* the sort
   key — a complete rollback to r2's founding-incident code — leaves `F4: width-26 oneline shows dead
   lane before done lane` **passing**, because the fixture's ids happen to sort dead-first anyway.
2. **The High fix's control is a `grep` of the source**, whose runtime half is dead code the author's
   own comment admits did not fire. Breaking the behaviour while leaving the literal string in a
   comment keeps the suite at `70 passed, 21 failed` while the surface renders 22 characters at
   COLUMNS=20.
3. **Four more fixes landed with no control at all** (MUT-Z, MUT-V, MUT-U, MUT-W all green), two of
   them the exact properties the brief named — "make its dropped-count exact, control on both halves"
   and "never cut inside an ANSI escape".
4. **Three new defects are measurable on the founder's line**: `lanes 3: +3` with no dead lane at
   COLUMNS=20; `·dead·9` where the age is `9m`; and colour stripped from the base at every width
   including 200 with 51 columns to spare.
5. **F5, F7, F8 are byte-identical to r2**, having been listed as "[High] not fixed" in the round-3
   brief.

Minimum to unblock: C1, C2, H1 (the four missing controls), H2, H3, H4. F7/F8 are cheap and have now
been carried for two rounds. M3 changes N6's story and should be stated in the commit message rather
than fixed here.

DELIVERABLE_COMPLETE
