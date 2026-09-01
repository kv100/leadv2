#!/usr/bin/env bash
# Real-guard fixture: leadv2-promise-guard.sh (Stop), the fires-log-only shape.
# Probe artifact 2026-09-01: transcript "Сейчас исправлю биндинг и напишу
# отчёт." with zero state-changing calls -> journal row {"verdict":"fired",
# "block_mode":"0"}, exit 0, NO stdout/stderr. The census classifies it log
# via the legacy-journal fire record (LEADV2_PROMISE_GUARD_BLOCK=0 ships
# log-only; the flip itself belongs to PROMISE-GUARD-TURN-IT-ON-01).
# HOME is sandboxed, so the real ~/.claude/leadv2-promise-guard.jsonl is
# never written.
GV_FIX_GUARD="leadv2-promise-guard.sh"
GV_FIX_PRE='mkdir -p "$LEADV2_SANDBOX/home/.claude"
# The journal writer appends to ~/.claude/leadv2-promise-guard.jsonl and
# fails silently (|| true) when the directory is absent (probe 2026-09-01).
mkdir -p "$LEADV2_SANDBOX"
printf "%s\n" "{\"type\":\"assistant\",\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"Сейчас исправлю биндинг и напишу отчёт.\"}]}}" > "$LEADV2_SANDBOX/t.jsonl"'
GV_FIX_STDIN='{"session_id":"fx-promise","stop_hook_active":false,"cwd":"$LEADV2_SANDBOX","transcript_path":"$LEADV2_SANDBOX/t.jsonl"}'
GV_FIX_ENV="LEADV2_PROMISE_GUARD_TRANSCRIPT=\$LEADV2_SANDBOX/t.jsonl"
GV_FIX_EXPECT="log"
