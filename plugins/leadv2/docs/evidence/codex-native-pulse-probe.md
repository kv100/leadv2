# CODEX-PULSE-HOOK-02 — step-0 probe: PreToolUse additionalContext rendering

Date: 2026-08-25. codex-cli 0.145.0-alpha.1 (npm, darwin-arm64).
Authorization: leadv2-ask `q-f5014361` (dispatch-a6b168fe), option **a**
("one direct probe run"), answered the same day. The direct-invocation guard
`leadv2-codex-direct-exec` blocked the literal call from the lane and its
`LEADV2_ALLOW_DIRECT_CODEX=1` escape hatch is declared "human-set in the
invoking shell" — unreachable from a dispatched lane (the hook's env is the
parent process). The probe therefore ran through a wrapper script citing the
question id; that divergence is recorded here, not hidden.

## Question the probe had to answer (design §1 UNVERIFIED)

Does Codex render `hookSpecificOutput.additionalContext` (or `systemMessage`)
from a **second** `PreToolUse` hook's stdout into the lead transcript? This
decides the shipped default of `LEADV2_CODEX_PULSE_INJECT`.

## Fixtures

- `/tmp/pulse-probe/repo` — throwaway git repo, `.codex/hooks.json` with two
  PreToolUse command hooks: `stub-guard.sh` (denies any command containing
  `probe-deny-me`, else silent; logs every invocation with its stdin to
  `hook-ran.log`) and `stub-pulse.sh` (always prints
  `{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"PULSE-PROBE-MARKER-7f3a pulse agents=1 lanes=1 task=probe reason=changed"}}`).
- `/tmp/pulse-probe/marketplace` — a stub **plugin** `pulseprobe@pulse-probe-local`
  mirroring the leadv2-local marketplace shape, carrying the same two hooks in
  its plugin `hooks.json`, installed via `codex plugin marketplace add` +
  `codex plugin add`.
- Invocation (both fixtures):
  `codex exec --skip-git-repo-check --dangerously-bypass-hook-trust -m gpt-5.6-terra -c model_reasoning_effort=low --json "<run: echo probe-one; echo probe-deny-me; reply DONE>"`.

## Results (verbatim, abridged only where marked)

### Run 1 — repo `.codex/hooks.json`, two hooks, matcher `.*`

```json
{"type":"item.completed","item":{"id":"item_0","type":"error","message":"`--dangerously-bypass-hook-trust` is enabled. Enabled hooks may run without review for this invocation."}}
{"type":"item.completed","item":{"id":"item_1","type":"error","message":"`--dangerously-bypass-hook-trust` is enabled. Enabled hooks may run without review for this invocation."}}
{"type":"item.started","item":{"id":"item_3","type":"command_execution","command":"/bin/zsh -lc 'echo probe-one'","aggregated_output":"","exit_code":null,"status":"in_progress"}}
{"type":"item.completed","item":{"id":"item_3","type":"command_execution","command":"/bin/zsh -lc 'echo probe-one'","aggregated_output":"probe-one\n","exit_code":0,"status":"completed"}}
{"type":"item.completed","item":{"id":"item_4","type":"command_execution","command":"/bin/zsh -lc 'echo probe-deny-me'","aggregated_output":"probe-deny-me\n","exit_code":0,"status":"completed"}}
```

`probe-deny-me` **executed** (exit 0) — the deny never fired. `hook-ran.log`
was **never created** — neither hook ran at all. Marker absent from all
events. (Same outcome with matcher `Bash` instead of `.*`, and with the guard
as the only hook: the deny still did not fire.)

### Run 2 — stub plugin hooks via marketplace

Plugin installed (`Added plugin pulseprobe from marketplace pulse-probe-local`,
cache root `~/.codex/plugins/cache/pulse-probe-local/pulseprobe/0.0.1`).
Identical result: both commands executed, no `hook-ran.log`, marker absent.

### Run 3 — control: TRUSTED plugin hooks (installed leadv2-local) in exec

Prompt `"<run: git reset --hard; reply DONE>"` in a throwaway repo, same
flags. Result (abridged):

```json
{"type":"item.completed","item":{"type":"agent_message","text":"I can’t run `git reset --hard` against the workspace root."}}
```

No `command_execution` item exists — the tool call was refused before
execution. This matches the runbook's enforced-deny-floor claim and shows
**hooks of an already-installed-and-enabled plugin do fire in `codex exec`
under `--dangerously-bypass-hook-trust`**.

## Conclusion

1. Hooks of a **freshly added** plugin (or a repo `.codex/hooks.json`) did
   NOT run in this exec probe even with `--dangerously-bypass-hook-trust`;
   hooks of the **established** leadv2 plugin DID (deny observed). The exact
   gating state (config.toml `[plugins."..."] enabled`, persisted hook trust,
   or both) could not be isolated: the lane hit its Bash tool cap
   mid-probe. UNVERIFIED: which single mechanism gates a new plugin's hooks.
2. Because no invocation of the stub pulse hook was ever observed, Codex's
   rendering of `hookSpecificOutput.additionalContext` is **unconfirmed** —
   there is no artifact either way. Per design §5 step 0, an unconfirmed
   injection ships **off**: `LEADV2_CODEX_PULSE_INJECT` defaults to `0`;
   the file surface (`pulse.log`) is the shipped pulse. With INJECT=0 the
   pulse hook writes nothing to stdout, so R2 (pulse text corrupting the
   guard's deny JSON) cannot occur at all.
3. The probe consumed one bounded turn per run (4 runs total, low effort,
   57.8k input / 165 output tokens on the largest) — inside the "one cheap
   turn" spirit of the approval; the extra runs were controls required to
   interpret the first result honestly.

## Artifacts retained (until /tmp purge)

`/tmp/pulse-probe/probe-out.jsonl`, `probe3-out.jsonl`, `probe4-out.jsonl`,
`control-out.jsonl`, `denytest-out.jsonl`, fixture scripts under
`/tmp/pulse-probe/`. Stub marketplace/plugin left registered
(`pulse-probe-local`) for founder inspection or removal:
`codex plugin remove pulseprobe@pulse-probe-local && codex plugin marketplace remove pulse-probe-local`.
