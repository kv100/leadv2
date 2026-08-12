#!/usr/bin/env bash
# Fixture: stub codex arm that simulates codex_enabled=false.
# Emits codex_skipped_by_policy token on stdout and stderr.
echo "codex_skipped_by_policy" >&2
echo "codex_skipped_by_policy"
exit 0
