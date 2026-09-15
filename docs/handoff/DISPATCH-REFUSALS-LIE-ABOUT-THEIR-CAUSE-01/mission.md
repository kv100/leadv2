# DISPATCH-REFUSALS-LIE-ABOUT-THEIR-CAUSE-01

Not a founder backlog row — three defects measured in one session, taken with founder approval
2026-09-15. All writes in **`~/Projects/leadv2`**, file
`plugins/leadv2/scripts/leadv2-dispatch-code.sh`.

Common shape: **the dispatcher refuses correctly and then names the wrong cause**, so the operator
fixes the wrong thing. Measured cost on 2026-09-14/15 alone: roughly an hour across eight refusals.

## D1 — an unknown `--kind` is silently treated as product
`LEADV2_NON_PRODUCT_KINDS` (`:4363`) is `plugin|tooling|tool|docs|documentation|diagnosis|diagnostic|investigation`.
`classify_product_work` walks exactly that list; anything else falls through to
`printf 'product\tconservative_default'`. There is **no error and no warning** — `--kind code`
(the obvious guess) is indistinguishable from declaring product work, which then forces the
architect prepass at its 420s default.

Measured: five lanes dispatched with `--kind code` sat in the prepass 6+ minutes each and wrote
**not one journal line**. From outside, identical to a hung dispatcher.

**Fix:** an unrecognized `--kind` is refused at argument-parse time, naming the value supplied and
listing the accepted set (read from the same variable, so the message can never drift). An
*absent* `--kind` keeps today's conservative default — that one is a deliberate policy, not a typo.

## D2 — `REFUSE mission: ... is absent` when the file is present
The refusal reads:

```
REFUSE mission: path=docs/handoff/<ID>/mission.md is absent from both
lane worktree=<path> and main
```

The file was present in the worktree; `git status` showed `?? docs/handoff/<ID>/mission.md`. The
check tests **git tracking**, not the filesystem. Copying the mission into the worktree — the fix
the message's own wording implies — does not clear it.

Measured: four refusals in a row across both repos before the cause was seen.

**Fix:** distinguish the two states. Absent from disk → say absent. Present but untracked → say
untracked, name the file, and give the remedy (`git -C <lane> add <path> && git commit`). Two
states, two messages.

## D3 — `premise_probe backlog_row_not_found` for a row that exists
`--task-id PLUGIN-TASK-ADD-DEAD-PROBE-01` was refused `backlog_row_not_found`, while
`docs/tasks.yaml` carries that exact string as `external_id:` (and `node_id: leadv2:<tag>`) on row
`4b22438d0053`. Passing `--task-id 4b22438d0053` resolved immediately. The resolver keys on the
`- id:` field only.

Residual worth noting honestly: a sibling row (`27e3c3e95aa3` / `PE-LANE-PREFLIGHT-GATE-01`) DID
resolve by tag, so the rule is not simply "tags never work". Establish what actually differs
between the two rows before changing the resolver — do not fix a rule you have not measured.

**Fix:** resolve by `id`, then `external_id`, then `node_id`; and when nothing matches, say which
keys were searched. Only if the measurement supports it.

## D4 — `--resume-lane` usage says sig8, the code wants a path
`usage()` prints `--resume-lane <task-sig8|founder-id>`. Passing the sig8 it documents is refused:

```
lane_placement_refused reason=no_lane_worktree_for_ref ref=e6816fbf given=e6816fbf
  looked_for=/Users/.../.claude/worktrees/e6816fbf
```

The resolver joins the given string onto `.claude/worktrees/` — so it wants the worktree
**basename or absolute path**, never the signature. A second refusal in the same family:
`--resume-lane` and `--worktree` are mutually exclusive, which the usage block does not say.

Measured 2026-09-15: three failed dispatches of the same lane before the shape was guessed.

**Fix:** make the usage string describe what the code accepts, and accept the sig8 as well (the
lane's own journal already maps sig8 -> worktree path) — or refuse it with a message naming the
path it would have used. Also state the `--worktree` exclusivity in usage.

## D5 — `row_owner_ambiguous` counts the dispatcher's own artifacts as backlog rows
`--task-id 0ef607442f84` was refused `row_owner_ambiguous -- 2+ backlog rows across the searched
repositories match this id`. There is exactly one backlog row with that id. What the search
actually matched:

```
docs/handoff/dispatch-8a0d9618/admission-receipt.yaml
docs/handoff/REAPER-DRY-RUN-ENV-VAR-IS-SILENTLY-IGNORED-01/mission.md
docs/handoff/0ef607442f84/brain.yaml
docs/handoff/0ef607442f84/cost-estimate.yaml
docs/handoff/0ef607442f84/task-class.yaml
```

Four of the five are files the dispatcher itself wrote moments earlier; the fifth is the mission
text, which names its own row id as any mission should. So the dispatcher creates the ambiguity it
then refuses on — the same shape as `argv[0]` exclusion never firing under `bash <script>`.

**Fix:** the backlog search must look only at backlog *sources* (`docs/tasks.yaml` and the
markdown backlog), never at `docs/handoff/`. When it still finds 2+, print the matching paths —
a refusal that names its evidence is debuggable in one read instead of five.

## Acceptance
Three tests, one per defect, driving the real functions:
- unknown kind → refused, message names the supplied value and the accepted set; absent kind →
  still the conservative default.
- mission present-but-untracked → the untracked message with the git remedy; mission absent from
  disk → the absent message.
- a row addressed by `external_id` resolves; a genuinely unknown id is refused with the searched
  keys named.

**Three negative controls, one per defect, each RUN and shown RED, then restored.** One mutation
is not a control for three independent defects.

## Off limits
- Arm selection, the route arbiter, quota logic, the review gate — untouched.
- Do not change the conservative default for an ABSENT `--kind`; this row makes a *wrong* kind
  loud, it does not relax the policy.
- Do not touch the architect prepass body — lanes `891a4f9b` and the queued
  `PLUGIN-PREPASS-FALLBACK-TRUTH-01` own it. Keep this diff to argument parsing, the mission
  presence check, and the premise resolver.

## Report
`docs/handoff/DISPATCH-REFUSALS-LIE-ABOUT-THEIR-CAUSE-01/report.md` — per defect: the fix, the
test, the control. End with `DELIVERABLE_COMPLETE`.
