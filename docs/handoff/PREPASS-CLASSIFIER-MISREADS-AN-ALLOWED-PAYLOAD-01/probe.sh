#!/usr/bin/env bash
# Two independent measurements, each printed with its own verdict.
set -uo pipefail
S="$HOME/Projects/leadv2/plugins/leadv2/scripts"
TMP="$(mktemp -d /private/tmp/probe34.XXXXXX)"; trap 'rm -rf "$TMP"' EXIT

[[ "$OUT" == "allowed" ]] && exit 0 || exit 1
