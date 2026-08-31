# ARM-CAPABILITY-FROM-OUTCOMES-01 — what each model can actually do must be measured on our own work, not asserted in a yaml

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ARM-CAPABILITY-FROM-OUTCOMES-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-arm-capability.sh,plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh,plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/config/leadv2-routing.yaml,plugins/leadv2/scripts/tests/test-arm-capability-from-outcomes.sh,tests/run-all.sh,docs/handoff/ARM-CAPABILITY-FROM-OUTCOMES-01/

Branch from current main. Run with `LEADV2_SUITE_LOCK_DISABLE=1`.

## Why this exists

Today `capability_matrix` in `leadv2-routing.yaml` encodes what each arm is *believed* to be good
at — hand-written `tags`, `kinds`, `sizes`, `cost`. Nothing checks that belief against what the arm
actually delivers, so a wrong cell stays wrong forever and we pay for it in review rounds.

Two live consequences measured on 2026-08-31:

- `glm-flash` (`model: glm-5.3-flash`, `cost: 0.4`, `tags: [cheap, mechanical]`, `sizes: [standard]`)
  took **five of eight** lanes in one window — including "compute the task class and refuse a
  downgrade" and "make the phase gate passable in every repo". Those are not mechanical work. The
  arbiter picked cheapest-capable and `standard` matches nearly everything, so `tags` did no work.
- The codex cell named a tier its launcher rejects and died at every spawn while still winning the
  auction, so the *declared* capability had no relationship to the *delivered* one.

The founder's point is the general one: as long as capability is an opinion in a config, we will
keep rediscovering it by paying for failed rounds.

## The data already exists — connect it

Do not invent a benchmark harness, and do not use published benchmark numbers: they measure other
people's tasks and they rot. We already produce ground truth on our own work:

- `leadv2-lane-outcome.sh` and `leadv2-dispatch-ledger.sh` record lane outcomes;
- `model_select_telemetry` records the chosen arm, model, work_kind, class, and terminal cause —
  and `grep -rln model_select_telemetry` shows its **only** consumer is its own test. Nothing feeds
  it back into routing.

The honest per-lane outcome we already generate is close to a labelled dataset: the lane's arm and
work shape on one side, and on the other whether it produced a real fix whose negative control went
red, a suite that stayed green without its own fix, a death with no work, or a second round.

## [Critical] 1 — build an arm-capability ledger from real outcomes

`leadv2-arm-capability.sh` reads the existing outcome/telemetry records and aggregates, per
`(arm, work_kind, complexity)`: attempts, and how they ended. It must:

- derive everything from records already written — add a new field only if something essential is
  genuinely absent, and say in `report.md` what you added and why;
- be recomputable from the ledger alone, so a number can always be traced to the lanes behind it;
- report **counts, not a score**, until there is enough data. A confident score from four samples
  is worse than an honest "insufficient data".

Say in `report.md` how many usable historical records exist right now. If it is very few, that is
the finding, and the ledger starts accumulating from today.

## [Critical] 2 — feed it back into routing, without hardcoding anything

The arbiter must consult the ledger as a signal alongside cost — an arm that repeatedly fails a
given `(work_kind, complexity)` becomes less preferred **for that shape only**, never globally, and
never by naming an arm in a script. The founder's standing rule holds: quota, task shape and
complexity decide routing; a hand-kept exclusion list never does.

Two guarantees you must not break:

- **an arm with no history is not penalised.** Absence of data is not evidence of failure — that is
  the same defect as `util_freepool=100` meaning "no telemetry";
- **an arm can recover.** Weight recent outcomes over old ones, so a model that improves, or a
  freepool route that changes underneath us, is not condemned by last month's record.

## [Critical] 3 — freepool must be re-discovered, not remembered

`leadv2-freepool-model-select.sh` already fetches the proxy's live `GET /v1/models` and runs a
content-based liveness probe rather than pinning a static route — that design is right and stays.
What is missing is that its findings are transient: which routes were live, which passed the probe,
and how the chosen one then performed is not recorded anywhere the arbiter can see.

Record the probe result and the resulting lane outcome against the concrete model id, so that
"freepool" stops being one opaque arm and becomes the set of models it actually resolved to. A new
good model appearing in the pool must be able to earn its place without a config edit.

## [Medium] 4 — make it readable

One command that prints the table: arm × work_kind × outcome counts, most-used first. The founder
must be able to see what each model is actually good at without opening a ledger file.

## Acceptance

Build `test-arm-capability-from-outcomes.sh` against fixture ledgers — never the real ledger, never
a real dispatch:

1. an arm with repeated failures on one `(work_kind, complexity)` ⇒ deprioritised **for that shape
   only**, still selected for shapes where it succeeds;
2. an arm with **no** history ⇒ not penalised, still selectable;
3. an arm whose recent outcomes improve ⇒ recovers its ranking;
4. fewer than the minimum samples ⇒ reported as insufficient data, not as a score;
5. two freepool routes with different outcomes ⇒ tracked separately by model id, not merged under
   "freepool";
6. the readable table renders the fixture data correctly;
7. every number in the table is traceable to the lane records that produced it.

Add the `EXTRA_SUITE_MAP` row and prove selection with `--scope changed`.

## Rules

- Mutation INSIDE the production body on the real call path, RED, revert, GREEN, clean
  `git diff --stat`. Removing the outcome feedback must turn this suite red.
- A kill counts only if this suite alone goes red, and only if the suite was green first.
- Never name an arm in a script branch. Never write to the real ledger from a test.
- No `grep` against script source as an assertion; no negated command as an assertion; a printed
  `FAIL:` line that leaves `$?` at 0 is not an assertion.
- Bash 3.2.57 only (no `mapfile`); every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. **Commit before you stop**, even if partial.

## Done means

Routing consults what each arm has actually delivered on our own work, an unproven arm is neither
punished nor blindly trusted, freepool models are tracked individually so a new good one can earn
its place, one command shows the table, and removing the feedback turns the suite red with the exit
code following.

## Addendum — published benchmarks are the PRIOR, our outcomes are the update

The founder asked for published benchmarks as a starting point, and he is right that we need one:
our own outcome ledger starts near-empty today, so with no prior the router has nothing to reason
from. Use them as a seed, never as the answer.

Numbers gathered 2026-08-31 (sources in report.md; re-fetch rather than trusting these forever):

- **GLM-5.3-Flash vs GLM-5.3** — DeepSWE v1.1 is the only benchmark both publish directly:
  Flash **63.4**, about **3.5 points** behind the flagship, at roughly **1/9 the price**
  ($0.15 vs $1.40 per 1M input). Flagship wins 5 benchmarks (Agents Last Exam, DeepSWE 1.1, HLE,
  NL2Repo, Terminal-Bench 2.1); Flash wins 3 (AutomationBench, GDPval-AA, Toolathlon).
- **GLM-5.3 overall** — Terminal-Bench 3.0 28.3 (from 4.6), CyberGym 84.5%.

**Every GLM figure above is vendor-reported by Z.ai and has not been independently re-run.** Weight
it accordingly: a vendor number is a weak prior, one of our own mutation-verified outcomes is
strong evidence. Say in `report.md` what weighting you chose.

### This corrects a claim in the body above

The body treats `glm-flash` taking five of eight lanes as evidence of mis-routing. On these
numbers that framing is wrong: 3.5 points behind the flagship for a ninefold saving is a good
trade, and the lanes it took were reasonable. The real defect is narrower and stays:

1. **the config mislabels it.** `tags: [cheap, mechanical]` describes a model that nearly matches
   the flagship on SWE-shaped work. The label understates it AND does not stop it taking hard
   work — the worst of both, because it makes the tag decorative;
2. **it is excluded from review by family** (`DEFAULT_REVIEW_EXCLUSIONS`, routing.yaml:135).
   Whether that exclusion is still justified is a question these numbers reopen — do not change it
   in this lane, but record the question in `report.md`.

So the capability table must carry both: a seeded prior per (arm, work_kind) from published
benchmarks, and the running posterior from our own lanes — with the source of each number visible,
so a vendor claim is never mistaken for something we measured.
