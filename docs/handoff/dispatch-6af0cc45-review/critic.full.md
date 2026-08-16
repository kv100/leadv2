REVIEW_VERDICT: FAIL
REVIEW_FINDINGS: critical=0 high=3 medium=4 low=3

# critic — dispatch-6af0cc45 (REVIEW-GATE-SHOWS-FINDINGS-01)

Diff reviewed: `docs/handoff/dispatch-6af0cc45/review.diff` (702 lines; engine +140,
new suite, run-core-offline registration, phases.md, mission report).

Evidence base: read the diff, read the surrounding engine (`leadv2-review-run.sh`
lines 186-215, 560-760), ran the new suite (**38 PASS / 0 FAIL**, exit 0 — the author's
claim is confirmed), and ran two purpose-built stub scenarios against the REAL engine in
the lane worktree to reproduce H2 and H3 (transcripts inline below).

Line numbers below are the **post-patch** line numbers in
`plugins/leadv2/scripts/leadv2-review-run.sh` as it exists in
`.claude/worktrees/6af0cc45/`, cross-referenced to the diff hunk.

---

## Critical

None.

---

## High

### H1 — `render_gate_findings` prints a pointer path that does not exist
**File:** `plugins/leadv2/scripts/leadv2-review-run.sh:325` (`json_rel=`) and `:337`
(the PARSE_FAILURE pointer). **Category:** correctness / dead reference.

```sh
local json_rel="docs/handoff/${TASK}/review-findings.json"
...
printf '    machine-readable (no FINDING: lines). Read the full body: docs/handoff/%s/review-%s.md\n' "${TASK}" "${reviewer_primary}"
```

`TASK` is the bare sig8, not the handoff directory name. The engine itself proves this
everywhere else: `:118`, `:133`, `:430` all build `${ROOT}/docs/handoff/dispatch-${TASK}-review`,
and the lane calls `--artifact "docs/handoff/dispatch-${TASK}/review-gate.md"`
(`leadv2-dispatch-product-close.sh:1711`). On-disk confirmation: this very dispatch has
`docs/handoff/dispatch-6af0cc45/` and `docs/handoff/dispatch-6af0cc45-review/`, i.e. the
engine was invoked with `--task 6af0cc45`.

So in production the cap notice reads
`full list: docs/handoff/6af0cc45/review-findings.json` — a path that does not exist. The
pointer is the *entire* mitigation for the cap truncation, the `low: N not shown` line and
the PARSE_FAILURE case; all three point at nothing.

The author's own fixtures show the bug and the report reprints it as correct output:
handoff dir is `dispatch-GATEFIND`, rendered pointer is `docs/handoff/GATEFIND/…`.
Reproduced:

```
$ LEADV2_GATE_FIND_TMP=/tmp/gfx bash plugins/leadv2/scripts/tests/test-review-gate-shows-findings.sh
$ tail -1 /tmp/gfx/s5/root/docs/handoff/dispatch-GATEFIND/review-gate.md
  … 5 more findings omitted (cap=20) — full list: docs/handoff/GATEFIND/review-findings.json
$ ls /tmp/gfx/s5/root/docs/handoff/
dispatch-GATEFIND
dispatch-GATEFIND-review
```

Worse, the test **asserts the wrong string** and so locks the defect in:
`test-review-gate-shows-findings.sh:693`
`grep -qF 'full list: docs/handoff/GATEFIND/review-findings.json'`.

**Required fix:** derive the pointer from `HANDOFF`, the same variable the engine actually
writes those files to (`FINDINGS_JSON="${HANDOFF}/review-findings.json"`,
`_file="${HANDOFF}/review-${_arm}.md"`). E.g.
```sh
local json_rel="${HANDOFF#${ROOT}/}/review-findings.json"
```
and the same treatment for the `review-<arm>.md` pointer. Then change the two test
assertions to expect `dispatch-GATEFIND`, and add an assertion that the printed path
resolves to an existing file under `${root}` — that is the assertion that would have
caught this.

---

### H2 — line-1 `summary:` and the new `verdict:` line assert counts that contradict the rows printed directly beneath them
**File:** `leadv2-review-run.sh:304-317` (`gate_summary_line`), `:416` (`printf 'verdict: %s\n'`).
**Category:** correctness / the gate states a falsehood.

`gate_summary_line` derives its counts from `FINDINGS_*_TOTAL`, which
`:608-611` copies from `FINDINGS_CRITICAL…FINDINGS_LOW` — set by `parse_review_verdict`
(`:186-215`) from **the primary arm's `REVIEW_FINDINGS:` header only**. The render TSV,
by contrast, is fed from `FINDINGS_DEDUP`, the union over **all** `ran_arms` **plus
hackdetect** (`:618-639`). The two populations are different, and the diff now prints them
adjacent to each other as if they were the same fact.

Reproduced against the real engine (stubs: codex = primary, returns a clean
`PASS 0/0/0/0`; glm = second arm, raises 1 Critical + 2 Medium; verifier upholds):

```
summary: PASS — 0 finding(s): 0 critical, 0 high, 0 medium, 0 low; 3 shown below
arms: codex,glm
verified: 1/1
status: pass
reviewer: codex
diff: bcbc12a6
verdict: PASS
critical: 0
high: 0
medium: 0
low: 0
  by_arm: codex=0 glm=3
findings:
  [Critical] src/a.py:1 (arm=glm, dim=security, verify=upheld) — hardcoded secret
  [Medium] src/b.py:2 (arm=glm, dim=quality) — nit one
  [Medium] src/c.py:3 (arm=glm, dim=quality) — nit two
```

Line 1 says **"0 finding(s): 0 critical"** and line 8 says **`verdict: PASS`**, above an
**upheld Critical**. The primary-only counting is pre-existing; what this diff adds is a
line-1 summary that makes an affirmative, false, human-facing claim, and a `verdict:` line
that presents a clean verdict as authoritative. The stated purpose of the mission is "a
reader who stops at line 1 still sees that remarks exist" (`:299-301`) — under fan-out ≥2
a reader who stops at line 1 is actively misled, which is strictly worse than the counts-only
gate it replaces. Note this is not exotic: default `--fanout` is 3.

**Required fix:** one of —
(a) compute the summary counts from the render TSV (all arms) and label the header counts
    as primary-only, or
(b) keep header counts as-is but have the summary report both populations explicitly,
    e.g. `… reviewer header: 0 c/0 h/0 m/0 l; rendered across arms: 1 c/2 m; 3 shown below`.
Either way the summary must never print a total lower than the number of rows it then prints,
and `verdict:` must be qualified when a non-primary arm raised an upheld Critical/High.
Add a fan-out scenario to the suite (all six existing scenarios keep glm silent, which is
exactly why this is invisible today).

---

### H3 — the parse-failure detector is defeated by any second arm, i.e. in the default configuration
**File:** `leadv2-review-run.sh:308` and `:333` — `if (( reported > 0 && med_rows == 0 ))`.
**Category:** correctness / the feature's headline guard does not fire.

`reported` is primary-arm-only (see H2); `med_rows` counts rows from **all** arms. So the
guard only fires when *every* arm produced zero medium+ rows. The moment any other arm
emits one `FINDING:` line, the primary's prose-only body — the exact REVIEW-BODY-PERSIST-01
sibling hole this feature exists to catch — is silently absorbed.

Reproduced (same stubs as H2, with codex's header changed to `medium=2` and its body
prose-only, zero `FINDING:` lines):

```
summary: PASS — 2 finding(s): 0 critical, 0 high, 2 medium, 0 low; 3 shown below
...
  by_arm: codex=0 glm=3
findings:
  [Critical] src/a.py:1 (arm=glm, dim=security, verify=upheld) — hardcoded secret
  [Medium] src/b.py:2 (arm=glm, dim=quality) — nit one
  [Medium] src/c.py:3 (arm=glm, dim=quality) — nit two
```

No `findings_parse: failed`, no PARSE_FAILURE block. codex's two medium remarks are gone
and nothing on the gate says so. Scenario 4b passes only because it runs `--fanout 1`.

The mirror-image false *positive* also exists: `reviewer_primary` is the first arm whose
body **parses** (`:574-590`), not necessarily `ran_arms[0]`; dedup keeps the first writer,
which is `ran_arms[0]` (`:643`). If arm0 failed the verdict parse but emitted `FINDING:`
lines identical to the primary's, the primary's rows are deduped away and the gate declares
a PARSE_FAILURE that did not happen.

**Required fix:** make the guard per-arm. Count render-TSV rows whose `arm` column ==
`reviewer_primary` and compare *that* against `reported`; extend to every arm whose body
carried a `REVIEW_FINDINGS:` header (the engine already parses each arm's file at `:574`).
Add a `--fanout 2` scenario where the primary is prose-only and the second arm is not.

---

## Medium

### M1 — `by_arm` is a post-dedup tally, so a non-silent arm is indistinguishable from a silent one
**File:** `leadv2-review-run.sh:278-287` (`_review_gate_by_arm_line`).

The tally counts rows in `RENDER_TSV`, which is fed from `FINDINGS_DEDUP` — deduped by
`(file,line,severity,dimension)`, first writer wins (`:643`). Two arms that independently
raise the same Critical produce `armA=1 armB=0`. The stated contract (diff comment
`:275-277`, report line "silence is legible, not masking") is that `=0` means the arm ran
and found nothing. It now also means "the arm agreed with another arm", which is the
opposite signal — corroboration rendered as silence.

**Fix:** tally from `FINDINGS_RAW` (pre-dedup) for the `by_arm` line, or emit both
(`codex=4 glm=4(3 deduped)`).

### M2 — `findings: none` is printed while the same file says `low: N`
**File:** `leadv2-review-run.sh:342-345`.

The parse-failure guard covers medium+ only (`reported` excludes `FINDINGS_LOW_TOTAL`). A
reviewer whose header says `low=3` but emits no `FINDING:` lines yields
`med_rows==0 && low_rows==0` → `findings: none`, directly under `low: 3`. The gate contradicts
itself in adjacent lines, and the diff's own justification for the PARSE_FAILURE path
("never conflated with the honest `findings: none`") applies verbatim here.

**Fix:** either include `FINDINGS_LOW_TOTAL` in the parse-failure predicate, or print
`findings: none rendered (reviewer header reports low: 3, no machine-readable rows)`.

### M3 — two new logic branches ship with zero coverage
**File:** `plugins/leadv2/scripts/tests/test-review-gate-shows-findings.sh` (whole file).

Uncovered new branches in `_review_gate_clip_desc` (`:262-273`):
- the clip branch — `(( ${#d} > max ))` / `${d:0:max}` / the `…` suffix /
  `LEADV2_REVIEW_GATE_DESC_CHARS`. No scenario uses a desc longer than 160 chars.
- the whitespace-collapse branch `tr -s '[:space:]' ' '`. Scenario 1 is advertised as
  covering it, but the fixture's `\x0d\x0a   marker   with   spaces` puts the whitespace run
  on a **second physical line**, which `grep -E '^FINDING:'` (`:622`) drops before the
  sanitiser ever sees it. The assertion `! grep -qF 'marker   with'` therefore passes for
  the wrong reason. Only the `tr -d '\r'` and the `sed` token-strip are genuinely exercised.

Per the review bar, a new logic branch with no test is blocking-adjacent; it is Medium here
only because the branches are display-only.

**Fix:** add a scenario with a 300-char desc asserting a 160-char clip plus the `…` suffix
and a non-default `LEADV2_REVIEW_GATE_DESC_CHARS`; add a single-line desc containing a
genuine internal whitespace run.

### M4 — the lead is never told to read the new surface, so the merge behaviour this mission targets is unchanged
**File:** `plugins/leadv2/docs/phases.md:229-241`.

The added paragraph describes the surface, but the decision table immediately below is
untouched: `status: pass → ACCEPT, append findings to followups.md, proceed to Phase 6`.
`PASS_WITH_NITS` still writes `status: pass` and still routes to ACCEPT. No consumer keys on
`summary:` or `verdict:` (verified: `leadv2-workflow-bypass-guard.sh:65` matches
`^[[:space:]]*status:` only; `leadv2-phase-record.sh:795,850` grep `^status:`; the existing
review tests anchor on `^status:`/`^arms:`). The diff is therefore additive display with no
behavioural hook — which is defensible as scoped, but the mission framing ("the case that
caused three bad merges") is not actually closed by it.

**Fix (or written justification in the commit message):** extend the `status: pass` bullet
to "read the `verdict:` line — `PASS_WITH_NITS` means findings exist; they go to followups
before Phase 6", so the surface has a documented consumer.

---

## Low

### L1 — the two new env knobs are unvalidated
`leadv2-review-run.sh:264`, `:304`, `:324`. `LEADV2_REVIEW_GATE_DESC_CHARS=abc` makes
`(( ${#d} > max ))` and `${d:0:max}` raise an arithmetic error; the script runs `set -uo
pipefail` with no `-e`, so it does not abort — the desc simply renders empty and the gate
looks like the reviewer said nothing. Same shape for `LEADV2_REVIEW_GATE_MAX_FINDINGS`.
**Fix:** `[[ "${max}" =~ ^[0-9]+$ ]] || max=160`.

### L2 — the `by_arm` tally includes Low rows while the block below excludes them
`:280-286` vs `:349-370`. Fixture 1 reads `by_arm: codex=4` above `3 shown below`. Not wrong,
but the two numbers invite the reader to reconcile them and they never will.
**Fix:** label it (`by_arm (all severities): …`) or exclude Low.

### L3 — the "subshell-safe" comment is inaccurate
`:388-390` in the diff ("appended with `>>` so it survives even if this loop runs in a
subshell"). The write sits in a plain brace group with `while … done < "${FINDINGS_DEDUP}"` —
a redirect, not a pipe, so there is no subshell on this path (unlike the `grep | while` loops
at `:622`/`:640`, which is where the original recompute note came from). The `>>` is correct;
the stated reason is not, and a future editor may rely on it.

---

## Verified as genuinely unchanged (no finding)

- Exit codes 0/6/7/9 — suite asserts all four, all pass.
- `status:` text at every write site — `grep -qx 'status: fail'` / `'status: pass'` /
  `'status: blocked'` assertions pass; exactly one `^status:` line per gate file (s1).
- Blocked/unreviewed write sites gain no new keys (s4a asserts `! grep '^summary:'`).
- The desc sanitiser cannot forge a `^status:` line: rows are always indented two spaces, and
  the bypass guard's `^[[:space:]]*status:` pattern still cannot be matched by a row because
  every row starts `  [`.
- `hackdetect` is not a member of `ran_arms` (`:502-535` vs `:632-639`), so the explicit
  `hackdetect=` clause in the tally does not double-count.
- The `>>` sidecar write does not corrupt `review-findings.json`: the brace group's stdout
  redirect is not affected by an explicit per-printf redirect.

## Type/lint evidence

Bash — no mypy/tsc applies. Syntax and behavioural evidence:

```
$ /bin/bash -n plugins/leadv2/scripts/leadv2-review-run.sh   # clean (asserted in-suite, PASS)
$ bash plugins/leadv2/scripts/tests/test-review-gate-shows-findings.sh
[TEST]   review-gate-shows-findings: PASS=38 FAIL=0
```

The suite is green. It is green while H1, H2 and H3 are present, because all six scenarios
either run `--fanout 1` or keep the second arm silent, and because the H1 assertion encodes
the wrong expected path.

---

## Verdict

**BLOCK** — 3 High. H1 is a one-line fix plus a test correction. H2 and H3 share a root cause
(primary-arm-only counters compared against all-arm rows) and need the summary/guard to be
computed over a consistent population, plus a fan-out scenario in the suite.

DELIVERABLE_COMPLETE
