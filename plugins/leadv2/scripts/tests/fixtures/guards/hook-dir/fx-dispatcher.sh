#!/usr/bin/env bash
# fx-dispatcher — synthetic MANIFEST-routing dispatcher (mirrors
# leadv2-bash-pre-dispatch.sh's convention) so the census's dispatcher-follow
# can be locked with a fixture, never only against the real plugin file.
set -uo pipefail
MANIFEST='fx-dispatched.sh|ALWAYS'
while IFS='|' read -r SCRIPT TRIGGER; do
  [ -n "$SCRIPT" ] || continue
  true
done <<< "$MANIFEST"
exit 0
