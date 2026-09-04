## Hack-detection review — dispatch-FP-03-review-hackdetect

**Mission:** Scan build.diff for TODO/FIXME band-aids, magic numbers, broad except, hardcoded creds/secrets, silent fallbacks.

**Findings:**

FINDING: severity=Medium file=plugins/leadv2/scripts/freepool-install.sh line=195 dimension=hack desc=Magic number 5 (curl timeout) lacks rationale or configurability; should be FREEPOOL_HEALTH_CHECK_TIMEOUT or documented
FINDING: severity=Medium file=plugins/leadv2/scripts/freepool-install.sh line=220 dimension=hack desc=Magic number 2 (sleep delay) before proxy liveness check; arbitrary value could cause race condition if startup exceeds 2s

**Excluded patterns (not applicable):**
- No TODO/FIXME markers found
- No hardcoded API credentials or secrets
- No broad-except error handlers (case `*)` properly logs and exits)
- Silent fallbacks with `2>/dev/null` (grep, kill -0) are standard shell idiom; not band-aids

**Rationale:**
- Line 195: `curl --silent --fail --max-time 5 "${url}"` — the 5-second timeout is arbitrary and hardcoded. A slow network or startup environment could exceed this without user visibility. Should be configurable via env var.
- Line 220: `sleep 2` — after spawning proxy in background, waits 2 seconds before checking if process is still alive. If the proxy takes >2s to initialize, the check may fail prematurely. Should be tunable or at minimum documented with rationale.

DELIVERABLE_COMPLETE
