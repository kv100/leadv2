# ARCHITECT PREPASS — REVIEW-GATE-SHOWS-FINDINGS-01

Scoped implementation design. **No implementation in this document.**

Owner file: `plugins/leadv2/scripts/leadv2-review-run.sh` (740 lines).
Repo: `~/Projects/leadv2` (shared plugin tree — lands in all consuming repos at once).

---

## 1. Current behaviour (verified on disk)

| Site | Lines | What it writes |
|---|---|---|
| FAIL terminal | 724–731 | `arms:` / `verified:` / `status: fail` / `critical:` / `high:` / `medium:` / `low:` |
| PASS terminal | 734–739 | `arms:` / `verified:` / `status: pass` / `reviewer:` / `diff:` — **no counts at all** |
| unreviewed / blocked branches | 450–452, 541–545, 560–562, 598–604 | `status: <s>` + `reason:` |

Two facts that make the fix cheap:

1. **The findings are already structured, in this same script, immediately above both
   write sites.** `${HANDOFF}/review-findings.json` is built at 653–708 from
   `${HANDOFF}/.review-findings-dedup.tsv` (columns: `arm, severity, file, line,
   dimension, desc`), enriched per Critical/High with `verifier_arm` /
   `verifier_verdict`. Dedup is by `(file,line,severity,dimension)` keeping the first
   arm to report — so **arm attribution already exists and is per-finding**. Nothing
   new must be parsed out of the review bodies.
2. **The counts and the finding list come from two different sources.**
   `FINDINGS_{CRITICAL,HIGH,MEDIUM,LOW}_TOTAL` (607–610) come from the *primary arm's*
   single `REVIEW_FINDINGS: critical=… high=… medium=… low=…` header line
   (`parse_review_verdict`, 186–214). The finding rows come from `^FINDING:` lines
   across **all** arms plus hack-detect. They can disagree. That disagreement is
   exactly the "9 findings, rendered as a bare `status: pass`" hole and also the
   detector for the parse-failure requirement.

`PASS_WITH_NITS` never appears in `review-gate.md`: `verdict` holds it, but the
non-FAIL branch hardcodes `status: pass`. Changing that word is **verdict-surface**
change and is out of scope per the mission; the verdict is instead surfaced additively
on a new `verdict:` key.

Consumers parse with `grep '^status:' | awk '{print $2}'` (`leadv2-phase-record.sh`
795, 850) and the bypass-guard hook checks for a parseable `status:` line. Therefore:
**line order is free, appended keys are free, but the `status:` line's own text must
stay byte-identical.**

---

## 2. Design

### 2.1 New render source: `.review-findings-render.tsv`

Inside the existing JSON-build loop (`while IFS=$'\t' read … done < "${FINDINGS_DEDUP}"`,
~672–706), append one tab-separated row per finding to
`${HANDOFF}/.review-findings-render.tsv`:

```
severity <TAB> file <TAB> line <TAB> arm <TAB> dimension <TAB> verifier_verdict <TAB> desc
```

Appended with `>>` (not a variable) so it survives regardless of whether that loop
executes in a subshell — the script already documents (709–712) that it does not trust
in-loop variable propagation there. The file is truncated (`: >`) next to
`FINDINGS_RAW` at 651 so a rerun never inherits a stale list.

Rationale for a sidecar TSV over re-parsing `review-findings.json`: the script has no
JSON parser and no python3 dependency on this path; hand-rolled JSON grepping is what
already produced the coarse `_blocking_refuted` approximation at 723. A TSV keeps the
renderer to `while IFS=$'\t' read`.

### 2.2 New function `render_gate_findings()`

Placed beside `review_floor_ok()` (≈line 232). Pure stdout, no side effects, no exits.
Inputs (globals already in scope): `HANDOFF`, `TASK`, the four `FINDINGS_*_TOTAL`,
`verdict`, `reviewer_primary`. Emits, in order:

```
findings:
  [Critical] platform/x.py:88 (arm=codex, dim=correctness) — <one-line claim>
  [High]     scripts/y.sh:12 (arm=glm, dim=security, verify=refuted) — <one-line claim>
  [Medium]   web/z.tsx:41 (arm=critic, dim=quality) — <one-line claim>
  low: 3 not shown — full list: docs/handoff/<task>/review-findings.json
```

Rules:

- **Severity floor:** Critical, High, Medium are rendered as rows. Low is never
  rendered as rows but is always accounted for by the trailing `low: N not shown` line
  (or omitted when `low == 0`). This satisfies "medium and above" without hiding lows.
- **Ordering:** Critical → High → Medium; within a severity, input (dedup) order.
  Implemented as three filtered passes over the TSV — no `sort` (locale-unstable).
- **Cap:** `LEADV2_REVIEW_GATE_MAX_FINDINGS`, default `20`. When the row count exceeds
  it, the renderer prints the first N and then a mandatory line:
  `  … <M> more findings omitted (cap=<N>) — full list: docs/handoff/<task>/review-findings.json`.
  Never a silent truncation. `desc` itself is clipped to
  `LEADV2_REVIEW_GATE_DESC_CHARS` (default `160`) with a literal `…` suffix so one
  runaway description cannot push the block off screen; clipping is visible by the
  suffix.
- **Multi-line safety:** `desc` may contain arbitrary text from a model. The renderer
  strips CR/LF and collapses runs of whitespace before printing, so one finding is
  always exactly one line and cannot forge a `status:` line. This is a hard
  requirement: an unsanitised `desc` containing `\nstatus: pass` would be read by
  `grep '^status:'` in `leadv2-phase-record.sh`. Sanitisation additionally strips a
  leading `status:`/`arms:`/`verified:` token from the clipped text.
- **Parse-failure detection (the REVIEW-BODY-PERSIST-01 sibling hole):** let
  `reported = critical+high+medium` (from the reviewer's own header counts) and
  `rendered_rows` = rows in the TSV at Medium-or-above. If `reported > 0 &&
  rendered_rows == 0`, the block is instead:

  ```
  findings: PARSE_FAILURE — reviewer reported <reported> finding(s) at medium+ but 0 were
    machine-readable (no FINDING: lines). Read the full body: docs/handoff/<task>/review-<arm>.md
  ```

  and an extra header key `findings_parse: failed` is emitted. When `reported == 0 &&
  rendered_rows == 0`, the block is the honest `findings: none`. The two cases are
  never conflated — that is the whole point of the requirement.
- **Arm attribution / silence masking:** every row carries `arm=<raiser>`. Because the
  dedup keeps the first raiser and the union is taken across *all* `ran_arms`, one
  arm returning nothing cannot suppress another's rows. To make silence itself
  legible, the block is preceded by a per-arm tally line:
  `  by_arm: codex=3 glm=0 critic=2 hackdetect=1` — an arm at `0` is visibly silent
  rather than invisibly absent.

### 2.3 New first line: `summary:`

Prepended (first physical line of the file) at both terminal write sites:

```
summary: PASS_WITH_NITS — 9 finding(s): 0 critical, 0 high, 6 medium, 3 low; 6 shown below
```

This satisfies "a reader who stops at the first line must still see that remarks
exist." It is additive: no existing consumer greps line 1, and all of them anchor on
`^status:` / `^critical:` etc. On the parse-failure path the summary reads
`… ; 0 shown — PARSE FAILURE, see review-<arm>.md`.

### 2.4 The two terminal write sites, after the change

FAIL (replacing 724–731) — existing lines byte-identical, new lines around them:

```
summary: <…>
arms: <csv>
verified: <n>/<m>
status: fail          <- unchanged
critical: N           <- unchanged
high: N               <- unchanged
medium: N             <- unchanged
low: N                <- unchanged
verdict: FAIL         <- new, additive
<findings block>
```

PASS / PASS_WITH_NITS (replacing 734–739):

```
summary: <…>
arms: <csv>
verified: <n>/<m>
status: pass          <- unchanged word, unchanged position semantics
reviewer: <arm>       <- unchanged
diff: <hash>          <- unchanged
verdict: PASS_WITH_NITS   <- new, additive: the real verdict, never overwriting status:
critical: 0           <- new, additive (pass path had no counts at all)
high: 0
medium: 6
low: 3
<findings block>
```

Both keep the existing `tmp` + `mv -f` atomic write and the write-race note at the top
of the script untouched.

### 2.5 Explicitly unchanged

- Verdict logic: `parse_review_verdict`, the contradiction override (212–214), the
  `verdict == FAIL` branch condition, and every `exit` code (0/6/7/9).
- The `unreviewed` / `blocked` branches (450, 541, 560, 598): they have no findings by
  construction. No `summary:`/`findings:` block there — adding one would imply a
  review ran.
- `review-findings.json`'s schema. It stays the machine surface; the gate is the human
  surface.
- The atomic-write pattern and the WRITE-RACE NOTE header.

---

## 3. Interface contract

| Key | Present on | Type | Backward-compat |
|---|---|---|---|
| `summary:` | fail, pass | free text, single line | new, line 1 |
| `arms:` `verified:` `status:` `critical:` `high:` `medium:` `low:` `reviewer:` `diff:` | as today | unchanged | **byte-identical** |
| `verdict:` | fail, pass | `PASS`\|`PASS_WITH_NITS`\|`FAIL` | new |
| `critical:`…`low:` on the pass path | pass | int | new (additive) |
| `findings_parse:` | fail, pass, only on failure | `failed` | new, conditional |
| `findings:` + indented rows | fail, pass | human block, 2-space indent | new; indented so no row can ever match a `^key:` grep |

Env knobs (both new, both `LEADV2_*` per convention, both optional with defaults):
`LEADV2_REVIEW_GATE_MAX_FINDINGS=20`, `LEADV2_REVIEW_GATE_DESC_CHARS=160`. Neither
name exists anywhere in the tree today (checked) — no semantic contradiction.

---

## 4. Risks and mitigations

| # | Risk | Mitigation |
|---|---|---|
| R1 | A model-authored `desc` containing a newline forges a `status:` line and flips a downstream parser | Renderer strips CR/LF, collapses whitespace, clips to N chars, and indents every row by two spaces. Covered by a dedicated fixture test. |
| R2 | The render-TSV write sits in a loop the script already suspects of subshelling | Row is appended with `>>` to a file; no variable crosses the boundary. Truncation happens once, before the loop. |
| R3 | Counts (primary arm header) and rows (all-arm `FINDING:` union) legitimately disagree — rows can exceed counts | Only the `reported>0 && rendered==0` direction is treated as a failure. The opposite direction renders all rows and the summary reports both numbers, so the disagreement is visible rather than reconciled by fiat. |
| R4 | Growing `review-gate.md` breaks a consumer that reads the whole file into a prompt | Cap bounds the file to ~20 rows × ~200 chars ≈ 4 KB worst case. Cap is announced when it bites. |
| R5 | Shared tree — the change lands in persona-engine / m3-market / respiro-ios simultaneously | Strictly additive; every existing key keeps its exact text and every existing exit code is untouched. |
| R6 | `.review-findings-render.tsv` left behind as a dotfile in `docs/handoff/` | Same convention as the existing `.review-findings-raw.tsv` / `-dedup.tsv` siblings — no new gitignore need. |

---

## 5. Out of scope (for the implementing agent)

- Any change to what passes and what fails.
- Changing `status: pass` to `status: pass_with_nits`.
- The `unreviewed` / `blocked` write sites.
- Re-parsing review bodies for findings the reviewer did not emit as `FINDING:` lines.
- `review-findings.json` schema, the verifier fan-out, `_blocking_refuted`.
- The write-race note and the tmp+`mv -f` pattern.
- Committing. The lead commits.

---

## 6. Evidence the implementation must produce

Four fixture renders pasted verbatim into the report — the mission rejects a
correctness claim without them:

1. `fail` with findings (≥1 Critical, ≥1 High, ≥1 Medium, ≥1 Low)
2. `PASS_WITH_NITS` with findings (0 critical, 0 high, 6 medium, 3 low) — the case that
   caused three bad merges
3. clean `pass`, zero findings → `findings: none`
4. lost/empty body → the existing `status: blocked / reason: review_body_lost` path is
   unchanged, **plus** the new sibling: non-empty body, `reported>0`, zero `FINDING:`
   lines → `findings_parse: failed`

A fifth is worth adding though not demanded: cap-exceeded (25 findings, cap 20) showing
the "5 more findings omitted" line.

---

## 7. acceptance

```yaml
acceptance:
  - surface: file_artifact
    observable: >
      docs/handoff/<task>/review-gate.md, for a review that returned
      PASS_WITH_NITS with six medium findings, shows on its first line a
      summary naming PASS_WITH_NITS and the finding counts, and below the
      unchanged status/critical/high/medium/low header shows a "findings:"
      block with one indented line per medium-or-above finding carrying its
      severity, its file:line, the arm that raised it, and its one-line claim.
    authored_at: 2026-08-14T00:00:00Z
  - surface: file_artifact
    observable: >
      For a clean pass with no findings, the same file reads "findings: none"
      — and for a non-empty review body from which zero findings could be
      parsed while the reviewer's own header reported findings, it instead
      reads "findings_parse: failed" together with a PARSE_FAILURE line naming
      the review-<arm>.md file to open, never "findings: none".
    authored_at: 2026-08-14T00:00:00Z
  - surface: file_artifact
    observable: >
      When more findings exist than the display cap, the last line of the
      findings block states how many findings were omitted and names
      review-findings.json as where the full list lives; no case exists where
      the block ends without either all findings or that omission notice.
    authored_at: 2026-08-14T00:00:00Z
  - surface: rendered_line
    observable: >
      In a two-arm fan-out where one arm returned nothing and the other raised
      three findings, the findings block shows a by_arm tally naming the silent
      arm with 0 and the other with 3, and all three findings appear attributed
      to the arm that raised them.
    authored_at: 2026-08-14T00:00:00Z
```

LANE_WRITES: plugins/leadv2/scripts/leadv2-review-run.sh, plugins/leadv2/scripts/tests/test-review-gate-shows-findings.sh, plugins/leadv2/scripts/tests/run-core-offline.sh, plugins/leadv2/docs/phases.md, docs/missions/REVIEW-GATE-SHOWS-FINDINGS-01-report.md

DELIVERABLE_COMPLETE
