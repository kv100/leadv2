DYNAMIC-WORKFLOW-SHAPE-AND-ARMS-01 — DESIGN ONLY. Deliverable is a report with a recommended seam,
NOT a diff. Two reviewers, deliberately: codex-astra and fable. Founder order 2026-09-08.

REPO under discussion: ~/Projects/leadv2 (the plugin) and `~/.claude/workflows/*.js`.

## Founder's brief, verbatim in substance

"было бы найс встроить в воркфлоу и кодекс и глм и все наши модели, все использовать можно, но
решает арбитр какие и как. Если арбитр не может решить — пусть фейбл и астра решают. Если у кодекса
есть свои похожие тулы, их тоже стоит использовать."

So there are three questions, and they are not the same question:
1. **Shape** — who decides how wide the fan-out is, how many rounds, whether to diverge at all?
2. **Arms** — how do codex / GLM / kimi / the Claude tiers become selectable inside a workflow at all?
3. **Escalation** — what happens when the arbiter cannot decide?

## What is actually true today — measured by the lead 2026-09-08T10:1xZ, do not re-derive

**Shape is a literal.** 8 workflows exist (`audit`, `causal-critique`, `diagnose`, `diverge`,
`intake-enrich`, `learn`, `ledger`, `po-feedback-loop`); 7 build agent graphs with
`agent()/parallel()/pipeline()`. But the graph's dimensions are authored, not chosen:
`leadv2-diverge.js:20  const FRAMES = [...]` fixes the fan-out width in the file. Content varies
per task; the shape never does. That is gate row 6's disease one level up — there the review depth
is a constant with a branch drawn around it, here the graph itself is.

**Arms are effectively Claude-only.** Only 2 of the 8 reach anything else, and the mechanism is a
shim, not an integration: `leadv2-audit.js:23-28` spawns a Claude subagent via `agent()` and
instructs it **in prose** to "(1) write the mission to a temp file; (2) run
`~/.claude/scripts/glm-coder.sh run <tempfile>`; (3) report", parsing a JSON envelope back. A
Claude agent driving a shell script is not GLM participating in the workflow. **Codex appears in
zero workflows.** `GLM_OK` is a boolean argument flag (`:19`), so even that shim is switched by the
caller, never chosen.

**The arbiter is not in this loop at all.** No workflow consults it. The fallback order in `audit`
is hardcoded GLM-then-`agent()`. So today the answer to "who decides which arm" is: whoever wrote
the file, months ago.

**Codex has surface we do not use.** `codex --help` lists `mcp-server` (run Codex AS an MCP server
over stdio), `agents` (browse agent sessions on the shared local app-server daemon), `exec-server`,
and `cloud`. `mcp-server` in particular is the obvious candidate for making codex a first-class
callable inside a workflow instead of a prose-driven shell-out — evaluate it, and say plainly if it
turns out not to fit.

## What the report must answer

- **The seam.** What is the smallest change that lets a workflow ask the arbiter "which arm for this
  step?" and get an answer, instead of hardcoding one? Name the file and the function. If the
  arbiter's current interface cannot answer a per-STEP question (it answers per-DISPATCH today),
  say so and say what the minimal extension is.
- **Arms as data, not code.** How do codex/GLM/kimi become callable without each one needing its own
  bespoke shim like `glmBuild`? Is `codex mcp-server` the right shape for codex, and is there an
  equivalent for GLM, or does GLM stay a shell-out behind a common adapter?
- **Shape.** Should the arbiter (or the judge, or the complexity estimator that landed as
  `a7db808f`) choose fan-out width and round count per task? Give a recommendation, not options —
  and state the failure mode of your own recommendation.
- **Escalation, per the founder's own instruction.** Define what "the arbiter cannot decide" MEANS
  concretely (no capable arm? tie? missing data?), and what fable+astra deciding looks like as a
  mechanism rather than a vibe. An escalation path nobody can trigger deterministically is not a
  path.
- **Cost.** Every arm added to a workflow multiplies by the fan-out. Say what this costs at the
  widest shape you recommend, in invocations, and what caps it.

## Sequencing — read before recommending anything urgent

This is queued AFTER the six pre-WAVES gate rows. The reason is on the record and the report should
respect it: introducing a self-shaping orchestrator before the FIXED-shape one is proven honest
adds a variable we cannot measure. Three times on 2026-09-07/08 this repo shipped a green that was
measuring nothing, in exactly the place where a shape was a constant with a branch drawn around it.
If your report concludes some part of this must land sooner, argue it explicitly against that
history rather than assuming urgency.

## Constraints
- **Report only. Do not modify any workflow, script, or config.** Write to
  `docs/handoff/SMART-ARBITER-DESIGN-20260907/dynamic-workflow-report-<arm>.md`.
- Two independent reports, one per reviewer; do NOT merge them into a consensus document. Where you
  disagree, the disagreement is the most useful output.
- Every claim about current behaviour carries a file:line. The measurements above are given so you
  do not re-derive them; verify any you intend to build on, and say if one is wrong.
- Never push to origin. Never `reset --hard`, `clean`, `stash`, `worktree prune`.

LANE_DELIVERABLE: report:docs/handoff/SMART-ARBITER-DESIGN-20260907/dynamic-workflow-report.md
LANE_WRITES: docs/handoff/SMART-ARBITER-DESIGN-20260907/dynamic-workflow-report.md

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-881f3851" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.

Before you finish, run your own falsification set and paste its raw output into
your final report: `bash -n` every shell file you changed, `python3 -m
py_compile` every Python file you changed, and the repo's changed-scope test
runner. Show the red output you got and the green output after your fix. A lane
whose self-check is missing or red is refused before any reviewer is spent on
it -- you will have burned the lane for nothing.

Commit your work on the lane branch before ending your session; an uncommitted
exit is treated as an incident.