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
