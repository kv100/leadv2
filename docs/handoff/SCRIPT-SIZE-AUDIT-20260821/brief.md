# Audit: are the plugin scripts too big, and is their size costing us speed?

**Deliverable is a DOCUMENT ONLY. Do not refactor, do not rewrite, do not "fix while you are in
there".** The founder will act on this in a dedicated session. A patch here is out of scope; an
accurate map is the whole product.

The founder's question:

> The plugin scripts are insanely huge, and maybe slow in themselves. Maybe we need a refactor, a
> rewrite, or a different approach?

Answer whether that is true, with measurements — and if it is not true, say so with the same rigor.
"Big" is not automatically "slow" and not automatically "wrong": a 5000-line script that runs in
40 ms and is edited twice a month costs nothing. What matters is where time and defects actually go.

## Starting facts (measured 2026-08-21 — re-derive them, do not trust them)

- **78,509 lines across 204 `*.sh` files** under `plugins/leadv2/scripts/` (+ `lib/`).
- Largest: `leadv2-dispatch-code.sh` **5549**, `leadv2-status-surface.sh` **3259**,
  `leadv2-dispatch-product-close.sh` **2667**, `leadv2-helpers.sh` **2594**, `leadv2-fanout.sh`
  **1965**, `codex-task.sh` **1862**, `kimi-coder.sh` **1804**, `glm-coder.sh` **1773**,
  `leadv2-lanes-snapshot.sh` **1389**, `leadv2-review-run.sh` **1217**.
- Several scripts embed sizeable Python heredocs inside bash (the reaper in `codex-task.sh`, the
  selfcheck's checks, the pulse renderer), so "bash" understates what is really two languages in one
  file with no boundary either can typecheck.

## What to answer

**Q1. Measure, do not eyeball.**
For the top ~15 scripts: wall-clock for a representative invocation (startup/parse time vs work
time), how many subprocesses each spawns, how often each is invoked per lane, and how much of a
lane's total wall-clock they account for. Separate **parse/startup cost** from **work cost** — that
distinction decides whether size itself is the problem or merely correlates with it.

**Q2. Is size hurting correctness rather than speed?**
The likelier cost of a 5500-line bash file is defects and review rounds, not milliseconds. Look for
evidence: functions with many callers and no tests, duplicated logic across scripts (the same
exclusion set copy-pasted at multiple sites is a known instance — one copy was widened and the other
was not on 2026-08-21), `set -u` landmines, unbound-variable paths reachable only in failure
handling, and long functions whose control flow no reviewer can hold at once. Quantify what you can:
longest functions, most-duplicated blocks, files with the most bug-fix commits.

**Q3. Bash vs something else.**
Give a real verdict on whether bash is still the right language here, and be specific about where.
Consider: the embedded-Python-in-bash seams, JSON handling, concurrency and process-group management
(a recurring source of dead workers), and testability. If the answer is "keep bash for the process
plumbing, move X and Y to Python", say exactly which X and Y and why. If the answer is "bash is
fine, the problem is structure not language", say that — it is an equally valid finding.

**Q4. If a refactor is warranted, what is the smallest one with the largest payoff?**
Rank by payoff-per-risk. The plugin is load-bearing for every lane in three repos, so a big-bang
rewrite is almost certainly wrong; name the seams where extraction is cheap and reversible. For each
proposal: what moves, what it costs, what could break, and how we would know a month later that it
helped (a measurement, not a feeling).

**Q5. What should simply be DELETED?**
Dead code, superseded mechanisms, scripts nothing calls, kill-switched features nobody turns on.
Deletion is the cheapest refactor and the one nobody proposes. Name candidates with evidence that
they are unreachable or unused.

## Rules
- **Evidence or it does not count**: a measured time, a count you derived, a `file:line`. An
  unevidenced claim about behaviour is the exact defect class we are trying to kill.
- Distinguish **"I measured this"** from **"this appears to be"**. Both are fine; conflating them is
  not.
- If the honest answer is "the size is not the problem", say it plainly and say what is.
- **No code changes.** Read, measure, and write the document.

Write your answer to `docs/handoff/SCRIPT-SIZE-AUDIT-20260821/codex-findings.md`.
