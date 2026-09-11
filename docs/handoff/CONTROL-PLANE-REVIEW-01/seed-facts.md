# CONTROL-PLANE-REVIEW-01 — seed facts (measured 2026-09-11, do not re-derive)

Every fact below was measured this session. Cite it, do not re-measure it. If you
believe one is wrong, say so explicitly and show the command that refutes it —
that is a finding in itself.

## S1. Fable sits in TWO quota buckets at once (founder correction, then proven)

Founder, 2026-09-11: "fable тот же бакет что и все другие модели антропик + у него
свой бакет."

Proven from the live payload of
`python3 plugins/leadv2/scripts/leadv2-quota-read.py anthropic` — each Anthropic
account's `limits` array carries BOTH:

    {"kind": "weekly_all",    "percent": 67, "is_active": true,  "scope": null}
    {"kind": "weekly_scoped", "percent": 16, "is_active": false,
     "scope": {"model": {"id": null, "display_name": "Fable"}}}

So spending fable consumes the SHARED weekly ceiling as well as its own
model-scoped one.

**What this refutes.** `plugins/leadv2/config/leadv2-routing.yaml:263-277`
(commit `9963f733`, FABLE-RESTORE-01) reads:

    # Own bucket per model-capability.yaml (cost_class: fable-scoped-weekly, NOT
    # proven same-bucket as opus) -- cost set below opus (9) to reflect that
    # separate quota ceiling, not a capability judgment

`NOT proven same-bucket as opus` is now refuted by the payload above. `cost: 8`
therefore encodes a premise that the live data contradicts.

## S2. The `cost` column mixes two incommensurable meanings

- `glm` `cost: 0.33` carries a comment deriving it from Z.AI's published credit
  multipliers — i.e. a real per-token price ratio.
- `fable` `cost: 8` is a quota-bucket preference nudge ("take fable before opus"),
  explicitly "not a capability judgment".

One scalar, two meanings, and `cheapest_capable` sorts on it as if it were one.
The lead misread the second as the first earlier today and gave the founder a
wrong cost comparison. Treat "is this column sound?" as in scope.

## S3. The arbiter returns a single-arm chain

    bash plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh reviewer \
      '{"work_kind":"audit","size":"heavy","subtype":"critic","task":"..."}'
    -> arm=codex kind=audit model=gpt-5.6-terra tier=standard effort=high
       reason=cheapest_capable chain=codex

`chain=codex` has no fallback entry. Also `cheapest_capable` picked terra
(cost 4) over sol (cost 7) — correct by the rule, but the founder's standing
instruction for this work was "пускай делают максимально умные модели", so the
rule and the operator's intent diverge with no way for the caller to express
"spend more for a better answer". Whether that is a defect or a missing knob is
yours to judge.

## S4. The balancer's pick and its printed score

    bash plugins/leadv2/scripts/leadv2-claude-profile-select.sh
    -> WARN: default_token_expired identity=max/kostiantyn.vlasenko@mythical.games
       -- inherited fallback will refuse; probe-qualified profile required
    -> profile=personal config_dir=~/.claude score=67 source=live
       reason=binding_window candidates=2
       cred=keychain:Claude Code-credentials-eb6c5b97
       identity=max/vkk1008k@gmail.com binding=seven_day:67
       windows=personal:seven_day=67|work:seven_day=56 demoted=work

It chose the profile with the HIGHER consumed percentage (67 vs 56). That may be
right — `usable_now` is 1.62 for personal vs 0.397 for work, because personal's
window resets in 20h and work's in 113h. But `score=67` is a consumed-percentage
printed as a score, so the direction of the number is not legible from the line.
Decide: is the ranking correct, and is the line honest about what it ranked?

## S5. The bound account is the one that cannot be read

Same payload: `"active_account": "max_20x"`,
`"account_resolution": "session_credential"`, and the `default` entry returns
`"http": 429` with every window `null` and
`"error": "429 rate_limited (reported as unknown, NEVER 0)"`.

The refusal-to-fake-a-zero is correct and must not be "fixed" into a 0. The
question is different: the account the session is actually bound to is the one
whose quota is unreadable, while the balancer ranks the two readable ones.

Top-level `"binding_window": null` while every account reports
`"binding_window": "seven_day"`.

`"fetched_at": "2026-09-11T01:01:04Z"`, read at ~01:35Z — a ~34-minute-old cache
served without the caller asking for cached data.

## S6. The registry is blind to live lanes

Every `~/.claude/leadv2-state/*/active.yaml` reported 0 lanes while a real codex
lane (`task-mtw9hku9-9rbxiy`) had been alive 25 minutes. A concurrent session
recorded the same thing independently at 01:17Z. Write-set collision protection
therefore is not protecting anything right now.

## Measurement traps that already produced wrong numbers today — do not repeat

- Counting watchdogs as workers: `codex-task.sh __deathwatch` and
  `__quota-watch` are siblings of the one real worker. 1 lane looked like 3.
- A `ps ax | grep <pattern>` matches its own command line. Write patterns to a
  file and use `grep -f`, and exclude `zsh -c source`.
- BSD `find -newermt '-180 minutes'` silently returned nothing on macOS. Use
  `ls -t` or an absolute timestamp.
- Transcript timestamps are UTC; the machine is UTC+3. A "3-hour gap" was a
  timezone.
