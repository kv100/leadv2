FINDING: severity=High file=plugins/leadv2/scripts/lib/leadv2-admission-class.sh line=1247 dimension=hack desc=bare except Exception swallows all exceptions including SystemExit; should catch specific (ValueError TypeError) for json parsing
FINDING: severity=Medium file=plugins/leadv2/scripts/leadv2-backlog-pump.sh line=581 dimension=hack desc=hardcoded sleep 2 magic number band-aid for spawn liveness; no LEADV2_PUMP_SETTLE_SEC timeout override or rationale comment
FINDING: severity=Medium file=plugins/leadv2/scripts/leadv2-backlog-pump.sh line=451 dimension=hack desc=source lib || true silent fallback; missing library allows function calls to fail later without clear error context
FINDING: severity=Medium file=plugins/leadv2/scripts/lib/leadv2-admission-class.sh line=1339 dimension=hack desc=2>/dev/null || printf empty silent error handling in file read; caller cannot distinguish missing receipt from parse failure
FINDING: severity=Medium file=plugins/leadv2/scripts/lib/leadv2-admission-class.sh line=1362 dimension=hack desc=2>/dev/null error redirection in atomic write with no logging; silent failures on permission or disk errors
FINDING: severity=Low file=plugins/leadv2/scripts/lib/leadv2-freepool-model-select.sh line=1322 dimension=hack desc=except ImportError sys.exit(0) silent exit if yaml import fails; no error context or fallback
FINDING: severity=Medium file=plugins/leadv2/scripts/lib/leadv2-freepool-model-select.sh line=1430 dimension=hack desc=2>/dev/null || true on Python subprocess; returns empty string silently on failure, indistinguishable from intentional empty
FINDING: severity=Low file=plugins/leadv2/scripts/leadv2-backlog-pump.sh line=469 dimension=hack desc=return 2 for git probe failure creates ambiguous code path; conflates Git errors with could_not_determine state

DELIVERABLE_COMPLETE
