# PLUGIN-PREPASS-TRUTH-BUNDLE-01 — three founder rows, one file, one lane

Backlog rows `28c85708da3e` (`PLUGIN-PREPASS-PHANTOM-DESIGN-01`), `09714c4fc3a7`
(`PLUGIN-PREPASS-MISLABELS-EVERY-FAILURE-01`) and `9314a9ffdd6e`
(`PLUGIN-PREPASS-EXCLUDES-CODEX-AS-SAME-PROVIDER-01`).

They are **one lane** because all three write the same region of the same file — the
`ARCHITECT_PREPASS_*` path in `plugins/leadv2/scripts/leadv2-dispatch-code.sh`. Run as three
lanes they would serialise behind each other for three rounds and each would have to declare the
other two off-limits. Run as one lane they are three small, independent changes with three
independent controls.

Repo for ALL writes: **`~/Projects/leadv2`** — you are in its lane worktree.

They are independent: **fix and prove each one separately.** Do not let a difficulty in one
defect stall the other two — a report that lands two of three with their controls, and names the
third as unfixed with its cause, is a better outcome than three half-fixes.

---

## Defect 1 — the prepass admits Build on the arm's PROSE
The architect prepass admits Build on what the arm *said* it did. An arm reported a design
"committed, 229 lines" at a path that exists in **no ref** — not in the worktree, not in `main`,
not in any branch — and the prepass still passed the lane to Build. The gate reads the claim; it
never looks at the artifact.

**Fix.** Before the prepass admits Build, verify the claimed design artifact:
1. Resolve the path the prepass believes was written (however it is currently derived).
2. It must exist and be readable — in the lane worktree, or resolvable via
   `git -C <lane-root> cat-file -e <ref>:<path>`. A path in no ref is a FAILURE.
3. It must be non-trivial: reject an empty file or a stub. Pick a floor, state it in a comment
   (e.g. fewer than 20 non-blank lines is a stub), and say why that floor.
4. Journal the outcome with **`design_artifact_verified`** on success and a **distinct, named**
   cause token on failure — `design_artifact_missing` / `design_artifact_stub`. Never reuse a
   generic reason word: the entire point of this defect is that a cause must be nameable from the
   journal alone.
5. A failed verification must NOT silently pass. Refuse the prepass with the named reason.

## Defect 2 — every prepass failure is labelled `rate_limited`
The prepass journals `reason=rate_limited` for outcomes that are not quota at all:
- **`rc=124`** — the arm was KILLED by the prepass's own timeout
  (`LEADV2_DISPATCH_ARCHITECT_TIMEOUT_SEC`, default **420s**). That is a timeout, not a quota
  refusal.
- **`rc=1` with `status=allowed`** — the arm was admitted and then failed for its own reason. Also
  not quota.

Consequence: the journal can never name the real cause, so nobody can tell a quota wall from a
too-short timeout from a broken arm. Live on 2026-09-14: five lanes dispatched at 18:3x sat in the
prepass 5+ minutes each and produced no journal line at all.

**Fix.** Give each outcome its own cause token. `rc=124` → **`prepass_timeout`**, journalling the
timeout value that killed it so a 420s default is visible AS the cause. `rc=1` with
`status=allowed` → its own distinct token. `rate_limited` must stay reachable ONLY for a real
quota refusal — narrow it, do not delete it.

## Defect 3 — codex is excluded as `same_provider`
The architect fallback skips codex with `reason=same_provider` after a claude failure. Codex is a
different provider with its own launcher and its own quota; excluding it means that after a claude
prepass failure there is **no arm left to try**, and the lane stalls. Measured 2026-09-14:
`arm=claude class=rate_limited consumed_pct=88 usable_now=0.491`, `util_glm=86` against a
no-bypass threshold of 80 — codex was the one arm with a launcher and free quota, and the fallback
refused to try it.

**Located for you — verify before trusting it.** This is a peer session's read, not a probe anyone
ran: `leadv2-dispatch-code.sh:5930` compares `prov == failed_prov`; the `claude*` branch at
`:6350` is expected to set `failed_prov=anthropic` and evidently does not, so `failed_prov` keeps
a value that also matches codex. Read both line regions yourself before changing anything. If the
real shape differs, fix what you actually find and say so in the report — a fix built on someone
else's read of a line number is how a premise goes wrong.

**Fix.** Codex must be eligible in the architect fallback after a claude failure. Correct the
provider identity **at its source** — the branch that fails to set `failed_prov` — not by
special-casing codex at the comparison site. If some pairing genuinely IS the same provider, keep
that case excluded and name it in a comment.

---

## Known trap
`price_ratio` / `excluded=` conflate "was not admitted" with "competed and lost". When you read
arbiter journal lines to confirm behaviour, read `arbiter_pick` and the utility values, never an
`excluded=` list.

## Acceptance — three registered probes, all must go rc=0
- `grep -q design_artifact_verified ~/Projects/leadv2/plugins/leadv2/scripts/leadv2-dispatch-code.sh`
- `grep -q prepass_timeout ~/Projects/leadv2/plugins/leadv2/scripts/leadv2-dispatch-code.sh`
- the codex-eligibility probe for `9314a9ffdd6e` (row `human-adhoc-e433291c6126`)

Those greps are necessary, never sufficient. Also required, under `plugins/leadv2/scripts/tests/`:

1. A test driving the **real** artifact-verification step with (a) a present, non-trivial artifact
   → admitted, (b) a path in no ref → refused with `design_artifact_missing`, (c) an empty/stub
   file → refused with `design_artifact_stub`.
2. A test driving the **real** prepass outcome-classifier with `rc=124` → `prepass_timeout`;
   `rc=1 status=allowed` → its own token; a genuine quota refusal → `rate_limited`.
3. A test that the architect fallback, after a claude failure, admits codex as a candidate.

Keep the production function under claim REAL and fake one level lower. A test that reimplements
the classifier proves only that you can write the same `case` statement twice.

## Negative controls — one per independent check, ALL RUN
1. Make the artifact verification return success unconditionally, inside the function body →
   test 1 goes RED.
2. Collapse the three outcomes back to `rate_limited`, inside the classifier the callers actually
   reach → test 2 goes RED.
3. Restore the `same_provider` exclusion for codex → test 3 goes RED.

Paste all three red/green pairs. One mutation is not a control for three checks, and a
single-point mutation against redundant readers proves nothing — mutate the code path the callers
actually take, never a copy. Every mutation anchor must fail **loudly** when it does not match: an
unmatched anchor is a test failure, never a silent skip, and an anchor bound to exact source bytes
rots into a permanent green the first time the line is reformatted.

## Off limits
- Do **not** change the prepass TIMEOUT VALUE. This row makes the timeout *nameable*, not longer;
  changing 420s is a separate decision.
- Do not touch arm selection outside the one `failed_prov` identity bug, the route arbiter, quota
  accounting, the no-bypass threshold, or the review gate.
- Do not edit `docs/tasks.yaml` in persona-engine — it is a generated mirror.
- Do not `git stash`, `git reset --hard`, or `git clean`: this checkout is shared with live
  sessions.
- Keep the diff minimal — three verification/labelling changes plus their tests, nothing else.

## Report
`docs/handoff/PLUGIN-PREPASS-TRUTH-BUNDLE-01/report.md`, with a section per defect so each row can
be closed on its own evidence: the diff summary, the probe rc, the test output green, the control
output red. If a defect is unfixed, say so under its own heading with the cause — do not fold it
into the others. End with `DELIVERABLE_COMPLETE`.
