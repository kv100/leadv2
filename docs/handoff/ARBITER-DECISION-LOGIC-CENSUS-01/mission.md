ARBITER-DECISION-LOGIC-CENSUS-01 — the arbiter now ANSWERS and RECORDS. It is not yet SMART.
Find every place where its decision is driven by a static label instead of a measured fact.

FOUNDER, 2026-09-04, after reading the first three holes: "это вовсе не делает арбитра умным, а я
просил именно это, я уверен что еще оч много таких дырок в логике." He is right, and the three
below were found by casual inspection in ten minutes — treat them as CALIBRATION for what a hole
looks like, not as the list to fix.

THIS IS A CENSUS FIRST, A FIX SECOND. A patch to one hole that leaves the census undone is a
failed task: the value here is the complete map, because the founder's stated doubt is "how many
more are there", and only a census answers that.

THE THREE KNOWN HOLES, measured on main `481c0be7`:

1. EFFORT FOLLOWS THE ARM, NOT THE TASK. `work_kind=build class=standard` returns
   `arm=glm-flash effort=low`, because `glm-flash` carries `tags: [cheap, mechanical]`
   (`config/leadv2-routing.yaml:101`) and `effort_matrix` has `{tags:[mechanical],effort:low}` and
   `{tags:[cheap],effort:low}`. The arbiter picks the cheapest capable arm, then LOWERS the
   thinking budget because the arm it picked is labelled cheap. Circular: the task's own hardness
   never enters. Whether low effort on code is even correct is separately doubted by the founder —
   do not assume the current value is right just because it is current.

2. CLAUDE QUOTA IS NEVER READ. The decision line prints `util_claude=0` — a number, not
   `unknown_capped` — while the same day's live probe reports 72% consumed on max_20x and 48% on
   max_5x. `config/leadv2-routing.yaml:35` admits it in its own comment: "codex and claude have no
   ceiling reader at all", yet `:41` declares `claude: { work_pct: 95, review_pct: 95 }`. So the
   ceiling exists on paper and binds nothing, and the arbiter believes Claude is always free.

3. COMPLEXITY IS ALWAYS UNKNOWN. Every decision line ends `complexity=unknown
   duration_class=unknown`. The `complexity_penalty` machinery in the yaml is written and
   commented, and it can never fire, because nothing supplies the estimate. Branch
   `worktree-COMPLEXITY-ESTIMATOR-IS-OFF-01` carries ONE empty anchor commit — verified 2026-09-04
   by a second session with `merge-base --is-ancestor` plus `diff --stat`.

THE WORK.

1. CENSUS. Take every input the arbiter's decision depends on — `work_kind`, `class`, `size`,
   `tags`, `protected`, `writes`, quota per provider, reset distance, complexity, duration, the
   floor, the freepool gate, the fallback chain — and for EACH one answer three questions with
   evidence:
     - Is it actually supplied at the call site, or is it always absent/default?
     - Does it actually change the outcome, or is it computed and then ignored?
     - Is it a MEASURED fact or a STATIC label someone typed once?
   A label is not automatically wrong — `protected` is a genuine policy. The defect shape is a
   label standing in for a measurement that exists and could be read.
2. Prove each finding by DIFFERENCE, never by reading: change the input, show the decision line
   change (or fail to change). A claim like "X is ignored" needs the two decision lines side by
   side, verbatim.
3. Rank what you found by consequence: which hole sends real work to the wrong arm, which merely
   prints a wrong number. The founder needs the ranking more than the count.
4. FIX only the top-ranked hole in this task, with the census delivered whole. Say plainly in the
   report which holes you left open and why.

ACCEPTANCE.

1. The census table: one row per input, with the three answers and the evidence command for each.
   Include the three known holes — if your method does not rediscover them independently, your
   method is too weak and the rest of the census cannot be trusted either. Say so if that happens.
2. For the hole you fix: a suite, plus a NEGATIVE CONTROL applied INSIDE the function body that
   reddens it, both outputs verbatim. A mutation inserted at top level reddens everything for the
   wrong reason and reads as a pass — that error was made on 2026-09-04 and invalidated a whole
   measurement.
3. Prove CI selects the suite with `LEADV2_RUN_ALL_SELECT_ONLY=1 tests/run-all.sh --scope changed`
   — modify the source in the working tree, show the `[SELECT]` line, revert, show it gone. Both
   directions. Do NOT run a full `tests/run-all.sh` in a live checkout: a full run repointed five
   live control-plane symlinks into a temp fixture directory and deleted their targets with it,
   measured 2026-09-04.
4. The arbiter must still answer for all four kinds when you are done: four decision lines,
   verbatim, `build` / `recon` / `review` / `plan`.

CONSTRAINTS. Shared plugin tree feeding three repositories; the founder authorised work in this
tree this session. `lib/leadv2-route-arbiter.sh` is yours for this task — no other lane holds it
now. Never `git add -A`. Do not push to origin. `tests/known-red-suites.txt` and
`tests/known-failures.txt` may only shrink. GLM is NOT restricted to build work — the founder
confirmed on 2026-09-04 that GLM may take any kind; any repo doc saying otherwise is stale and
must not drive a routing decision here.
