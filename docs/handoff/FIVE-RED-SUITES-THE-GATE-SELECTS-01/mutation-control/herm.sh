#!/usr/bin/env bash
# Hermeticity probe: same suite, ordinary env vs a scrubbed HOME.
# A verdict that differs between the two depends on something outside its subject.
PIN="$1"; shift
FAKE="$PIN/../herm-home"; mkdir -p "$FAKE"
cp "$HOME/.gitconfig" "$FAKE/.gitconfig" 2>/dev/null || true
cd "$PIN" || exit 1
verdict() { grep -oiE '(passed|PASS)=[0-9]+ *(failed|FAIL)=[0-9]+|[0-9]+ passed, [0-9]+ failed|PASS=[0-9]+ FAIL=[0-9]+|[0-9]+ PASS, [0-9]+ FAIL' "$1" | tail -1; }
for s in "$@"; do
  f="plugins/leadv2/scripts/tests/test-$s.sh"
  timeout 200 bash "$f" >/tmp/h-a-$s.log 2>&1; rcA=$?
  HOME="$FAKE" timeout 200 bash "$f" >/tmp/h-b-$s.log 2>&1; rcB=$?
  vA="$(verdict /tmp/h-a-$s.log)"; vB="$(verdict /tmp/h-b-$s.log)"
  mark=same; [ "$rcA" != "$rcB" ] && mark=RC-DIFFERS; [ "$vA" != "$vB" ] && mark=VERDICT-DIFFERS
  printf '%-36s rc %s/%s  %-24s | %-24s  %s\n' "$s" "$rcA" "$rcB" "${vA:-?}" "${vB:-?}" "$mark"
done
