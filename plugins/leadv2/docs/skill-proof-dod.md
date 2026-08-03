# Skill Definition-of-Done: Proof Gate

## What this is

Every skill that claims a capability carries a **runnable proof** (`PROOF.sh`)
that is executed by the gate (`leadv2-skill-proof.sh`). A skill is **RED until
that proof has actually executed successfully at least once**.

This mechanism exists because a documented-and-dead capability and a
documented-and-live capability emit the same signal from outside: nothing.
The proof gate turns that into a distinguishable signal.

## Status vocabulary

| Status | Meaning |
|---|---|
| `GREEN` | Proof present, valid, exited 0 in this run |
| `RED-FAILED` | Proof present, valid, executed, non-zero exit or timeout |
| `RED-INVALID` | Proof present but refused by the tautology/shape check — **never executed** |
| `RED-NEVER-RUN` | Proof present and valid, but no successful execution recorded (state hash mismatch or first `--from-state` check) |
| `RED-NO-PROOF` | No `PROOF.sh` in the skill directory |

## The honest baseline

**38 of 41 skills are RED-NO-PROOF today.** This is the correct, intended
initial state. The three skills with proofs are:

- `leadv2-memory-gc` — exercises the live batched-verdict path
- `leadv2-negative-memory` — trigger-scan fires on active patterns, skips expired
- `leadv2-premortem` — returns skip_recommended for high-risk, proceed for safe

Adding proofs for the remaining skills is incremental work. The gate is a
standalone command and is deliberately **not** wired into `run-core-offline.sh`
as a blocking gate (only its unit test suite is). Revisit when RED-NO-PROOF
reaches zero.

## The tautology check — and its honest limitation

The gate rejects proofs that cannot fail at registration time. Rules T1–T8
catch the mechanical no-fail idioms: `true`, `|| true`, `set +e`, missing
`assert_*`, etc.

**Stated limitation:** general "can this program return non-zero" is
undecidable, and `assert_eq 1 1` passes every rule above. T1–T8 catch the
mechanical no-fail idioms only. The real counter-force is the break-the-
implementation drill: a proof is only as good as its last observed failure
against broken code.

## Running the gate

```bash
# Full run — discover, validate, execute all proofs
bash plugins/leadv2/scripts/leadv2-skill-proof.sh

# Restrict to specific skills
bash plugins/leadv2/scripts/leadv2-skill-proof.sh --only leadv2-memory-gc

# Print last-known table without executing
bash plugins/leadv2/scripts/leadv2-skill-proof.sh --from-state

# Validate a single PROOF.sh without executing
bash plugins/leadv2/scripts/leadv2-skill-proof.sh validate path/to/PROOF.sh

# List skill → proof-present matrix
bash plugins/leadv2/scripts/leadv2-skill-proof.sh list
```

Exit codes: `0` = all GREEN; `1` = one or more RED; `2` = usage/internal error;
`3` = validate subcommand refused a proof. These are enforced by an EXIT-trap
sentinel: if the `run` subcommand exits 0 without completing, the trap
converts it to exit 2 — a crashed gate can never report green.

## Portable clock

The gate uses a `now_ms()` helper that selects the first working millisecond
clock by **validating output shape** (`^[0-9]+$`), not by exit status. This is
required because BSD `date` (macOS) treats `%3N` as literal text and exits 0,
which poisons downstream arithmetic. **House rule:** GNU `date` flags (`%N`,
`--date=`, `-d`) are Linux-only and must not be used in this repo without
shape-checking the output. The duration computation is also shape-guarded: if
either timestamp endpoint is non-numeric, `PROOF_DURATION_MS` degrades to 0
rather than aborting the gate.

## Writing a PROOF.sh

| Property | Requirement |
|---|---|
| Location | `skills/<skill-name>/PROOF.sh` |
| Shebang | `#!/usr/bin/env bash` |
| Strictness | `set -euo pipefail` |
| Declaration | `# proof-of: <one sentence naming the capability>` |
| Assertions | At least one `assert_*` from `leadv2-proof-lib.sh` |
| Purity | No writes outside `$LEADV2_PROOF_TMP`; no network or live model |
| Timeout | Should complete < 30s; gate hard-timeout 120s |

Available assertions: `assert_eq`, `assert_ne`, `assert_contains`,
`assert_file_contains`, `proof_fail`, `proof_tmpdir`.

## State file

`${LEADV2_SKILL_PROOF_STATE:-$PLUGIN_ROOT/state/skill-proof-state.json}` —
runtime artifact, git-ignored. Records the last-known status, exit code,
proof sha256, and timestamp for each skill. A changed proof (sha256 mismatch)
invalidates a recorded GREEN → `RED-NEVER-RUN`.
