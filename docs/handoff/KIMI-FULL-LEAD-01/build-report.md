# KIMI-FULL-LEAD-01 — build report (narrow finisher)

Repo: `~/Projects/leadv2` (the plugin single-source tree — NOT persona-engine).
Scope authority: the architect prepass scoped design. Item 1 = verify-only (no
edits). Item 2 = data file only (already on disk, no wiring). Item 3 = the
resolver change + tests + sweep + live demo. **No commit, no push, no branch.**

## Item 1 — `--provider kimi` launch-site wiring (verified, no edits)

The prepass verdict held: item 1 needed no code change. Confirmed on disk:

- `leadv2-fanout.sh:163,175,185-186` — usage string + validation case list `kimi`;
  invalid values still exit 1.
- `leadv2-fanout.sh:1093,1100,1200,1364` — every child-launch path exports
  `LEADV2_SESSION_PROVIDER="${provider}"` (tmux / windows / headless / lane).
- `leadv2-session-runner.sh:110-116` — `kimi)` branch `exec`s
  `leadv2-kimi-session-runner.sh`, hard-errors if missing/not-executable.
- `leadv2-kimi-session-runner.sh:62` —
  `export KIMI_STALL_S="${KIMI_STALL_S:-900}"` at the lead launch site (rationale
  comment :21-23: kimi-coder.sh's 300 default would kill a thinking lead). This
  is a lead-runner export, NOT a new global default in `kimi-coder.sh` — exactly
  the mission constraint (KIMI-STALL-TUNE-01 is out of scope).
- `leadv2-fanout-lane-launcher.sh:49,66,129,336,434` — generic `--provider`
  pass-through (registry receipt + `LEADV2_SESSION_PROVIDER`); no kimi-literal,
  zero half-done edit.

`bash -n` clean on `leadv2-fanout.sh`, `leadv2-fanout-lane-launcher.sh`,
`leadv2-kimi-session-runner.sh`. **Conclusion: item 1 COMPLETE, no edit.**

## Item 2 — capability data file (no wiring)

`plugins/leadv2/config/model-capability.yaml` present (untracked). Wiring it into
resolver scoring is an explicit non-goal; left untouched.

## Item 3 — UI-TO-KIMI-01 resolver change (the real scope)

### Files changed (LANE_WRITES, both)

- `plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py`
- `plugins/leadv2/scripts/tests/test-kimi-spill-resolve.py`

### What changed

`resolve_glm_policy()` gained one optional defaulted parameter
`kimi_bin: str = None`. After the strict-precedence `rules` loop, a single
**lazy** override block fires only when `rule == "ui_design_judgment"` AND a
kimi bin was supplied:

| `kimi_review_available(kimi_bin)` | arm | reason |
|---|---|---|
| `True` (probe rc 0) | `kimi` | `sonnet_exception:kimi` |
| `False` (probe rc 77) | `sonnet` | `sonnet_exception:kimi_probe_down` |
| `None` (bin missing / rc 75 / timeout / exception) | `sonnet` | `sonnet_exception:kimi_probe_unknown` |

Design adherence:

- **Laziness** — the probe (a 15s subprocess) runs ONLY after the UI rule matched
  and only if `kimi_bin` is truthy. A caller that never passes `kimi_bin` gets
  byte-identical today behaviour (`arm=sonnet`, `reason=sonnet_exception`, no
  subprocess). Locked by a raising-stub test (`test_no_probe_when_not_ui` and
  `test_no_kimi_bin_is_byte_identical_to_today`).
- **Fail CLOSED on unknown** — `None` collapses to `sonnet` here, deliberately
  different from `resolve_review_pool`'s fail-open-to-UNKNOWN: stranding a UI
  task on an unreachable arm is a stall, not a downgrade. Covered by a separate
  test case from `False`.
- **`rule` stays `ui_design_judgment`** in every branch (the yaml
  `sonnet_exceptions` id + single-source-of-truth gate). Only `arm`+`reason`
  vary → downstream consumers keying on `rule` (router.sh:595-609 reason
  passthrough; bandit `glm_default` special-case) are unaffected.
- **Precedence untouched** — `safety_gate_publish_payments` and
  `integration_critical_4subsystems` sit ABOVE the UI row and `break` first, so a
  safety-touched UI task still resolves `sonnet` (rule `safety_gate...`). The
  override is guarded by `rule == "ui_design_judgment"`, so it never fires on a
  higher-precedence match.
- **CLI surface** — `_main` reuses the already-parsed `--kimi-bin` (the
  review-pool gate's flag) for the new parameter. No second flag added.
- **No other exception row touched** — `safety_gate_publish_payments`,
  `integration_critical_4subsystems`, `glm_failed_twice`,
  `glm_lock_busy_no_second_channel`, `codex_fitting_mission_kind`,
  `opus_only_mission_kinds` are byte-identical.

### §6 downstream arm-name pre-check (gate before shipping)

Confirmed `kimi` is an arm the build-phase command builder can dispatch:
`leadv2-dispatch-code.sh:627` (`kimi)` case in the status/command builder) and
`:1401` (`kimi)` spawn dispatch). `leadv2-router.sh` has no `kimi` branch — but
router.sh never passes `kimi_bin` (so the override is skipped → byte-identical
sonnet, the resolver never hands it a `kimi` arm). No caller-flag gating needed;
no `command_template` fix shipped (out of scope).

## Side-by-side resolver output (UI-TO-KIMI-01)

Same UI-design-judgment task, two probe states — shown side by side:

```
signals = {"ui_design_judgment": true}, job=build, base_arm=glm

  kimi channel REACHABLE          |   kimi channel UNREACHABLE
  (probe rc 0)                    |   (probe rc 77)
  ---------------------------     |   ---------------------------
  arm=kimi                        |   arm=sonnet
  rule=ui_design_judgment         |   rule=ui_design_judgment
  reason=sonnet_exception:kimi    |   reason=sonnet_exception:kimi_probe_down
  tier=                           |   tier=
  codex_quota_blocked=0           |   codex_quota_blocked=0
```

Precedence proof (safety beats UI even when kimi is reachable):
```
signals = {"protected_path": true, "ui_design_judgment": true}, kimi reachable
  arm=sonnet
  rule=safety_gate_publish_payments
  reason=sonnet_exception
```

## Live routing demo (Light-class, provider=kimi)

The session router's M2 guard skips the kimi launch probe when glm is eligible
and within quota, so to demonstrate the kimi path the glm quota gate was forced
to refuse (simulating glm-over-quota) — this lets the kimi probe run. The kimi
channel is genuinely reachable here (`kimi-coder.sh probe` rc 0):

```
$ LEADV2_GLM_QUOTA_GATE=/tmp/pe-demo-glm-gate-over.sh \
    bash scripts/leadv2-session-route.sh --provider kimi --class Light
[leadv2-session-route] provider=kimi model=moonshotai/kimi-k3-free effort=low \
    reason=explicit provider override: kimi displaced=none
provider=kimi
model=moonshotai/kimi-k3-free
reason=explicit provider override: kimi
kimi_eligible=true
```

`provider=kimi` confirmed for a Light-class request.

## Full test sweep — six suites, all green

| # | suite | dir | result |
|---|---|---|---|
| 1 | `test-kimi-spill-resolve.py` | `scripts/tests/` | Ran 11 tests — OK |
| 2 | `test-kimi-session-route.sh` | `scripts/tests/` | PASS=11 FAIL=0 |
| 3 | `test-review-arm-pool.sh` | `tests/` | 21 passed, 0 failed |
| 4 | `test-codex-quota-gate.sh` | `scripts/tests/` | 5 passed, 0 failed |
| 5 | `test-smart-routing-v2-t6.py` | `scripts/tests/` | Ran 15 tests — OK |
| 6 | `test-t-core-filter-arms-parity.py` | `scripts/tests/` | Ran 16 tests — OK |

`python3 -m py_compile plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py` → OK.
Note suite 3 lives under `plugins/leadv2/tests/`, the rest under
`plugins/leadv2/scripts/tests/` (two directories).

New test cases added to suite 1 (extend, not replace): ui+kimi-available→kimi;
ui+kimi-unavailable(`False`)→sonnet/kimi_probe_down; ui+kimi-unknown(`None`)→
sonnet/kimi_probe_unknown; safety-overrides-ui→sonnet/rule=safety; no-probe-when-
not-UI (raising stub); no-`kimi_bin`→byte-identical-today (raising stub).

## Non-goals honoured

No commit / push / branch. Item 1 no edits. Item 2 data-only, no resolver wiring.
No change to any other exception row, `resolve_review_pool`, or
`kimi_review_available` internals. No new global `KIMI_STALL_S` default in
`kimi-coder.sh`. No `command_template` builder fix. No `.claude/scripts/` copies
in persona-engine — the plugin repo is the single source.

DELIVERABLE_COMPLETE
