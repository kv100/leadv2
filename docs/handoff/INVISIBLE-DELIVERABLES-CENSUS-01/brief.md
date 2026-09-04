LANE_WRITES: plugins/leadv2/scripts/lib/leadv2-lane-address.sh (to-create), plugins/leadv2/scripts/leadv2-lane-report.sh (to-create), plugins/leadv2/scripts/tests/test-lane-report-address.sh (to-create), plugins/leadv2/scripts/leadv2-recovery-context.sh, docs/handoff/INVISIBLE-DELIVERABLES-CENSUS-01/

# INVISIBLE-DELIVERABLES-CENSUS-01 — one way to ask "what did this lane produce?"

Measured against `main` at `a02c9189`, 2026-09-04. Every count carries the command that re-derives
it. **Read §1 and §2 before §3: half of what this lane looks like it is about is already fixed, and
the two obvious designs are both wrong for reasons that were only found by measuring.**

---

## 0. The one-paragraph verdict

Seven times in one night a lane produced a result and the lead concluded it had produced nothing.
Three "deaths" of D4 were three successful completions. D6 was re-dispatched while its finished
report sat on disk. Two different leads read `docs/handoff/<founder-task-id>/` while the report was
in `docs/handoff/dispatch-<sig8>/` — one of them while verifying the lane that exists to fix exactly
that. The cause is not invisibility of files. It is **address resolution plus an uninformative
absence**: a lane has two names, the report lands under the second one 279 times out of 292, and
because 848 of 1137 handoff dirs hold no deliverable at all, "nothing here" is the *normal* reading
and carries no information about whether the worker died. Your deliverable is one way to ask the
question that answers correctly from either name, prints the directories it searched next to its
answer, and distinguishes `none` from `unknown`.

**And the honest headline of §3: no durable index exists.** 216 of the 291 dispatch directories that
hold a deliverable carry no field-level pointer back to the founder id at all. So the tool is not a
lookup — it is a bounded, exact-attribution scan that publishes its own coverage and returns
`unknown` for the 74% it cannot resolve. A lookup that cannot answer is not evidence of absence.
That sentence is the entire lane.

---

## 1. What is already fixed — do not go there

An earlier lane allowlisted `*.full.md` / `*.summary.md` in `.gitignore` and a follow-up commit
tracked 358 previously-invisible files.

```
deliverables on disk (main tree)   573   (*.full.md + *.summary.md)
  tracked by git                   559
  untracked                         13   <- all recent, simply not yet committed
```

None of the 13 is *ignored*; they are this session's, awaiting a commit. **A brief that re-solves
gitignore invisibility is re-doing finished work.** Do not touch `.gitignore`. If you find yourself
reading the ignore rules, you have taken a wrong turn.

`plugins/leadv2/scripts/leadv2-lane-liveness.sh:637` `deliverable_dirs(tid, session)` is likewise
correct for what it does, and its comment block (`:638-655`) states the invariant you must inherit
verbatim:

> Never glob `docs/handoff/`: the pointer comes from THIS lane's row (keyed by this task_id, written
> by the dispatcher at spawn), which is exact attribution; a glob would credit another lane's report
> to this one — a false `finished_unlanded`, the mirror mistake.

That refusal is not conservatism, it is the correctness condition. Carry it forward unchanged.

---

## 2. The open failure modes

### 2a. The registry route is empty for every lane that has finished

`deliverable_dirs()` has exactly one non-trivial source: the lane's live `active.yaml` row, whose
`log_path` names the dispatch dir. Measured now, hours after seven lanes ran:

```
python3 -c "import yaml;d=yaml.safe_load(open('docs/leadv2/active.yaml'));print('sessions:',len(d['sessions']))"
sessions: 0
```

**Zero rows.** The registry is ephemeral by design. For a lane that has *finished* — the entire
population of "what did this lane produce?" — that route resolves nothing and the function falls
back to its first candidate, `docs/handoff/<tid>/`, the naive path. `deliverable_dirs()` is correct
while a lane is live and blind the moment it is not. That is the mechanism of all seven incidents.

### 2b. The sig8 is a hash of the mission text, so the mapping is not computable

`plugins/leadv2/scripts/leadv2-task-judge.sh:81`:

```bash
SIG8="$(python3 -c "import hashlib,sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest()[:8])" <<<"${MISSION_TEXT}")"
```

The dispatch name is `sha256(mission_text)[:8]`. It is **not** a function of the founder task id.
No arithmetic turns `D6-REGISTRY-LANE-OWNERSHIP-01` into `e525df4d`; you would need the mission text
byte-for-byte. The mapping must be *recorded* to be recoverable. Any design that tries to derive it
is wrong on its first line.

*(Corroborating, and it makes the receipt trustworthy as a record: for all 188 admission receipts in
the tree, `mission_digest[:8] == sig8` — 188 consistent, 0 inconsistent.)*

### 2c. Work that exists only inside a lane worktree — OPEN, and nearly lost tonight

The first measurement of this said `0`. It came from
`find .claude/worktrees -maxdepth 4 -name '*.full.md'`; a worktree's deliverable sits at
`.claude/worktrees/<lane>/docs/handoff/dispatch-<sig8>/developer.full.md`, which is **depth 5**. The
depth limit truncated the search and the truncation was read as a negative fact. Corrected:

```
find .claude/worktrees -maxdepth 6 -name '*.full.md' | wc -l   ->  22541  (all roles, all rounds)
deliverable files inside lane worktrees                            9912   (every worktree carries a full copy of docs/handoff)
deliverables present in the MAIN tree                               216
deliverables existing ONLY in a lane worktree                        55
```

Those 55 include the reports of `DEEPTHINK-MODE-IS-NOT-WIRED-01`,
`SUITES-MUTATE-LIVE-CONTROL-PLANE-01`, `ARBITER-ESTIMATES-BLIND-01` and the `COMPLEXITY-ESTIMATOR-*`
lanes. Worktrees are swept after a merge; each was one sweep from gone. They have since been rescued
additively (`5764a917` — copied into the main tree, nothing overwritten or deleted), but the failure
mode is open. **The resolver must either search worktrees or say plainly that it did not**, with the
paths. Silence about a location you did not look in is the defect.

### 2d. Absence carries no information

```
handoff dirs total                 1137
  dispatch-<sig8> named             846
  founder-task-id named             291
dirs actually holding a *.full.md   289      <- 75% of dirs hold no deliverable at all
deliverable files in dispatch dirs  279
deliverable files in founder dirs    13
```

Because "no deliverable here" is the majority state of a handoff dir, a bare zero cannot distinguish
*the worker died* from *this dir was never where the report goes*. Every one of the seven incidents
read the second as the first. **This is why the search path must be printed next to the answer, and
why `none` must never be a bare zero.**

### 2e. This brief has now produced two false zeros of its own — read them as the spec

§2c is one: a `maxdepth` that truncated a search, read as a negative fact. §3a is the other: an
index this brief previously recommended, whose 84% coverage was a directory-name bucketing error and
whose real coverage is **zero**. Both were caught only by re-deriving the number a second way, by
someone other than its author. Two people writing a brief *about* false zeros produced one each,
inside the brief, in one night. Design for a reader who is about to make the third.

---

## 3. The lookup sources — measured, and mostly absent

### 3a. RETRACTED: the journal index does not exist

An earlier draft of this brief recommended `docs/leadv2/tasks/<founder-id>/journal.md` as the
primary durable index at "602 of 715 (84%)". **That number was wrong and the source is unusable.**
The classifier that produced it excluded only directory names matching `^[a-f0-9]{8}$`, so all 617
`dispatch-*`-named task dirs landed in the "founder-named" bucket and matched their own name inside
their own journal — a self-reference counted as a mapping. Correct bucketing:

```bash
for d in docs/leadv2/tasks/*/; do n=$(basename "$d"); j="$d/journal.md"
  if   [[ "$n" =~ ^[a-f0-9]{8}$ ]]; then b=8hex
  elif [[ "$n" == dispatch-*   ]]; then b=dispatch
  else b=founder; fi
  [ -f "$j" ] && grep -qE 'dispatch-[a-f0-9]{8}|task=[a-f0-9]{8}' "$j" && echo "$b hit" || echo "$b miss"
done | sort | uniq -c
```

```
tasks dirs total:        921
  bare-8hex named:       205   (journals 205; carrying a sig8 token: 1)
  dispatch-* named:      617   (journals 617 — these were the phantom 602)
  FOUNDER-shaped named:   99   (journals 98)
    with dispatch-<8hex>:  0
    with task=<8hex>:      0
```

**Zero, on both token shapes.** Spot check confirms it: `docs/leadv2/tasks/D3-DERIVE-DIRTY-HAS-NO-COVERAGE-01`
does not exist at all, though that lane ran tonight and its report is in
`docs/handoff/dispatch-57a94876/`. A resolver built on this index would return `none` for every
founder id a lead actually types — the precise failure this lane exists to remove, shipped as its
fix. **Do not use the journals.**

### 3b. What is left, with real coverage

Restricted to the **291** dispatch dirs that actually hold a deliverable — the only ones the question
is ever asked about:

| # | source | what it is | coverage of 291 | verdict |
|---|---|---|---|---|
| A1 | `docs/leadv2/active.yaml` row `log_path` | a field, keyed by tid | **0 rows now**; live lanes only | keep. The only O(1) source while a lane runs, and what `deliverable_dirs()` already uses. |
| A2 | `docs/handoff/dispatch-<sig8>/admission-receipt.yaml` → `task_id:` | a named field in a designated file | **66** with a *founder-shaped* value (72 have the field at all) | best source. Exact in both directions. **Caveat measured:** repo-wide, 49 of 188 receipts hold a self-referential `dispatch-<sig8>` as their `task_id` — the same disease as 3a. The resolver must reject a `dispatch-*`-shaped `task_id` as a founder pointer. |
| A3 | `docs/handoff/dispatch-<sig8>/lane-mission.md` → **first line only**, `^# <TID>` | a structured position, not free text | **60** | admissible only anchored to line 1 and only as the first token after `# `. Anywhere else in the file it is prose and inadmissible (§3c). |
| — | **A2 ∪ A3** | | **75 of 291 (26%)** | |
| — | **neither** | | **216 of 291 (74%)** | **unattributable. These are the `unknown` population and they are the majority.** |
| A4 | `docs/handoff/<founder-id>/` itself | trivially | 13 deliverable files live here | keep as a candidate; never as the only one. |
| ✗ | `sessions.map` | labels + session UUIDs only; 13 of 409 contain any uppercase token | 272 (93%) | best-covered artifact in the tree and useless here. Do not use it. |

Re-derive A2/A3 with the loop in §7's fixture notes, or:

```bash
grep -h '^task_id:' docs/handoff/dispatch-*/admission-receipt.yaml | awk '{print $2}' \
  | awk '{if($0~/^dispatch-/)d++;else f++}END{print "self-ref:",d," founder:",f}'
# -> self-ref: 49  founder: 139
```

### 3c. The obvious wrong answer: grepping the dispatch dirs for the founder id

The move a worker reaches for first is `grep -rl "$TID" docs/handoff/dispatch-*/`. **It is the mirror
mistake at scale.** Census over five known lanes:

```
D3-DERIVE-DIRTY-HAS-NO-COVERAGE-01  ->  dispatch-1cba2dfa (review.diff)
                                        dispatch-2236d405 (review.diff)
                                        dispatch-3011c36c (main-dirt.base)
                                        dispatch-33e16647 (main-dirt.base)
                                        dispatch-3dd21396 (main-dirt.base)
                                        dispatch-57a94876 (developer.full.md)   <- the only real one
```

Six dirs, one correct. A review lane's `review.diff` contains every founder id whose brief the diff
touched; `main-dirt.base` lists dirty paths across the whole tree; `e2e-gate.log` and
`developer.stream.jsonl` quote mission text verbatim. **Banned as attribution sources, by name:**
`review.diff`, `review.diff.repos`, `main-dirt.base`, `e2e-gate.log`, `e2e-gate.md`, `selfcheck.md`,
`*.stream.jsonl`, and the body of any `*.full.md` / `*.summary.md`. Attribution comes from a **named
field in a designated file**, or it does not happen.

---

## 4. Shape: a shared library plus a thin CLI — a declared-coverage scan, reimplemented

**Build two new files and adopt them in one existing consumer:**

| file | role |
|---|---|
| `plugins/leadv2/scripts/lib/leadv2-lane-address.sh` (to-create) | the resolver. Sourceable; returns the resolution, the search-path record, and the coverage counts as data. No printing. |
| `plugins/leadv2/scripts/leadv2-lane-report.sh` (to-create) | the CLI. Takes either name, prints the answer *and* the search path in the contract of §5. Owns all formatting. |
| `plugins/leadv2/scripts/leadv2-recovery-context.sh` | the one adopting consumer (§6). |

### 4a. Why a scan and not an index

Because §3 measured that no index covers more than 26%, and an index that silently covers a quarter
of the cases while reading as authoritative is strictly worse than no index — it converts "I don't
know" into "nothing there", which is the incident. So:

- The resolver **scans** the 846 dispatch dirs' designated fields (`admission-receipt.yaml:task_id`,
  `lane-mission.md` line 1), plus A1 and A4. It is a field match, not a name glob, so the exact-
  attribution invariant of §1 holds.
- It **publishes its own coverage on every run** — how many candidate dirs were consulted and how
  many of those carry no pointer at all. The number is the reader's calibration.
- When the scan finds nothing **and** unattributable dirs exist, the answer is **`unknown`**, not
  `none`. `none` is reserved for the case where the scan is complete: no pointer matched *and* every
  consulted dir carried a pointer. On today's tree that is rare, and it should be — 216 of 291
  deliverable-holding dirs cannot be attributed to anyone, so honest ignorance is the common answer
  and must read as such.
- Cost: ~846 `head -1` reads plus ~188 small yaml greps. Bounded, no recursion, sub-second. Do not
  build a cache in this lane; a cache is a second index and it will rot the same way.

### 4b. Why reimplement rather than extract `deliverable_dirs()`

| | |
|---|---|
| **Its source set is wrong for this question, not merely narrow.** | Its only non-trivial route is A1, which resolves nothing for a finished lane (§2a). Extracting it verbatim ships a *shared* resolver returning `none` for exactly the population the lane serves. You would be standardising the bug. |
| **It lives in a blast radius this lane must not take.** | Python inside a heredoc in a 1065-line bash file with a bug-magnet history, whose return value feeds a *liveness verdict* which feeds the reaper (`leadv2-dispatch-ledger.sh::_dl_reap_one_lane`). Live D2 lanes are editing it right now. A resolver answering a read-only question must not be able to change whether a lane gets reaped. |
| **What transfers is the invariant, not the code.** | Cite `leadv2-lane-liveness.sh:645-651` at the top of the new resolver and honour it. Crediting another lane's report is a false positive as damaging as the false negative — §3c shows it costs five wrong dirs out of six. |

**Do not modify `leadv2-lane-liveness.sh` in this lane.** Making liveness consume the shared library
is a real follow-up; name it as a debt row, do not do it here.

### 4c. Non-negotiable properties

1. **Three-valued.** `found` / `none` / `unknown`. A candidate dir that exists but cannot be read
   (EACCES, a racing sweep) is `unknown`; so is a complete scan with no match while unattributable
   dirs remain. Never coerce either to `none`. Mirror `deliverable_dirs()`'s `unreadable` handling
   (`:665-674`).
2. **Exact attribution only.** Named field in a designated file. The §3c ban list is binding.
   A `dispatch-*`-shaped `task_id` is a self-reference and is not a founder pointer.
3. **The search path and the coverage are part of the answer, not debug flags.** Emitted on every
   run, including successful ones.
4. **The worktree horizon is explicit.** Either search `.claude/worktrees/*/docs/handoff/` (depth 5,
   §2c) or state in the searched-path line that you did not. There is no third option in which the
   output is silent about it.
5. **A founder id may legitimately map to several dispatch dirs** (re-dispatch, fix rounds). Return
   all of them, each labelled. Never pick one.

---

## 5. Output contract — the load-bearing part

**Every location consulted prints its own labelled line, even when it contributed nothing.** A
location that yields zero must not print zero bytes: in a concatenated listing the next location's
output slides into the empty slot, and that is how one lane's answer was read as the answer to a
different question tonight. `-> absent` and `-> 0 rows` are output; nothing is not.

Found:

```
lane: D6-REGISTRY-LANE-OWNERSHIP-01
resolved: tid=D6-REGISTRY-LANE-OWNERSHIP-01 sig8=e525df4d via=receipt
searched:
  registry   docs/leadv2/active.yaml                                  -> 0 rows
  receipts   846 dispatch dirs, 188 with a receipt                    -> 1 task_id match
  missions   846 dispatch dirs, 354 with lane-mission.md              -> 1 H1 match (same dir)
  eponymous  docs/handoff/D6-REGISTRY-LANE-OWNERSHIP-01/              -> absent
  worktrees  NOT SEARCHED (pass --worktrees)
coverage: 291 dirs hold a deliverable; 75 carry a pointer; 216 unattributable
found:
  [main/dispatch]  docs/handoff/dispatch-e525df4d/developer.full.md     4821b  2026-09-04T03:44Z
  [main/dispatch]  docs/handoff/dispatch-e525df4d/developer.summary.md   612b  2026-09-04T03:44Z
result: found 2
```

Unknown — the common honest answer, and it must not read as `none`:

```
result: unknown (no pointer matched FOO-01, but 216 of 291 deliverable-holding dirs carry no
        pointer at all; searched: docs/leadv2/active.yaml [0 rows], 188 receipts, 354 missions,
        docs/handoff/FOO-01/ [absent]; NOT searched: .claude/worktrees/*/docs/handoff/)
```

None — reserved for a complete scan, and never a bare zero:

```
result: none (searched: docs/leadv2/active.yaml [0 rows], 188 receipts [no task_id match],
        354 missions [no H1 match], docs/handoff/FOO-01/ [absent]; 0 unattributable dirs remain;
        NOT searched: .claude/worktrees/*/docs/handoff/)
```

Unreadable:

```
result: unknown (docs/handoff/dispatch-abc12345/ exists but listdir failed: EACCES)
```

Exit codes: `0` found · `1` none · `2` unknown · `3` usage. **`1` and `2` are different answers**;
a consumer that treats them the same has reintroduced the bug.

Input: accept a founder task id, a bare `sig8`, or `dispatch-<sig8>`, and reach the same report from
all three. No `--kind` flag — requiring the caller to know which name it holds is the problem, not
the solution.

---

## 6. The one adopting consumer

`plugins/leadv2/scripts/leadv2-recovery-context.sh:40`:

```bash
HANDOFF_DIR="${PROJECT_ROOT}/docs/handoff/${TASK_ID}"
```

The naive construction, on the **death→resume path** — the script that runs when the lead believes a
lane died and is deciding what to salvage. It was wrong when D6 was re-dispatched over its own
finished report. 186 lines, one commit in its history, no live lane touching it.

Convert it to resolve through the library, and make it *print* the searched paths and the coverage
line into its own `recovery-full.md`. A recovery context that says "no prior deliverable" without
saying where it looked is the artifact that caused the re-dispatch.

**Scope stop.** 31 further scripts reference `*.full.md` / `*.summary.md` (`claude-subsession.sh` 19
refs, `leadv2-phase-advance.sh` 12, `leadv2-broad-status.sh` 6, `leadv2-dispatch-product-close.sh` 5,
`leadv2-recovery-context.sh` 4, plus three hooks). List them in your report as the migration backlog
with counts. **Convert exactly one.** A repo-wide migration is not this lane and will not finish.

---

## 7. Acceptance

### 7a. Suite cases — minimum set

New suite `plugins/leadv2/scripts/tests/test-lane-report-address.sh`. Every case builds its own
fixture tree with `mkdir`/`cp`; nothing reads the live `docs/handoff/`, and nothing uses
`git archive` (§7c).

| # | case | must assert |
|---|---|---|
| C1 | founder id in, report in the dispatch-named dir, receipt present | resolves to the dispatch dir's report; exit 0 |
| C2 | `dispatch-<sig8>` in, same fixture | the **same** report as C1, byte-identical path |
| C3 | bare `<sig8>` in, same fixture | the same report again — three names, one answer |
| C4 | no report anywhere, and **every** fixture dir carries a pointer | `none`, exit 1, **and the searched paths are listed** — assert each expected path string, not merely the word `none` |
| C5 | **no pointer matched, but the fixture contains unattributable dirs** | `unknown`, exit 2, and the output names the unattributable count. **Assert it is not `none`.** This is §3b's 74% and the case the whole lane turns on |
| C6 | report exists but its dir is unreadable (chmod 000) | `unknown`, exit 2, not `none` |
| C7 | **the mirror**: a report belonging to a different lane sits in a neighbouring `dispatch-*` dir, and the founder id appears inside that dir's `review.diff` and `main-dirt.base` (§3c) | it is **never** listed. Assert absence by path. Without the planted `review.diff`, this case does not test the real failure |
| C8 | receipt whose `task_id` is `dispatch-<sig8>` (self-referential — 49 real ones exist) | rejected as a founder pointer; does not resolve a founder-id query |
| C9 | report only under `.claude/worktrees/<lane>/docs/handoff/dispatch-<sig8>/` (depth 5) | with `--worktrees`: found, labelled with its worktree. Without: not `found`, **and the output states worktrees were not searched** |
| C10 | one founder id, two dispatch dirs (two rounds) | **both** returned, each labelled. Assert two paths, not one |
| C11 | every consulted location prints a labelled line | where registry, receipts, missions and eponymous all yield nothing, assert **four** labelled lines are present. A location that contributes nothing must still print |

C6 needs a skip-guard if the suite ever runs as root (chmod 000 does not bite root); skip loudly with
a printed reason, never silently.

### 7b. Ten consecutive runs

Ten, not five. Paste every count line. A defect elsewhere in this repo appeared twice in thirteen
runs and only under load. Runs 1–10 with identical `PASS=n FAIL=0` is the evidence; nine is not.

### 7c. Negative controls

One per changed function body, applied through the real instrument:

```bash
bash plugins/leadv2/scripts/leadv2-mutation-control.sh \
  plugins/leadv2/scripts/tests/test-lane-report-address.sh \
  plugins/leadv2/scripts/lib/leadv2-lane-address.sh \
  '<sed expression>' \
  docs/handoff/INVISIBLE-DELIVERABLES-CENSUS-01
```

**NC-1 is mandatory and is this lane's proof:** disable the rung that adds the resolved
dispatch-named directory to the candidate set, and show C1/C2/C3 go red while the eponymous path
still works. That mutant reproduces the original bug exactly; if the suite stays green under it, the
suite does not test the thing this lane exists to build.

**NC-2 is strongly recommended:** make the `unknown` branch fall through to `none` and show C5 goes
red. If C5 survives that mutation, the distinction the lane is built on is not actually tested.

Rules that have already cost rounds tonight:

- **The mutation goes INSIDE a function body.** A line-number insert landing at file top level
  reddens every suite for the wrong reason and reads as a pass. That happened on 2026-08-25 and the
  first measurement was invalid.
- **Evidence is the `baseline_rc=0` / `mutated_rc=1` pair plus the literal red line.** A `diff_hash`
  is not evidence, nor is the tool's summary without the failed-assertion text.
- **A mutant that reddens by crashing is not a control.** A stack trace instead of a failed
  assertion means the anchor is wrong — fix the anchor and re-run. One was discarded and redone on
  another lane tonight (`JSONDecodeError`).

**Known instrument gap — report it, do not route around it.** `leadv2-mutation-control.sh` refuses
with `control_not_applied reason=baseline_not_green baseline_rc=1` for suites whose setup runs
`git archive <sha>`: that step fails under the tool's isolation even when the suite is green in its
own worktree. Build fixtures with `mkdir`/`cp` and you sidestep it. If you hit it anyway, **report
the literal refusal line** and say which controls you could not run. Do **not** mutate files in place
as a workaround — the tree is shared and other lanes are live right now.

---

## 8. Constraints

- **Off limits:** `tests/known-red-suites.txt`, `main`, `docs/leadv2/`, `.gitignore`,
  `plugins/leadv2/scripts/leadv2-lane-liveness.sh`.
- **`tests/run-all.sh` — held, not forbidden.** See §8a; it is a concurrency lock with a defined
  release, not permanent debt.
- Never `reset --hard`, `clean`, `stash`, or `worktree prune`. The tree is shared and live lanes
  stand next to yours. A `worktree prune` killed two live lanes on a previous night.
- No assertion is weakened. Nothing is added to `known-red-suites.txt`.
- **Commit incrementally, not at the end.** The e2e gate times out at 900s and kills workers on the
  threshold between finished and committed. Uncommitted work in the worktree is lost — and per §2c a
  worktree is one sweep from gone.
- Do not merge to main. Leave the branch green with a report.
- **If any instruction here rests on a false premise, stop and say so with the measurement.** That is
  a complete and welcome answer. §2c and §3a of this brief are both corrected false premises, each
  caught by re-deriving a number a second way — one of them after it had already been written down
  as a recommendation.

### 8a. CI registration — a lock with a release date, not debt

`tests/run-all.sh` is held off-limits because it is the single highest-contention file in the repo:
it is clean in the main tree right now (`git status --short tests/run-all.sh` → empty; last commit
`ac05fe70`), **more than five other open lanes name it in their `LANE_WRITES`**, and five or more
live worktrees hold a modified copy. Two lanes editing its suite table concurrently produce a merge
conflict on the one file that decides what CI runs. That is the whole reason — nothing about this
suite is unregisterable.

**So the row goes in the moment the file is free, and here it is.** `EXTRA_SUITE_MAP` takes
`"<changed-stem>:<suite>"` rows, one per line (`tests/run-all.sh:129-134`). Three rows, because the
suite must be selected on a change to any of the three files this lane touches:

```
leadv2-lane-address.sh:plugins/leadv2/scripts/tests/test-lane-report-address.sh
leadv2-lane-report.sh:plugins/leadv2/scripts/tests/test-lane-report-address.sh
leadv2-recovery-context.sh:plugins/leadv2/scripts/tests/test-lane-report-address.sh
```

Put this block verbatim in your report under the heading `CI-ROW-PENDING`, with the note that it is
a three-line append to `EXTRA_SUITE_MAP` and needs no other change. A suite CI never selects is worth
nothing (E2E-KILLRATE-01 §3); this one is one append away, and the lead lands it when the lock
clears. Do not apply it yourself.

**Other named debt — put it in the report, do not build it:**

1. Making `leadv2-lane-liveness.sh::deliverable_dirs` consume the shared library.
2. The remaining 31-consumer migration list from §6.
3. **The real fix behind the 74%:** `admission-receipt.yaml` should be written for every dispatch,
   with a founder-shaped `task_id`, so coverage climbs from 26% toward 100% and the scan becomes a
   lookup. That is a dispatcher change and a separate lane. Say so; do not do it here.

---

## 9. Report

In `docs/handoff/INVISIBLE-DELIVERABLES-CENSUS-01/developer.full.md`:

- Ten suite count lines.
- The NC-1 pair with its literal red line, NC-2 if run, plus one pair per changed function body.
- The C4, C5 and C9 outputs verbatim — the `none (searched: …)` and `unknown (…)` strings are this
  deliverable's user interface and must be readable in the report.
- The `leadv2-recovery-context.sh` before/after for line 40, and one real invocation showing a
  founder id reaching a dispatch-named report.
- The coverage numbers your resolver prints against the live tree, next to §3b's, so a reader can
  see whether they still hold.
- The `CI-ROW-PENDING` block from §8a.
- The consumer-migration list with per-file reference counts, and the three debt rows.
- Commit shas.

Nothing else.
