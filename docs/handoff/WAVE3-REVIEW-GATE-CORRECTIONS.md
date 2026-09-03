# Wave 3 — corrections that must be enforced at REVIEW, not in the mission

Two lanes are running with a mission snapshot taken before these corrections existed. A brief edit
never reaches a running lane (see backlog row `BRIEF-EDITS-NEVER-REACH-A-RUNNING-LANE-01`), and
both lanes are actively producing, so restarting them would destroy live work to deliver a narrow
note. The corrections are therefore enforced at review. **A lane below does not close until its row
here is satisfied.**

## CLASSIFIER-CALLS-SAFETY-DOCTRINE-SIMPLE-01 (lane `dispatch-ac7b08fc`)

Running against the pre-census brief. Required at review:

1. **The declared-paths matcher arm must NOT ship.** The architect's own census retracted it:
   `Reads:` / `Writes:` / `Touches:` lines appear in **0 of 324** lane missions, so the arm cannot
   fire. Ship the id + title arm alone. Do not accept the path arm "for later" — a branch that
   cannot fire in prod is not groundwork, it is a false sense of coverage, and this repo bans a
   control that changes nothing.
2. If paths are wanted eventually, they come from the dispatcher's own `_effective_protected`
   resolution, as a separate task — not from mission prose.
3. The census caveat stays in the brief verbatim: **5.2% is an upper bound, not a fleet number** —
   the corpus is leadv2's own missions, which discuss routing vocabulary more than a product repo
   would. We will quote this figure to other tenants; without the caveat it overstates the problem.

## CLAUDE-PROFILE-DEFAULT-TOKEN-EXPIRED-01 (lane `dispatch-ca26c56e`)

Running against a mission that carries the `/login` coupling note but not this refinement.
Required at review:

1. The remedy string interpolates the config dir from the warn itself and must be impossible to
   copy-paste as a bare `claude /login` — that bare form is what collapses two slots into one
   account when the dir is wrong.
2. **The remedy line must NOT print an email address or a subscription type next to the command.**
   The directory: yes. The identity: no. Otherwise someone pastes the remedy into a chat and the
   account identity travels with it. Credential values were never in scope and stay out.
3. The causal link between the false warn and the two collapse episodes stays **PLAUSIBLE, not
   proven** — in comments, in the commit message, and in any doc the lane writes. Twice today we
   won by refusing to promote a hypothesis to a fact; do not lose that here.

## Applies to every Wave 3 lane

- Negative control goes INSIDE a function body; proof is the `baseline_rc` / `mutated_rc` pair plus
  the literal red suite line. `diff_hash` may be cited again — that restriction was lifted after
  the fix was found already in main with zero blast radius.
- `git diff --stat main..HEAD` before merge. If the lane deletes files because it branched early,
  restore them from `main`.
- Green on macOS and in a linux container, both exit codes pasted.
