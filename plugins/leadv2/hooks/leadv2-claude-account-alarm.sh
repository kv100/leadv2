#!/usr/bin/env bash
# leadv2-claude-account-alarm.sh — SessionStart banner (TWO-SLOTS-COLLAPSE-INTO-ONE-ACCOUNT-01 §2c)
#
# The write that collapses two Claude-profile slots onto one real account
# happens inside the Claude CLI (an interactive /login while
# CLAUDE_CONFIG_DIR points at the wrong dir), outside this repo entirely --
# it cannot be prevented from here. This hook makes it LOUD instead: every
# session start, independently of whether any lane spawned or the selector
# ever ran, it re-derives both registry slots' real account identity
# straight from disk (2 file reads, no keychain, no network, <50ms) and
# banners if they collapsed.
#
# Deliberately does NOT read the alarm file the selector writes (2b) -- that
# keeps this banner correct even when no lane has run yet this session, and
# immune to a lost concurrent alarm-file write (worst case there is a
# stale-by-one-run alarm; this check is unaffected either way).
#
# rc<=2 pass-through per the existing hooks.json wrapper idiom; anything
# else is swallowed by the caller and appended to LEADV2_DEGRADE_LOG.
set -uo pipefail

REGISTRY="${LEADV2_CLAUDE_PROFILES_FILE:-$HOME/.claude/state/leadv2/claude-profiles.tsv}"

[[ -r "$REGISTRY" ]] || exit 0

REGISTRY="$REGISTRY" python3 -c '
import json, os, sys

registry = os.environ.get("REGISTRY", "")
slots = []
try:
    with open(registry) as f:
        for line in f:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) < 2:
                continue
            label, config_dir = parts[0], parts[1]
            if not label or not config_dir:
                continue
            slots.append((label, config_dir))
except Exception:
    sys.exit(0)

if len(slots) < 2:
    sys.exit(0)

def account_uuid(config_dir):
    try:
        with open(os.path.join(config_dir, ".claude.json")) as f:
            cj = json.load(f)
    except Exception:
        return None
    return (cj.get("oauthAccount") or {}).get("accountUuid")

resolved = [(label, account_uuid(d), d) for label, d in slots]

i = 0
while i < len(resolved):
    j = i + 1
    while j < len(resolved):
        label_a, uuid_a, dir_a = resolved[i]
        label_b, uuid_b, dir_b = resolved[j]
        if uuid_a and uuid_a == uuid_b:
            tail = uuid_a[-6:]
            ctx = (
                "[CLAUDE ACCOUNT ALARM] Slots \x27" + label_a + "\x27 and \x27" + label_b +
                "\x27 in the Claude multi-profile registry resolve to the SAME real " +
                "account (uuid ..\x27" + tail + "\x27). One of them was likely re-logged-in " +
                "while CLAUDE_CONFIG_DIR pointed at the other dir. Remedy: run " +
                "`CLAUDE_CONFIG_DIR=" + dir_a + " claude /login` (or the other dir) to " +
                "restore the intended account for that slot. Confirm with: " +
                "bash plugins/leadv2/scripts/leadv2-claude-account-check.sh"
            )
            print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": ctx}}))
            sys.exit(0)
        j += 1
    i += 1
' 2>/dev/null

exit 0
