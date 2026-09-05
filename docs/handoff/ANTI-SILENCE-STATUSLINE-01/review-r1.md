status: fail
reviewer_says: do_not_merge

# ANTI-SILENCE-STATUSLINE-01 — adversarial review r1

Lane: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ANTI-SILENCE-STATUSLINE-01` @ `8ad022f`

## Suites, as run by me

```
plugins/leadv2/scripts/tests/test-statusline-readable.sh   pass=16 fail=0 skip=0   (in the lane)
plugins/leadv2/scripts/tests/test-statusline-readable.sh   pass=14 fail=0 skip=1   (clean checkout — R1/R2 skip)
plugins/leadv2/scripts/tests/test-status-surface.sh        66 passed, 21 failed
```

The 21 `test-status-surface.sh` failures are **pre-existing**, not a regression: at the lane
anchor `91c9919` the same suite is `62 passed, 21 failed`. This diff adds 4 passing assertions
and fixes none of the 21. Not charged against this diff.

## Requirements

| # | Requirement | Verdict | Evidence |
|---|---|---|---|
| 1 | Lanes render FIRST; zero lanes -> short explicit token | **MET** | ran — ordering mutation goes RED (2 fails); `emit_oneline` prints bare `lanes 0` at `LANE_COUNT<=0` (leadv2-status-surface.sh:1673-1679) |
| 2 | A silent/dead lane is the most prominent field | **UNMET** | ran — at narrow widths the silent lane is dropped and a *live* lane rendered instead (F4) |
| 3 | Budgeted to width; never cuts mid-word; names dropped count | **UNMET** | ran — budget exceeded (63>60, 39>38); base cut mid-word on every render; dropped-count reports 3 where 5 are hidden |
| 4 | Quotas shrink or vanish when lanes are live | **MET** | ran — base goes empty->13->5->full across COLUMNS 40/80/120/200 |
| 5 | No hook / loop / notifier / send door added | **PARTIAL** | read — none added; but an out-of-writeset hook file was edited (F10) |

---

# Findings

## CRITICAL

### F1 — The field-boundary cut, the entire reason this finisher round exists, has NO executing control
`plugins/leadv2/scripts/tests/test-statusline-readable.sh:242-257` (R12)

The finisher brief was explicit: *"Negative control for the boundary fix: remove the field-boundary
cut, show R12 RED, revert, show GREEN."* I ran that mutation. **It does not go red.**

```
=== MUTATION 2: remove the field-boundary backoff (tail hard clamp) ===
1098c1098
<     [[ "$TRIMMED" == *" "* ]] && TRIMMED="${TRIMMED% *}"
---
>     : # MUTATED: field-boundary backoff removed
--- RED run ---
pass=14 fail=0 skip=1          <-- STILL GREEN
```

Same result for the composer's copy of the same fix on the founder's live path:

```
=== MUTATION 3: remove boundary backoff in the COMPOSER (founder live path) ===
216c216
<       [[ "$_surf_trimmed" == *" "* ]] && _surf_trimmed="${_surf_trimmed% *}"
---
>       : # MUTATED
pass=14 fail=0 skip=1          <-- STILL GREEN
```

This is not "the branch never runs". I instrumented it — the clamp branch executes **6 times**
during the suite, including once at exactly the width R12 inspects:

```
=== widths where the hard clamp fires during the suite ===
   4 clamp at width=112
   1 clamp at width=200
   1 clamp at width=80
```

The reason R12 cannot discriminate is its glob at line 249:
`*·[a-z?]·[0-9]*` accepts **any** prefix before the first `·`. A raw character slice that leaves
the `·arm·age` tail intact matches the "healthy token" pattern and passes. R12 only rejects a
fragment with no `·arm·` structure at all — a narrow subset of mid-word cuts.

**Required fix:** R12 must compare the rendered lane tokens against the *known fixture lane names*
(every shown label must be a prefix-with-`…` of a real lane id, or the `+N` marker), not a shape
glob. Then re-run both mutations above and show them RED.

### F2 — The width budget is computed and then exceeded on the live path
`plugins/leadv2/scripts/leadv2-lane-status-line.sh:211-222`

`_surf_trimmed="${_surf_oneline:0:$_surf_budget}"` slices to budget, then backs off to a word
boundary, then appends ` +${_surf_dropped_n}` — **after** the budget check, unaccounted. When the
backoff recovers fewer characters than the marker costs, the line overflows.

Measured, real render through `leadv2-lane-status-line.sh`:

```
W=60  vis=63  LANE-SEG: lanes 7: AAAAAAAAAAAAAAA·silent·14m BBBBBBBBBBBBBBB·live·9m +3
                ^^^^^^ 3 characters OVER the requested budget
```

Failure scenario: founder's IDE terminal panel is 60 columns. The statusline emits 63 visible
characters, the panel soft-wraps, and the line he was told is budgeted eats two rows — which is
the original complaint (an unreadable, overflowing status line), reintroduced by the fix for it.

**Required fix:** reserve the marker width *before* selecting tokens — compute
`budget - len(" +N")` as the token budget whenever `dropped > 0`, then fit.

### F3 — The dropped-count lies: it counts the upstream `+M` marker as one lane
`plugins/leadv2/scripts/leadv2-lane-status-line.sh:216-220`

```bash
_surf_dropped_rest="${_surf_oneline:${#_surf_trimmed}}"
_surf_dropped_n="$(printf '%s' "$_surf_dropped_rest" | tr -s ' ' '\n' | grep -c . || true)"
```

This counts whitespace-delimited **tokens**, not lanes. `emit_oneline` has already appended its own
`+M` token when it dropped lanes upstream. When the composer's clamp then trims across that marker,
the literal `+2` string is counted as *one* dropped lane, and the two lanes it represented are
silently discarded.

Measured — memo is 7 lanes, 4 listed plus an upstream `+2`:

```
W=60  LANE-SEG: lanes 7: AAAAAAAAAAAAAAA·silent·14m BBBBBBBBBBBBBBB·live·9m +3
W=75  LANE-SEG: lanes 7: AAAAAAAAAAAAAAA·silent·14m BBBBBBBBBBBBBBB·live·9m +3
```

2 lanes shown, marker says `+3`. **Actual hidden: 5.** The count is wrong by 2 and swallows the
upstream marker's information entirely.

Failure scenario: 7 lanes, 2 visible, line claims 3 more. The founder reads "5 lanes accounted
for", closes the panel, and 2 lanes — possibly the silent ones — are invisible with no signal that
anything is missing. This is precisely the "dropped-count that lies" shape.

**Required fix:** parse a trailing `+M` out of the incoming digest and add `M` to the newly-dropped
lane count; count lane *tokens* (those containing `·`), never all whitespace tokens.

### F4 — A silent lane is dropped in favour of a live one (requirement 2 defeated)
`plugins/leadv2/scripts/leadv2-status-surface.sh:~1706-1709`

```bash
if [ $(( cur_len + tlen )) -gt "$budget" ]; then
    n_dropped=$(( n_dropped + 1 ))
    continue          # <-- skips this lane, keeps admitting later, shorter ones
fi
```

The sort correctly ranks non-live lanes first. The greedy fitter then **`continue`s** past a
silent lane whose token does not fit and admits a later, shorter *live* lane. Prominence-by-sort
is undone by fit-by-length.

Measured, driving `emit_oneline` directly (one long-named silent lane, four short live lanes):

```
W=30  len=26  lanes 5: shortA·live·1s +4
W=34  len=26  lanes 5: shortA·live·1s +4
W=38  len=39  lanes 5: VERYLONGLANENAM…·silent·14m +4
```

At W=30 and W=34 the **only** lane on the line is a healthy live one; the silent lane is hidden
behind `+4`. Requirement 2 says a silent lane must outrank every quota field — here it does not
even outrank a live lane.

Failure scenario: three lanes running, one goes silent, its task-id happens to be long (all real
ids are — `ANTI-SILENCE-STATUSLINE-01` is 26 chars). Terminal is narrow. The founder sees a
healthy live lane and `+2`, and the silent lane is invisible. **This is verbatim the incident
that opened this task.**

**Required fix:** `break` instead of `continue` (never admit a lower-ranked lane after a
higher-ranked one was dropped), and guarantee slot 1 to the top-ranked lane by shrinking its
label rather than dropping it.

---

## HIGH

### F5 — The base/quota half is cut mid-word on every render, with no dropped-count
`plugins/leadv2/scripts/leadv2-lane-status-line.sh:236-242`

```bash
_base_out_plain="$(printf '%s' "$_base_out" | sed -E 's/\x1b\[[0-9;]*m//g')"
if (( ${#_base_out_plain} > _base_visible_budget )); then
  _base_out="${_base_out_plain:0:$_base_visible_budget}"     # raw character slice
fi
```

No boundary backoff, no marker. Requirement 3 governs *the line*, not only the lane segment.
Every one of my four renders below cuts the base mid-token (`~/P`, `Opus `,
`cx 93%·wk/6d17h` with ` · glm 19%·wk/20h53m` silently gone). It also drops all color on the
truncating path (`_base_out_plain` replaces the ANSI original), so the line changes appearance
depending on width.

The founder's stated complaint was "self-truncated mid-word". That behaviour still ships — it
moved from the lane segment to the quota segment.

**Required fix:** apply the same boundary backoff + `+N`-dropped-fields marker to the base, or
drop whole ` · `-delimited quota fields and name the count.

### F6 — `emit_oneline` overflows its own budget by the `+N` marker
`plugins/leadv2/scripts/leadv2-status-surface.sh:~1717-1720`

Same defect as F2, second site: `cur_len` is held `<= budget`, then `toks="${toks} +${n_dropped}"`
is appended unconditionally.

```
W=38  len=39  lanes 5: VERYLONGLANENAM…·silent·14m +4  <<< OVER BUDGET by 1
```

### F7 — The `width` control is not a control: 22 characters of slack, measured on ANSI bytes
`plugins/leadv2/scripts/tests/test-statusline-readable.sh:458`

```bash
if (( ${#NARROW_LINE} <= 40 + ${#DEAD_ONLY_LINE} )); then
  ok "width: narrow-COLUMNS render did not balloon past the requested budget"
```

`DEAD_ONLY_LINE` is 22 chars, so a **40-column** render passes at up to **62 characters** — 55%
over budget. And `${#NARROW_LINE}` counts raw bytes including ~15 characters of ANSI escapes, so
it is not measuring visible width at all. This assertion is why F2 and F6 shipped green.

**Required fix:** `visible_len "$(strip_ansi …)" <= 40`, exactly, no slack. The helper
`visible_len`/`strip_ansi` already exists in this file and is used by R8.

### F8 — The R1/R2 baseline control is git-dependent and silently reverts to SKIP
`plugins/leadv2/scripts/tests/test-statusline-readable.sh` (R1/R2)

In the lane worktree: `pass=16 fail=0 skip=0`. In a clean checkout of the same tree:

```
[SKIP] R1/R2 pre-fix baseline -- git archive of prior revision unavailable in this checkout
pass=14 fail=0 skip=1
```

The finisher's own words: *"A permanently-skipped assertion is not a control."* The skip was
resolved by depending on reachable git history rather than, as the brief offered, an inline
fixture of the old output. Any CI runner with a shallow clone or a squashed base loses both
regression guards and still reports green.

**Required fix:** inline the pre-fix output as a literal fixture. It is two strings.

### F9 — New synchronous subprocess spawns on a path the file itself contracts to have none
`plugins/leadv2/scripts/leadv2-lane-status-line.sh:218, 239`

The file header (B13 FIX-ROUND-4, lines 30-45) states the contract, and why it exists — a measured
300ms+ regression where cold renders returned a bare fallback:

> *"This script now performs ZERO synchronous subprocess spawns in its main path."*

This diff adds `tr` + `grep` (line 218) and `sed -E` (line 239) to the branch that renders for
every non-supervisor session — i.e. the founder's live path in single-lead mode. Full synchronous
spawn list on that branch: `stat` (190), `tr`+`grep` (218), `jq` (224),
`timeout 2 bash -c "$USER_CMD"` (226), `sed` (239), plus `python3` + state-path resolve on a cold
supervisor memo.

Measured with a trivial `printf` as the user command:

```
render 1: 99ms   render 2: 100ms   render 3: 100ms   render 4: 106ms   render 5: 100ms
```

That is ~100ms with a no-op base command. The founder's real `~/.claude/burn/statusline.sh` is the
dominant term and is bounded only by `timeout 2` — a 2-second ceiling on a surface repainted every
few seconds.

**Required fix:** move the dropped-count arithmetic and the ANSI strip into the already-detached
refresher (both are pure post-processing of a cached string), or do them with bash builtins,
spawning nothing.

---

## MEDIUM

### F10 — Out-of-writeset edit to a hook file
`plugins/leadv2/hooks/leadv2-codex-first-nudge.sh:78`

The close mission's `LANE_WRITES` lists six paths; this hook is not among them. The change is a
reminder-string rewrite unrelated to the statusline. Requirement 5 exists specifically to keep this
lane out of hook territory. No hook was *added*, so this is not a requirement-5 breach, but it is
an unreviewed drive-by in a file the brief did not open. Revert it or move it to its own commit.

### F11 — `render-proof.md` is untracked and does not exist where the lead was told to look
The review request cites `docs/handoff/ANTI-SILENCE-STATUSLINE-01/render-proof.md`. That path does
not exist in the main checkout. The file exists **only** inside the lane worktree and
`git ls-files --error-unmatch` reports it untracked:

```
error: pathspec 'docs/handoff/ANTI-SILENCE-STATUSLINE-01/render-proof.md' did not match any file(s) known to git
```

The finisher's Done-means required it "on disk" and "Commit before you stop". An untracked file in
a worktree is swept by the SessionStart worktree cleanup. The acceptance artifact is one `git add`
from being lost.

### F12 — The author's own proof shows a lane hidden at 200 columns with ~82 columns free
`docs/handoff/…/render-proof.md`, "width = 200"

```
AFTER : lanes 3/5 dispatch-c98a1414-archi…·?·1s dispatch-5bfce73e·?·2s +1 | Opus 5 (1M context) in /var/.../repo 79% ctx
```

That is ~118 visible characters against a 200-column budget, and the third of three lanes is
still hidden behind `+1`. The proof text frames this as intentional ("even at 200 columns the
ladder still prefers a whole `+1` drop"), but requirement 1 is that lanes render, and there were
82 unused columns. A lane hidden while the budget is 40% unspent is a ladder that terminates too
early, not a design choice.

### F13 — The `silence` control never executes the sort it claims to protect
`plugins/leadv2/scripts/tests/test-statusline-readable.sh:427-434`

```bash
DEAD_ONLY_LINE='lanes 1: mylane·dead·9m'
SILENCE_OUT="$(HOME="$tmp/composer-home" run_composer 120 "$DEAD_ONLY_LINE")"
```

The fixture is a **pre-sorted, hand-written memo string** injected straight into the composer's
memo file. The dead-first ordering actually lives in `rows.sort(...)` in the tail's Python and in
the `rank=(cls=="live")?1:0` awk in `emit_oneline` — neither is executed by this assertion. It
proves the composer concatenates a string it was handed, which was never in doubt. It cannot
catch F4.

### F14 — Byte-vs-character slicing under a non-UTF-8 locale corrupts the multibyte separators
`plugins/leadv2/scripts/leadv2-lane-status-line.sh:213`, `leadv2-lane-status-line-tail.sh:1096`

Every budget cut is `${var:0:N}`. Bash slices by **character** only in a multibyte locale; under
`LC_ALL=C`/`POSIX` it slices by **byte**. The rendered tokens contain `·` (2 bytes) and `…`
(3 bytes), and the surface's table strings contain Cyrillic. A statusline command inherits whatever
locale Claude Code's environment carries — it is not set anywhere in these scripts. A byte-slice
landing inside `·` or `…` emits a partial UTF-8 sequence and renders a replacement glyph or
garbage in the panel.

**Required fix:** set `LC_ALL=en_US.UTF-8` (or `C.UTF-8`) at the top of both scripts, or measure
with a codepoint-safe helper.

## LOW

### F15 — Trailing space on the budget-exhausted render
`leadv2-lane-status-line.sh:222` — `_surf_tail="$_surf_trimmed "` appends unconditionally, so a
render with no room for a base ends in a space (`… +4 ` at COLUMNS=40, `… +3 ` at W=60). Cosmetic,
but it also consumes one of the budgeted columns.

---

# My four width renders, verbatim

Real `plugins/leadv2/scripts/leadv2-lane-status-line.sh`, founder-shaped `statusLine.command`
(`Opus 5 in ~/Projects/leadv2 | cc 87%·7d/5d17h · cx 93%·wk/6d17h · glm 19%·wk/20h53m`), 5-lane
fixture (2 silent, 3 live), ANSI stripped, `visible` = visible character count:

```
COLUMNS=40  visible=40   lanes 5: ANTI-SILENCE-ST…·silent·14m +4
COLUMNS=80  visible=80   lanes 5: ANTI-SILENCE-ST…·silent·14m BROAD-STATUS-RO…·silent·9m +3 Opus 5 in ~/P
COLUMNS=120 visible=120  lanes 5: ANTI-SILENCE-ST…·silent·14m BROAD-STATUS-RO…·silent·9m dispatch-c98a1b·live·1s dispatch-5bfce2·live·3s +1 Opus
COLUMNS=200 visible=200  lanes 5: ANTI-SILENCE-ST…·silent·14m BROAD-STATUS-RO…·silent·9m dispatch-c98a1b·live·1s dispatch-5bfce2·live·3s GATE-FOREIGN-01·live·2s Opus 5 in ~/Projects/leadv2 | cc 87%·7d/5d17h · cx 93%·wk/6d17h
```

What this shows:
- The four widths **do** differ — the width logic reaches the live path. Requirement 3's
  "budgeted" half is genuinely fixed relative to the byte-identical renders the close brief recorded.
- Lanes lead at every width, and lane identities are distinguishable (`dispatch-c98a1b` vs
  `dispatch-5bfce2`) — no `dispatch-…`/`dispatch-…` collision in this fixture.
- Dropped counts in *this* fixture are honest (1+4, 2+3, 4+1, 5+0 against `lanes 5`).
- But the base is cut mid-word at 80 (`~/P`), 120 (`Opus`) and 200 (` · glm 19%·wk/20h53m`
  dropped with no marker) — F5.

And the overflow case, same script, memo carrying an upstream `+2` marker (F2 + F3 together):

```
W=60  vis=63  lanes 7: AAAAAAAAAAAAAAA·silent·14m BBBBBBBBBBBBBBB·live·9m +3
W=75  vis=75  lanes 7: AAAAAAAAAAAAAAA·silent·14m BBBBBBBBBBBBBBB·live·9m +3
W=90  vis=90  lanes 7: AAAAAAAAAAAAAAA·silent·14m BBBBBBBBBBBBBBB·live·9m CCCCCCCCCCCCCCC·live·1s +2 Opu
```

`vis=63` against `W=60`: **the budget is exceeded**. `+3` against 5 genuinely hidden lanes: **the
count lies**.

---

# Mutation pairs I ran myself

**Pair 1 — ordering (RED/GREEN, control works):**

```
MUTATION: FINAL_LINE printf reverted to '%s \033[34m| %s' "$FINAL_BASE" "$LANES"  (2 sites)
RED:  [FAIL] R5 -- no rows and no +M token -- lanes vanished entirely: Opus 5 in repo
      [FAIL] R12 -- mid-word-truncated token found: 'repo' in: Opus 5 in repo
      pass=12 fail=2 skip=1
REVERT
GREEN: pass=14 fail=0 skip=1
```

**Pair 2 — field-boundary cut (NO RED, control is absent):**

```
MUTATION A (tail):     [[ "$TRIMMED" == *" "* ]] && TRIMMED="${TRIMMED% *}"        -> : # MUTATED
  result: pass=14 fail=0 skip=1   <-- GREEN, mutation survived
MUTATION B (composer): [[ "$_surf_trimmed" == *" "* ]] && _surf_trimmed="${_surf_trimmed% *}" -> : # MUTATED
  result: pass=14 fail=0 skip=1   <-- GREEN, mutation survived
Branch reachability: clamp branch entered 6x (4x@112, 1x@200, 1x@80) — it runs, it just isn't asserted on.
```

All mutations applied to a scratch `git archive` copy at `/tmp/asl-mut`; `plugins/` in the lane was
never modified (the suite's own `REAL_TAIL_MD5` tamper guard did not fire, and the lane's
`git status` shows no source-file changes).

---

# Contradiction scan

- `LEADV2_STATUSLINE_WIDTH` vs `COLUMNS`: consistent — `${LEADV2_STATUSLINE_WIDTH:-${COLUMNS:-80}}`
  in both `emit_oneline` (leadv2-status-surface.sh:1670) and the composer (line 211); the detached
  refresher exports `LEADV2_STATUSLINE_WIDTH` explicitly because `$COLUMNS` does not survive
  `setsid`. Correct.
- `LEADV2_STATUSLINE_SUPERVISOR_ONLY` defaults to `1`, so with the supervisor retired
  (single-lead mode) the founder always takes the non-supervisor R4 branch. That branch *does*
  render lanes — the supervisor gate does **not** hide them. Verified by reading lines 176-263 and
  by every render above. No contradiction with the retired-supervisor rule.
- Brief/path mismatch: the close mission's `LANE_WRITES` names
  `plugins/leadv2/scripts/tests/run-all.sh`, which **does not exist**. The author edited
  `tests/run-all.sh` instead. The author is right and the brief is wrong; not a finding against
  the diff.
- `tests/run-all.sh` EXTRA_SUITE_MAP rows: the three added rows key on the changed file's basename
  and point at suites that exist on disk — verified by read. I could **not** complete a live
  `--scope changed` selection run (it exceeded a 120s timeout in a scratch clone), so CI selection
  is read-verified, not run-verified. Flagged as unproven rather than met.
- No hook, loop, notifier, or send door was added anywhere in the diff — verified against the full
  `--stat` (7 files: 3 scripts, 2 suites, 1 hook string, 1 CI map).

---

# Verdict

**BLOCK.** Four Critical and five High findings.

The round did land real progress — the ordering fix is genuine and mutation-proven, the width
budget now reaches the live path (the close brief's byte-identical renders are gone), and lane
identities no longer collapse to identical stubs in the fixture I tested. Requirements 1 and 4 are
met.

But the two claims this finisher round was created to establish are both false as shipped:
the field-boundary cut has no control that can detect its removal (F1, two mutations survived),
and the budget it enforces is exceeded by its own dropped-count marker (F2/F6) while that marker
reports a number that is wrong (F3). Worst, F4 reproduces the founding incident exactly — at a
narrow width a silent lane is dropped and a healthy one is shown in its place, which is the one
outcome this surface exists to prevent.

Minimum to unblock: F1, F2, F3, F4. F5 and F7 should land in the same round — F7 is what let F2
and F6 through, and leaving it means the next round's green is worth as little as this one's.
