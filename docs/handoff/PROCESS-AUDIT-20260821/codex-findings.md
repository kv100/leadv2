# Process audit: the new machinery mostly moved failure around

Git-history cutoff: repo HEAD `e930421c`, committed `2026-08-21 17:36 +03`. The separately labelled
persona artifact snapshot includes architect streams through `18:15 +03`; those current worktree
artifacts inform Q2/Q3 and timings, not the landed-commit census. All counts below are lower bounds
unless explicitly labelled exact. I used first-parent mainline history so that merges made *inside*
a lane are not counted as landed lanes.

## Verdict

The complaint is supported. In the 15 landed lanes from 08-17 through the cutoff, the retained
artifacts prove at least **18 model-review invocations and 10 explicit FAIL rounds**. In the 11
standardized `merge: ... lane <id>` landings, the lower bound is **15 invocations and 10 FAILs**:
**1.36 review invocations and 0.91 explicit FAIL rounds per landed lane**. Ten of those lanes reached
a model reviewer; among them the lower bounds are **1.5 invocations and exactly 1.0 explicit FAIL per lane**.
Those are not the numbers of a process that has demonstrated fewer review rounds. Evidence:
first-parent merge subjects/bodies listed in the table below; reproduction command in Appendix A.

Three pieces did something useful, but more narrowly than advertised:

1. **STOP-GATE preserved dirty work; it did not stop deaths.** Six unique post-merge commits say
   `auto-checkpoint on worker exit (STOP-GATE)` (`5b35a06`, `7ebb24a`, `96ff69c`, `e329f7b`,
   `dccd21e`, `eb51d0d`). That is recovery evidence, not reliability or speed evidence.
2. **The builder selfcheck catches mechanical failures.** Its own lane caught an invalid Python
   fixture before landing (`0537906`), and current C0 rejects off-write-set/over-40-file diffs
   (`plugins/leadv2/scripts/lib/leadv2-builder-selfcheck.sh:150-205`). It did not reduce later
   model rounds: the eight later landings contain at least 11 reviews and nine explicit FAILs.
3. **Suite sharding produced a real timing improvement in a benchmark, not a production win.**
   `a5db688` records serial `60/0` in **1417 s** and sharded runs in **339-1035 s**, but also two
   repo-state collisions; the safe default therefore remained serial.

The sharpest failure is the test-falsification gate. It executes the current test once and trusts a
stdout sentence as proof of a counterfactual it never runs
(`builder-selfcheck.sh:397-450`). In persona-engine, **0 of 755 matching shell tests** contains the
marker. Of 18 current dispatch selfchecks, 13 are RED and 12 contain
`falsification_missing|marker_missing`; in other words, **12/13 REDs are convention mismatch, not a
failed behavioral check**. `dispatch-32351f66/selfcheck.md:9-50` is the clean demonstration: scope
and syntax pass, the test itself reports `21 passed / 0 failed`, then the lane is RED only because
the marker is absent.

## Q1 — what measurably worked

### Landed-lane review census

“Review” means a distinct retained adversarial verdict or explicit round label. “FAIL” requires the
literal verdict/merge evidence; missing artifacts are never inferred as PASS. Machine selfcheck
blocks are separate.

| Landing | Lane | Min model reviews | Explicit FAIL | Evidence / assessment |
|---|---|---:|---:|---|
| `a1ab5c5` | FORK-RUNS-A-SESSION-01 | 1 | 0 | Branch range contains its review/fix commit; legacy merge lacks standardized round metadata. |
| `b0690d4` | WHEN-TO-FORK-01 | 1 | 0 | Branch range contains reviewed r3 work; legacy merge. |
| `a4e3f89` | founder pulse | 1 | 0 | Branch range retains one review-bearing implementation commit; legacy merge. |
| `601e882` | founder lane view | 0 | 0 | No retained model-verdict proof; do not infer one. |
| `82da344` | SUPERVISOR-DELETE-01 | 1 | 0 | Merge says `review PASS_WITH_NITS 16b2dc89`. |
| `4f9d4b8` | V3-GLM-LADDER-01 | 2 | 1 | Merge says `review r2 PASS_WITH_NITS`; retained `docs/handoff/dispatch-eb2d7143-review/critic.full.md:6` says `VERDICT: FAIL`. |
| `53d4465` | BUILDER-SELFCHECK-GATE-01 | 1 | 0 documented | `faf3003` calls the implementation r7, but the only retained formal review proof is the merge’s `PASS_WITH_NITS`; implementation rounds are not counted as review invocations. |
| `2bfbf8e` | SUPERVISOR-RESIDUE-SWEEP-01 | 1 | 0 | Merge says `PASS_WITH_NITS`. |
| `36c6ceb` | SUPERVISOR-RESIDUE-FOLLOWUP-01 | 1 | 1 | Merge says `codex review FAIL findings both fixed`. |
| `6ae373a` | V3-STOP-GATE-01 | 3 | 3 | Merge: `opus-critic FAIL + codex r2 FAIL + codex r3 FAIL`. |
| `585ad7f` | V3-DISPATCHER-ACCEPTANCE-01 | 3 | 2 | Merge: `codex r3 PASS after opus-critic FAIL + codex r2 FAIL`. |
| `51aa2b2` | SCOPE-DISCIPLINE-01 | 1 | 1 | Merge: `codex r1 FAIL closed by 191d8f1`. |
| `215890e` | COMBO / TIERED-REVIEW | 1 | 1 | Merge: `codex r1 FAIL closed by dccd21e`. |
| `89fe065` | TEST-FALSIFICATION-GATE-01 | 1 | 1 | Merge: `codex r1 FAIL closed by 80147a7`. |
| `a5db688` | SUITE-SPEED-01 | 0 | 0 | Machine-blocked before model review: `dispatch-74658fef/review-gate.md` names three marker-missing failures. |

This population is **15 exact first-parent two-parent landings**: 11 standardized lane merges plus
four legacy worktree/hash merges. There are 132 commits in the time window, but most are lane
checkpoints, fix commits, state, docs, or unrelated status work; treating all 132 as independent
“fixes” would double-count the same lane.

### Mechanism scorecard

| Commit(s) | Claimed mechanism | Observed result | Judgment |
|---|---|---|---|
| `6b79c2c` | Exhaustive round 1, verification-only later rounds | Later standardized landings still have 10 explicit FAIL rounds. The implementation tells later reviews to admit a new finding only if a fix introduced it (`leadv2-review-run.sh:694-710`), so it can narrow later review without proving round 1 was complete. | **No measured round reduction; potentially hides an old miss.** |
| `9a512a2` | Prepass rc/artifact race grace | Commit names two complete designs parked twice and adds a <=10 s recheck. No later same-shape incident is retained in the audit window. | **Worked on two concrete false parks; broader rate unknown.** |
| `53d4465` | Builder selfcheck before review | It catches syntax/changed-suite failures and caught the invalid fixture fixed at `0537906`. Eight later landings still show >=11 model reviews / 9 FAILs. | **Worked narrowly; did not demonstrate fewer reviews.** |
| `6ae373a` | Commit-before-exit STOP-GATE | Six later auto-checkpoint commits prove preservation. At least five later landed lanes still contain >=6 reviews / 5 FAILs, and worker exits continued. | **Recovery worked; death prevention and round reduction did not.** |
| `585ad7f` | Absolute handoff root, foreign-root guard, safe retry-dead | Three later reviewed lanes all have explicit FAIL, followed by a machine-blocked lane. Same-day dispatch repairs `5ad93de`, `e9d8812`, `a5a06c5`, `3640a5b` show the subsystem was still unstable, though not necessarily the same three faults. | **Specific guards exist; outcome claim not demonstrated.** |
| `51aa2b2` | Bounce off-write-set diffs before review | Current code does reject off-write-set paths, but skips when no write set exists (`builder-selfcheck.sh:150-205`). Only one later model-reviewed lane exists before overlapping mechanisms land. | **Enforcement exists; insufficient post-exposure evidence.** |
| `215890e` / `fd2be5b` | Machine round 0 + tiered review | Round 0 consumes only a hash-matched RED selfcheck (`leadv2-review-run.sh:826-857`). Product-close already exits on the same RED at `leadv2-dispatch-product-close.sh:2088-2103`, before review. The lane review engine is default-off in production (`review-run.sh:24-27`; `dispatch-product-close.sh:2220-2235`). | **Redundant on the production lane path; no measured saving.** |
| `89fe065` / `80147a7` | Require RED-then-GREEN proof | It immediately blocks incompatible persona tests and trusts a marker without executing the negative state. Current persona evidence: 0/755 matching tests carry it; 12/13 RED selfchecks are marker mismatch. | **Net-negative hard block; delete/default-off now.** |
| `a5db688` | Parallel suite shards | `1417 s` serial versus `339-1035 s` sharded, but two repo-state collisions. No later landing exists in-window. | **Benchmark win; not acceptance-equivalent or ready as default.** |
| `5ad93de`..`7660fb1` | Detached workers, dead-row release, trusted worktrees, log-mtime liveness, shared-transport attribution | These landed after the main lane census. Their own bodies document one sweep killing four lanes in 15 s (`5ad93de`) and one shared transport stopping three in 32 s (`7660fb1`). There is no post-exposure cohort in-window. | **Plausible fixes, no outcome evidence yet. Do not declare victory.** |

### What the named gates actually enforce

- **Scope:** C0 parses both sides of diff headers, rejects a path outside a declared write set, and
  rejects more than 40 changed files; with an empty declaration it explicitly SKIPs
  (`builder-selfcheck.sh:150-205`). The earlier dispatch declaration guard is weaker: it accepts row
  writes, a report deliverable, prepass `LANE_WRITES`, **or merely an existing lane worktree**
  (`leadv2-dispatch-code.sh:2671-2704`); because worktree ensure occurs before it
  (`:4395-4435`), that last alternative can make declaration enforcement vacuous. In the persona
  corpus, 587/641 prepasses have `LANE_WRITES`; 54 do not. The separate LANE-SHAPE diagnostic gate
  is off by default (`leadv2-dispatch-code.sh:4653-4678`).
- **Stop:** dispatch-code only adds a sentence telling the worker to commit
  (`leadv2-dispatch-code.sh:4641-4650`). The real mechanism is product-close’s scoped temp-index
  checkpoint (`leadv2-dispatch-product-close.sh:1461-1573`), which no-ops without a write set/lane/
  dirt and logs then returns 0 on checkpoint errors. It is recoverability, not enforcement against
  death or uncommitted exit.
- **Review:** round 0 consumes an exact-diff RED; round 1 asks for five lenses; later changed diffs
  become verification-only only when prior findings are parseable (`leadv2-review-run.sh:583-710`,
  `:826-857`). Default fanout remains three plus hack detection (`:63-64`, `:880-918`), so “tiered”
  narrows the later prompt but does not by itself reduce arm count.

One part of the complaint is **not** supported: infrastructure deaths did not create the formal
review findings. The 10 formal FAIL rounds retained by six merge subjects plus the GLM critic
artifact are substantive; the history names **zero formal FAIL verdicts caused by infrastructure**. Infrastructure did burn at
least one reviewer attempt (`d85fbfb` records an untrusted-worktree review body of 158 bytes versus
1909 bytes after trust) and generated retries, but it is not an explanation for the Critical/High
defects reviewers found.

## Q2 — why rounds multiply

The founder’s hypothesis is directionally right, but “the consequence was not drawn” is false in
the concrete example.

Round 5’s original mission explicitly says a Codex review found three Highs
(`persona-engine/docs/handoff/dispatch-32351f66/lane-mission.md:208-217`). The prepass copies that
shape into `Design — three changes` (`architect-prepass.md:23-25`). It also records that only
`check_voice_quality` is retried and every other stage is terminal (`:15-17`), then deliberately
designs unreadable policy as rc 2 -> build rc 3 -> terminal/no retry (`:31-58`, `:122-130`). The
prepass even names the consequence: “freezes the post queue for a tenant,” and answers “Blocking is
the point” (`:133-143`, specifically `:137`).

So the failure was not failure to notice. It was **mission-framed judgment plus incomplete
mechanism census**: “fail open” made “fail closed” look like the only safe opposite, and the plan did
not require enumerating every caller/configuration state before accepting that availability trade.
Round 6 then finds the missing mechanism:

```text
dispatch-832270b2/architect-prepass.md:44-58
Door A: over-cap policy -> rc=2 -> rc=3 -> immediate return -> every post slot dies
Door B: enforcement reader, not named by the mission -> rc=2 -> every post burns all redrafts
```

The same artifact proves both oversize modes cause the outage and the live file has only 72 bytes of
headroom (`dispatch-832270b2/architect-prepass.md:64-97`). This is exactly defect-at-a-time design:
round 5 fully implements the named H1/H2/H3 framing; round 6 discovers an unenumerated caller and a
configuration boundary.

The corpus supports the mechanism but not the strongest universal wording. Across 641 persona
prepasses, 575 (89.7%) contain at least three numbered design steps, 300 (46.8%) mention findings,
and 144 (22.5%) title themselves round 2 or later. Nineteen (3.0%) contain the literal phrase
“three changes”; ten use it in a heading and eight use it in a `Design` heading. Forty-seven (7.3%)
contain both H1 and H2 headings. Across the 427 paired `lane-mission.md` files with an
original-mission separator, 346 (81.0%) contain at least three Markdown list items, 123 (28.8%)
mention findings, and 30 (7.0%) have H1+H2 headings. Lists are prevalent; “every mission is an H-list”
is not supported.

The dispatcher structurally reinforces fixation. Its architect prompt asks for “changes, exact
files, and explicit non-goals” (`leadv2-dispatch-code.sh:2860-2862`). It then gives the builder an
“authoritative” design and says `Implement ONLY` it; the design wins on conflict
(`leadv2-dispatch-code.sh:4576-4591`). There is no required caller census, state-transition table,
configuration boundary census, or counterexample to the mission’s framing in that contract.

The better root cause is therefore:

> Findings define the boundary; the prepass makes that boundary authoritative; the builder is
> forbidden to leave it; and the review sees the mechanism. Without a required whole-mechanism
> census before build, omitted callers and states become later review rounds.

## Q3 — what the tests prove

### The current falsification gate is an attestation ritual

The gate does four things: recognizes only shell basenames `test-*.sh|*_test.sh`, executes the
current-tree test once, requires rc 0, then greps its stdout for
`RED-then-GREEN: ... (pre_rc=1 -> post_rc=0)` (`builder-selfcheck.sh:423-447`). It does **not**:

- run the test against the pre-fix tree;
- apply or verify a mutant/negative control;
- bind the marker to the command that failed;
- ensure the negative program parsed successfully;
- cover Python/TypeScript/Swift test files.

Therefore the marker proves only “a passing shell process printed a sentence.” A test can print the
regex and pass the gate; conversely a genuine paired falsification in a repo whose harness uses a
different output convention is rejected. The current persona example is the latter:

```text
dispatch-32351f66/selfcheck.md:9-12     scope=0, bash-n=0, falsification_missing
dispatch-32351f66/selfcheck.md:14-48    real directory + chmod cases, 21 passed, 0 failed
dispatch-32351f66/selfcheck.md:50       verdict: RED
```

The three reviewer examples in the brief are the other side of the same defect. Comparing 9 of 11
lines, letting a doubled cap survive, or recomputing the same algebra does not become independent
evidence because stdout claims RED/GREEN. The present gate never perturbs the claimed invariant, so
it cannot distinguish those tests from a useful one (`builder-selfcheck.sh:397-450`).

### Replace it with evidence the machine reproduces

The minimum meaningful contract is:

1. The planner pins a surface-level acceptance fixture/probe before implementation; hash it in the
   prepass artifact.
2. The lane supplies a **semantic negative-control patch** against production code, not the test.
   The gate applies it in a temporary tree, verifies bytes changed, and requires syntax/compile to
   stay valid. Deleting a function or creating a syntax error is not a killed mutant.
3. The gate executes the same test/probe command against the mutant and requires nonzero, restores
   the exact lane tree, then requires zero. Persist base/lane/mutant hashes, commands, rc, and stdout
   digests in `selfcheck.md`; never accept a prose marker.
4. Review checks that the mutant changes the stated acceptance invariant, not an unrelated branch.
   Full-boundary expected fixtures/literals are preferred over an oracle algebraically derived from
   the implementation.

This does not prove the system correct. It proves one narrower and honest thing: a valid, runnable
wrong implementation of the named invariant is rejected while the candidate passes. That is more
than the suite currently proves and much less than the current marker claims.

## Q4 — where wall-clock goes

Exact total attribution is impossible from the retained artifacts: checkpoints timestamp recovery,
not dispatch start, and 5-10 hour lane windows mix building, deaths, review, fixes, and suites. The
ranking below separates measured units from unknown totals.

The incident lower bound is constructed without adding overlapping mentions:

| Date/cohort | Confirmed deaths | Other abnormal exits | Evidence |
|---|---:|---:|---|
| 08-20 GLM-LADDER | 1 | 0 | `4077109`: worker died at acceptance wait. |
| 08-20 ENV-GUARDS | 1 | 0 | `79c25ed`: task died at turn 111; `1806b4f` is the same incident and is not added. |
| 08-20 residue sweep/followup | 2 | 0 | `c312ac8` and `517bc13`. |
| 08-20 STOP-GATE | >=6 | 0 | `40922a8`: “6th worker death on this lane”; `747f453`/`ee3d74b` are members, not additions. |
| 08-20 dispatcher | 1 | 1 | `7052aed`: fix3 worker died; `029ce01`: a distinct worker exited uncommitted, cause unstated. |
| 08-21 STOP checkpoints | not inferred | 6 | Six unique task IDs at `5b35a06`, `7ebb24a`, `96ff69c`, `e329f7b`, `dccd21e`, `eb51d0d`. |
| 08-21 four-lane sweep | >=4 | counted within the day’s six-exit lower bound, not added again | `5ad93de`: one unrelated sweep killed four working lanes in 15 s; `e9d8812` names four checkpoint/dedup aftermath lanes. |
| 08-21 shared transport | not added (overlap unresolved) | not added | `7660fb1`: three lanes stopped in 32 s; identity overlap with the two cohorts above is not proven. |

Thus 08-20 contributes >=11 deaths and 12 abnormal lifecycle incidents; 08-21 contributes >=4
confirmed deaths and six distinct abnormal checkpoint exits. Across the two dates the conservative
lower bounds are **>=15 deaths** and **>=18 abnormal lifecycle incidents**. The shared-transport
three are deliberately not added.

| Rank | Cost center | Measured evidence | What to cut |
|---:|---|---|---|
| 1 | Abnormal worker lifecycle | On 08-20: 11 explicitly called deaths plus one distinct uncommitted exit. Across 08-20..21: >=15 confirmed deaths and >=18 abnormal/dirty exits; exact overlap is unknown. `7052aed` directly records one stale stream for **34 min**. `5ad93de` records four lanes killed in 15 s by one sweep; `7660fb1` records three stopped within 32 s by shared transport. | Cut shared/global reaping and multi-lane failure domains; keep checkpoint recovery. Do not convert checkpoint count into “reliability success.” |
| 2 | Review + fix cycles | Standardized lanes: 10 exact explicit FAIL rounds. STOP-GATE first visible checkpoint-to-land = **10:06:47** (`747f453` -> `6ae373a`); dispatcher acceptance = **10:14:43** (`029ce01` -> `585ad7f`). These are upper envelopes, not pure review time. | Cut defect-at-a-time missions and non-authoritative fanout, not the final verification itself. |
| 3 | Full suite | `a5db688`: serial **23:37** per 60-suite run; shards **5:39-17:15**, but two collisions. | Isolate the two repo-state suites, then enable shards. Do not enable unsafe sharding first. |
| 4 | Architect prepass | Current 08-21 persona sample: 17 architect streams, median **190 s**, mean **196.6 s**, range **111-348 s**; total compute **3342 s**. Resolver classify->build is median **33 s**, mean **168.8 s**, because cached prepasses are often reused. | Keep the ~3 min pass, but change its required output. It is too small to be the primary speed target. |
| 5 | Ordinary dispatch overhead | In the same 17-lane sample, classify->build median **33 s**; the long tail is prepass/spawn work (max **698 s**). | Do not optimize the median before deaths/reviews/suite isolation. |

Infrastructure and review cost are not additive from those rows. The only direct “idle waste” text is
`>=34 min`; the multi-hour lane windows are not claimed as death time. Likewise, the 18 abnormal
exits are incident counts, not 18 formal review rounds. Nine merge-named FAIL rounds were substantive,
and one reviewer attempt is explicitly infrastructure-burned (`d85fbfb`).

## Three changes to implement next

### 1. Pilot mechanism closure before the design becomes authoritative

**Hypothesis:** highest leverage on late-round mechanism defects; the current artifacts do not prove
causality, so stage it as a measured pilot rather than a fleet-wide new gate.

- File: `plugins/leadv2/scripts/leadv2-dispatch-code.sh`, architect prompt at `:2860-2862` and
  builder mission assembly at `:4576-4591`.
- Change: replace “changes/files/non-goals” as the complete prepass contract with four mandatory
  sections: caller/callee census; state-transition and return-code table; configuration-boundary
  census including min/max/absent/malformed states; and one counterexample answering “what can still
  violate the system invariant after every named finding is fixed?” The builder design is
  authoritative only when those sections are nonempty. Change `Implement ONLY` to “implement this
  mechanism-closed design; stop if code discovery falsifies its census.”
- Do **not** add a second prose critic. Make the existing prepass spend its ~190 s on closure rather
  than an H-list rewrite.
- Instrument one baseline week, enable the schema on a tagged cohort, then measure for three weeks:

  ```bash
  git log --first-parent --merges --since='30 days ago' --format='%H%x09%s' |
    rg 'merge: .* lane ' |
    # join to review-round events; report p50/p90 model reviews and FAILs per landed lane
    ...
  ```

  Acceptance target: p90 reviews/landed lane <= 2 (the current p50 is already 1), while upheld
  Critical/High findings discovered only in round 2+ fall versus the instrumented baseline week.

### 2. Make review synthesis real, or pay for one arm only

**Hypothesis:** reviewer-cost reduction and fewer arguable passes once applied to an active path.

- File: `plugins/leadv2/scripts/leadv2-review-run.sh`.
- Evidence: default fanout is three (`:63-64`), all arms plus hack-detect run (`:880-918`), and every
  Critical/High may trigger another verifier (`:1094-1116`). But the gate’s verdict is the first
  surviving parsable arm (`:1006-1027`); secondary findings are unioned into JSON, while final gating
  still keys on that first `verdict` (`:1152-1164`). `_blocking_refuted` and effective counters are
  computed but not used (`:1141-1148`).
- The engine is default-off for product-close (`dispatch-product-close.sh:2220-2235`), so changing
  `review-run.sh` alone does **not** save production-lane cost. First measure direct/interactive
  invocations, then enable the engine only for a tagged plugin-lane pilot or apply the same synthesis
  rule to the active inline body.
- Change: in that active pilot/path, set fanout default to 1 until synthesis is implemented. Then make the union authoritative:
  any non-refuted Critical/High from any arm blocks; a refuted one stays in JSON but does not block.
  Once an offline fixture proves this, restore fanout only for Heavy/safety lanes.
- Delete the redundant machine round 0 (`:826-857`) from the product lane path: product-close already
  exits on the same RED (`dispatch-product-close.sh:2088-2103`). Also delete verification-only’s ban
  on pre-existing new findings (`review-run.sh:696-700`); a missed mechanism defect does not become
  acceptable because round 1 missed it.
- One-month measurement after the path is enabled: event query for `review_arm_started`, `review_verifier_started`, and
  `review_gate`; report arms and verifier calls per landed lane, upheld C/H by source arm, cost, and
  p50/p90 review wall-clock. Target: >=50% fewer arm calls with no increase in post-merge defect
  reopenings.

### 3. Delete the marker block; replace it with executed paired falsification

**Expected effect:** removes the dominant false block and raises the meaning of GREEN.

- File: `plugins/leadv2/scripts/lib/leadv2-builder-selfcheck.sh:397-452`.
- Delete/default-off C4 now. Keep C0 scope, bash syntax, Python compile, and changed-scope suites.
- Implement the isolated mutant/baseline/lane protocol above. Extend classification beyond shell
  basenames using repo test configuration rather than a hand-coded filename pair.
- File: `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh:2088-2103`; make the new evidence
  artifact the input to the hard block.
- One-month measurement: count selfcheck RED reasons and review findings tagged
  `tests-cannot-fail`. Target: marker/convention blocks = 0, paired-run execution coverage = 100% of
  test-touching diffs, and upheld “test cannot fail” findings fall by >=50% from the first week’s
  baseline.

## What I would not do

- **Do not add another reviewer arm.** The current three-arm fanout does not make secondary Highs
  authoritative (`review-run.sh:1006-1027`, `:1152-1164`). More arms currently buy more prose, not a
  stronger gate.
- **Do not add another marker.** The current marker is the failure: it attests to a counterfactual
  the gate never executes (`builder-selfcheck.sh:397-450`).
- **Do not delete the architect prepass for speed.** Its measured median is ~190 s; the review/death
  cycle is hours. Change its output contract.
- **Do not turn shards on globally yet.** `a5db688` records two collisions; isolate those suites
  first.
- **Do not call STOP-GATE a prevention gate.** Keep the scoped temp-index checkpoint
  (`dispatch-product-close.sh:1461-1573`), but delete the prompt-only admonition
  (`dispatch-code.sh:4641-4650`) and report checkpoint counts as incidents.
- **Do not hard-fail merely because a diff exceeds 40 files.** Keep off-write-set rejection, but turn
  the arbitrary count ceiling (`builder-selfcheck.sh:198-201`) into a split/escalation signal.

## Appendix A — reproduction excerpts

Lane population:

```bash
git log --first-parent --merges \
  --since='2026-08-17 00:00:00 +0300' \
  --until='2026-08-22 00:00:00 +0300' \
  --date=iso-local \
  --pretty=format:'%H%x09%ad%x09%P%x09%s'
```

Derived output:

```text
first_parent_merges  15
standard_lane_merges 11
model_review_invocations >=18
explicit_FAIL_rounds     10
```

Persona marker convention:

```bash
find tests -type f \( -name 'test-*.sh' -o -name '*_test.sh' \) | wc -l
rg -l 'RED-then-GREEN:' tests -g 'test-*.sh' -g '*_test.sh' | wc -l
```

```text
755
0
```

Current persona prepass timing (first-to-last timestamp in each matching architect stream):

```text
n=17 total=3342s mean=196.6s median=190s min=111s max=348s
```

Current persona resolver timing (`classify.started_at` to `build.started_at`):

```text
n=17 total=2869s mean=168.8s median=33s min=1s max=698s
```

Worker incident census commands:

```bash
git log --all --since='2026-08-20 00:00:00 +0300' \
  --until='2026-08-22 00:00:00 +0300' \
  --date=iso-strict --pretty=format:'%H%x09%aI%x09%cI%x09%s'

git show -s --format='COMMIT %H%nSUBJECT %s%nBODY%n%b' \
  40922a8 7052aed 5ad93de 7660fb1
```

Counting caution: `1806b4f` repeats the ENV-GUARDS death from `79c25ed`; `747f453` and `ee3d74b`
are members of STOP-GATE’s “6th worker death” aggregate at `40922a8`; `e9d8812` repeats the
four-lane checkpoint aftermath from `5ad93de`. They are not added twice.
