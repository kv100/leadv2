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

## Test Results
All tests pass:
- ✅ Skeleton created when absent
- ✅ Existing .env untouched byte-for-byte (preserved + missing key comments appended)
- ✅ --check output shape correct (machine-parsable KEY=present|missing)
- ✅ --check returns 0 when all keys present
- ✅ Negative control verified (mutated installer would overwrite, real installer preserves)
- ✅ REAL installer preserves existing .env and appends only missing key comments

## Verification
- bash -n passes on modified script
- Test suite runs successfully (6 PASS, 0 FAIL)
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