# FP-03 freepool installer — env skeleton, ownership table, health check

## Summary
Implemented FP-03: Enhanced `freepool-install.sh` to create `~/.fcc/.env` skeleton, print FCC admin UI ownership table, and verify proxy health.

## Changes Made

### Modified Files
1. `plugins/leadv2/scripts/freepool-install.sh` - Main implementation
2. `plugins/leadv2/scripts/tests/test-freepool-install.sh` - New test file

### Key Features Implemented

1. **~/.fcc/.env skeleton creation**:
   - Creates directory and file if absent with commented placeholders for all required keys
   - Idempotent: preserves existing content and only appends missing key comments
   - Never overwrites existing .env file values
   - Includes all keys: FCC_CONFIG_SCHEMA, DEEPSEEK_API_KEY, GEMINI_API_KEY, GROQ_API_KEY, MISTRAL_API_KEY, NVIDIA_NIM_API_KEY, OPENROUTER_API_KEY, PROXY_AUTH_ENABLED, PORT

2. **FCC admin UI ownership table**:
   - Printed during installation as required by FP-03
   - Documents operator vs system responsibilities for each setting
   - Clarifies that provider API keys are operator responsibility (once), everything else is system defaults/yaml

3. **Health verification**:
   - Checks `${FREEPOOL_PROXY_URL:-http://127.0.0.1:8317}/health` with 5s curl timeout
   - If down and `FREEPOOL_AUTOSTART!=0`, attempts one `freepool-proxy.sh start` + re-check
   - Exits non-zero with clear reason if still down

4. **--check mode**:
   - Report-only, machine-parsable output
   - Outputs KEY=present|missing lines (one per key)
   - No writes when in check mode
   - Returns 0 if all keys present, non-zero if any missing

## Fix-round test results

The test suite is hermetic. It places a fake `curl` before `PATH`, records
every health probe, and supplies an explicit up/down response sequence. Every
installer invocation also uses `env -u FREEPOOL_PROXY_URL`; it cannot depend
on a listener at `127.0.0.1:8317` (or on any proxy environment variable).
The fixture supplies an existing fake checkout and `git`, so it makes neither
network nor GitHub calls.

- Skeleton creation and partial `.env` preservation use one fake health-up probe.
- The health-down / `FREEPOOL_AUTOSTART=0` case proves the installer exits non-zero.
- The negative control copies `freepool-install.sh` to a temporary path and
  mutates the real `create_fcc_env_skeleton` existing-file guard from
  `[[ ! -f "${FCC_ENV_FILE}" ]]` to `true`; the untouched-existing-`.env` run
  is killed (overwrites its custom value).
- The autostart branch receives `down,up`, and asserts exactly one start-script
  invocation and exactly two health probes (initial check plus one re-check).

Raw suite output (`env -u FREEPOOL_PROXY_URL bash plugins/leadv2/scripts/tests/test-freepool-install.sh`):

```text
PASS: case1: hermetic health-up install creates all skeleton comments
PASS: case2: existing .env bytes preserved; missing key appended as comment
PASS: case3: --check reports missing keys without installation
PASS: case4: --check returns 0 when all keys are present
PASS: case5: NEGATIVE CONTROL KILLED by mutation in real installer function
PASS: case6: real installer preserves untouched existing .env
PASS: case7: health-down with autostart disabled exits non-zero
PASS: case8: autostart attempts once and health re-checks once

================================================
  freepool install test: PASS=8 FAIL=0
================================================
```

## Verification
- bash -n passes on modified script
- Test suite runs successfully without a live proxy (8 PASS, 0 FAIL)
- Manual verification shows proper behavior in various scenarios:
  - Clean environment: creates .env with commented placeholders
  - Existing partial .env: preserves values, adds missing key comments
  - Existing complete .env: preserves completely, no additions needed
  - --check mode: proper machine-readable output

## Next Steps
Operator must:
1. Fill in provider API keys in `~/.fcc/.env` (uncomment and add values)
2. Optionally configure Fallback Models in FCC admin UI (127.0.0.1:8317/admin)
3. Start proxy with `freepool-proxy.sh start`

The installer now satisfies all FP-03 requirements and is ready for use.
