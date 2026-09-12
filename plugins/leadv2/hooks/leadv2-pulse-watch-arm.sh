#!/usr/bin/env bash
# TOMBSTONE — the beat/pulse chain was retired (founder order 2026-09-12, one
# status mechanism). Its registration is already gone from hooks.json, but a
# session that started BEFORE the deletion still fires the cached registration
# and prints "No such file or directory" on every tool call. This no-op absorbs
# that until those sessions end. Delete it once no pre-deletion session is live.
exit 0
