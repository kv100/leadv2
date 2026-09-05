# WORKER-DOD-GATE-01 — adversarial review of architect.md

Reviewer: critic (sole challenger; Codex second brain unavailable 2026-09-02).
Scope: the plan only. No implementation exists yet (`leadv2-dod-gate.sh`,
`leadv2-mutation-control.sh` both confirmed absent on disk).

Severity counts: **Critical 5 · High 6 · Medium 4 · Low 2**.

Type-checker note: the change set is bash-only. No `.py`/`.ts` file appears in LANE_WRITES,
so `mypy --strict` / `npx tsc --noEmit` have no input and were not run; `shellcheck` has no
input either because both new scripts are to-create. Raw evidence for every finding below is
the command shown inline with its actual output.

---

## CHALLENGE-01 — CRITICAL — the entire hard-gate surface is inert in production

`plugins/leadv2/scripts/leadv2-review-run.sh` is only called by the lane when
`LEADV2_REVIEW_ENGINE=1`. The flag defaults to **0** and the engine's own header says it
"must stay 0 in production per ONE-PATH-EVERYWHERE-01 rollout". It is set nowhere in this
repo's settings, nor in persona-engine's.

```
$ grep -n 'LEADV2_REVIEW_ENGINE' plugins/leadv2/scripts/leadv2-dispatch-product-close.sh
2756:if [[ "${LEADV2_REVIEW_ENGINE:-0}" == "1" ]]; then
$ sed -n '24,36p' plugins/leadv2/scripts/leadv2-review-run.sh
# FLAG: LEADV2_REVIEW_ENGINE gates whether the LANE calls this script (default 0, must
# stay 0 in production per ONE-PATH-EVERYWHERE-01 rollout).
# NOT COVERED: leadv2-dispatch-product-close.sh's inline review body used at
# LEADV2_REVIEW_ENGINE=0 (the production default) never calls this engine
$ grep -rn 'REVIEW_ENGINE' .claude/settings.json .claude/settings.local.json \
    /Users/kostiantyn.vlasenko/Projects/persona-engine/.claude/settings.json
(no output)
```

The plan's §14 acceptance ("review-run.sh refuses a round … before pool resolve") is therefore
true only on a path production does not take. The soft tier does not compensate (CHALLENGE-09).
Net: on tonight's 12 real lanes the plan as written would have caught **zero** of the 15
mechanical Highs, and the stated ROI (a 30–45 min round saved) is zero.

**Required fix:** the plan must state which of these it does, and prove it:
(i) place the hard gate in `leadv2-dispatch-product-close.sh`'s inline review body *as well*
(requires a LANE_WRITES extension the architect explicitly declared off-limits in §11), or
(ii) make flipping `LEADV2_REVIEW_ENGINE=1` a delivered, verified step of this task with a
run showing the engine path taken, or (iii) put the enforcing tier in the epilogue (which does
run unconditionally) and demote review-run.sh to the second line of defence. §11 currently
forbids (i) and §7 assumes (ii) silently. This is a plan-blocking decision, not an
implementation detail.

---

## CHALLENGE-02 — CRITICAL — §0's finding is right but incomplete: 3 of 8 LANE_WRITES rows fail the scoper, including `docs/handoff/WORKER-DOD-GATE-01/`

§0 is **CONFIRMED**: the file is at `plugins/leadv2/scripts/lib/leadv2-worker-epilogue.sh`.

```
$ ls plugins/leadv2/scripts/leadv2-worker-epilogue.sh
ls: plugins/leadv2/scripts/leadv2-worker-epilogue.sh: No such file or directory
$ ls -la plugins/leadv2/scripts/lib/leadv2-worker-epilogue.sh
-rwxr-xr-x  1 ... 6748 Sep  2 01:34 plugins/leadv2/scripts/lib/leadv2-worker-epilogue.sh
```

But §0's next sentence — "Every other listed LANE_WRITES path was existence-checked and is
correct" — is **REFUTED**. `_lv2_epilogue_path_in_scope` (`lib/leadv2-worker-epilogue.sh:48-57`)
matches with a **quoted** case pattern (`case "${path}" in "${lw}"|"${lw}"/*`), so glob
metacharacters in a LANE_WRITES row are literal and a trailing slash produces a `//`. I ran the
real function against the real brief's rows:

```
$ bash /tmp/dodtest.sh        # sources lib/leadv2-worker-epilogue.sh, feeds brief.md's 8 rows
FOREIGN    plugins/leadv2/scripts/lib/leadv2-worker-epilogue.sh   <- §0's finding
FOREIGN    plugins/leadv2/prompts/dod-fragment.md                 <- `prompts/**` never globs
FOREIGN    docs/handoff/WORKER-DOD-GATE-01/report.md              <- trailing slash -> `//*`
IN_SCOPE   tests/run-all.sh
IN_SCOPE   plugins/leadv2/scripts/lib/leadv2-dod-gate.sh
```

The third row is the self-defeating one: **this task's own `report.md` would be classified
`foreign_dirty` and never committed**, and the task's own check (a) demands report.md be
committed at HEAD. The gate would refuse its own lane, for a reason that has nothing to do
with the worker's behaviour.

**Required fix:** three separate corrections, not one — (1) `lib/` on the epilogue row;
(2) replace `plugins/leadv2/prompts/**` with `plugins/leadv2/prompts`; (3) strip the trailing
slash from `docs/handoff/WORKER-DOD-GATE-01/`. And since the same two shapes appear in
REVIEW-SENTINELS-LANGUAGE-01's brief (`prompts/**`, trailing-slash handoff dir) and in
TESTS-POLLUTE-REAL-JOURNAL-01's (`plugins/leadv2/scripts/tests/`, trailing slash), this is a
census-worthy pattern: `_lv2_epilogue_path_in_scope` should normalise (strip trailing `/`,
strip a trailing `/**` or `/*`) rather than every brief author remembering the quoting rule.
That normalisation is a one-liner in the file this task already owns.

---

## CHALLENGE-03 — CRITICAL — checks (a)/(b)/(e) read `${HANDOFF}`, which is `docs/handoff/dispatch-<sig8>`, not the task's handoff dir

§4 says checks (a), (b), (e) read `${HANDOFF}/report.md` and `${HANDOFF}/brief.md`, and (a)
additionally `git show HEAD:docs/handoff/<task>/report.md`. Both are wrong for the same reason:

```
$ grep -n '^HANDOFF=' plugins/leadv2/scripts/leadv2-dispatch-product-close.sh
210:HANDOFF="${ROOT}/docs/handoff/dispatch-${TASK}"
$ ls -d docs/handoff/dispatch-* | wc -l
     760
$ ls -d docs/handoff/dispatch-* | head -2
docs/handoff/dispatch-00455db5
docs/handoff/dispatch-0057aae6
```

`TASK` is a **sig8**, not the founder task id. `brief.md` and `report.md` live at
`docs/handoff/WORKER-DOD-GATE-01/`; `${HANDOFF}` is `docs/handoff/dispatch-<8 hex>`. Consequences
if built as specified:
- check (a) reads a path that never exists → **fires on 100% of lanes**;
- check (b) reads a `brief.md` that never exists → **zero paste-lines → vacuous pass, forever**
  (the check meant to close cause-row-2, 4/19 Highs, would silently never fire);
- `git show HEAD:docs/handoff/<sig8>/report.md` resolves nothing.

Worse, review-run.sh **cannot** resolve the founder task id from its own arguments — it takes
only `--task --root --handoff --diff --author`:

```
$ grep -n 'FOUNDER_TASK_ID\|LEADV2_FOUNDER' plugins/leadv2/scripts/leadv2-review-run.sh
(no output)
$ sed -n '68,76p' plugins/leadv2/scripts/leadv2-review-run.sh
TASK=""; ROOT=""; HANDOFF=""; DIFF_FILE=""; AUTHOR=""; FANOUT_ARG=""
    --root)    ROOT="${2:-}"; shift 2 ;;
    --handoff) HANDOFF="${2:-}"; shift 2 ;;
```

**Required fix:** the plan must add an explicit `--task-dir` (or `--founder-task-id`) argument
to `leadv2-review-run.sh` and thread `FOUNDER_TASK_ID` through from
`leadv2-dispatch-product-close.sh:2766`'s engine call — which is an edit to a file §11 declares
off-limits. Either extend LANE_WRITES or resolve the task dir from the lane's mission file
(`LANE_WRITES:` line's `docs/handoff/<ID>/` row) inside the gate. Do not leave this to the
implementer to discover.

---

## CHALLENGE-04 — CRITICAL — check (a)'s heading regex refuses 37 of 37 real reports; the check is calibrated against nothing

I ran the plan's exact regex over every `report.md` in the repo:

```
$ bash -c 'a=0;t=0; for f in docs/handoff/*/report.md; do t=$((t+1)); \
   grep -qE "^##[[:space:]]+(Round[[:space:]]+[0-9]+[[:space:]]+Evidence|Evidence)[[:space:]]*$" "$f" \
   || a=$((a+1)); done; echo "total=$t refused=$a"'
total=37 refused=37
$ grep -h -iE '^#{1,3}[[:space:]].*evidence' docs/handoff/*/report.md | sort | uniq -c | sort -rn | head -4
   5 ## Round 2 evidence
   2 ## Round 4 evidence
   2 ## Round 3 evidence
   1 ### Post-fix evidence
```

Two independent defects: the real convention is lowercase `evidence` (the brief itself writes
"## Round N evidence"), and the `[[:space:]]*$` anchor kills real headings like
`## Round 4 evidence (reconciliation commit)`. Even after fixing both, **20 of 37** reports carry
no evidence-shaped heading at all — i.e. a hard check (a) refuses the majority of lanes that
historically passed review, on day one, with no migration path.

**Required fix:** case-insensitive, non-anchored (`^#{2,3}[[:space:]].*[Ee]vidence`); and check (a)
must be conditional on the brief actually asking for a report (`grep -qi 'report\.md' brief.md`),
otherwise a brief that never asked for one gets refused for not producing it. Add the 37-file
census above to the suite as a calibration fixture so this regression cannot recur silently.

---

## CHALLENGE-05 — CRITICAL — `git archive` scratch tree makes `leadv2-mutation-control.sh` lying-green by construction

§5 step 5: "Exit 0 despite the mutation → mutant_survived. Non-zero → success: print
`MUTATION-CONTROL ok`". There is **no baseline-green run**. A `git archive` tree has no `.git`,
and 114 of 310 plugin suites touch git:

```
$ ls plugins/leadv2/scripts/tests/test-*.sh | wc -l ;  grep -l 'rev-parse\|git -C' plugins/leadv2/scripts/tests/test-*.sh | wc -l
     310
     114
$ s=$(mktemp -d); git archive HEAD | tar -x -C "$s"; ls "$s/.git"
ls: /tmp/dodscratch.f4s8/.git: No such file or directory
$ cd "$s" && bash tests/run-all.sh --scope changed; echo "rc=$?"
run-all: FATAL root_escape expected=/tmp/dodscratch.f4s8 resolved=<not-a-repo>
rc=2
```

A suite that dies with rc=2 because the scratch tree is not a repo is *non-zero*, so the runner
prints `MUTATION-CONTROL ok suite=… red_line=…` and exits 0. Check (b)'s sub-check then greps
for that exact sentinel and blesses the round. The tool built to kill cause-row-2 ("a mutation
control that never applied its mutant") reproduces cause-row-2 with a machine-generated
sentinel — strictly worse than the hand-typed transcripts it replaces, because the gate now
vouches for it.

Second defect in the same mechanism: `git archive HEAD` carries **committed content only**. The
worker is told (brief item 2) to use this runner *while working*, when the suite and the file
under mutation are typically uncommitted — the runner would snapshot a tree without them.

**Required fix, all three:**
1. Run the suite in the scratch tree **unmutated first and require rc=0**; a non-green baseline
   is `control_not_applied`/undetermined, never `ok`. This is exactly what
   `leadv2-suite-falsifiable.sh` already does (rc=2 = "already red at baseline: never a pass, and
   never an accusation", `leadv2-suite-falsifiable.sh:29-30`) — copy it.
2. Snapshot the **working tree**, not `HEAD`: `git -C ROOT ls-files -co --exclude-standard` piped
   into `tar -T -`, or `cp -a` minus `.git`. Keep `git archive` only if the runner is declared
   committed-only and the brief text changes to match.
3. Give the scratch tree a git identity (`git init -q && git add -A && git commit -qm base`) so
   git-dependent suites run for the right reason. Note this does **not** reopen R2: a fresh
   `git init` in a mktemp dir registers nothing in the lane's `.git/worktrees/`, so it is
   prune-safe and R2's reasoning does not forbid it.

---

## CHALLENGE-06 — HIGH — check (c)'s `--dry-run` mutates lane state and poisons the very selection it is checking

`tests/run-all.sh --scope changed` is **stateful and incremental**: it persists the last-checked
SHA and diffs from *that*, not the merge-base, on every subsequent run. The write happens at
lines 316-324, i.e. **before** the suite-selection loop (325) and long before the `~406`
execution loop where §6 proposes to put the `--dry-run` early-exit.

```
$ sed -n '316,324p' tests/run-all.sh
  # Record this run's HEAD as "checked" so a future clean-HEAD run only sees
  # what's newly dirty, not the whole lane range again.
  if [[ -n "${_state_file}" ]]; then
    _head_sha="$(git -C "${ROOT}" rev-parse HEAD 2>/dev/null || true)"
      printf '%s\n' "${_head_sha}" > "${_state_file}.tmp.$$" ... && mv -f ...
$ sed -n '275,279p' tests/run-all.sh
  changed="$(git -C "${ROOT}" diff --name-only HEAD 2>/dev/null)"
  for _cand in main origin/main; do
```

Three consequences, all false-refusals:
- The plan runs the DoD gate **twice** (soft in the epilogue, hard in review-run). The first
  invocation stamps HEAD as checked; the second sees an empty range, lists zero suites, and
  reports every added suite as `suite_unregistered`.
- Any lane that ran its own tests before review (which every brief demands) has already stamped
  HEAD → the hard gate refuses a correctly-registered suite.
- Base-ref preference is `main` **before** `origin/main` (line 278), the opposite of
  review-run.sh's own `LANE_START_SHA → origin/main` resolution (`leadv2-review-run.sh:398-412`),
  so the two halves of the same gate disagree about what "the diff" is.

**Required fix:** `--dry-run` must be side-effect-free — early-return *before* the state write,
not at line 406 — and must accept an explicit base (`--since <ref>`) so the gate is
deterministic. Better: drop the shell-out entirely and have check (c) resolve registration
directly in `lib/leadv2-dod-gate.sh` (stem-convention candidates + `EXTRA_SUITE_MAP` key match
— ~12 lines, reading the same string block at `tests/run-all.sh:105`), which removes both the
state hazard and the portability hazard of CHALLENGE-08.

---

## CHALLENGE-07 — HIGH — checks (a), (b) and (e) are all gameable with report text alone; only (d) is artifact-bound

Answering the mission's per-check question directly:

| check | gameable by report text with no artifact? | how |
|---|---|---|
| (a) report exists+headed | **yes, trivially** | `printf '## Round 1 evidence\n' > report.md && git commit` |
| (b) paste-lines answered | **yes** | paste any fenced block under a heading reusing 50% of the brief's words |
| (b) mutation sub-check | **yes — and this is the load-bearing one** | the sentinel `MUTATION-CONTROL ok suite=… mutant=… red_line=…` is a *plain grep for a literal string in prose*. The worker preamble (brief item 2) will publish that exact string to workers. Typing it is one line. |
| (c) suite registered | no (reads run-all.sh) — but see CHALLENGE-06 | |
| (d) runtime-state paths | **no** — reads the diff. The only genuinely sound check of the five. | |
| (e) external claims | **yes, trivially** | append the literal token `UNVERIFIED` or a bare `evidence: see above` within 2 lines |

§4 claims the (b) sub-check is "the direct fix for cause-row-2 … a hand-typed 'ran the mutation,
it went red' transcript with no runner sentinel". It is not a fix; it upgrades the required
forgery from a paragraph to a one-line string, while giving the forged line the authority of a
machine sentinel.

**Required fix:** bind check (b) to an **artifact**, not to text. `leadv2-mutation-control.sh`
must write `${TASK_DIR}/mutation-control/<run-id>.txt` containing `suite=`, `file=`, `anchor=`,
`baseline_rc=0`, `mutated_rc=<n>`, `red_line=`, and `diff_hash=<sha256 of the round's diff>`;
the gate verifies the artifact exists **and** its `diff_hash` equals the round's `diff_hash`
(review-run.sh already computes it — `REVIEW_DIFF_HASH_OK`/`diff_hash` at
`leadv2-review-run.sh:1250-1251`). A worker can still fabricate the file, but it now has to
fabricate a sha256 that matches the diff it is being reviewed on, and the forgery is a
committed artifact in the diff rather than prose. Same treatment for (e): require the evidence
line to name a file or a command, not merely the token.

---

## CHALLENGE-08 — HIGH — the plan is not portable; check (c) breaks or explodes in every adopted repo

Mission constraint: "must work in any adopted repo (persona-engine, m3-market, respiro-ios), not
only the plugin repo — reads the lane's LANE_WRITES / handoff, not repo-specific paths."
`tests/run-all.sh` is **repo-native, not plugin-owned** — it lives outside `plugins/`, so adding
`--dry-run` in leadv2 does nothing anywhere else:

```
$ grep -c 'dry-run' /Users/kostiantyn.vlasenko/Projects/persona-engine/tests/run-all.sh
0
$ sed -n '56,59p' /Users/kostiantyn.vlasenko/Projects/persona-engine/tests/run-all.sh
  case "$1" in
    --scope)
      SCOPE="${2:?--scope requires a value (changed|all)}"
```

persona-engine's copy has no `--dry-run`; respiro-ios (Swift) very likely has no
`tests/run-all.sh` at all. Depending on the local parser, the gate either takes an
unknown-argument error path or — the dangerous case — **executes the full changed-scope suite
inside the DoD gate**, blowing the brief's explicit "bash + grep + git only, under 5 s" budget
by minutes on every review.

The plan has no `undetermined`-vs-`fail` mapping for "this repo has no run-all.sh / no
--dry-run", and §4's table gives check (c) no rc contract at all.

**Required fix:** check (c) must (1) skip with an explicit `dod_skip check=suite_registration
reason=no_run_all` when `tests/run-all.sh` is absent, (2) never shell out to a `run-all.sh` that
lacks `--dry-run` (probe for the flag first), and (3) preferably resolve registration in-process
per CHALLENGE-06. State the same skip-vs-fail contract for (a)/(b) in a repo with no
`docs/handoff/<id>/` convention.

---

## CHALLENGE-09 — HIGH — the soft tier writes a field nothing reads: a control with no reader

§8 wires the epilogue to write `worker_dod=pass|fail:<checks>` into `progress.log`/`meta.yaml`.
Nothing in the plan reads it, and nothing existing reads sibling fields from that file either —
`leadv2-lane-outcome.sh` only *appends*:

```
$ grep -rn 'progress.log' plugins/leadv2/scripts/leadv2-lane-outcome.sh plugins/leadv2/scripts/leadv2-dispatch-product-close.sh
leadv2-lane-outcome.sh:19:# Side effect: ... appends one line to <run_dir>/progress.log
leadv2-lane-outcome.sh:192:  || echo "LEADV2_LANE_OUTCOME_WRITE_FAILED ..." >> "${RUN_DIR}/progress.log"
leadv2-lane-outcome.sh:195:  ... >> "${RUN_DIR}/progress.log"
(no consumer of worker_exit= / worker_dod= anywhere)
```

Under this repo's own doctrine ("a rule without a reader is not a rule"; CONTROL-TRUTH), a
report-only field with no consumer is decoration. It costs a gate invocation per lane and buys
nothing. **Required fix:** either name the reader (e.g. `leadv2-lane-outcome.sh` downgrades
`work=yes` to `work=yes dod=fail`, and the status surface shows it) and put that reader in
LANE_WRITES, or delete the soft tier from the plan. Do not ship a two-tier design where tier
one is inert (this finding) and tier two is flag-gated off (CHALLENGE-01).

---

## CHALLENGE-10 — HIGH — §7's recommended Option A contradicts a stated mission constraint and drops brief item 3

Brief item 3: on `dod_fail`, "feed the reason lines back to the worker as the next turn … up to 2
times, then exit `complete_with_dod_fail`". Mission constraint: "**Never a lead-side ritual.**"
Option A's own words: "The 'next turn' happens at the lead level: the lead reads
`reason: dod:<check>`, appends the gate's reason lines to the mission, and re-dispatches." That
is precisely a lead-side ritual, i.e. the thing the constraint forbids, and it deletes the
mechanical-retry half of the mission while being labelled "delivers the full mission goal".

The architect then rejects Option B for a re-entrancy risk (R5) **created by putting the retry in
the wrong layer**. The retry does not belong in `leadv2-review-run.sh` (post-hoc, out-of-process,
needs recursive dispatch). It belongs in the epilogue tier, which already runs inside the coder
wrapper's finalize path where "another turn" is native and no `--resume-lane` recursion is
needed. That is Option C and it is not considered. It costs a LANE_WRITES extension to
`glm-coder.sh`/`kimi-coder.sh`/`freepool-coder.sh`/`claude-subsession.sh` — §11 declares those
off-limits, which is exactly the scope decision that must go back to the lead rather than being
resolved by silently dropping the brief item.

**Required fix:** present Option C, and have the lead decide between (i) extend LANE_WRITES to
the wrapper finalize paths and implement the real in-worker retry, or (ii) explicitly descope
brief item 3 in writing. Do not describe Option A as delivering the full mission goal.

---

## CHALLENGE-11 — HIGH — sibling write-set collisions are understated; two lanes are editing `leadv2-review-run.sh` right now

R7 calls the only overlap a LOW, pre-existing `tests/run-all.sh` conflict. The real overlap is
three files with REVIEW-SENTINELS-LANGUAGE-01:

```
$ head -3 docs/handoff/REVIEW-SENTINELS-LANGUAGE-01/brief.md | tail -1
LANE_WRITES: plugins/leadv2/scripts/leadv2-review-run.sh,plugins/leadv2/scripts/lib/leadv2-review-parse.sh,plugins/leadv2/skills/leadv2-review/ref/reviewer-setup-steps.md,plugins/leadv2/prompts/**,plugins/leadv2/scripts/tests/test-review-sentinels-language.sh,tests/run-all.sh,docs/handoff/REVIEW-SENTINELS-LANGUAGE-01/
$ head -5 docs/handoff/TESTS-POLLUTE-REAL-JOURNAL-01/brief.md | tail -1
LANE_WRITES: plugins/leadv2/scripts/lib/leadv2-events.sh,plugins/leadv2/scripts/tests/,tests/run-all.sh,docs/handoff/TESTS-POLLUTE-REAL-JOURNAL-01/
```

Overlap set: `leadv2-review-run.sh` (both insert near the gate region), `plugins/leadv2/prompts/**`
(both add worker-facing fragments), `tests/run-all.sh` (three lanes),
`plugins/leadv2/scripts/tests/` (TESTS-POLLUTE claims the whole directory, this task adds a file
into it). §9's claim that the sentinel contract is "satisfied by construction because all strings
are English" is also too weak: that sibling's deliverable is a **parser that fails loud on an
unparsed status line**, so a brand-new `reason: dod_<check>` token is an unregistered value, not a
language question.

**Required fix:** (1) serialise `leadv2-review-run.sh` between this lane and
REVIEW-SENTINELS-LANGUAGE-01, or make this task's insertion a single `source`-guarded one-liner
that keeps the conflict to one line; (2) register the `dod_*` reason enum with
REVIEW-SENTINELS-LANGUAGE-01's parser explicitly (a handshake, not an assumption); (3) coordinate
`prompts/**` fragment ownership; (4) raise R7 from LOW to HIGH and name all four overlapping paths.

---

## CHALLENGE-12 — MEDIUM — checks (c)/(d) re-derive the diff with `git diff main HEAD` while review-run.sh already resolved a base, and `main` is the wrong ref

§4 specifies `git diff main HEAD --name-status` (c) and `git -C ROOT diff main HEAD --name-only`
(d). review-run.sh does not use a bare `main` anywhere; it resolves
`LEADV2_LANE_START_SHA → merge-base → origin/main → merge-base`:

```
$ sed -n '398,412p' plugins/leadv2/scripts/leadv2-review-run.sh
_review_resolve_codex_base() {
  if ! git -C "${ROOT}" rev-parse --is-inside-work-tree ...; then printf 'HEAD'; return 0; fi
  local sha="${LEADV2_LANE_START_SHA:-}" base
  ... git -C "${ROOT}" cat-file -e "origin/main^{commit}" ...
```

A stale local `main` in a long-lived lane worktree pulls in other lanes' merged commits, so
check (d) would flag `docs/leadv2/**` paths committed by *someone else* as this lane's
runtime-state pollution — a false Critical, the most expensive false positive this gate can
produce. Meanwhile the falsifiability gate this plan says it mirrors reads the **round's own
`DIFF_FILE`**:

```
$ sed -n '1314,1316p' plugins/leadv2/scripts/leadv2-review-run.sh
done < <(sed -n 's|^+++ b/||p' "${DIFF_FILE}" 2>/dev/null \
| grep -E '(^|/)(tests/|plugins/leadv2/scripts/tests/|...)test-[^/]+\.sh$' | sort -u || true)
```

**Required fix:** checks (c) and (d) read `DIFF_FILE` (already the round's authoritative diff),
falling back to `_review_resolve_codex_base` when invoked outside review-run.sh. Never `main`.

---

## CHALLENGE-13 — MEDIUM — exit 8 reuse journals the wrong cause

§2/§7 reuse exit 8 for the undetermined path because it "maps to existing `dead review_roundcap`".
It does:

```
$ sed -n '2775,2777p' plugins/leadv2/scripts/leadv2-dispatch-product-close.sh
    8) _dl_note dead review_roundcap "engine=1 rc=${_engine_rc}"; _stamp_review_terminal blocked ;;
    *) _dl_note dead review_engine_error "engine=1 rc=${_engine_rc}"; _stamp_review_terminal blocked ;;
```

The architect rejects the `*` catch-all because it "buckets under the misleading
`review_engine_error` cause" — and then accepts exit 8, which buckets a DoD-undetermined lane
under `review_roundcap`, an equally false cause. The ledger is a diagnosis surface; a lane blocked
because `git diff` failed will read as "hit the round cap" forever.

**Required fix:** accept one edit to `leadv2-dispatch-product-close.sh` (add
`10) _dl_note dead review_dod_blocked`) and extend LANE_WRITES by that one file, or state in the
plan that the mislabelling is a known, accepted cost with the follow-up task id.

---

## CHALLENGE-14 — MEDIUM — check (e) duplicates a rule the reviewer already enforces, and has a measured ~19% false-refusal rate

The claims-without-evidence rule already exists on the model side:

```
$ sed -n '977p' plugins/leadv2/scripts/leadv2-review-run.sh
printf 'Claims-without-evidence rule: ... Each must carry inline evidence ... or the literal tag UNVERIFIED. An untagged evidence-free claim that DRIVES a decision ... is a BLOCKING finding.'
```

The model version has the discriminator the bash version cannot have ("*drives a decision*").
The bash version, run over real reports with the plan's exact regex and ±2-line window, refuses
7 of 37:

```
$ bash -c '... for f in docs/handoff/*/report.md; ... grep -n -iE "docs say|macOS|Claude Code|Z\.AI|endpoint|rate limit|version [0-9]" ... sed -n "$((ln-2)),$((ln+2))p" | grep -qE "evidence:|UNVERIFIED" ...'
total=37 check_e_would_refuse=7
```

Several are pure false positives — any report mentioning `Claude Code`, an `endpoint` in prose, or
`version 2.1` trips it regardless of whether a claim is being made. Per CHALLENGE-07 it is also
the most trivially gamed check. Net value: negative-to-marginal for a gate whose whole premise is
that a false refusal costs a round.

**Required fix:** make (e) **report-only** in `dod-gate.md` (never a refusal reason) until its
false-positive rate is measured below a stated threshold on the 37-report corpus, and record that
threshold in the plan. Keep the blocking version on the model side where it already lives.

---

## CHALLENGE-15 — MEDIUM — the plan's own test coverage is short of what the brief demands

Brief item 4 requires: "Mutation negative controls, **RUN via the new runner** and paste: remove
check (d) → its fixture red; remove the anchor-count guard → the second runner case red." Plan
step 7's acceptance requires only that `leadv2-suite-falsifiable.sh` returns 0 and that a
`--scope changed --dry-run` lists the suite. That is falsifiability of the suite as a whole, not
per-check negative controls, and it never runs the two named mutations through
`leadv2-mutation-control.sh`.

New logic branches with no declared test at all:
- the review-run.sh block itself: no mutation proving that deleting `exit 7` makes a suite go red,
  i.e. no proof the gate actually refuses before pool resolve (step 4's acceptance is a manual
  eyeball of log lines, not an assertion);
- the epilogue's "always returns 0" contract when the gate crashes (step 5 tests the happy fail
  path only);
- `--dry-run`'s no-side-effect property (CHALLENGE-06) — untested because unnoticed;
- every `undetermined` (rc=2) path for all five checks;
- the portability skip paths of CHALLENGE-08.

There is also a bootstrap circularity nobody flagged: the suite's negative controls are to be run
through `leadv2-mutation-control.sh`, which is itself under test in the same suite. The plan must
name which control proves the runner, independent of the runner.

**Required fix:** one negative control per check (a–e) **plus** one for the review-run refusal
path and one for `--dry-run` purity, each named in the suite header, each run, each shown red.
Per this repo's E2E doctrine a mutation-kill claim without the run output is not a claim.

---

## CHALLENGE-16 — LOW — check (b)'s ≥50% token-overlap heuristic is unfalsifiable as specified

R4 admits the threshold is a heuristic and says fixtures will "calibrate" it. There is no stated
success criterion for calibration — no corpus, no target false-positive rate, no decision rule for
what to do if 50% is wrong. A tunable with no measurement procedure is a knob nobody will ever
turn. **Required fix:** state the corpus (the 37 real reports + their briefs) and a numeric bar,
or replace (b) with the artifact check of CHALLENGE-07 and drop the fuzzy match entirely.

---

## CHALLENGE-17 — LOW — R6 (`prompts/**` wiring unverified) is left to the implementer while being load-bearing

R6 correctly notes that no mechanism was found by which `plugins/leadv2/prompts/**` reaches a live
worker system prompt. But brief item 2 depends on it: "Briefs and the worker preamble **tell
workers to use it** instead of hand-editing." If the fragment never reaches a worker, no worker
ever runs `leadv2-mutation-control.sh`, check (b)'s sub-check fails every lane, and the gate
becomes a refusal machine. That is not a MEDIUM implementation detail; it decides whether the
cause-row-2 fix functions at all. **Required fix:** resolve the wiring question *before*
implementation — the `_LEADV2_EVIDENCE_CONTRACT_MISSION` readonly string in
`plugins/leadv2/scripts/leadv2-helpers.sh:62-66` is the proven mechanism for getting contract text
in front of every arm (it was added for exactly this reason: "Round 1 shipped the review-side rule
with no reader on the writing side for non-claude arms — this is the fix"). Use that pattern, not
an unwired file under `prompts/`.

---

## Contradiction scan (mandatory, pre-finalize)

- **Env-var names vs settings:** `LEADV2_DOD_GATE`, `LEADV2_DOD_GATE_MAX_RETRIES` — no prior usage,
  naming consistent with `LEADV2_REVIEW_*`. No contradiction. **But** `LEADV2_REVIEW_ENGINE`'s
  documented production value (0) contradicts the plan's §14 acceptance — CHALLENGE-01.
- **Flag semantics vs other usages:** exit 7/8 reuse contradicts the ledger's cause vocabulary —
  CHALLENGE-13. `--scope changed` assumed stateless, is stateful — CHALLENGE-06. `main` assumed to
  be the base, is not — CHALLENGE-12.
- **Path existence:** `plugins/leadv2/scripts/leadv2-worker-epilogue.sh` absent (§0 CONFIRMED);
  `plugins/leadv2/prompts/**` and `docs/handoff/WORKER-DOD-GATE-01/` fail the live scoper
  (CHALLENGE-02); `${HANDOFF}` ≠ task handoff dir (CHALLENGE-03); `lib/leadv2-land.sh` confirmed
  absent — the architect's treatment of it is correct and needs no change; `tests/run-all.sh`
  exists here, exists without `--dry-run` in persona-engine (CHALLENGE-08).
- **Self-contradiction within the plan:** §11 declares `leadv2-dispatch-product-close.sh` and the
  coder wrappers off-limits, while CHALLENGE-01/03/10/13 each require an edit to one of them. The
  plan's declared scope is not sufficient for its own acceptance criterion.

---

## Verdict

1. **REDESIGN** — not adopt-with-changes. Five Criticals are structural, not editorial: the
   enforcement surface is off in production, the gate reads the wrong handoff directory, check (a)
   refuses 37/37 real reports, the mutation runner is lying-green by construction, and the
   LANE_WRITES defect §0 found is three rows deep, not one.
2. The design's genuinely sound pieces are check (d) (diff-bound, ungameable) and the decision to
   mirror the falsifiability gate's refuse-before-pool-resolve shape. Keep both.
3. The plan's declared scope (§11 off-limits) cannot satisfy its own §14 acceptance; the lead must
   rule on extending LANE_WRITES before any implementation starts.
4. Brief item 3 (in-worker retry) is silently descoped by the recommended option while being
   described as full delivery — that must be an explicit lead decision, not an architect default.
5. Re-plan first; do not dispatch a builder against this document as written.

### Ordered plan changes (blocking, in this order)

1. Resolve enforcement placement (CHALLENGE-01): review-engine flag flip vs. inline-body gate vs.
   epilogue-as-enforcer, and extend LANE_WRITES accordingly. Nothing else matters until this is
   answered.
2. Fix all three LANE_WRITES rows and normalise `_lv2_epilogue_path_in_scope` for trailing `/` and
   `/**` (CHALLENGE-02); apply the same census to the two sibling briefs.
3. Thread the founder task dir into `leadv2-review-run.sh` (new `--task-dir` arg + product-close
   call-site edit) or derive it from the mission's LANE_WRITES row (CHALLENGE-03).
4. Rewrite check (a): case-insensitive non-anchored heading regex, conditional on the brief asking
   for a report, calibrated against the 37-report corpus (CHALLENGE-04).
5. Rewrite `leadv2-mutation-control.sh` §5: baseline-green gate first, working-tree snapshot not
   `git archive HEAD`, git identity in the scratch tree (CHALLENGE-05).
6. Replace check (b)'s prose-grep sentinel with a `diff_hash`-bound artifact under the task dir
   (CHALLENGE-07); make check (e) report-only (CHALLENGE-14).
7. Make check (c) stateless: resolve registration in-process from `EXTRA_SUITE_MAP` + stem
   convention; if `--dry-run` is kept, early-return before the state write and add `--since`
   (CHALLENGE-06); add explicit skip contracts for repos without `run-all.sh`/`--dry-run`
   (CHALLENGE-08).
8. Repoint checks (c)/(d) at `DIFF_FILE`, never `main` (CHALLENGE-12).
9. Decide the soft tier: name its reader or delete it (CHALLENGE-09). Decide brief item 3: Option C
   with extended LANE_WRITES, or a written descope (CHALLENGE-10).
10. Serialise `leadv2-review-run.sh` against REVIEW-SENTINELS-LANGUAGE-01, register the `dod_*`
    reason enum with its parser, raise R7 to HIGH with all four overlapping paths (CHALLENGE-11);
    resolve the `prompts/**` wiring via the `leadv2-helpers.sh` readonly-string precedent
    (CHALLENGE-17).
11. Expand the test plan to one negative control per check plus the review-run refusal path,
    `--dry-run` purity, and all rc=2 paths; each RUN and shown red (CHALLENGE-15, CHALLENGE-16).
12. Fix the exit-8 ledger cause or record the accepted mislabelling with a follow-up task id
    (CHALLENGE-13).

DELIVERABLE_COMPLETE
