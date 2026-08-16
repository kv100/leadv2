# ARCHITECT PREPASS — REVIEW-GATE-SHOWS-FINDINGS-01

Repo: `~/Projects/leadv2` (plugin source). Design only — no implementation here.

---

## 0. Finding that changes the mission's file list (read this first)

The mission names `leadv2-review-run.sh` as the gate writer. **It is not the writer that produced
the three real gates.** Evidence:

| | writes `review-gate.md` at | pass line shape |
|---|---|---|
| `plugins/leadv2/scripts/leadv2-review-run.sh` | 726, 736 (plus 450/541/560/598/601) | prefixed by `arms: …` + `verified: …` (lines 725/735) |
| `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` | **2037, 2045** (plus 155/232/1489/1510/1532/1553/1569/1955/2017) | exactly `status:/reviewer:/diff:` — no `arms:` line |

All three real gates (`dispatch-{9573bd97,95eb1cb9,82e1056d}`) contain **no `arms:` line**, so they
were written by `leadv2-dispatch-product-close.sh:2037/2045` — the lane path that actually runs.
A fix landed only in `leadv2-review-run.sh` would satisfy every unit test and change nothing the
founder sees. **Both writers must render, through one shared renderer.**

Second consequence: `review-run.sh` already builds `review-findings.json` (structured per-finding
records with severity/file/line/arm/verifier_verdict, lines 613–690) **from `FINDING:` lines**, and
`review-run.sh:434` asks reviewers to emit them. `product-close`'s reviewer contract does not, and
**none of the three real reports contains a single `FINDING:` line** (verified by grep). So the
structured path is empty on the live path; the renderer's real work is markdown extraction.

---

## 1. Change in one sentence

Add one sourceable renderer that turns a reviewer report into a findings block, and append that
block to `review-gate.md` at both writers' `fail` and `pass` exits — plus a report-level
`do_not_merge` advisory flag — without touching any verdict, exit code, or ledger decision.

---

## 2. Components

### 2.1 New: `plugins/leadv2/scripts/leadv2-review-findings.sh` (to-create)

Dual-mode: sourceable library **and** standalone CLI (so it is testable and re-runnable against
any report on disk — the mission's evidence step needs exactly this).

```
Usage: leadv2-review-findings.sh --report <review-<arm>.md> [--json <review-findings.json>]
                                 [--arm <name>] [--report-path <repo-relative path to print>]
       (as library)  source …; render_gate_findings "<report>" ["<json>"] ["<arm>"] ["<relpath>"]
```

Writes the findings block to **stdout only**. Never writes `review-gate.md`, never exits non-zero
on a parse failure (a renderer that can kill the gate is a worse bug than the one being fixed).
Contract: **rc is always 0**; degradation is expressed in the emitted text.

Extraction, in priority order:

1. **`FINDING:` lines** (`review-run.sh:434` contract) or a non-empty `review-findings.json`
   `findings[]` → `findings_source: finding_lines`. Highest fidelity: severity/file/line/desc and,
   when present, `verifier_verdict` (`upheld`/`refuted`/`unverified`) carried through verbatim.
2. **Markdown severity sections** → `findings_source: markdown_sections`. Section heading regex
   (case-insensitive, tolerates trailing text like `## Medium (3)`):
   `^#{1,6}[[:space:]]*(Critical|High|Medium|Low|Критич|Высок|Средн|Низк)`; section ends at the
   next `^#{1,6}[[:space:]]` heading. Item-start regex inside a section — all three real reports
   are covered by exactly these three shapes:
   - `1. **text**` / `2) text` (9573bd97, 95eb1cb9)
   - `**H1 — text**` (82e1056d)
   - `- text` / `* text`
   Per item: take the item's first line, strip the list marker, strip `**`/`` ` ``/`—` noise,
   collapse whitespace, truncate to `LEADV2_GATE_DESC_MAX` (default 180) chars with a trailing `…`.
   Anchor = first backticked token in the item matching `[A-Za-z0-9_./-]+\.[A-Za-z0-9]+(:[0-9]+)?`
   (yields `scripts/gate-cost-report.sh`, `scripts/vps-release-deploy.sh`, `grounding-gate.sh:973`
   on the three real reports). No anchor → omit the anchor field, keep the finding.
3. **Neither yields an item** → `findings_source: none` + the degrade block (§4).

### 2.2 Edits: the two writers

- `leadv2-review-run.sh` — append renderer output at 723–731 (`fail`) and 734–738 (`pass`).
  It already has `${HANDOFF}/review-${reviewer_primary}.md` and `review-findings.json`.
- `leadv2-dispatch-product-close.sh` — same at 2036–2038 (`fail`) and 2045 (`pass`). Report file =
  `${REVIEW_ARTIFACT:-${review_out}}` (already resolved into `review_file` at 1977).

Both keep their `printf` head bytes byte-identical and **append**; both keep the tmp+`mv -f`
atomic-write discipline (`product-close`'s direct `>` at 2037/2045 should be brought to tmp+mv
while the block is being added — the file is now multi-line and a torn read is newly possible).

The `blocked` / `unreviewed` / `no_verdict_marker` writers are **out of scope**: no reviewer report
exists on those paths, so there is nothing to render.

---

## 3. Gate format (additive, existing keys unchanged and first)

```
status: fail
critical: 0
high: 2
medium: 1
low: 6
reviewer_says: do_not_merge
findings_source: markdown_sections
findings:
- [High] scripts/gate-cost-report.sh — the only anchor proven present in the prod journal is computed and then silently discarded — the report can never produce output on live data
- [High] scripts/gate-cost-report.sh — `^`-anchored anchor regexes can never match the actual journal MESSAGE format
- [Medium] ENGINE-REFERENCE.md — new PE_* flag has no ENGINE-REFERENCE.md row
omitted: low=6
report: docs/handoff/dispatch-82e1056d/review-glm.md
```

Rules, in force of precedence:

1. **Every Critical and every High is rendered, always.** No cap, no count-only collapse, no
   `+N more` for these severities. The mission's non-negotiable.
2. **Blocking Mediums are rendered** — a Medium is blocking if its own text matches the
   do-not-merge/blocking phrase set, **or** if the report-level `do_not_merge` flag is set (in
   which case every Medium renders uncapped; case 2 lives in the verdict section, not in the item,
   so an item-local test alone would miss it).
3. Non-blocking Mediums: up to `LEADV2_GATE_MEDIUM_MAX` (default 5), remainder folded into
   `omitted:`.
4. Lows are never rendered — only `omitted: low=N`. If the block must shrink, Lows go first;
   Criticals/Highs never shrink.
5. `verifier_verdict` is appended as ` (verified: upheld|refuted)` only when the structured source
   supplied it; `refuted` findings still render (they are information, and today's verdict already
   ignores them — see §6 R3).
6. `report:` always present when a report file exists — the pointer for the human.
7. Verdicts with zero findings emit `findings: none` (explicit), never an absent key.

Key order is fixed and existing keys keep their current positions, so `head -1`, `^status:` greps,
and `sed -n '1p'` consumers are unaffected.

### `reviewer_says: do_not_merge`

Emitted when the report body matches any of (ASCII case-insensitive; Cyrillic matched in both
lower- and capitalised forms because BSD `grep -i` is not reliable on non-ASCII):

`do not merge`, `don't merge`, `not merge as-is`, `must not land`, `should not be merged`,
`не мержить`, `не мержим`, `нельзя мержить`, `не мержить как есть`

Matches 95eb1cb9's «Код не мержить как есть» in the Вердикт section.

**It does not change `status:`.** Hard constraint: this changes what the gate SHOWS, not what it
DECIDES. A `PASS_WITH_NITS` + `do not merge` report still writes `status: pass` and exit 0 — with
`reviewer_says: do_not_merge` and the Medium itself now on the face of the gate. Turning that into
a blocking verdict is a real follow-up but it is a **decision** change and belongs to its own lane
with its own approval. Flagged in §7.

---

## 4. Parse-failure degradation (the anti-lying-green requirement)

If `critical+high+medium > 0` per `REVIEW_FINDINGS:` but the extractor produced zero items for
those severities, the block is:

```
findings_source: none
findings: unavailable
findings_reason: parse_failed
report: docs/handoff/dispatch-<id>/review-<arm>.md
```

Same block, `findings_reason: report_missing`, when the report file is absent/unreadable. Never a
`status: pass` with a silently absent findings block: the block is written on **every** pass/fail
exit of both writers, so its absence can only mean an old build, and its `unavailable` form is
visibly different from `findings: none`.

Zero counts and zero items is the one legitimate quiet case → `findings: none`.

---

## 5. Data flow (numbered)

1. Reviewer arm writes `docs/handoff/dispatch-<id>/review-<arm>.md` (unchanged).
2. Writer parses `REVIEW_VERDICT:`/`REVIEW_FINDINGS:` via `parse_review_verdict` (unchanged).
3. Writer decides verdict + exit code (**unchanged, byte for byte**).
4. **New:** writer calls `render_gate_findings <report> [<json>] <arm> <relpath>`; renderer tries
   structured → markdown → degrade; emits block on stdout.
5. Writer concatenates existing head lines + block into `review-gate.md.tmp`, `mv -f` into place.
6. Ledger `emit decision` line gains one additive token `do_not_merge=1` when the flag fired
   (log surface for the same fact); all existing tokens unchanged.

---

## 6. Risks

| # | Risk | Mitigation |
|---|---|---|
| R1 | **Fix lands only in `review-run.sh`** → invisible on the live path (§0). | Both writers call the same renderer; the evidence step runs against the three real `product-close`-written gates. Acceptance is a rendered gate file, not a unit test. |
| R2 | **13 test files under `plugins/leadv2/scripts/tests/` reference `review-gate.md`**; some may assert exact content/line counts. | Before editing, grep those 13 for exact-match/`wc -l`/`diff` assertions on the gate; run the full suite after. Additive-and-append-only key order is chosen precisely to keep `^status:` and `head -1` consumers green. |
| R3 | Renderer crash (bad regex, unset var under `set -u`) **kills the gate mid-write**. | Renderer is rc-always-0 and stdout-only; writer invokes it as `render_gate_findings … || true` and the head lines are printed **before** the call, so a total renderer failure degrades to today's exact output, never to a missing gate. |
| R4 | **False-positive `do_not_merge`** ("no reason not to merge"). | Phrase set is narrow and imperative-only; the flag is advisory and changes no decision, so a false positive costs one noise line, never a wrong merge. Deliberate asymmetry: false-negatives are the expensive direction. |
| R5 | **BSD/macOS toolchain** — no `grep -P`, bash 3.2, no `grep -i` guarantee on Cyrillic, no GNU `sed -i`. | `grep -E`/POSIX `awk`/`sed -E` only; Cyrillic phrases listed in both cases; no in-place edits. Same constraint set the surrounding scripts already obey. |
| R6 | Reviewer prose contains characters that break the block (backticks, `:`, newlines in an item). | Items are single-line by construction (first line only), truncated, and whitespace-collapsed; leading `- ` list form keeps a stray `:` harmless for a YAML-ish reader. |
| R7 | `product-close` writes the gate with a non-atomic `>` at 2037/2045; the file becomes multi-line, so a concurrent reader can now see a torn gate. | Convert both to `> …tmp; mv -f` in the same change (matches `review-run.sh`'s existing discipline). |
| R8 | Extractor tuned to three reports; a fourth arm's shape (codex/opus tables) misses. | That is exactly what §4 exists for — a miss degrades to `findings: unavailable` + pointer, which is strictly better than today and never a silent pass. |

---

## 7. Non-goals (explicit — implementer must not do these)

- **No verdict/exit-code/ledger-decision change.** `PASS_WITH_NITS` + do-not-merge still exits 0.
- No change to the reviewer prompt/`review_contract` (adding `FINDING:` lines to `product-close`'s
  contract would improve fidelity but changes reviewer behaviour and cost — separate lane).
- No change to `blocked`/`unreviewed`/`review_body_lost`/`no_verdict_marker` gate writers.
- No change to `review-findings.json`'s schema or to the verify/dedup synthesis (613–711).
- Nothing under any consuming project (`~/Projects/persona-engine` is **read-only evidence** here).
- No new dependency (`jq`/`python` not required on the render path).
- No `docs/leadv2/**` or `docs/handoff/**` writes from the lane.

---

## 8. Evidence procedure (mission requirement)

For each of `dispatch-{9573bd97,95eb1cb9,82e1056d}` in `~/Projects/persona-engine/docs/handoff/`:
run the renderer CLI against that lane's `review-glm.md` and splice its output under the lane's
real `review-gate.md` head lines, producing the gate that lane would now get. Paste all three
verbatim into `docs/missions/REVIEW-GATE-SHOWS-FINDINGS-01.report.md`. Expected, per the mission's
three cases: 9573bd97 → 3 Mediums visible incl. the stale `stop_reason` mirror; 95eb1cb9 →
`reviewer_says: do_not_merge` + the symlink-over-tracked-files Medium; 82e1056d → both Highs
named. Do not mutate persona-engine files.

---

acceptance:
  - surface: file_artifact
    observable: |
      docs/missions/REVIEW-GATE-SHOWS-FINDINGS-01.report.md shows the review-gate.md that lane
      82e1056d now produces, and a reader sees two lines beginning "- [High] scripts/gate-cost-report.sh"
      — one naming the discarded anchor, one naming the regex that cannot match the journal format —
      instead of only "high: 2".
    authored_at: 2026-08-14T23:04:30+03:00
  - surface: file_artifact
    observable: |
      In the same report, lane 95eb1cb9's gate shows the line "reviewer_says: do_not_merge" and a
      "- [Medium] scripts/vps-release-deploy.sh …" line about symlinks over git-tracked files, while
      its "status: pass" line is unchanged from today.
    authored_at: 2026-08-14T23:04:30+03:00
  - surface: file_artifact
    observable: |
      A reviewer report whose findings cannot be parsed yields a gate reading "findings: unavailable"
      with "findings_reason: parse_failed" and a "report: …/review-<arm>.md" pointer — a human sees an
      explicit unavailability, never a pass with no findings section.
    authored_at: 2026-08-14T23:04:30+03:00

LANE_WRITES: plugins/leadv2/scripts/leadv2-review-findings.sh, plugins/leadv2/scripts/leadv2-review-run.sh, plugins/leadv2/scripts/leadv2-dispatch-product-close.sh, plugins/leadv2/scripts/tests/test-review-gate-shows-findings.sh, docs/missions/REVIEW-GATE-SHOWS-FINDINGS-01.report.md

DELIVERABLE_COMPLETE
