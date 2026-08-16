# architect — REPORT-ONLY-GATE-01 round 2 (rebase/merge resolution)

## Scope

Land already-reviewed work. **No behaviour is redesigned.** The single deliverable is a
correct three-way resolution of one conflict hunk plus a re-run of both suites.

## State on disk (verified)

- Branch `main` is mid-merge: `MERGE_HEAD = b1c9bd3d` (the lane), `HEAD = bb400e9`.
- Exactly one file is `UU`: `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh`.
- Exactly one conflict hunk: lines 2152–2179 — the **review-gate PASS exit**.
- Everything else auto-merged clean, including:
  - lane files `lib/leadv2-report-deliverable.sh` (new), `tests/test-report-only-gate.sh`
    (new), `tests/run-core-offline.sh` (registration at line 127), `leadv2-dispatch-code.sh`;
  - main's PR02 reliability fixes and the FAIL-exit findings rendering (line ~2136-2150),
    which the lane never touched.

So the "one conflict" framing is accurate, and the PR02 items (run_dir at both reap sites,
pgid group signalling, grace-branch reorder) are already carried in the working tree — the
resolution must not re-edit them.

## Why the two sides are complementary, not competing

| side | question it answers | mechanism |
|---|---|---|
| `HEAD` (REVIEW-GATE-SHOWS-FINDINGS-01) | *how* does the gate report? | append `render_gate_findings` block to the pass artifact, tmp+mv, `RGF_DO_NOT_MERGE` advisory suffix |
| `b1c9bd3d` (REPORT-ONLY-GATE-01) | *what* did the lane produce? | branch on `_pc_kind == report`; emit `kind:/deliverable:/bytes:/review:` head lines and pass the harvested path as `_dl_note` arg 9 |

The first changes the artifact's **tail** and its write discipline; the second changes its
**head lines** and the ledger row. They compose by nesting: keep the report/diff branch on
the head-line `printf`, and apply the findings-append + tmp/mv to **both** arms.

Any resolution that drops one side is wrong by construction. Specifically:
- dropping `render_gate_findings` on the report arm would mean a report lane's pass artifact
  silently loses the block that REVIEW-GATE-SHOWS-FINDINGS-01 R7 says is written on *every*
  pass/fail exit — its absence would then no longer prove "old build";
- dropping the `_pc_kind` branch reverts REPORT-ONLY-GATE-01's whole gate surface.

## Target resolution (replace lines 2152–2179, the markers inclusive)

```bash
# REVIEW-GATE-SHOWS-FINDINGS-01: same append + tmp/mv discipline on the pass exit —
# the block is written on EVERY pass/fail exit, so its absence can only mean an old
# build, and a do-not-merge report shows on the face of a passing gate (advisory only:
# status: stays pass, decision semantics unchanged).
_rgf_rel="docs/handoff/dispatch-${TASK}/review-${reviewer}.md"
[[ -n "${REVIEW_SOURCE:-}" ]] && _rgf_rel="${REVIEW_SOURCE#artifact:}"
_rgf_dnm=""; [[ "${RGF_DO_NOT_MERGE:-0}" == "1" ]] && _rgf_dnm=" do_not_merge=1"
if [[ "${_pc_kind}" == "report" ]]; then
  # REPORT-ONLY-GATE-01: the report lane's pass shape — kind/deliverable/bytes/review
  # name the file a human can open in the main checkout after the lane worktree is gone.
  # Terminal is the unchanged `landed`; write-terminal's deliverable arg (9th) carries
  # the harvested path, commit stays "none" (no code landed).
  {
    printf 'status: pass\nreviewer: %s\nkind: report\ndeliverable: %s\nbytes: %s\nreview: %s\n' \
      "${reviewer}" "${_pc_report_deliverable}" "${_pc_report_bytes}" "${verdict}"
    render_gate_findings "${review_file}" "" "${reviewer}" "${_rgf_rel}" || true
  } > "${HANDOFF}/review-gate.md.tmp"
  mv -f "${HANDOFF}/review-gate.md.tmp" "${HANDOFF}/review-gate.md"
  _dl_note landed review_verdict_pass \
    "diff=${diff_hash:0:8} deliverable=${_pc_report_deliverable}${_rgf_dnm}" \
    "" "${_pc_report_deliverable}"
else
  {
    printf 'status: pass\nreviewer: %s\ndiff: %s\n' "${reviewer}" "${diff_hash:0:8}"
    render_gate_findings "${review_file}" "" "${reviewer}" "${_rgf_rel}" || true
  } > "${HANDOFF}/review-gate.md.tmp"
  mv -f "${HANDOFF}/review-gate.md.tmp" "${HANDOFF}/review-gate.md"
  _dl_note landed review_verdict_pass "diff=${diff_hash:0:8}${_rgf_dnm}"
fi
```

Deliberate points:

1. `_rgf_rel` / `_rgf_dnm` are hoisted **above** the branch — one definition, both arms.
   `_rgf_dnm` is now computed before `_dl_note` on both arms (HEAD computed it after the
   write, which was fine because it only fed `_dl_note`; hoisting preserves that and
   removes the duplicate).
2. The report arm's evidence string gains `${_rgf_dnm}` — it is the same advisory suffix
   the diff arm carries; omitting it on report lanes would make do-not-merge invisible in
   the ledger for exactly the lane type whose whole output is prose.
3. `_pc_kind` is unquoted-safe: set unconditionally at line 43 (`_pc_kind="diff"`), so no
   `set -u` exposure. `_pc_report_deliverable` (line 1514) and `_pc_report_bytes`
   (line 1502) are only read inside the `report` arm, which is only reachable after the
   block that sets them.
4. `render_gate_findings` has a no-op fallback at line 77
   (`command -v … || render_gate_findings() { :; }`), so the report-lane tests that do not
   source the findings lib still produce the exact head lines they assert on
   (`^kind: report`, `^deliverable: docs/handoff/dispatch-rog1c1sig/report.md`) — the
   append is empty, not garbage. This is why nesting is safe without touching the tests.
5. `> …tmp` + `mv -f` replaces the lane's direct `>` on the report arm too. The lane's
   original single-`printf` write was atomic-enough; once a multi-line append follows it,
   it is not. Same reasoning R7 applied to the fail exit.

## Non-goals (implementing agent: do not do these)

- Do **not** re-open `lib/leadv2-report-deliverable.sh`, `tests/test-report-only-gate.sh`,
  `leadv2-dispatch-code.sh`, or `run-core-offline.sh` — they merged clean and are reviewed.
- Do **not** touch the FAIL exit (~2136-2150) or the `no_verdict` / `unreviewed` exits.
- Do **not** add a report branch to the FAIL exit. Out of scope for this lane; a report
  lane that fails review takes main's shape, unchanged from before.
- Do **not** touch `docs/leadv2/open-threads.md` or anything under `docs/leadv2/`.
- No deploy, no push to any other repo. `~/Projects/leadv2` is the single source.

## Risks

| risk | mitigation |
|---|---|
| Resolution keeps only one side (the classic merge failure this lane exists to avoid) | the target block above contains both markers' comment headers; a post-resolve `grep -c 'render_gate_findings' ` on the pass region must be **2**, and `grep -c '_pc_kind.*report'` must be ≥1 |
| Stale conflict markers left in file | `grep -n '^<<<<<<<\|^=======$\|^>>>>>>>' <file>` must return empty; `bash -n <file>` must be clean |
| Green-before-rebase mistaken for green-after | both suites are re-run **after** `git add` of the resolved file and before commit; paste actual output |
| Report arm loses do-not-merge signal | `${_rgf_dnm}` appended to the report arm's `_dl_note` evidence (point 2) |
| `_dl_note` arg-9 position drifts | signature comment at line 93 confirms `<terminal> <cause> [<evidence>] [<commit>] [<deliverable>]`; the report arm passes `""` for commit, path for deliverable — unchanged from the lane's reviewed form |

## Verification plan

1. `bash -n plugins/leadv2/scripts/leadv2-dispatch-product-close.sh`
2. `bash plugins/leadv2/scripts/tests/test-report-only-gate.sh` — 5/5
3. `bash plugins/leadv2/scripts/tests/run-core-offline.sh` — full suite, includes both
   `test-report-only-gate.sh` (line 127) and the review-gate-findings coverage carried by
   main. A pass here is the only evidence that the two behaviours coexist.
4. `git add` the resolved file, `git commit` the in-progress merge.

## acceptance

```yaml
acceptance:
  - surface: file_artifact
    observable: >
      After a report-only lane passes review, opening
      docs/handoff/dispatch-<TASK>/review-gate.md shows, in one file, both a head naming the
      prose deliverable ("kind: report" and a "deliverable:" path a human can open in the
      main checkout) and, below it, the reviewer's findings block — not bare counts.
    authored_at: 2026-08-16T00:00:00Z
  - surface: rendered_line
    observable: >
      The core offline suite's terminal output ends with every check reported as passing,
      with the "report-only gate (REPORT-ONLY-GATE-01: report lane deliverable)" line and
      the review-gate-findings line both shown as passing in the same run.
    authored_at: 2026-08-16T00:00:00Z
  - surface: file_artifact
    observable: >
      leadv2-dispatch-product-close.sh, opened in an editor, contains no conflict markers
      anywhere.
    authored_at: 2026-08-16T00:00:00Z
```

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-product-close.sh

DELIVERABLE_COMPLETE
