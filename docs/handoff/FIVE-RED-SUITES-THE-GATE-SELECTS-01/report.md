# FIVE-RED-SUITES-THE-GATE-SELECTS-01 — report

Measured at **`5cc0319e`**, on macOS, in a pinned scratch tree built with
`git archive | tar -x`. Both halves of that sentence are load-bearing; see
"The list is only valid with a sha AND an environment".

| commit | what |
|---|---|
| `0e3b51e0` | `test-lane-watch-v2` — selection proof re-pointed at the live mechanism |
| `092e936a` | `leadv2-lane-watch-v2.sh` — an unreadable queue is UNKNOWN, it was answering zero |
| `837c39b9` | `test-skill-telemetry` — the second and last stale `EXTRA_SUITE_MAP` proof |
| `9d5532d1` | `leadv2-writes-overlap.sh` — fail-open kept, its silence removed |
| `195f04b3` | `test-status-churn` — its own negative control had stopped firing |

---

## Step 0 killed half the premise

The row said: five red suites the gate selects, one of them hanging. All three
parts needed checking before any of them could be fixed.

**Selection: true.** All 17 named suites exist and all carry a
`# run-all-triggers:` marker, so `--scope changed` really does select them.

**"Five": false, in both directions.** The list moved 5 → 11 → 15 over one
night while two of the original five had gone green under merges that landed in
between. At `5cc0319e` the honest count is **3 green, 14 red, 0 hanging**.

**"Hangs": false, entirely.** Four suites had been recorded at `rc=124`. Given
the full 240s budget:

```
effort-routing                    rc=1  118s  7/4
phase-gate-inversion              rc=1  127s  red
lane-registry-outlives-dispatcher rc=1   47s  6/4
plugin-papercuts                  rc=0  182s  14/0   <- green, not even red
```

None hangs. `plugin-papercuts` — the one whose hang had been seen first-hand —
passes completely in 182 seconds. And the decisive fact behind all four:
**`tests/run-all.sh` has no per-suite timeout at all.** The only occurrence of
the word in the file is a comment on line 76. The gate cannot emit `rc=124`;
every 124 we had came from our own measuring wrappers and was then attributed
to the subject. "Hangs" was a property of the instrument.

That matters beyond bookkeeping. A red suite makes a claim you can refute. A
suite marked "hangs" makes none, and the next person inherits the verdict with
no way to check it.

*Adjacent, not fixed here:* `leadv2-suite-falsifiable.sh` defaults to a 180s
budget and `plugin-papercuts` takes 182. A suite that flips on two seconds is a
future "sometimes red", and those live in lists for years.

---

## The third class is one dependency, not seven suites

The mission asked to look specifically for suites whose verdict depends on
`$HOME`, live state, or a neighbour. Eight of fourteen did. Running each twice
— ordinary environment, then a scrubbed `$HOME` containing only `.gitconfig` —
eight verdicts moved.

The obvious reading is eight non-hermetic suites. A third measurement says
otherwise: same scrubbed `$HOME`, plus `PYTHONPATH` pointing at the real
site-packages.

| suite | ordinary | scrubbed `$HOME` | scrubbed + PyYAML |
|---|---|---|---|
| `liveness-tristate-01` | 13/1 | 10/4 | **13/1** |
| `arm-capability-honoured` | 1/3 | 2/2 | **1/3** |
| `fork-storm-watcher-liveness` | 5/1 | 2/4 | **5/1** |
| `broad-status-foreign-lanes` | 5/3 | 3/5 | **5/3** |
| `collector-sees-registered-lane` | 2/2 | 1/3 | **2/2** |
| `backlog-pump` | 17/5 | 15/7 | **17/5** |
| `lane-registry-outlives-dispatcher` | 6/4 | 3/7 | **6/4** |
| `lane-watch-v2` (before the fix) | 33/1 | 32/2 | 33/1 |

Every one returns to its ordinary verdict, to the digit. One variable, seven
verdicts, exact agreement. PyYAML on this machine lives in
`$HOME/Library/Python/3.14/lib/python/site-packages` — a **user-site install**,
not a system package. The whole leadv2 control plane parses its YAML through
it: the lane registry, the board, `docs/tasks.yaml`, status. On a host without
that install — a CI runner, a fresh VPS, any container — there is no parser.

**And it degrades toward the reassuring answer.** Not a crash, not a
complaint: an empty queue, no live lanes, no rows, no conflicts. Silence is
indistinguishable from health, and the hosts without the install are exactly
the ones nobody watches by eye.

So the suites were not unreliable. They were reporting a real property of the
product, faithfully, and we mistook the messenger for the message.

### `arm-capability-honoured` — the sharpest instance, and a correction

This one gets *better* with a scrubbed `$HOME`: 1/3 → 2/2. Exactly one
assertion flips — with the real home, "arbiter picked freepool despite router
exclusion"; without it, "arbiter honours the router's exclusion".

Mid-investigation I reported this as "routing looks into the developer's home
directory". The direction was right and the mechanism was wrong, and the wrong
version travelled further than it should have before I corrected it. The
accurate statement is narrower and more checkable: **the arbiter changes its
decision depending on whether a YAML parser is importable**, because it too
degrades silently when it cannot read its own state.

### A hypothesis of mine that was wrong

I proposed `lane-registry-outlives-dispatcher` as a third-class candidate on
the evidence of `rm: /tmp/leadv2-lrod-…: Directory not empty` in its tail. Run
twice in a row with that residue left in place, it gives 6/4 and 6/4 —
byte-identical verdicts. The residue is cosmetic. It *is* third class, by
`$HOME`, not by disk state. Right class, wrong signal — recorded in both halves
because the wrong signal was one I had already stated in public, and someone
would otherwise have inherited it and searched the wrong place.

---

## The list is only valid with a sha AND an environment

Two independent reasons, both measured here:

- **Time.** 5 → 11 → 15 red over one night, with two of the original five
  going green in the same window. A red list without the sha it was taken at
  is wrong in both directions within hours.
- **Environment.** Eight of fourteen give a different verdict at the *same*
  sha depending on whose machine it is.

So "this suite is red" is not a fact on its own. "This suite is red at
`<sha>`, in `<environment>`" is.

---

## What was fixed, and why the old assertion was wrong in each case

### 1. `lane-watch-v2` — a proof of a mechanism that no longer exists

The block grepped `tests/run-all.sh` for the literal `leadv2-lane-watch-v2`,
assuming selection was spelled out in an `EXTRA_SUITE_MAP` table there. That
table was emptied by `65734576` — *"wip(SUITE-MAP): CHECKPOINT —
self-registration markers across 102 suites, **ACCEPTANCE NOT PROVEN**"* — when
selection moved to the `# run-all-triggers:` marker the suite already carries
on line 3. The assertion could only ever fail, and its red said nothing about
lane-watch.

Worth stating plainly: **the commit that broke it labelled its own acceptance
as unproven, in its own message, and that is precisely what surfaced three
weeks later as a red suite.** That is a better argument for the doctrine than
anything we could construct.

The intent was right and is kept. Only the mechanism is re-pointed, and the new
form is stronger: it asks `run-all.sh` what it actually maps
(`LEADV2_RUN_ALL_LIST_TRIGGERS=1`, which prints the discovered rows and exits at
`run-all.sh:213` before the harness mutates anything) instead of matching a
string that any comment would satisfy. An empty map is now its own failure
line — "no row for me" and "no rows for anyone" are different facts.

### 2. `leadv2-lane-watch-v2.sh` — the queue counter answered zero for "cannot read"

`_lw_queued_task_count` parsed `docs/tasks.yaml` under `except Exception:
items = None` plus `|| printf '0'`. Every way of failing to read the file
produced the number **0**. With PyYAML absent, the counter answered "nothing is
queued" forever, `LANE-IDLE` never fired, and the watcher looked exactly like a
watcher with nothing to report.

This is the week's fourth instance of one disease and the most comfortable-
looking: in the arbiter, unknown became *forbidden*; in the write-set guard,
*conflict*; in the review gate, *permission*; in the DoD gate, *positive
confirmation*. Here unknown became **reassurance**.

Three answers now. No task store is still a real zero. A file that exists and
cannot be read exits 3, the shell returns rc=2, and the caller prints
`LANE-IDLE-UNKNOWN` naming the file.

### 3. `skill-telemetry` — the same defect, found by census rather than by luck

The same shape twice is a pattern, so the second one was found by looking
rather than by stumbling. Searched by **behaviour**, not text: a `fail()` whose
message names `EXTRA_SUITE_MAP`. Exactly two suites in the tree, both now
fixed. Of the other 107 references, 99 are the line-2 migration comment and 8
are fixture data inside suites that test the trigger parser itself — left
alone. Its assertion also spelled the stems with a `.sh` the marker does not
carry, so it would not have matched even a live table.

### 4. `leadv2-writes-overlap.sh` — fail-open kept, its silence removed

The header documents the policy: any missing dependency yields "no conflicts
found" and exit 0, because this checker must never be why a dispatch fails.
That policy is untouched — control flow, stdout contract and exit code are
byte-identical on every path that could look.

What does not follow from the policy is that a checker which *cannot* look
should be indistinguishable from one that looked and found nothing. With no
parser it printed exactly what it prints for a clean tree. So on CI and the
VPS every lane passed a check that never ran, while the same lanes were being
refused on a laptop — both halves of a confusing night were true at once.

Four ways of not being able to look now have names — `no_yaml_parser`,
`liveness_unparseable`, `active_yaml_unreadable`, `liveness_bin_absent` /
`liveness_probe_failed` — reported on **stderr** (never stdout, which callers
parse as conflict rows, where an "I could not look" line would read as a
conflict — the opposite error, and fail-open would have become fail-closed by
accident, through an output format) plus a durable journal finding under
`--notify`. A missing registry file and an empty lane list stay real zeros.

*Its neighbour already disagrees with it:* `leadv2-fanout.sh` fails **closed**
on the same unparseable registry — "refusing to fan out (fail-closed)". One
input, two adjacent tools, opposite behaviours. Not an argument for either; an
argument that the decision was never made in one of them. Until it is, a third
tool will pick a third answer.

### 5. `status-churn` — a control that could not run, reported as a control that found nothing

The suite builds a mutated copy of `lib/leadv2-status-cache.sh` with the
`flock` call removed and requires ≥2 recomputes to prove it is really
exercising the lock. It reported *"mutation control did not reproduce the race
(got 0)"*. The mutation had not failed to reproduce anything: **the mutant
never ran.**

The fixture symlinked `leadv2-state-path.sh` alone into a bare directory. That
script sources `leadv2-portable-lock.sh` from its *own* directory — and for a
symlinked script that is the symlink's directory, not the target's. The source
failed, every invocation exited 1 before writing a snapshot, `make_stale` then
raised a bare `FileNotFoundError` into the log, and zero recomputes was read as
"no race". Worth checking wherever else a fixture symlinks one script into a
bare directory: the same silent death is available there.

Three changes, all in the fixture, no assertion weakened: link the sibling;
keep the warm step's exit code and stderr so "COULD NOT RUN" is a distinct
outcome from "ran and found no race"; keep the five consumers' exit codes and
stderr and put them, plus the journal line count, in the failure text — an
empty journal and a journal of five `hit` rows are different facts.

The control now reproduces the race it was written for: **5 recomputes where 1
is correct.**

#### The evidence caught me, not my reasoning

Mid-repair I dropped the `make_stale` line while restructuring that block, and
the suite went to "ran but did not reproduce the race" — the exact wording of
the original bug. I did not find that by thinking about it. I found it because
the failure text now carries the journal line count, and it said five lines
with zero recomputes, which can only mean five `hit` rows, which can only mean
the snapshot was never staled. The change paid for itself before it was
committed, against its own author.

---

## Suite state, before and after

| suite | before | after | hermetic? |
|---|---|---|---|
| `test-lane-watch-v2.sh` | 33 / 1 | **35 / 0** | named, not hermetic — see below |
| `test-skill-telemetry.sh` | 38 / 1 | **39 / 0** | yes (39/0 in both) |
| `test-writes-overlap.sh` | 12 / 0 | **17 / 0** | no, and was not before either |
| `test-status-churn.sh` | 12 / 1 | **13 / 0** | yes (13/0 in both) |

### "Not hermetic" and "named" are different things

`r2-5` in `lane-watch-v2` needs a *readable* queue, so it needs a parser, so
without one it fails and must fail — a case that cannot run is never quietly a
pass. What changed is not whether it fails but what its failure says. It used
to dump three variables and read as a lane-watch defect; it now says "PyYAML is
absent, so the watcher cannot count the queue at all — environment gap, not a
lane-watch defect". The difference is not the colour. It is where the next
person goes.

The new case beside it (`r2-unknown`) *is* hermetic: a file that is present and
unparseable fails at the parse step when a parser exists and at the import step
when it does not, so it reaches the same state either way.

`test-writes-overlap.sh` was already non-hermetic under a scrubbed `$HOME`
before this change — verified by running the pre-change file — for the same
root cause. This commit does not widen that.

---

## Negative controls — every one run, by regex, inside a function body

| control | mutation | result |
|---|---|---|
| `unreadable-queue-answers-zero` | both producer refusals become an answer of zero | `r2-unknown` red, **in both environments** |
| `watcher-knows-the-queue-is-unreadable-and-does-not-say` | the unknown branch is skipped | `r2-unknown` red, both environments |
| `trigger-discovery-returns-an-empty-map` | `scan_suite_triggers()` collects nothing | `lane-watch-v2` **and** `skill-telemetry` red, naming the EMPTY map |
| `overlap-checker-cannot-say-it-did-not-look` | every `sys.exit(20)` becomes `sys.exit(0)` | 2 of 3 cases red — see note |
| `overlap-checker-knows-and-does-not-say` | the announcement branch is skipped | all 3 red |
| `status-snapshot-recomputes-without-the-lock` | `flock` removed (the suite's own) | 5 recomputes vs 1 |

Two of these report something the passing version would have hidden, and both
are kept as measured rather than tuned:

- **`overlap-checker-cannot-say-it-did-not-look` does not kill the liveness
  case**, because that reason is raised in the shell rather than by the python
  exit. Two causes, two sites. The control says so instead of being widened
  until it looks complete.
- **A third assertion I wrote alongside `r2-unknown` survived BOTH of its
  controls.** `r2-unknown-b` asserted the *absence* of a `LANE-IDLE` count —
  and an answer of zero does not print one either, so it held for a reason
  unrelated to the property. **A case that cannot be killed is not a case.** It
  was deleted rather than kept for the count.

Where the parser has to be absent, it is removed by a `yaml.py` on
`PYTHONPATH` that raises `ImportError`, not by touching `$HOME` — so the cases
read the same on a host where PyYAML is installed system-wide.

Catalog: **29 rows, all `expected: killed`.** Nothing was removed from it.

## CI selection, proven from the PRODUCTION file each time

```
CONTROL  clean tree                                  3 selected
PROOF    leadv2-lane-watch-v2.sh          -> 4  incl. test-lane-watch-v2.sh
PROOF    lib/leadv2-status-cache.sh       -> 4  incl. test-status-churn.sh
```

`skill-telemetry` and `writes-overlap` are proven by the same seam from inside
their own suites, which now assert selection against the live map rather than
against a string.

---

## Classification of all 17

**Green at this sha, handed over as red** (3) — `brain-class-live` 24/0,
`codex-longrun` all-pass, `plugin-papercuts` 14/0 in 182s.

**Fixed** (4) — `lane-watch-v2`, `skill-telemetry`, `status-churn`, and
`writes-overlap` (green before, now carrying the cases that make its green
mean something).

**Correctly red, product defect, known and awaiting its own lane** (1) —
`liveness-tristate-01`. Its T5 is a **deliberate** red: the suite scans for
liveness decided by process-table enumeration plus a text row-select and finds
`lib/leadv2-lane-state.sh:248`. I verified the finding is that single known
violator and nothing new. I did not touch it: the suite is honest and the fix
is a behavioural change to liveness in another lane's file.

But a permanently-red-by-design suite is a `known-red-suites.txt` entry
wearing different clothes — nobody can tell a new violation from the old one,
which is exactly how it arrived in my list of fifteen. The choice between
"keep it red as pressure" and "pass while the known violator is the ONLY
finding, and fail loudly on a new one" belongs to whoever owns that fix, so it
is named here rather than taken.

**Still red, not yet reached** (9) — `claude-profile-select` 79/2,
`beat-loop-orphans` 29/1, `broad-status-foreign-lanes` 5/3,
`collector-sees-registered-lane` 2/2, `status-repo-scoped` 4/3,
`lead-worker-channel` 11/1, `backlog-pump` 17/5,
`lane-registry-outlives-dispatcher` 6/4, `effort-routing` 7/4,
`phase-gate-inversion`, `arm-capability-honoured` 1/3,
`fork-storm-watcher-liveness` 5/1.

**Nothing was added to `tests/known-red-suites.txt` or `known-failures.txt`.**

---

## Named, not taken

- **The PyYAML dependency itself.** 90 files under `plugins/leadv2/scripts`
  import `yaml`, and several already name the hazard in their own comments —
  `leadv2-status-collector.sh` says "no yaml import — the plugin cannot assume
  PyYAML", `leadv2-dispatch-code.sh:7703` says "non-fatal registry error (e.g.
  missing PyYAML) — never block dispatch on it". The codebase knows. What
  nobody measured is the aggregate: each site chose "carry on", and together
  they make a control plane that reports health when it cannot see. A single
  loud preflight would convert ninety silent degradations into one clear
  error; that is a product decision with real blast radius and does not belong
  inside a lane about red suites.
- **Whether CI actually lacks the parser.** The mechanism is proven; that CI
  is one of the affected hosts is plausible and **unmeasured**. The check is to
  compare the failure suffix under a scrubbed `$HOME` with what the CI log
  shows.
- **`leadv2-suite-falsifiable.sh`'s 180s budget** against a 182s suite.
- **The symlinked-script-needs-its-sibling shape** wherever else a fixture
  links one script into a bare directory.

---

# Continued — commits 6 through 9

| commit | what |
|---|---|
| `122049f1` | `leadv2-backlog-pump.sh` — it could not reserve a single lane, and that read as restraint |
| `176f792b` | `test-lane-registry-outlives-dispatcher` — it depended on a gate it never mentioned |
| `5a44bc33` | `test-liveness-tristate-01` — a deliberate permanent red stopped being pressure |
| `a12fdf11` | `test-collector-sees-registered-lane` — 2/2 → 4/1, and the last red is a real question |

## 6. `backlog-pump` — the most expensive find after PyYAML, and unrelated to it

`_pump_reserve_lane` called the registry's `register` op directly with 15
positional fields. The registry has expected 16 since it gained `writes`, so
every call raised

```
ValueError: not enough values to unpack (expected 16, got 15)
```

and every candidate was skipped as `pump_skip reason=lane_reserve_failed`. The
loop treats a failed reservation as a capacity refusal — **deliberately,
fail-closed** — so a pump that could register nothing at all was
indistinguishable from a pump correctly declining to overfill.
`LEADV2_BACKLOG_PUMP` defaults to 1, so this was the enabled path.

That shape is worth naming on its own: this is not "unknown became
permission". It is **correct caution swallowing a hard failure.** The safe
behaviour was doing its job and hiding an outage at the same time.

Checked whether it was mine: built a pin at the parent of my own earlier
carousel commit and ran the suite there — the same 17/5, the same
`lane_reserve_failed`. Not mine, and settled by measurement rather than by
argument.

**17/5 → 23/0.** All five failures were this one root cause.

Every other caller reaches the registry through the `leadv2_active_register`
wrapper and was carried along by the field addition; only this site had pinned
the positional contract by hand. **Census of direct callers: four**
(`backlog-pump` ×2, `phase8-close`, `stale-sweeper`), and only `register` had
drifted — the others use ops with short stable signatures. One instance, not a
class. Recorded as a result of the census rather than as its absence.

### A control that killed nothing, which was the point

The second control — drop `detail=` from the pump's journal line — killed
**nothing** on its first run. The reason was in the output but asserted by no
test, and an untested diagnostic is the first thing to rot; that is exactly how
the arity failure survived its whole life. A case was added
(`reserve_failure_names_its_cause`, hermetic: the registry is pointed at a
directory where a file belongs) and the control now kills it. Catalogued as
measured, not as intended.

## 7. `lane-registry-outlives-dispatcher` — a suite depending on a gate it never mentioned

Four failures, one root, and **not** the pump's root. BEAT-LOOP-ORPHANS-01
added a session-kind gate to `_arm_lane_pulse_watch`: only a `lead`
classification arms a persistent loop, and `unknown` fails closed, because
headless worker sessions were arming loops nobody could disarm (measured
2026-09-01: 53 orphaned loops, load 244). A suite harness has no transcript, so
it classifies as unknown, no watcher was ever armed, and "watcher stub never
started" cascaded into three assertions about a registry pid that could not
exist.

The suite now declares `LEADV2_SESSION_KIND=lead`. Not a workaround: the
production code offers that pin for exactly this case. **6/4 → 10/0**, one
line, nothing weakened.

**A paired case was written and deleted.** "A worker session arms nothing"
survived its control (delete the gate, so every kind arms), because a second
dispatch never reaches the arming call in this fixture — it held for a reason
unrelated to the gate. The gap it leaves is written into the suite in plain
words: **the orphan gate is uncovered here.** The opposite mutation is caught:
refusing every kind takes the suite from 10/0 to 6/4, exactly the four failures
it carried.

## 8. `liveness-tristate-01` — a deliberate permanent red that had stopped being pressure

T5 scans the two canonical liveness libs for decisions made by enumerating the
process table and selecting rows by text, and failed whenever any finding
existed, with the known violator named only in prose — a standing red as
pressure until its fix lane lands.

It had stopped being pressure. Nobody scanning a red list can tell a new
violation from the standing one, and the proof is that this suite arrived in a
fifteen-suite red census as *red*, not as *pressure*. It was making noise, not
applying it. Same shape as a `known-red-suites.txt` entry without being in the
file.

The known violator is now a list — one entry,
`lib/leadv2-lane-state.sh:248` — which may only **shrink**. Exactly the known
set is green and says so by name; anything else is red and names the file. A
listed violator that has **moved** passes while telling you which line to
update; one that has **disappeared** prints a note to shrink the list.
**13/1 → 14/0.**

### The subtlety a control caught before it shipped

Keying the list on the **file** would have been a blindfold: a second violation
in an already-listed file would read as "the standing one moved" and be
excused. The moved-branch therefore counts findings per file. The control
proves it — a second injection into `leadv2-lane-state.sh` gives 13/1 and names
**both** lines rather than excusing either.

Both controls here are deliberately distinct from the suite's own T5-NC: that
one proves the **scanner** works, these prove the **list** does not excuse what
it was never given. Without them the suite would be green with any list at all,
including an empty one.

## 9. `collector-sees-registered-lane` — 2/2 → 4/1, and the last red is a real question

The fixture never created the PULSE-REPO-SCOPED-03 ownership mark. The renderer
keeps a foreign-repo row only when this repo dispatched it, and
`docs/leadv2/tasks/<task_id>/` is what says so. That rule landed after the
fixture was written, so the board-level case asserted the older behaviour and
could only fail. The other half of the rule is now pinned too — a foreign lane
this repo never dispatched must be dropped — with a third branch that
distinguishes "the unowned one was dropped" from "nothing rendered at all".
`run_board` also clears the cached snapshot so each case measures a fresh
render.

**The remaining red is left red on purpose.** The suite's own mutation control
stripped the collector's `LEADV2_LANES_ALL_REPOS=1` pin and expected the
foreign lane to vanish. First finding: `leadv2-lanes-snapshot.sh` defaults the
same variable to 1, so that was a single-site mutation of a two-site property.
Both sites removed, measured three ways with the board rendering correctly:

```
pin removed, ownership mark present  -> foreign lane still on the board
pin removed, ownership mark absent   -> foreign lane still on the board
pin AND snapshot default removed     -> foreign lane still on the board
```

Foreign-lane visibility is governed by **neither** of the two things that claim
to govern it. There is a third, unidentified discovery path. That is a product
question about the collector/renderer, larger than this lane, and the honest
state is a red assertion with the measurement written beside it — not a green
bought by lowering the bar. The failure text says so and asks not to be
silenced.

Why it went unnoticed: while the board-level case was broken the lane was
absent from every render, so "absent after the mutation" held for free. **A
control whose expected outcome is an absence proves nothing until something has
been shown to make the thing present.** Fixing the case above is what first
gave this control the ability to fail.

Also hardened: that control mutates the real production files in place and now
restores **both** under an `EXIT` trap. A suite that dies between mutation and
revert leaving a production file mutated is the vandal shape that has already
cost us a working tree once. Verified clean after the run.

---

## State

| | |
|---|---|
| green | `lane-watch-v2` 35/0 · `skill-telemetry` 39/0 · `writes-overlap` 17/0 · `status-churn` 13/0 · `backlog-pump` 23/0 · `lane-registry-outlives-dispatcher` 10/0 · `liveness-tristate-01` 14/0 |
| improved, one honest red | `collector-sees-registered-lane` 4/1 |
| not yet reached | `claude-profile-select` 79/2 · `beat-loop-orphans` 29/1 · `broad-status-foreign-lanes` 5/3 · `status-repo-scoped` 4/3 · `lead-worker-channel` 11/1 · `effort-routing` 7/4 · `phase-gate-inversion` · `arm-capability-honoured` 1/3 · `fork-storm-watcher-liveness` 5/1 |
| catalog | 34 rows, all `expected: killed` |

`broad-status-foreign-lanes` and `status-repo-scoped` both fail on a
`founder-status.md` that renders almost nothing, which is the same board the
question above is about. They are worth taking together rather than one at a
time: if the root is shared it is one finding, not three.

Still nothing added to `tests/known-red-suites.txt` or `known-failures.txt`.

---

## `status-repo-scoped` — four hypotheses, all falsified, nothing shipped

Taken together with `broad-status-foreign-lanes` because both fail on a
`founder-status.md` that renders a board without the content they assert, and
if the root were shared it would be one finding rather than three. It is not
shared, and I did not find it. Recording the dead ends is the useful part:
each one costs the next person a probe.

The suite is honest about the important thing already — every beat's table
carries an own-repo row precisely so that a failed render cannot satisfy an
absence assertion by accident. That control holds: the board renders, the own
row is there, and the render is not degraded.

```
2026-08-31T09:00:00Z [BROAD_STATUS] dispatched=1
09:00

| Линия | Что делает | Состояние |
|---|---|---|
| dispatch-own00001 (dispatch id unknown) | — | writing |
```

The `09:00` line IS the product line, rendered with only its timestamp: the
renderer emits the метрики bits only when `repo_facts` carries one of six
keys, and it carries none. C4's dispatched foreign row is likewise absent.

Falsified, in order:

1. **A cached snapshot across cases.** Clearing the status snapshot inside
   `run_beat` changes nothing — 4/3 before and after. (The same cache WAS a
   real problem in `test-collector-sees-registered-lane`, which is why it was
   the first guess.)
2. **The PULSE-REPO-SCOPED-03 ownership mark**, the root of the collector
   suite's board failure. This suite already seeds it (`seed_dispatch_record`)
   and C4 calls it before the beat.
3. **State escaping the sandbox.** The fixture pins `LEADV2_STATE_ROOT` but not
   `LEADV2_STATE_BASE`, and its sibling pins both. Pinning it changes nothing;
   the resolved path was already inside the sandbox. **The change was reverted
   rather than shipped** — a fixture edit that fixes nothing and is justified by
   nothing does not belong in the tree, however tidy it looks.
4. **The suite reading a different file than the renderer writes.**
   `$REPO/docs/leadv2/founder-status.md` is a symlink to
   `$TMP/state/founder-status.md`; same inode, same bytes.

What is left: the stub honours the real calling convention
(`--out <path>`, verified against `leadv2-broad-status.sh:299`), the snapshot
shape matches what the renderer reads (`sections.repo_facts.data`,
`leadv2-broad-status.sh:520`), and the lanes table from that same snapshot
renders — so the snapshot is being read. Why `repo_facts` from it does not
reach the product line is the open question, and it is where the next probe
should start.

**Nothing was committed for this suite.** Three red assertions with four named
dead ends is a more useful handover than a fixture edit that moves a number
without explaining it.

---

## The board finding — one root, two suites, six red assertions

The section above closed `status-repo-scoped` as four dead ends and nothing
shipped. That was the honest state at the time; it is now superseded, and the
root is one line from the third hypothesis I had reverted. **The revert was
still right**: pinning `LEADV2_STATE_BASE` fixed nothing and explained nothing.
The state root was never the problem — the *board path* was.

### What it is

`docs/leadv2/founder-status.md` is a RENDER-class control-plane name: a symlink
into the state root, and `leadv2-state-path.sh` repairs that symlink on every
call. The renderer writes with temp+rename, which forks the link into a real
file; the repair puts the symlink back. Measured 2026-09-05 across three beats:

```
beat 1  snapshot [dispatch-fee00001]                board row: fee00001
beat 2  snapshot [dispatch-own00001, error-row]     board row: fee00001
beat 3  snapshot [dispatch-own00002]                board row: fee00001
```

The snapshot is fresh every beat, the script exits 0, the symlink is present
and re-created every beat, the state-side copy's md5 never changes. Pointing
`LEADV2_FOUNDER_STATUS_PATH` at a plain file in the sandbox — the override
PULSE-READABLE-01 added for exactly this — and the same three beats render
`fee00001 → own00001 → own00002`, which is what the suites always asserted.

So both suites were reading beat 1's board forever. Their assertions were never
wrong about production; they were reading the wrong artifact. Nothing was
weakened to make them pass.

| suite | before | after |
|---|---|---|
| `test-status-repo-scoped.sh` | 4/3 | **7/0** |
| `test-broad-status-foreign-lanes.sh` | 5/3 | **8/0** |

### The second defect, unrelated and worse

`test-broad-status-foreign-lanes.sh` installed S3's liveness stub with
`env LEADV2_LANE_LIVENESS_BIN=… snap`. `snap` is a shell **function**; `env`
execs a binary. That line has failed with `env: snap: No such file or
directory`, rc=127, empty output on every run since it was written — the stub
was never installed and S3 measured nothing at all.

It stayed invisible because of two swallows in a row: `snap()` discards stderr,
and the verdict used `2>/dev/null || true`. The result was a failure line that
read, in full:

```
[TEST] FAIL: S3:
```

A red that names nothing is the mirror image of a green that proves nothing —
same disease, opposite colour. The suite now distinguishes "the instrument did
not run" from "the answer was wrong", and says which.

### Negative controls — three, all by regex inside a body, all run

| # | mutation | result |
|---|---|---|
| 1 | `leadv2-broad-status.sh`: the PULSE-REPO-SCOPED-03 ownership test becomes `or True` | `status-repo-scoped` 7/0 → **6/1**, C3 names the unowned lane on the board |
| 2 | `leadv2-broad-status.sh` (render.py): stop extracting `{repo,error}` rows | `foreign-lanes` 8/0 → **7/1**, R2 red |
| 3 | `leadv2-lanes-snapshot.sh`: a failed foreign liveness read reports `live` | `foreign-lanes` 8/0 → **7/1**, S3 red, naming the row |

Control 1 was also run against `foreign-lanes` and killed **nothing** (8/0) —
its foreign lane is owned, so unconditional ownership changes nothing there.
Recorded because a control that does not fire is a fact about coverage, not a
detail to leave out: it is *not* that suite's control, and is not claimed as one.

All three are in `tests/mutations/catalog.yaml` (37 rows, every one
`expected: killed`). Production files verified clean after each run.

### CI selection, proven by changing the production file

```
$ printf '\n# marker\n' >> plugins/leadv2/scripts/leadv2-broad-status.sh
$ LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed
[SELECT] …/tests/test-broad-status-foreign-lanes.sh
[SELECT] …/tests/test-status-repo-scoped.sh
```

Both carry `# run-all-triggers: leadv2-broad-status.sh`. The marker was reverted
immediately; `SELECT_ONLY` exits at run-all.sh:412, before the control-plane
symlink relocation that makes a full run unsafe in a live checkout.

### One open product question, not fixed here

A beat's freshly written board can be discarded by the control-plane symlink
repair. In the fixture that is certain and measured. Whether it can happen to
the founder's real board I have **not** established — production may be saved
by the repair's migrate branch, and I did not test it, so I am not claiming a
production defect. But the two components run in the same order there, and the
failure is silent: the script exits 0 and the stale board keeps its old
timestamp-bearing content. It deserves a backlog row of its own. I did not file
it — that is the lead's call and outside this lane's write set.

---

## `lead-worker-channel` — the third suite on the same root

C5 drains a row from the lead inbox and finds it in the rendered board. C5b
runs a second beat and asserts the consumed row does **not** repeat. It did
repeat — because the second beat's board *was the first beat's file*. Same
control-plane symlink, same freeze.

The channel itself was never at fault, and the suite already proved that: C3
("a second drain returns nothing") and C4 (twenty rows, two concurrent drains,
each delivered exactly once) exercise the drain API directly and were green
throughout. Only the case that looked at the contract *through a rendered
beat* was reading a stale artifact. **11/1 → 12/0**, nothing weakened.

### The control that fired for the wrong reason

First attempt: swap `drain` for `peek` in the beat's call. It reddened the
suite — at **C5**, not C5b. `peek` is not a subcommand, so the row never
rendered at all and the fixture broke instead of the contract. A control that
reddens a suite by breaking its fixture proves nothing about the behaviour
under claim, and would have gone into the catalogue as a kill it never made.

Retargeted at the contract itself: in `leadv2-inbox.sh`, the lead's read-offset
never advances (`f.write(str(len(lines)))` → `f.write("0")`), so every drain
re-delivers the whole inbox. **12/0 → 9/3** — C3, C4 and C5b, the same contract
at three levels. Both attempts are recorded in the runner and in the catalogue
note; the dead one was not quietly replaced.

CI selection proven by changing `leadv2-inbox.sh`, a trigger this suite
declares: `[SELECT] .../tests/test-lead-worker-channel.sh`.

### A commit guard that fires on every commit in this checkout

`scripts/open-threads-guard.sh` refused both commits: the shared control-plane
copy of `docs/leadv2/open-threads.md` diverges from HEAD, so any commit "would
lose hand-authored content". No commit of mine caused that and none can fix it
— the file is a symlink into shared live state that other sessions write.

Both commits were made with `PE_ALLOW_OPEN_THREADS_SHRINK=1` **and an explicit
two-path pathspec**, so neither could carry that file whatever the index held;
`git show --stat` on each confirms it. Recorded rather than silently overridden,
because a guard that fires on every commit trains everyone to override it, and
the next person will do so without the pathspec.

---

## `claude-profile-select` — both halves of T23 asserted a shape that never existed

79/2 → **82/0** (three assertions where there were two).

T23 and the D3 rescue landed on the same day, 2026-09-03, in two commits whose
own subjects say what they are: *"rescue uncommitted lane work after worker
death"* and *"checkpoint of a worker that died mid-write — NOT finished work"*.
The suite and the production file disagree because **neither half was
finished**, not because the product regressed. Worth naming as a shape: when a
suite and its subject contradict, the date and the commit subject on each side
decide which one to believe — not which one is easier to change.

- The warn carries `sub=` and `account=`, not `identity=`. The `identity=` form
  is from `f6c580d8` (2026-08-27) and was replaced by the same rescue commit
  that added this case.
- `profile=same-fresh … candidates=2` is **unreachable by design**. Two slots on
  one real account is "the incident" in the script's own header table, and its
  documented response is to select nothing — `profile=- reason=same_account` —
  so the caller keeps the profile it inherited instead of silently collapsing
  two slots onto one account. No code path reaches a candidate count after a
  same_account hit. "fail-open, as with T14" was carried over from T14, whose
  case has no same_account hit at all.

T23's intent is untouched and is now asserted on both sides: the stale sibling
is warned about **and kept** (D3), the pair is then detected and named, and the
incident response is pinned with it.

| control | result |
|---|---|
| a `continue` after the `expiresAt_stale` warn — the pre-D3 hole reopened | 82/0 → **77/5**, T23b among them |
| the `same_account` refusal removed | 82/0 → **77/5**, T23c plus T14b/T14c/T21b/T21c |

Control A leaves T23a green **on purpose**: T23a asserts the warn, which still
fires. The *kept* half of the contract is what A proves. Said out loud rather
than left to look like a gap.

## `beat-loop-orphans` — a standing red that had stopped being pressure

29/1 → **30/0**, with both known sites named in the passing line.

F2 greps the plugin tree for `claude -p` spawn sites that do not pin a
subsession role, and failed on any finding at all — with the two standing ones
named nowhere. That is a `known-red-suites.txt` entry living inside the file:
nobody scanning a red list can tell a new violation from the standing one, and
the proof is that this suite arrived in a fifteen-suite red census as *red*, not
as pressure. Same disease as `liveness-tristate-01`, same treatment.

`leadv2-dispatch-code.sh:4860` and `leadv2-active-registry.sh:323` are now
pinned by file:line. Exactly that set is green and says so by name; anything
else is red and names the file:line. A listed site that **moved** passes while
printing the line to update; one that **disappeared** prints a note to shrink
the list. The list may only shrink — and both entries have a filed task to pin
the sites themselves. Both halves are needed: the list is what lets the suite
catch a new violation *today*, the task is what stops the list becoming
permanent.

| control | result |
|---|---|
| an unpinned spawn in a new, unlisted file | 30/0 → **29/1**, names `zz-mutant-spawn.sh:3` |
| a **second** unpinned spawn inside a **listed** file | 30/0 → **29/1**, names `leadv2-active-registry.sh:324` as NEW |

The second control is the one that matters: a list keyed on the *file* would
read that as "the known one moved" and excuse it forever, so the list counts
findings per file. The suite's own NC4 still fires — these controls prove the
**list**, NC4 proves the **gate**.

Both CI selections proven by changing production files
(`leadv2-claude-profile-select.sh`, `leadv2-dispatch-code.sh`), markers
reverted. Catalogue: **42 rows, every one `expected: killed`.**

## `test-plugin-papercuts.sh` — 14/0 the whole time; the budget was the defect

This one was not red. At full budget it is **14 passed / 0 failed** and 182s
long, against a 120s wrapper. `rc=124` was a property of the budget.

The first sample of "where does the time go" was **wrong, and wrong in the
accusing direction**: filtering `ps` by NAME (`leadv2|codex|glm|claude`) put
`leadv2-status-collector-guard.sh` (42 samples) and `leadv2-status-collector.sh`
(35) at the top, which reads as a fixture leak arming real watchers — the very
thing this fixture's own `LEADV2_PULSE_MODE=0` guard exists to prevent. Those
were this machine's OTHER live sessions. Re-sampled scoped to the suite's own
process group (`set -m`, so the background suite gets its own pgid): across 59
samples the group contained exactly two things — `leadv2-dispatch-code.sh` (60)
and `sleep 1` (44). Nothing external, nothing hung.

The `sleep 1` is two codex post-spawn deadlines, both polling, both waiting for
an artifact a **stubbed** launcher never writes, so both always run to full
term here — once per codex-arm dispatch (P3b, P5, P6):

| window | knob | default | per run |
|---|---|---|---|
| `_arm_early_verdict_window` | `LEADV2_ARM_EARLY_VERDICT_S` | 20s | ×3 = 60s |
| `_codex_instant_complete_deadline_check` | `LEADV2_CODEX_INSTANT_COMPLETE_SECS` | 30s | ×3 = 90s |

150s of a 182s run. Pinned to 0 — each knob's own documented disable value
(`[[ "${deadline}" != "0" ]] || return 0`). **182s → 32s, still 14/0.**

The second half is not budget at all. `_codex_instant_complete_deadline_check`
scans via `_codex_newest_rollout_since`, which walks
`${CODEX_HOME:-$HOME/.codex}/sessions` — **1955 real rollout files on this
machine** — once a second for 30s, three times a run, because the fixture never
pinned `CODEX_HOME`. Stated precisely, because the two halves differ: the file
it **picks** is cwd-filtered, so a foreign rollout could not be misread as the
fixture's; the `candidates=` count it reports is **not** filtered and feeds an
emitted decision line (`arm_dead_instant_complete_ambiguous_rollout`). So a
concurrent real codex session changed what this fixture's dispatch wrote to its
own journal. `CODEX_HOME` now points at the sandbox.

Written into the fixture rather than left implicit: disabling those two windows
covers nothing this suite ever claimed. It claims tier validation, spawn
fallthrough, resume placement and backlog-write refusal — no codex liveness.

| control (production, by regex, inside a body) | result |
|---|---|
| `_codex_tier_validate`: `top\|standard\|volume\|spark) return 0 ;;` | 14/0 → **13/1**, P3 |
| the absolute-path branch: `if false; then` | 14/0 → **13/1**, P6 |

Control A is the informative one: under it the journal reads
`route_resolved by=router model=codex` for `tier=spark` — the banned tier wins
the auction and would die inside `codex-task.sh` at spawn. That is the silent
fallthrough to a costlier arm the resolution-time check exists to prevent, and
the suite sees it. Control B kills P6 while **P5 (bare name) and P6b (bad ref
refuses with guidance) stay green**, so the two accepted shapes are pinned
separately and neither mutation can excuse itself with the other form.

CI selection proven by changing the production file
(`leadv2-dispatch-code.sh`, marker reverted): `[SELECT] …/test-plugin-papercuts.sh`,
`run-all: 106 selected, scope=changed`.

Commits: `833adb6f` (fixture), catalogue + this section following.
Catalogue: **50 rows, every one `expected: killed`.**
