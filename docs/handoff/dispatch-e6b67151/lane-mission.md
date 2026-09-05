GLM-53-FLASH-ARM-01 (plugin side; founder order 2026-08-26). GLM-5.3 Flash released. On our legacy coding plan its prompts weigh 0.4x (vs 1x for glm-5.3) and max-context calls 1.2x (vs 3x) => ~2.5x quota efficiency. Wire it into the dispatch capability matrix as a CHEAP arm option so the route arbiter can pick it for light/mechanical work.

Scope:
1. glm-coder.sh: support model override (env, e.g. GLM_MODEL / existing profile mechanism — find how the model id is currently pinned; do not invent a second mechanism if one exists). Default stays the current model; glm-5.3-flash selectable per-dispatch.
2. Capability matrix / routing config (.claude/leadv2 config yamls in the plugin: routing.yaml / main-model.yaml / wherever arms+models are declared — find the real reader first): add glm-5.3-flash as an arm/tier with capability notes: good for mechanical edits, small fixes, doc rounds, test authoring; NOT for protected/safety/publish (existing triple guard must keep matching it as glm-family — verify the guard patterns match 'glm-5.3-flash' string and add a test if they key on exact 'glm').
3. Route arbiter: teach headroom/quota logic that flash consumption weighs 0.4x if the arbiter models quota weights; if it does not, add only a static preference note (do not build a quota model in this round).
4. Tests: extend the dispatch/arbiter suite — (a) flash arm selectable and produces correct model id in the spawn argv; (b) protected-path task NEVER routes to glm-5.3-flash (negative control: mutate the guard, show red, revert per E2E-KILLRATE-01 discipline).
5. Doc: one row in the plugin's model-routing doc describing when flash is chosen.

Constraints: base = current checkout branch (t14-worker-mcp lineage) or main — whichever the dispatcher gives you; bash -n every touched script; no changes to safety/publish routing semantics; commit on the lane branch.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-e6b67151" "<question>" \
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