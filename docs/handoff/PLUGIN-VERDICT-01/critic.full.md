# PLUGIN-VERDICT-01 — critic (adversarial)

Question: "мы месяцами фиксим плагин, каждый раз одно и то же — может, переписать на Python?"

Verdict up front: **NO. Do not rewrite.** The repo contains a natural experiment that already
ran, and it says the language is not the variable. But the founder's frustration is *correct* —
he has simply mis-attributed it. The real cause is measured in §4 and §5, and it is worse than
"bash is bad", because a Python rewrite would carry it across intact.

Measurement window: `--since='90 days ago'`, HEAD = `258d018e` (2026-09-02).
Every number below carries the command that produced it. Ranges are given where n is small.

---

## 0. Baseline

```
git log --since='90 days ago' --oneline | wc -l                       → 1436 commits
git log --since='90 days ago' --format='%s' | sed -E 's/^([a-z]+).*/\1/' | sort | uniq -c
                                                                      → fix 490, feat 217, docs 208
git log --since='90 days ago' --format='%H' --grep='^fix' -E | wc -l  → 500 fix commits
```

**500 fix commits in 90 days = 5.6/day, and fixes are 35% of all commits.** The founder's
premise is factually true. Now the three claims.

---

## 1. ATTACKING "bash is fine, the problem is architecture"

### 1a. Automated signature scan — a deliberately generous UPPER bound

Classifier: `scratchpad/classify.sh` — for each of the 500 fix commits, `git show --unified=0
<sha> -- '*.sh' '*.py' '*.js'`, then regex the added lines for seven bug-class signatures.

```
cut -f2 /tmp/fixclass.tsv | tr ' ' '\n' | sort | uniq -c | sort -rn
  363 SILENT      (2>/dev/null or || true added/removed)
  357 UNSET       (${X:-} , -z "$X" , set -u added)
  331 PATHGUARD   (mkdir -p, -f "$X", BASH_SOURCE)
  287 ARITH       (-eq/-gt/$(( )))
  259 EXITCODE    (PIPESTATUS, pipefail, $?, rc=)
  201 SUBSHELL    (< <( ), mapfile, (cd ))
  172 QUOTE       (IFS=, "$@", ${a[@]}, read -r)
   62 OTHER  10 NONSHELL  9 JSON
```

**I do not believe this number and neither should the merge.** Median fix diff is 118 changed
lines:

```
while read h; do git show --pretty=format: --numstat "$h" -- '*.sh' | awk '{a+=$1+$2} END{print a+0}'; done < /tmp/fixshas.txt | sort -n
  → n=500 p25=40 median=118 p75=253 p90=491 max=7100
```

At 118 lines a diff touches every signature by accident. The scan is an upper bound of ~86%
and it is worthless as an estimate. It is reported only to show that the obvious method
over-reports, which is exactly how someone will argue for a rewrite.

### 1b. Hand-read sample, n=42 — the number I stand behind

Sample: `awk 'NR%12==5' /tmp/fixshas.txt` (deterministic every-12th, n=42 of 500). Each commit
classified by reading its subject + diff into one primary class:

| class | n | would a typed language have caught it at author time? |
|---|---|---|
| **T** — type checker flags it (schema/optional/arg type) | 2 | yes |
| **S** — bash-native semantics, structurally impossible in Python | 11 | mostly |
| **L** — logic / policy / predicate error | 14 | no |
| **D** — distributed: liveness, deploy drift, tmux death, quota, worktrees | 10 | no |
| **test-infra** | 2 | no |
| **config / feat-as-fix** | 3 | no |

**Generous count (T+S) = 13/42 = 31%.** Binomial 95% CI at n=42: **17%–45%**.

**Strict count.** Re-reading the 11 `S` adversarially against myself: only 4 are truly
*language*-caused rather than *design*-caused —

- `4c114ed0` HANDLE-POLLUTION-01 — a quota-gate OK line printed to stdout polluted the
  background handle. Impossible when a function returns a value instead of printing one.
- `4e48b618` "fail closed when codex quota gate is broken" — fail-open on a swallowed error.
  Exceptions make fail-closed the default.
- `a382c233` "no-findings greps are errexit-safe under `bash -e`" — pure `set -e`/grep-exit-1
  semantics. Has no Python analogue.
- `fadd0bec` "a missing test file is no longer indistinguishable from a failing one" —
  exit 127 vs exit 1 conflation.

The other 7 (`+`-prefix regex bug, BOM stripping, symlink-aware sync, token-exact sentinel
matching, env-prefix argv parsing, process-tree predicate anchoring, `set +e` chain guard)
are bugs that reproduce verbatim in Python. Regex escaping, byte-order marks, `os.path`
symlink semantics and string-matching-instead-of-an-enum are not bash problems.

**Strict count (T + 4) = 6/42 = 14.3%.**

> **Answer to Q1: 14%–31%, best estimate ~20%.** The defensible floor is 14%.

### 1c. The falsification that ends the argument

If the fixes were quoting/word-splitting/unset-var bugs, a linter that detects exactly those
classes would light up. It does not:

```
shellcheck --severity=error -f gcc plugins/leadv2/scripts/<file>.sh | wc -l
  leadv2-dispatch-code.sh          (8405 LOC, 102 fixes) → error=0   warning+=27
  leadv2-status-surface.sh         (3353 LOC,  21 fixes) → error=0   warning+= 1
  leadv2-dispatch-product-close.sh (3291 LOC,  51 fixes) → error=0   warning+=16
  leadv2-helpers.sh                (2603 LOC,  12 fixes) → error=0   warning+= 5
  leadv2-plugin-sync.sh            (           24 fixes) → error=0   warning+= 1
```

**Zero error-severity shellcheck findings in the five most-fixed files in the repo.** The
code is already clean of the lexical class. The team writes careful bash — `set -euo pipefail`,
`"${var}"`, `read -r` are the house style, and 151 test suites run `bash -n`
(`grep -rlc 'bash -n' plugins/leadv2/scripts/tests/ | wc -l → 151`).

The defects are **semantic and architectural**. A rewrite relocates them.

### 1d. The natural experiment — already ran, in this repo

43 Python files, 9,518 LOC, already shipped inside the plugin
(`git ls-files 'plugins/leadv2/**/*.py'`). Defect density over the same 90 days:

```
py:  fix commits touching *.py = 40  ; LOC = 9,518            → 4.2 fixes / 1k LOC
sh:  fix commits touching production *.sh (excl tests) = 434
                                     ; LOC = 114,299          → 3.8 fixes / 1k LOC
```

**Python's measured defect density in this codebase is 4.2 vs bash's 3.8 — it is not lower.**

Honest caveats, stated because they cut both ways:
- Python files are newer (median add-age 47d vs 62d for sh), and new code is fixed more. This
  biases Python's rate *upward*; discount it and the two converge to roughly equal.
- Python was chosen for the *hard* parts (`leadv2-glm-policy-resolve.py` took 16 fixes;
  `leadv2-lane-class.py`, `leadv2-drift-only-vendored-check.py` are classification logic).
  Harder problems, more fixes. This also biases Python upward.

Even granting both caveats generously, the strongest defensible statement is
**"Python is no better than bash here"** — not "Python is worse". There is no version of this
data that shows Python is *better*, and that is the load-bearing point.

**Claim 1 verdict: "bash is fine, the problem is architecture" survives the attack.** Not
because it is comforting, but because shellcheck finds nothing and the in-repo Python is no
cleaner. ~20% of fixes are language-attributable; 80% are not.

---

## 2. ATTACKING "a rewrite is too expensive"

This is the claim I expected to demolish. It half-survives.

### 2a. The load-bearing core is genuinely small

```
find scripts -name '*.sh' -not -path '*/tests/*' | xargs wc -l | sort -rn
  → 267 files, 99,072 LOC
  top  5 files = 19% of LOC     top 10 = 29%     top 20 = 42%     top 40 = 56%
```

Runtime call graph (inbound refs from `scripts/`, `hooks/`, `commands/`, `.claude-plugin/`;
tests and docs excluded):

```
  0 runtime refs : 64 scripts  (12,895 LOC = 13% of production LOC)
  1 runtime ref  : 44
  2–3 refs       : 47
  ≥4 refs (core) : 70
```

**64 of 225 top-level scripts (28%) have no static runtime caller at all** —
`leadv2-cache-warm.sh`, `leadv2-context-diet-probe.sh`, `leadv2-wiki-query.sh`,
`leadv2-rag-intake.sh`, `leadv2-negative-memory-compile.sh`, `leadv2-po-queue.sh`,
`leadv2-trajectory-check.sh`, and 57 more. They are invoked, if at all, by prose in a
CLAUDE.md or by a human typing the name.

So the honest scope of a rewrite is not "245 scripts". It is roughly **20 files / ~42,000 LOC**
for the top-20-by-LOC core, or **70 files** by call-graph centrality. That is a real project,
not a fantasy — the "too expensive" objection is weaker than it sounds, and I will not pretend
otherwise.

### 2b. Why it still loses

The rewrite argument gets stronger on cost and collapses on **benefit**. §1d already priced the
benefit at zero-to-negative. You would spend ~42K LOC of rewrite to buy a 14–20% reduction in
one bug class, while carrying 100% of the L and D classes (57% of all fixes) across unchanged
— *and* while running with no CI (§3) to catch the port's own regressions.

There is also a live blast radius that no estimate has counted: **4 consumers**
(persona-engine, respiro-ios, m3-market, getmany-followup-bot) consume this plugin through
per-file symlinks to canonical, per the founder's 2026-07-29 shared-tree decision. A rewrite is
a simultaneous 4-repo cutover of the control plane those repos dispatch through.

**Claim 2 verdict: partially demolished.** "Too expensive" is a weak argument — the core is 20
files. But cost was never the binding constraint; benefit is.

---

## 3. ATTACKING "the tests protect us"

This claim does not survive. It is the worst finding in the report.

### 3a. The suites themselves are better than expected

Sampled 8 suites (`ls *.sh | awk 'NR%40==7' | head -8`) and read their assertion structure:

| suite | invokes real production code? |
|---|---|
| test-adoption-gate-passable.sh | yes — `bash "$INSTALL"` |
| test-codex-resume-argv.sh | yes — real `$RUNNER`, faked `codex` binary stub |
| test-drift-guard-safety-fixes.sh | yes — `bash "${DRIFT_GUARD}"`, real `$CLASSIFY` |
| test-lane-close-loop.sh | yes — `bash "${LEDGER_BIN}" reconcile` |
| test-leadv2-phase8-assert-a2-schema.sh | yes — `_e2e_run` on shipped `$ASSERT_SH` |
| test-plan-in-lane.sh | partial — extracts a function from dispatch-code and sources it |
| test-review-body-persist.sh | yes — `bash "$PRODUCT_CLOSE_SH"` |
| test-status-surface.sh | yes — `bash "$RENDER"` in a sandbox |

**7/8 exercise the real production script with only the transport faked.** That is exactly the
right shape. Test authorship is not the problem. Credit where due, and it is the only place in
this report where anything gets credit.

### 3b. The negative controls are nearly all imaginary

```
grep -lciE 'mutant|mutation|negative control|red-first' *.sh | wc -l          → 93   (claim it)
grep -lE "sed -[Ee]?.*(s\||s/).*(>|-i).*(mut|copy|MUT)|perl -pi" *.sh | wc -l →  2   (do it)
grep -lE '^#.*(chang|flip|mutat|revert).*(re-?run|this suite)' *.sh | wc -l   →  9   (prose only)
```

**93 suites use negative-control vocabulary. 2 of 315 actually apply a mutation
programmatically and assert red.** The rest describe, in a comment, a mutation a human once
performed by hand — e.g. `test-leadv2-phase8-assert-a2-schema.sh:35`: *"changing
leadv2-phase8-assert.sh's rc==3 branch to an OR and re-running this suite"*. That is a
historical anecdote, not a control. It does not re-verify on any future run.

**Sampled ratio: 2/315 = 0.6% of suites have a real, automated negative control.**

Git corroborates that this has already bitten, three times, in the sample window:
- `b9959aa7` — *"C7 red-first leg includes plugins/leadv2/skills in the baseline archive
  (was vacuously red)"* — a control that was red for the wrong reason and read as working.
- `2916fe0c` — *"two standing reds were the tests' fault"*.
- `fadd0bec` — *"a missing test file is no longer indistinguishable from a failing one"* — for
  some period the harness could not tell an absent suite from a failing one.

### 3c. CI runs zero tests

```
ls .github/workflows/                                     → validate-skills.yml   (one file)
grep -rl 'run-all.sh\|run-core-offline' .github/ | wc -l  → 0
ls .git/hooks/ | grep -v sample                           → (empty — no active git hooks)
```

**The entire GitHub Actions surface is one job that runs
`plugins/leadv2/scripts/leadv2-validate-skills.sh` — a SKILL.md front-matter linter — on pushes
that touch skills.** 351 tracked test suites and 84,823 LOC of tests
(`find scripts/tests -name '*.sh' | xargs wc -l | tail -1`) execute in CI **zero times**.

### 3d. The gate that does exist selects a small, hand-maintained slice

`leadv2-phase8-e2e-gate.sh:3` runs `tests/run-all.sh --scope changed`. Never `--scope all`.
(`run-all.sh:29 → SCOPE="changed"`. I initially counted 183 "orphan" suites and **that count was
wrong** — `run-all.sh:272` does glob all four test dirs, but only on `--scope all`, which no
caller uses. Correcting my own error here rather than shipping the scarier number.)

On `--scope changed`, selection is by stem convention (`foo.sh` → `test-foo.sh`) plus 95
hand-written `EXTRA_SUITE_MAP` rows. For the ten most-fixed scripts in the repo:

| script | fixes/90d | `test-<stem>.sh` exists? | EXTRA_SUITE_MAP rows |
|---|---|---|---|
| leadv2-dispatch-code.sh | 102 | **no** | 12 |
| leadv2-dispatch-product-close.sh | 51 | **no** | 5 |
| leadv2-plugin-sync.sh | 24 | **no** | **0** |
| leadv2-status-surface.sh | 21 | **no** | 1 |
| leadv2-broad-status.sh | 18 | **no** | 13 |
| claude-subsession.sh | 18 | **no** | 1 |
| leadv2-phase8-close.sh | 17 | **no** | **0** |
| leadv2-dispatch-ledger.sh | 16 | **no** | 3 |
| leadv2-supervise.sh | 15 | **no** | **0** |
| leadv2-helpers.sh | 12 | **no** | **0** |

**Not one of the ten most-fixed files has a stem-convention suite. Five have zero or one
mapping row.** `leadv2-plugin-sync.sh`, `leadv2-phase8-close.sh`, `leadv2-supervise.sh` and
`leadv2-helpers.sh` — 68 fix commits between them — select **no behavioral suite whatsoever**
when changed.

And `tests/test-codex-quota-gate.sh` — 18,199 bytes of test — is named in **no runner**
(`grep -c 'test-codex-quota-gate' run-core-offline.sh tests/run-all.sh → 0, 0`), while
`4e48b618 fix: fail closed when codex quota gate is broken` shipped inside my 42-commit sample.
The test for the quota gate exists, has never been selected, and the quota gate broke.

**Claim 3 verdict: demolished.** The suites are well-built and structurally honest; the
*harness around them* is not a gate. Good tests, no enforcement.

---

## 4. What the fixes actually are

Three measurements that name the real disease.

**Rework, not new ground:**
```
git log --since='90 days ago' --grep='^fix' -E --format='%H' \
  | while read h; do git show --pretty=format: --name-only $h; done \
  | grep '\.sh$' | sort | uniq -c
  → 493 distinct .sh files fixed
  → 254 fixed ≥2× (51%)
  →  68 fixed ≥5× (13%)
```
**Half of every file fixed in 90 days was fixed again in the same 90 days.**

**A fifth of the "fixing" is the review loop talking to itself:**
```
grep -ciE 'round.?[0-9]|r[0-9] |fix-round' /tmp/fixsubj.txt   → 100 / 500  (20%)
grep -ciE 'round|finding|critic|review|High|Critical' ...     → 159 / 500  (32%)
```
100 commits are explicitly `fix-round 2/3/4` — resolving the project's *own reviewer's*
findings, not a production failure. When the founder says "мы месяцами фиксим одно и то же",
a fifth of what he is watching is the review gate iterating, which is the system working,
mis-read as the system failing.

**One file dominates:**
```
leadv2-dispatch-code.sh: 8,405 LOC (8.5% of production LOC), 102 fixes (20.4% of all fixes)
  → 12.1 fixes / 1k LOC   vs   3.8 repo average   = 3.2× the repo rate
```
**One 8,405-line file carries a fifth of all defects at 3.2× the repo's defect density.** That
is the architecture claim, quantified. It is a file-size problem, not a language problem — and
it is the same problem in any language.

**Bonus, found by accident and worth an incident on its own:**
```
ls .claude/worktrees | wc -l     → 136
du -sh .claude/worktrees         → 7.8G
du -sh .                         → 8.3G
git worktree list | wc -l        → 137
```
**136 stale lane worktrees, 7.8 GB of an 8.3 GB repo (94%).** Every one is a full checkout of
the plugin. Any `grep -r` from the repo root scans 137 copies of everything — this cost me two
timed-out probes during this review, and it silently corrupts every census anyone runs from the
root. Do not `git worktree prune` blindly (the standing memory: pruning killed two live lanes);
reap by lane-terminal state.

---

## 5. Answers

### Q1 — What fraction of 90 days of `fix:` commits would a typed language have prevented at author time?

**14%–31%, best estimate ~20%.** Method: hand-classification of a deterministic n=42 sample
(every 12th of 500), 95% CI 17–45% on the generous count; strict count 6/42 = 14.3% after
removing bugs (regex, BOM, symlink, string-matching, argv parsing) that reproduce verbatim in
Python. Cross-checked against `shellcheck --severity=error`, which finds **0** issues in the
five most-fixed files — the lexical class the question presumes is already absent.

### Q2 — Rewrite: yes or no?

**No.**

Strongest evidence *against my own answer*, stated in full because it is real:

1. `leadv2-dispatch-code.sh` at 8,405 lines and 12.1 fixes/1kLOC is not maintainable by anyone,
   and it must be decomposed regardless. If you are going to break it into ~15 modules anyway,
   writing those modules in Python costs only marginally more than writing them in bash — the
   rewrite becomes nearly free as a *side effect* of work you already owe.
2. The 4 genuinely language-caused bugs in my sample (stdout-as-return-value pollution,
   fail-open on swallowed error, `set -e`/grep exit semantics, exit-127-vs-1) are *structurally
   impossible* in Python, not merely less likely. That class will keep recurring forever in
   bash. 20% of 500 is 100 commits per quarter.
3. My Python-density figure (4.2 vs 3.8) rests on 43 files / 9,518 LOC with a 15-day age
   disadvantage and adverse selection toward hard logic. It is suggestive, not conclusive. A
   fair reading is "no measurable difference", and someone could argue that a *disciplined*
   Python port with `mypy --strict` is not what those 43 opportunistic scripts represent.

I still say no, because: benefit ≈ 20% of one bug class; 57% of fixes (L + D classes) port
across untouched; there is no CI to catch the port's own regressions (§3c); and the cutover is
simultaneous across 4 consumer repos on the control plane they dispatch through. Rewriting the
control plane with no working test gate is how you turn a 90-day fix rate into a 90-day outage.

**Sequencing, if the founder overrides this:** do §Q4 first, then decompose
`leadv2-dispatch-code.sh`, and only then consider language. The smallest first module would be
`leadv2-glm-policy-resolve.py`'s neighbourhood — routing/quota policy resolution: pure
input→decision, no filesystem or process state, already partly Python, 16 fixes in 90 days.
Equivalence proof would be a **differential shadow harness**: run the bash and Python resolvers
side by side on every live routing decision for 2 weeks, log both verdicts, and ship only after
N≥500 real decisions with zero divergence. Nothing switches on a passing unit test.

### Q3 — Most dangerous thing currently believed true and is not

> **"The E2E gate protects the plugin."**

It does not, and the belief is load-bearing — `.claude/CLAUDE.md`'s E2E-KILLRATE-01 rule and the
phase-8 close path both treat a green gate as evidence. Concretely:

- CI executes **zero** test suites. One workflow, and it lints SKILL.md front-matter
  (`ls .github/workflows/ → validate-skills.yml`; `grep -rl run-all.sh .github/ → 0`).
- The gate runs `--scope changed`, and **none of the ten most-fixed scripts has a
  stem-convention suite**; four of them map to no suite at all.
- **2 of 315 suites** have a real automated negative control; 93 use the vocabulary.
- `test-codex-quota-gate.sh` (18 KB) is in no runner, and the quota gate broke inside the
  sample window (`4e48b618`).

The plugin's own doctrine has a name for this shape: *lying green*. The gate is currently the
largest instance of it in the system, and it is the mechanism by which "we fix the same thing
every month" is generated — nothing prevents a regression from returning, so it returns.

Second place, worth naming: **"the 245 scripts are the system."** 64 of 225 have no runtime
caller; ~28% of the surface people believe they must maintain is not on any live path.

### Q4 — Highest defect-prevention per unit of work

**Add one GitHub Actions job that runs `tests/run-all.sh --scope all` on every push and PR.**

- **Work:** one ~20-line YAML file. No new code, no refactor, no migration.
- **What it buys:** converts 351 already-written suites and 84,823 LOC of existing test code
  from decoration into an enforced gate. The tests are already good (§3a: 7/8 exercise real
  production code). They are simply never executed.
- **Why it beats every alternative:** a Python rewrite buys ≤20% of one bug class for ~42K LOC.
  This buys enforcement of *all* classes — L and D included, which are 57% of fixes and which no
  language change touches — for one file.
- **Expect it to be red on day one.** That is the point, and it is the measurement nobody has:
  the first run tells you how many of the 351 suites currently fail, which is a number no one in
  this project knows today. Land it as `continue-on-error: true` for one week to get the
  baseline, then flip to blocking. Do not "fix them all first" — that is how it never lands.
- **Runner-up (do second):** promote the 2/315 mutation-control ratio. Every suite guarding a
  core flow gets a programmatic mutant — full copy, baseline shown green, mutation applied
  inside the function body, suite shown red — not a comment describing one.

---

## Pre-finalize contradiction scan

- **Self-correction, stated rather than buried:** my first orphan-suite count (183 "never
  selected") was **wrong**. `tests/run-all.sh:272` globs all four test dirs on `--scope all`.
  The correct finding is narrower and still damning: the *gate* only ever calls
  `--scope changed` (`leadv2-phase8-e2e-gate.sh:3`, `run-all.sh:29 SCOPE="changed"`), and that
  path selects by stem + 95 map rows, which miss all ten most-fixed files.
- **Second self-correction:** `test-deploy-merge-blocker-gate.sh` and
  `test-status-surface-single-lead.sh` are not missing; they live in `plugins/leadv2/tests/` and
  `tests/`. My basename comparison crossed directories. `run-core-offline.sh:237-241` does
  correctly detect a genuinely missing suite (added by `fadd0bec`).
- **Method contradiction, resolved:** the automated signature scan (~86%) and the hand sample
  (14–31%) disagree by 3–6×. I report the hand sample and explain why the scan over-reports
  (median diff 118 lines matches every signature by accident). Anyone quoting 86% is quoting an
  artifact.
- `shellcheck` is installed locally (`/opt/homebrew/bin/shellcheck`) and referenced in 139
  files, but those are `# shellcheck disable=` / `source=` annotations, not enforcement — it
  appears in `run-core-offline.sh` once and in `.github/` zero times. No contradiction with
  §1c; the point stands that error-severity is already clean.
- The repo-wide shellcheck census timed out at 5 min (137 worktrees). The per-file numbers in
  §1c are complete and are what the argument rests on; no repo-wide count is claimed.
- Consumer path `~/MythicalGames/m3-market` was given in the mission and not independently
  verified by me; it does not affect any number above.
- `mypy --strict` / `tsc --noEmit` were not run: this review has no diff under it and the plugin
  ships no TypeScript. `shellcheck` (§1c) is the applicable analogue and its raw per-file output
  is quoted verbatim there.
- Founder's premise ("месяцами фиксим, каждый раз одно и то же") vs my data: **confirmed** —
  51% of fixed files were re-fixed within the window. No contradiction. The disagreement is only
  about the cause.

Otherwise: none.

DELIVERABLE_COMPLETE
