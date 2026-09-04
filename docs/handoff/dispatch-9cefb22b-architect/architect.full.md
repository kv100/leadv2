# CLAUDE-MULTIPROFILE-QUOTA-02 — architect prepass

Scope: portable, opt-in Anthropic multi-profile selection for Claude lanes in this plugin.
No account name, email, path, token, or machine default enters the repo.

## 1. What already exists (reuse, do not rebuild)

- `plugins/leadv2/scripts/leadv2-quota-read.py::read_anthropic()` already enumerates **every**
  `Claude Code-credentials*` keychain service and returns one entry per account with
  `account_label`, `five_hour_pct`, `seven_day_pct`, `status`, plus `active_account`
  (`_keychain_services()` L307, `read_anthropic()` L421, `resolve_active_account()` L388).
  Per-profile quota reading is therefore already independent and already label-only.
- `resolve_active_account()` already honours `LEADV2_ANTHROPIC_ACTIVE_SERVICE` /
  `CLAUDE_CODE_CREDENTIALS_SERVICE` — a per-profile scoping hook already exists.
- `leadv2-provider-quota-gate.sh` is the established fail-open + bounded-subprocess pattern
  (integer clamp 1..60, `FAIL-OPEN:` on every telemetry fault). The selector copies it.
- `plugins/leadv2/scripts/claude-subsession.sh` is the **single choke point** for every Claude
  child: `claude "${CLAUDE_ARGS[@]}"` at L600 (wait path) and `setsid_wrapper claude ...` at
  L1265 (background path). Both are in one file, so no dispatch script needs touching.

UNVERIFIED: how Claude Code derives a keychain service name from a given `CLAUDE_CONFIG_DIR`.
I have no probe artifact for that mapping. **The design therefore never derives it** — the
registry carries the credential source explicitly (§2), so no guess is encoded.

## 2. Registry — user-level, out of the repo

Path: `${LEADV2_CLAUDE_PROFILES_FILE:-$HOME/.claude/state/leadv2/claude-profiles.tsv}`
(same state root the plugin already uses for `quota-cache`). **Never** committed; the repo ships
only `docs/` prose describing the format.

Format — TSV, no YAML dependency (matches the existing "PyYAML is not a runtime dependency of
this credential reader" constraint at `leadv2-quota-read.py:346`):

```
# label<TAB>config_dir<TAB>credential_source(optional)
alpha	/abs/path/to/config/dir	keychain:Claude Code-credentials
beta	/abs/path/to/other/dir	file:/abs/path/to/other/dir/.credentials.json
```

| Field | Rule |
|---|---|
| `label` | `^[a-z0-9][a-z0-9_-]{0,31}$`. Rejected otherwise. This is the ONLY field ever journalled. An `@` or `.` in a label is a hard reject (blocks emails). |
| `config_dir` | Absolute, existing directory. Non-absolute / missing → line skipped with one stderr warning. |
| `credential_source` | Optional. `keychain:<service>` or `file:<abs path>`. Absent → default to `file:<config_dir>/.credentials.json`. |

Blank lines and `#` comments ignored. `< 2` valid lines ⇒ multi-profile is inert.

## 3. Selection algorithm — `leadv2-claude-profile-select.sh`

Opt-in gate first: `LEADV2_CLAUDE_MULTIPROFILE` unset or `!= 1` ⇒ print nothing, exit 0.

1. Parse registry. `<2` valid entries ⇒ print `profile=- reason=single_profile` on stdout,
   exit 0 (caller leaves `CLAUDE_CONFIG_DIR` untouched — **fallback preserved**).
2. For each entry, **independently** probe availability by invoking the probe
   (`${LEADV2_CLAUDE_PROFILE_PROBE:-<scripts>/leadv2-quota-read.py} anthropic --no-cache`)
   with `LEADV2_ANTHROPIC_ACTIVE_SERVICE=<service>` when the source is `keychain:`, and with a
   per-profile cache dir `${LEADV2_QUOTA_CACHE_DIR}/profile-<label>`. One profile's failure never
   affects another (per-profile try/except, mirrors the bucket independence in `quota-live`).
   Whole loop bounded by `LEADV2_CLAUDE_PROFILE_TIMEOUT` (default 12s, integer-validated,
   clamped 1..60 — copy the clamp block from `leadv2-provider-quota-gate.sh:31-38`).
3. Score = `max(five_hour_pct, seven_day_pct)` (worst-window utilisation). `status != ok`
   or unparseable ⇒ score `101` (`source=unknown`).
4. Pick the **lowest** score; ties broken by registry order ⇒ fully deterministic.
   All scores `101` ⇒ pick the first valid entry, `reason=all_unknown`.
5. Emit exactly one stdout line:
   `profile=<label> config_dir=<path> score=<n> source=live|unknown reason=<reason>`
   `config_dir` is on **stdout only**, consumed by the caller; it is never journalled,
   never logged, never sent to handoff.

Failure of the selector itself (crash, timeout, malformed file) ⇒ non-zero-safe: caller treats
any absent/unparseable stdout as `single_profile` and proceeds unchanged. **Fail-open, always.**

## 4. Integration — `claude-subsession.sh` only

One helper `leadv2_select_claude_profile()` invoked once, before the `CLAUDE_ARGS` build, so both
launch sites inherit it:

- Run selector with a bounded subprocess (existing pattern).
- If a `config_dir=` was returned and the dir is readable ⇒ `export CLAUDE_CONFIG_DIR="$dir"` for
  the child only. Otherwise leave the inherited value alone.
- Emit exactly ONE stderr line, label-only:
  `[claude-profile] selected=<label> score=<n> source=<live|unknown> candidates=<n>`
  (or `[claude-profile] single-profile fallback`).
- Append the same label-only line, ISO-8601 prefixed, to
  `docs/handoff/<TASK_ID>/claude-profile.log`. No path, no service name, no token, no email.

## 5. `leadv2-quota-read.py` change (additive)

Add `--credential-file <path>` so a profile whose source is `file:` can be read without keychain.
When passed, `read_anthropic()` reads that JSON blob instead of enumerating the keychain and
returns a single-entry `accounts` list. Default behaviour (no flag) is byte-identical to today —
backward compatible, no caller updates required.

## 6. Tests — hermetic, no network, no keychain

New `plugins/leadv2/scripts/tests/test-claude-profile-select.sh`, registered in
`run-core-offline.sh`. Probe stubbed via `LEADV2_CLAUDE_PROFILE_PROBE` (a fixture script echoing
canned JSON), registry via `LEADV2_CLAUDE_PROFILES_FILE`, all under `mktemp -d`.

| T | Case | Expect |
|---|---|---|
| T1 | opt-in unset | no stdout, exit 0, `CLAUDE_CONFIG_DIR` unchanged |
| T2 | registry missing | `reason=single_profile` |
| T3 | 1 valid entry | `reason=single_profile` (fallback preserved) |
| T4 | 2 entries, 20% vs 80% | picks the 20% label |
| T5 | one `status=unknown`, one ok | picks the ok one, `source=live` |
| T6 | both unknown | first registry entry, `reason=all_unknown` |
| T7 | malformed line + label with `@` | both skipped, one warning each |
| T8 | probe hangs | timeout, `single_profile`, exit 0 under 15s |
| T9 | leak scan | stdout+stderr+handoff log grepped for `sk-ant`, `@`, `/` — handoff log and stderr must contain none |
| T10 | determinism | identical scores ⇒ same pick over 5 runs |

Plugin cache validation: run `plugins/leadv2/scripts/leadv2-plugin-sync.sh` and
`leadv2-validate-skills.sh` after the change so the new scripts land in the plugin cache; the two
new scripts must be `chmod +x` and appear in the sync manifest.

## 7. Risks

| Risk | Mitigation |
|---|---|
| Keychain access prompts / slow probe multiplies per profile | opt-in default off; bounded 12s total; per-profile cache dir with existing TTL |
| A non-default `CLAUDE_CONFIG_DIR` lacks settings/hooks the lane needs | selector verifies the dir is readable; operator owns registry content; documented in `docs/` |
| Label leaking an identity (email as label) | label regex rejects `@`/`.`; only the label ever leaves the process |
| Two concurrent lanes writing the same profile cache | cache dir keyed per label + existing atomic `cache_put` write |
| `config_dir` accidentally journalled | it exists only on the selector's stdout; the stderr line and handoff log are constructed from `label`/`score`/`source` only — asserted by T9 |
| Selector bug bricks all dispatch | every fault path is fail-open to single-profile; T8 pins it |
| Env drift `LEAD_V2_*` vs `LEADV2_*` | all four new vars are `LEADV2_*`; no existing usages of these names (grep is clean) |

## 8. Non-goals

- No changes to GLM/Codex buckets, routing weights, ceilings, or `leadv2-routing.yaml`.
- No automatic account switching, login, or credential writing — read-only selection.
- No changes to `leadv2-dispatch-code.sh`, `leadv2-fanout.sh`, or any review path.
- No keychain-service derivation from a config dir (unverified — registry states it explicitly).
- No application/product code. No new runtime dependency (no PyYAML, no jq).
- Linux/CI keychain support beyond the `file:` source.

## 9. Acceptance

```
acceptance:
  surface: log_line
  observable: >
    With two profiles registered and LEADV2_CLAUDE_MULTIPROFILE=1, the operator sees a single
    line in the lane's stderr reading "[claude-profile] selected=<label> score=<n> source=live
    candidates=2", naming the profile with the lower usage, and the same label-only line appears
    in docs/handoff/<task-id>/claude-profile.log — with no path, email, service name, or token
    anywhere on either line. With the flag unset, no such line appears and the lane runs exactly
    as before.
  authored_at: 2026-08-25T00:05:00Z
```

LANE_WRITES: plugins/leadv2/scripts/leadv2-claude-profile-select.sh, plugins/leadv2/scripts/lib/leadv2-claude-profile-pick.py, plugins/leadv2/scripts/claude-subsession.sh, plugins/leadv2/scripts/leadv2-quota-read.py, plugins/leadv2/scripts/tests/test-claude-profile-select.sh, plugins/leadv2/scripts/tests/run-core-offline.sh, docs/model-routing.md

DELIVERABLE_COMPLETE
