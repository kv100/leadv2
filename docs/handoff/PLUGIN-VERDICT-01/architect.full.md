# leadv2 plugin — architect's independent verdict

**Author:** architect (one of three independent opinions; read no other opinion, did not open
`docs/handoff/CONTROL-PLANE-HAS-NO-OWNER-01/brief.md`).
**Date:** 2026-09-02. **Repo:** `/Users/kostiantyn.vlasenko/Projects/leadv2`, working tree.
**Window for every git number below:** `--since="90 days ago"` (≈ 2026-06-04 → 2026-09-02).

**Founder's question:** «мы месяцами фиксим плагин, каждый раз одно и то же — может, это та же
болезнь, что у продукта? может, переписать на Python?»

**Short answer:** the disease is real and it is **not** bash. It is ~195,000 lines of orchestration
sharing mutable state through a filesystem with no owner, no schema and no transaction — plus a test
gate that cannot select 69% of its own suites. A Python rewrite buys, by this repo's own
measurement, between 0% and 19% fewer defects for 20+ weeks of work. **Do not rewrite. Collapse the
copies, extract one state owner, make test selection structural.**

---

## 0. Measurement method — read before trusting any percentage

Every number carries its command. Three caveats to hold throughout:

1. **The unit is a `fix:` commit subject, not a defect.** One defect produced up to 7 fix commits in
   this repo (measured in §2c); one commit can fix several defects. So the percentages describe
   *where repair effort goes* — which is exactly what the founder asked about ("месяцами фиксим") —
   not a defect census.
2. **Classification is disjoint regex over commit subjects, first match wins.** Bucket order is
   deliberate: bash-mechanics is tested **first**, so the language bucket is measured generously in
   its own favour. 16.5% stayed unclassified; I hand-read 25 of those 82 and report the reallocation
   as a range, not a point.
3. **Per-file fix sums exceed the commit total** (612 vs 496) because a commit touching 4 files is
   counted 4 times. The bias is constant across languages, so language *ratios* survive it; absolute
   per-file counts do not.

Three numbers are soft. They are tagged `[SOFT]` and none of them carries a recommendation alone.

---

## 1. The system, measured

```bash
git log --since="90 days ago" --pretty=format:"%s" \
  | sed -E 's/^([a-z]+)(\(.*\))?:.*/\1/' | sort | uniq -c | sort -rn
```

| kind | commits (90d) |
|---|---:|
| **fix** | **496** |
| feat | 217 |
| docs | 208 |
| merge | 80 |
| test | 56 |
| wip | 47 |
| chore | 42 |
| **total** | **1,436** |

**fix : feat = 2.29 : 1.** For every unit of new capability the repo ships 2.3 units of repair. That
ratio *is* the founder's complaint, quantified.

### Surface

```bash
find plugins/leadv2/scripts -name "*.sh" -not -path "*/tests/*" -not -path "*/node_modules/*" -exec cat {} + | wc -l
find plugins/leadv2/scripts/tests -name "*.sh" -exec cat {} + | wc -l
cat plugins/leadv2/hooks/*.sh | wc -l
```

| layer | files | LOC |
|---|---:|---:|
| production shell (`scripts/` + `scripts/lib/`) | 257 | **98,786** |
| test shell (`scripts/tests/`) | 312 | **83,382** |
| hooks | 93 | **13,202** |
| Python | 43 | 9,518 |
| JS workflows | 16 | ~2,000 |
| skills / agents / commands | 41 / 4 / 2 | — |
| **shell under management** | | **≈195,400** |

195K lines of shell is not a plugin. It is a mid-size distributed system whose IPC is the filesystem.

### Concentration — the fixing is not spread out

```bash
git log --since="90 days ago" --pretty=format:"%H %s" | grep -iE "^[0-9a-f]+ fix" | cut -d' ' -f1 \
  | while read h; do git show --pretty=format: --name-only $h; done | sort | uniq -c | sort -rn | head
```

| file | LOC | fix commits 90d | **fixes / KLOC** |
|---|---:|---:|---:|
| `tests/run-all.sh` | 455 | 38 | **83.5** |
| `leadv2-plugin-sync.sh` | 1,084 | 24 | **22.1** |
| `leadv2-dispatch-product-close.sh` | 3,291 | 49 | 14.9 |
| `claude-subsession.sh` | 1,310 | 18 | 13.7 |
| `leadv2-broad-status.sh` | 1,426 | 18 | 12.6 |
| `leadv2-dispatch-code.sh` | **8,405** | **95** | 11.3 |
| `leadv2-active-registry.sh` | 1,388 | 12 | 8.6 |
| `leadv2-status-surface.sh` | 3,353 | 20 | 6.0 |

Read the top two rows carefully. **The two worst files per line are the test selector and the
installer** — the machinery that decides *whether a change gets checked* and *whether a change
reaches the running system*. Not the product logic. The meta-layer is the sick layer.

`leadv2-dispatch-code.sh` deserves its own line: **8,405 LOC, 160 shell functions, 123 distinct
`LEADV2_*` variables read in that one file**
(`grep -ohE "LEADV2_[A-Z0-9_]+" … | sort -u | wc -l`). That is not a module. It is a program with
123 undeclared globals.

---

## 2. Q1 — Language, architecture, process, or surface? The split.

### 2a. Classifier output (disjoint, first-match, all 496 subjects)

```bash
git log --since="90 days ago" --pretty=format:"%s" | grep -iE "^fix" > /tmp/pv_fix.txt
python3 classify.py    # bucket regexes reproduced in the table below
```

| bucket | count | share |
|---|---:|---:|
| **L1 bash mechanics** — heredoc, quoting, escaping, `errexit`, unbound, subshell, pipefail, stderr/stdout pollution, sourcing, regex, bash-3.2 | 43 | **8.7%** |
| A3 process lifecycle & concurrency — pid, liveness, reap, sweep, orphan, terminal, fallback, cleanup, race, cap/floor, stall, signal | 119 | 24.0% |
| A1 state & ownership — registry, ledger, `active.yaml`, journal, lock, atomic, dedup, stale, residue, untracked | 96 | 19.4% |
| A2 install / path / copy topology — symlink, plugin-sync, one-copy, cache, worktree, cross-repo, canonical, merge-base | 58 | 11.7% |
| A4 wiring / inert — "never fired", "not wired", no-op, fail-open, routing, arm, chain, admission | 31 | 6.2% |
| A5 contract / shape — schema, extractor, json, field, identity, taxonomy, row, semantics, header, csv | 26 | 5.2% |
| A6 guard heuristics — promise-guard, false positive, selfcheck, marker, refuse, bypass, threshold | 14 | 2.8% |
| P1 test-only churn — suite, mutation, control, hermetic, flake, vacuous, `EXTRA_SUITE_MAP`, coverage | 27 | 5.4% |
| unclassified | 82 | 16.5% |

**Architecture (A1–A6) = 344 = 69.4% strict. Language = 8.7%. Test churn = 5.4%.**

I hand-read 25 of the 82 unclassified: ~20 were architectural in substance ("completion sentinel
single-writer", "the consumer, not the resolver", "the three wiring points", "close signal and
ownership windows", "bootstrap dirt the plugin itself created"), ~3 test, ~2 feature. Proportional
reallocation puts architecture at **~81%**. I report the range, not the point.

### 2b. The answer, as the founder asked it

Surface and process are **multipliers, not causes** — they do not sit on the same axis as language
and architecture, and a split that pretends otherwise is arithmetic theatre. So: the causal split
first, then the two multipliers separately. That is the honest shape of this answer.

| driver | share of the 496 fix commits | counting method | confidence |
|---|---:|---|---|
| **ARCHITECTURE** — no state owner, no schema, no transaction, no declared contracts | **71%** (range 69–81) | A1–A6 strict = 69.4%; upper bound adds the hand-sampled 16.5% residue | high |
| **SURFACE SIZE** — one concept implemented in N places, so a fix must land N times | **12%** (range 9–15) | A2 = 11.7%, which is almost entirely symlink / copy / cache / cross-repo / canonical | medium |
| **LANGUAGE (bash)** — quoting, heredoc, `errexit`, unbound, subshell, stream pollution | **9%** (range 5–12) | L1 = 8.7%, measured *first* in the classifier so it is generous to itself; corroborated independently in §3 | high |
| **PROCESS** — test-only churn and guard-heuristic tuning that changed no product behaviour | **8%** (range 6–10) | P1 (5.4%) + A6 (2.8%) | medium |

SURFACE and ARCHITECTURE overlap by construction — surface size is *how* this architecture fails,
not a separate disease. In one sentence: **four out of five fix commits in this repo are the system
failing to agree with itself about state; fewer than one in ten are bash being bash.**

### 2c. The process multiplier, measured separately

```bash
grep -icE "round[ -]?[0-9]|fix-round|judge|selfcheck|review" /tmp/pv_fix.txt          # 155
git log --since="90 days ago" --pretty=format:"%s" | grep -iE "^fix" \
  | grep -oE "\b[A-Z][A-Z0-9]+(-[A-Z0-9]+)+-[0-9]{2}\b" | sort | uniq -c | sort -rn
```

- **155 / 496 = 31.2%** of fix commits carry an explicit review-round marker (`round 2`,
  `R5 fix-round`, `judge fix round 2`, `selfcheck fix round`).
- Only **161 / 496 = 32.5%** name a task-id at all. **Two thirds of the repair work is untraceable
  to the task that caused it.**
- Of 129 distinct task-ids, 6 needed ≥3 fix rounds. Worst: `E2E-GATE-RESIDUE-01` at **7**;
  `DRIFT-GUARD-ADVISES-BACKWARD-SYNC-01` at 5.
- Subjects in the log reach **"round 12"** (`fix(statusline): field-boundary R12 fix`), with round
  11, 10 and 9 also present in the statusline and dispatch families.

**Interpretation.** Process causes few defects but multiplies each one into 1.25–7 commits. The
founder's felt experience — "месяцами фиксим одно и то же" — is partly this: an 11-round statusline
task genuinely *looks* like fixing the same thing eleven times, because it is. And the reason it
takes eleven rounds is that there is no contract for the reviewer to check the fix against.
Architecture again, wearing a process costume.

### 2d. The recurring shapes, named

```bash
for k in inert "never reached" "live path" symlink "false green" vacuous fail-open "did not fire" "stale copy" drift; do
  printf "%-16s %s\n" "$k" "$(grep -rliF "$k" docs/handoff/*/ | wc -l)"; done
```

Across **972 handoff directories**: `silently` 1,343 files · `drift` 1,117 · `symlink` 819 ·
`fail-open` 815 · `inert` 404 · `vacuous` 188 · `never reached` 137 · `live path` 105 ·
`did not fire` 24.

Eight names for one shape: **the code that was supposed to run did not run, and nothing said so.** A
guard that fails open, a symlink pointing at the wrong copy, a suite that passes vacuously, a hook
whose output was discarded. That shape is not expressible as a language choice. It is the absence of
a contract stating who owns what and what "it ran" means.

---

## 3. Q2 — Rewrite in Python: **NO.** The measurement that decides it.

This repo has already run the experiment. It contains **43 Python files alongside 780 shell files** —
same team, same review process, same problem domain, same 90-day window. So compare fix density
directly:

```bash
# per file: wc -l  +  git log --since="90 days ago" -- <file> | grep -c '^fix'
bash lang.sh
```

| language | files | LOC | fix touches 90d | **fixes / KLOC / 90d** | fixes / file |
|---|---:|---:|---:|---:|---:|
| Python (`scripts/*.py`, non-test) | 28 | 8,080 | 43 | **5.32** | 1.54 |
| Bash (`scripts/*.sh`, top level) | 225 | 93,139 | 612 | **6.57** | 2.72 |
| JS (workflows) | 8 | 1,979 | 24 | **12.13** | 3.00 |
| **`scripts/lib/*.sh`** — fairest control | 32 | 5,647 | 57 | **10.09** | 1.78 |
| **`scripts/lib/*.py`** — fairest control | 8 | 2,293 | 22 | **9.59** | 2.75 |

**Read the last two rows.** In the one place the comparison is apples-to-apples — same directory,
same role (small focused helpers called by the same dispatchers) — **Python is 9.59 vs bash 10.09
fixes/KLOC: a 5% difference, inside noise.** Per file, bash is *better* in that sample (1.78 vs
2.75). The top-level comparison flatters Python (5.32 vs 6.57, −19%), but that sample is confounded:
those Python files are newer, smaller, and do leaf computation, while the bash files are the
8,405-line orchestrators.

`[SOFT]` LOC normalisation across languages is inherently unfair — bash is more verbose per unit of
logic, which inflates bash's denominator and therefore *flatters bash*. Correcting for that would
move Python's advantage up, plausibly into the −20%…−35% band. Take even the most generous reading:
**the language accounts for at most a third of the fix rate, and the independent subject classifier
in §2 says 8.7%.** Two methods, different data, same direction: language is a minority driver.

And note JS at **12.13 — the highest fix density in the repo is already in the non-bash language.**
Moving to a "better" language did not help the workflows.

### The cost, in the migration surface I counted

| item | measured |
|---|---|
| production shell to port | **98,786 LOC** / 257 files |
| test shell to port | **83,382 LOC** / 312 suites |
| hooks to port | **13,202 LOC** / 93 hooks |
| distinct `LEADV2_*` identifiers to re-home | **981** (670 assigned somewhere; **294 read but never assigned** — see §8) |
| distinct lock filenames to model | **56**, across **309** `flock` call sites in **71** files |
| live consumer repos that may not break mid-migration | **4** — persona-engine, respiro-ios, m3-market, getmany-followup-bot |
| non-code integration contracts to reimplement byte-identically (Claude Code hook protocol, `claude -p` argv, slash commands, skill frontmatter, plugin manifest, statusline) | ~6 |

At a realistic 4:1 shell→Python compression on logic and 1:1 on subprocess orchestration, 195K LOC
becomes **~40–55K LOC of Python**. At a *sustained* 2K LOC/week of reviewed, mutation-tested code —
generous given this repo's own 1.25–7 rounds per task — that is **20–27 weeks**, throughout which
both implementations must run live because four repos depend on the plugin daily.

**Twenty-plus weeks to remove 9% of the defects, while carrying 71% of them across the language
boundary intact, plus a fresh crop of asyncio-specific ones (task cancellation, event-loop
reentrancy, subprocess reaping) that bash never had.** That is the whole argument. It is not close.

### What to do instead — in build order

| # | do this | defect mass it addresses | est. |
|---|---|---:|---:|
| **1** | **Collapse the install topology to one inode.** Delete the two stale plugin-cache version trees; convert the 53 real files in `~/.claude/leadv2-shared/scripts` to symlinks (4 have already drifted — §4). Add a boot assertion that every plugin-owned path resolves to canonical, failing **loud**. | **11.7%** (A2) | **1 day** |
| **2** | **One state owner.** A single SQLite file with a single writer process, replacing `active.yaml` + `dispatch-ledger.jsonl` + `phases.d/` + 56 lock names. Bash keeps working — it calls one CLI (`leadv2-state claim / release / get / set`). No bash is rewritten; only its *storage* changes. Write **this one component** in Python, because it is precisely where types, transactions and process supervision earn their keep. | **43.4%** (A1+A3) | 3–4 wk, ~3K LOC |
| **3** | **Declare the config.** One YAML registry of every `LEADV2_*` — type, default, owner — plus a boot validator that hard-fails on an unregistered or misspelled name. Removes the 294 unbacked reads and makes "flag set but nothing reads it" structurally impossible. | ~5% (part of A4/A5) | 3 days |
| **4** | **Test selection by construction.** Every suite carries `# covers: <path>` in its header; `run-all.sh` derives its map from those headers instead of the 98 hand-written `EXTRA_SUITE_MAP` rows. A suite that cannot name what it covers is deleted. Converts the 216 unselectable suites (§4) into coverage or deletion. | prevention across all buckets | 1 wk |
| **5** | **Split `leadv2-dispatch-code.sh`.** 8,405 LOC / 160 functions / 123 globals → three files (arm routing, quota gate, close gate) with declared interfaces and no shared mutable globals. | ~10% (the 95 fixes on this file) | 2 wk |

Total **≈7 weeks** against **20–27** for the rewrite, targeting 60%+ of the defect mass instead of
9%. Steps 1 and 3 are reversible in an afternoon; only step 2 needs a soak.

---

## 4. Q3 — What must be DELETED

### The largest thing I would remove outright: **the multi-copy install topology.**

```bash
ls -la ~/.claude/plugins/cache/leadv2-local/leadv2/                              # 0.1.0, 0.3.0, 0.5.7
find ~/.claude/plugins/cache/leadv2-local -name "*.sh" | wc -l                   # 1968
find ~/.claude/plugins/cache/leadv2-local -name "*.sh" -exec cat {} + | wc -l    # 512422
find ~/.claude/leadv2-shared/scripts -maxdepth 1 -type l | wc -l                 # 193 symlinks
find ~/.claude/leadv2-shared/scripts -maxdepth 1 -type f | wc -l                 # 60 REAL FILES
```

**Three stale plugin-cache version trees — 1,968 shell files, 512,422 lines — plus 53 real-file
duplicates of canonical scripts in `~/.claude/leadv2-shared/scripts` that project doctrine says must
be symlinks.**

Defence, three facts, none theoretical:

1. **The drift is present right now.** I diffed all 53 real duplicates against canonical:
   **49 identical, 4 already DRIFTED** — `leadv2-broad-status.sh`, `leadv2-pulse-beat.sh`,
   `leadv2-lane-shape.sh`, `leadv2-ask.sh`.
   ```bash
   for f in ~/.claude/leadv2-shared/scripts/*.sh; do
     c="plugins/leadv2/scripts/$(basename $f)"; [ -f "$c" ] && ! cmp -s "$f" "$c" && echo "DRIFTED: $(basename $f)"; done
   ```
2. **The drifted set intersects the most-fixed set.** `leadv2-broad-status.sh` is #5 by fixes/KLOC
   (18 fix commits in 90 days) and exists in two different versions on this machine right now. Every
   one of those 18 fixes had a coin-flip chance of landing in the copy nobody executes.
3. **The class already costs 11.7% of all fixing.** A2 = 58 fix commits in 90 days naming
   symlink / copy / cache / plugin-sync / canonical / cross-repo. The log even contains
   `fix(PLUGIN-CACHE-THIRD-COPY-REVERTS-FIXES-01)` — the system has named this defect after itself
   and fixed it twice.

Cost of the deletion: one symlink pass and an `rm -rf` of two version directories. Risk: rolling
back to 0.3.0 becomes a `git checkout` instead of a directory swap — which is strictly better,
because git knows what version it is and the cache does not. **Highest-value deletion in the
repository, and it costs a day.**

### Runner-up (product surface): three of the four status renderers

`leadv2-status-surface.sh` (3,353) + `leadv2-lanes-snapshot.sh` (1,734) + `leadv2-broad-status.sh`
(1,426) + `leadv2-lane-status-line*.sh` ≈ **7,000 LOC whose entire output is text describing the
system to the founder.** They produced **63 / 496 = 12.7%** of all fix commits in 90 days
(`grep -icE "statusline|pulse|beat|broad-status|status" /tmp/pv_fix.txt`) and zero product
capability. Four independent renderers each re-deriving lane truth from the filesystem is exactly
why they disagree with each other, and exactly why "round 12" exists. After step 2 there is one
state DB — collapse to **one** renderer that reads it and delete the other three.

### Third: the 216 test suites no gate can ever select

```bash
# suites whose stem matches no source file AND which appear in no EXTRA_SUITE_MAP row
# → unselectable_suites 216   LOC 51,376   (62% of all test LOC)
# → suites naming a negative control: 38 / 312 = 12%
```

I am **not** recommending blind deletion — that trades a fake gate for no gate. Recommendation:
every suite gets a `# covers:` header within one cycle (step 4); anything that still cannot name
what it covers after that is deleted. Expect a large fraction of the 216 to go.

---

## 5. Q4 — The single change with the highest defect-prevention per unit of work

**Collapse the install topology to one inode (step 1): 11.7% of the defect mass for one day of work
— 11.7 percentage points per day.**

Nothing else in the repo is within an order of magnitude of that ratio:

| change | defect mass addressed | work | **pp / day** |
|---|---:|---:|---:|
| **install topology → one inode** | 11.7% | 1 d | **11.7** |
| config registry + boot validator | ~5% | 3 d | 1.7 |
| **single state owner (SQLite)** | **43.4%** | 20 d | **2.2** |
| split `dispatch-code.sh` | ~10% | 10 d | 1.0 |
| test selection by `# covers:` | prevention, not cure | 5 d | — |
| **full Python rewrite** | 8.7% | **100–135 d** | **0.07** |

The rewrite is the worst option on this table by a factor of ~160 against the best one.

But be precise about what "per unit of work" hides: the install collapse is a **one-off**. It
removes a class and is then done, and the 43% state-and-lifecycle mass is still there tomorrow. So
the correct instruction is: **do step 1 this week because it is nearly free, then commit the next
four weeks to step 2, which is the highest *absolute* prevention available.** If the founder can
fund only one multi-week thing this quarter, it is the single state owner: one process owns lane
state, locks, liveness, reaping and sweeping, with real transactions, and every other script asks it
instead of guessing from mtimes and lock files.

Supporting evidence for the state claim — and one honest complication:

- **A1 (96) + A3 (119) = 215 / 496 = 43.4%** of fix commits name state, ownership, locking,
  liveness or lifecycle.
- The current mechanism is **56 distinct lock filenames across 309 `flock` sites in 71 files**, plus
  a YAML file referenced by **155 files**.
- **But the registry library is actually well disciplined.** Of 21 files that write `active.yaml`,
  only **one production script bypasses `leadv2-active-registry.sh`**
  (`leadv2-task-init-pattern.sh`; the other two bypasses are test files). So the problem is *not*
  undisciplined writers, and "add another guard" will not help.
- **The problem is that a 1,388-line bash library is being asked to provide transactions, and it
  cannot.** That is the one place where the language genuinely is the binding constraint — and it is
  ~3K lines of Python, not 195K. This is the narrow, defensible slice of the founder's Python
  instinct, and it should be honoured exactly there and nowhere else.

---

## 6. Q5 — What would change my mind

Three measurements. The first would flip the verdict; the other two would reorder it.

### 6.1 `[WOULD FLIP ME]` Where each defect was **found**, not what the fix said

My entire classification reads commit subjects, which describe *the fix*, not *the discovery*. Label
each of the 496 fix commits by discovery channel — (a) a reviewer, in the same task's review round;
(b) an automated test; (c) the founder, in live use; (d) another lane crashing — and:

- **If >60% are (a),** the recurrence is **PROCESS**, not architecture. The "months of fixing" would
  then be the review loop being *logged* as fixes: work that never reached the founder, never broke
  anything, and is simply how this repo spells "code review". In that world neither a rewrite nor a
  state DB is the answer — you fix acceptance-criteria quality, stop counting review rounds as
  defects, and the fix:feat ratio drops without a line of code changing.
- **If >40% are (c),** my answer stands and hardens.

**This is not idle.** 31.2% of fix commits *already* carry an explicit review-round marker, and that
is a **lower bound** on channel (a) — many rounds go unlabelled. If the true (a) share is 60%+, my
71% must be read as "71% of *repair effort*", not "71% of *escapes*", and the build order in §3
changes: step 4 and acceptance-criteria discipline move above step 2. **I would want this measured
before anyone commits four weeks to step 2.**

Probe: join `git log --since="90 days ago" --pretty="%H %ct %s"` against
`docs/handoff/<task>/review-findings.json` — a fix commit whose task has a findings file dated
before it is channel (a); one with no findings file but a founder message nearby is (c).

### 6.2 A fair language comparison at equal complexity

My §3 numbers are confounded: Python here does leaf computation, bash does orchestration. Take
**three** subsystems of comparable orchestration complexity — quota gating, lane liveness,
merge-queue reclaim — reimplement one in Python behind the same CLI, and measure fixes/KLOC over the
following 90 days against the two bash controls. **If the Python arm lands below 3.0 fixes/KLOC
while the bash controls stay near 10**, the language effect is ~3× rather than the ~1.05× I measured
in `lib/`, and a staged rewrite becomes defensible on numbers instead of feelings. Step 2 above *is*
this experiment, run on the highest-value subsystem — a further reason to do it first.

### 6.3 `[SOFT]` Whether the unselectable suites are actually dead

I measured *selectability under `--scope changed`* — the gate that runs on a lane:

```
suites_total 312 · auto stem-match 14 · EXTRA_SUITE_MAP 82 · selectable union 96
NEVER selectable on --scope changed: 216  (51,376 LOC = 62% of all test LOC)
suites naming a negative control: 38 / 312 = 12%
```

I did **not** measure whether a full `run-all.sh` (no scope) executes them, nor whether any CI or
timer ever runs full scope. If full scope runs nightly across all 312 and passes, the coverage hole
is much smaller than I claim and step 4 drops in priority. **If nobody runs full scope, then 62% of
the test LOC in this repo has never protected anything** — and "months of fixing the same thing" has
a mechanical explanation needing no theory at all. One command settles it: whether any CI config or
systemd timer invokes `tests/run-all.sh` without `--scope changed`. I did not run it. It is the
cheapest open question in this document.

---

## 7. Scope note — what I deliberately did not do

- Read no other opinion; did not open `docs/handoff/CONTROL-PLANE-HAS-NO-OWNER-01/brief.md`.
- Modified, staged and committed nothing. `docs/handoff/PLUGIN-VERDICT-01/` is the only path written.
- Did not run `tests/run-all.sh` — it would mutate lane state on a live machine.
- Did not evaluate the 41 skills or 4 agents for content quality: out of scope for a defect-rate
  question, and they carry 0 of the 496 fix commits.
- Scratch scripts (`classify.py`, `lang.sh`) live in the session scratchpad, not in the repo.
- **Out of scope for the implementing agent:** any change to prompts, skills, agent definitions,
  model routing, or the four consumer repos. Steps 1–5 touch install topology, state storage, config
  declaration, test selection, and one file split. Nothing else.

## 8. Pre-finalise contradiction scan

- **Env-var naming vs settings:** uniform `LEADV2_*` prefix; **981** distinct identifiers in shell,
  **670** assigned somewhere in shell/docs/config, **294 read-shaped but never assigned anywhere**.
  `[SOFT]` — an unknown fraction of those 294 are journal *event names* sharing the prefix (e.g.
  `LEADV2_ASK_RACE_FOUNDER_WON`), not env vars, so **294 is an upper bound** on unbacked config
  reads, not a count. The structural finding is unaffected and is precisely the point: with no
  registry, the two kinds of identifier are indistinguishable by inspection. This is why step 3
  exists.
- **Path existence:** every path cited was stat'd this session.
  `docs/handoff/PLUGIN-VERDICT-01/` was `(to-create)` and was created by this run.
- **`claude -p` commands:** this document proposes none. Nothing to check.
- **Concurrent access:** step 2 *is* the mitigation for the read+write race across parallel lanes.
  Steps 3–5 touch no runtime state. **Step 1 must run with no lanes active** — it moves files the
  running dispatcher resolves through. Recorded as an ordering constraint, not a lock.
- **Config contradiction:** none found. Steps 1–5 introduce **no new `LEADV2_*` name**; step 3
  *registers* existing ones rather than adding any.
- **Self-check finding, `source: architect(self-check)`:** the `[SOFT]` 294 above, and the two open
  questions in §6.1 and §6.3, are flagged rather than resolved. §6.1 is a genuine threat to the
  headline percentage and is named as such.
- **Result: no CRITICAL contradictions.**

---

## 9. The verdict in one paragraph

The plugin has the same disease as the product, but the disease is not the language — it is
**lying-green state**: 195,000 lines coordinating through an unowned filesystem, 56 lock names, 981
undeclared variables, 4 copies of the install (4 of them already drifted), and a test gate that
cannot select 69% of its own suites. Bash accounts for 8.7% of repair effort by subject
classification, and for a 5% difference against Python in the only fair in-repo control. Rewriting
costs 20–27 weeks and carries 71% of the defects across the language boundary intact. **Delete the
extra copies this week (1 day, 11.7% of the defect mass), then give the system one state owner
written in Python (4 weeks, 43% of the defect mass), then make test selection structural. Do not
rewrite the plugin.**

DELIVERABLE_COMPLETE
