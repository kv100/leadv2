#!/usr/bin/env bash
# Emit one shared observability note for either independent review resolver call site.
leadv2_review_reroute_note() {
  local task="${1:-}" pool="${2:-}" reviewer="${3:-}" disposition
  [[ -n "$reviewer" && "$reviewer" != codex ]] || return 0
  disposition="$(printf '%s' "$pool" | tr ',' '\n' | sed -n -E 's/^(codex:(blocked|unknown):[^,]*)$/\1/p' | head -n1)"
  [[ -n "$disposition" ]] || return 0
  printf 'codex_dead_reroute task=%s from=codex to=%s codex=%s pool=%s\n' "$task" "$reviewer" "$disposition" "$pool"
  return 0
}
