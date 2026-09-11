#!/usr/bin/env bash
# .claude/hooks/mojibake-guard.sh - Stop hook (MOJIBAKE-GUARD-01, 2026-07-17)
#
# WHY: the lead writes to the founder in Russian, and twice on 2026-07-17 it
# emitted mojibake - UTF-8 Cyrillic bytes re-decoded as latin1/cp1252, so a
# clean Russian word rendered as a wall of U+00D0/U+00D1 + high latin1 chars
# (proven lead-side: the corrupt bytes are in the transcript itself, 2 of 197
# assistant messages; no config knob exists). This guard detects it AFTER
# generation and BLOCKS the Stop so the lead must re-send the message cleanly.
#
# WHAT IT READS: ONLY the transcript's last assistant message text blocks
# (chat output) - never any repo file. So a handoff doc / mission file that
# deliberately quotes the mojibake pattern inside a fenced code block is not
# inspected and cannot trip this guard.
#
# STDIN HANDLING: the Stop payload (JSON with transcript_path) arrives on this
# hook's stdin. We read it into a var FIRST, then pass it to python via the
# PE_STOP_PAYLOAD env var - because "python3 - <<PYEOF" below uses stdin for
# the script source, so python's own stdin cannot also carry the payload.
#
# FAIL OPEN (hard rule): any internal error - bad stdin JSON, missing or
# unreadable transcript, malformed JSONL, python missing/crash - exits 0 (never
# wedges the session) but logs a one-line note to stderr so it is not silently
# swallowed. The ONLY blocking exit (2) is a CONFIRMED mojibake run; its stderr
# feeds back to the model so the lead re-sends cleanly. "Nothing to check"
# (last turn had no text) and "clean content" exit 0 SILENTLY.
#
# DETECTION: a UTF-8 Cyrillic char is bytes 0xD0|0xD1 + a second byte in
# 0x80-0xBF. Re-decoded as latin1/cp1252 that becomes U+00D0 or U+00D1
# immediately followed by a high latin1 char (a fraction, punctuation mark, or
# smart quote). We require a RUN of >=3 such pairs in one message, so a lone
# legitimate Spanish capital N-tilde (U+00D1, always followed by an ASCII
# letter, e.g. "NINO") never trips it. The regex is built from chr() codepoints
# at runtime, so this source file contains no literal control bytes.
set -uo pipefail

# 1) grab the Stop payload off stdin BEFORE the heredoc below reuses stdin.
_payload="$(cat)" || _payload=""
export PE_STOP_PAYLOAD="$_payload"

# 2) All real work in one python3 pass. Python catches every internal error and
#    exits 0 (fail open) or 2 (block). The bash wrapper below is the fail-open
#    backstop: a python crash / missing python / SIGPIPE -> exit 0 + stderr.
python3 - <<'PYEOF'
import json, os, re, sys


def bail(msg):
    sys.stderr.write("mojibake-guard: " + msg + " (failing open)\n")
    sys.exit(0)


# --- parse the Stop payload (passed in via env var, see STDIN HANDLING above) ---
try:
    payload = json.loads(os.environ.get("PE_STOP_PAYLOAD", "") or "")
except Exception as e:
    bail("could not parse Stop payload JSON: " + repr(e)[:120])
if not isinstance(payload, dict):
    bail("Stop payload is not a JSON object")
path = payload.get("transcript_path")
if not isinstance(path, str) or not path:
    bail("Stop payload missing transcript_path")

# --- read the LAST assistant message's concatenated text blocks ---
try:
    f = open(path, encoding="utf-8")
except Exception as e:
    bail("cannot open transcript: " + repr(e)[:120])
last_text = ""
try:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)
        except Exception:
            continue  # skip non-JSON lines silently (transcripts append atomically)
        if not isinstance(rec, dict) or rec.get("type") != "assistant":
            continue
        msg = rec.get("message")
        if not isinstance(msg, dict):
            continue
        content = msg.get("content")
        # content may be a bare string (older format) or a list of blocks.
        if isinstance(content, str):
            if content:
                last_text = content
            continue
        if not isinstance(content, list):
            continue
        parts = [
            c.get("text", "")
            for c in content
            if isinstance(c, dict) and c.get("type") == "text" and c.get("text")
        ]
        if parts:
            last_text = "\n".join(parts)
except Exception as e:
    bail("error reading transcript: " + repr(e)[:120])

if not last_text:
    sys.exit(0)  # last assistant turn had no text -> nothing to check, silent

# --- strip fenced code blocks so byte examples / doc quotes are not live mojibake ---
s = re.sub(r"```.*?```", " ", last_text, flags=re.DOTALL)
s = re.sub(r"~~~.*?~~~", " ", s, flags=re.DOTALL)

# --- detect latin1-mangled Cyrillic ---
# Lead char: U+00D0 or U+00D1 (the "D-stroke" / "N-tilde" a latin1 mis-decode of
# the UTF-8 lead byte 0xD0/0xD1 produces). Second char: the UTF-8 Cyrillic
# second byte is 0x80-0xBF; as latin1 that is U+0080-00BF, and as cp1252 the
# 0x80-0x9F bytes additionally map to smart quotes / symbols (listed below).
LEAD = chr(0xD0) + chr(0xD1)
SECOND = "".join(chr(c) for c in range(0x80, 0xC0))
for cp in (0x20AC, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6,
           0x2030, 0x0160, 0x2039, 0x0152, 0x017D, 0x2018, 0x2019, 0x201C,
           0x201D, 0x2022, 0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A,
           0x0153, 0x017E, 0x0178):
    if chr(cp) not in SECOND:
        SECOND += chr(cp)
pat = re.compile("[" + LEAD + "][" + SECOND + "]")

hits = pat.findall(s)
if len(hits) >= 3:
    m = pat.search(s)
    ctx = s[max(0, m.start() - 12):m.end() + 30].replace("\n", " ")
    sys.stderr.write(
        "mojibake-guard: your last message contains latin-1-mangled Cyrillic "
        "(mojibake) " + chr(0x2014) + " the founder sees an unreadable wall of "
        + chr(0xD0) + "/" + chr(0xD1) + " instead of clean Russian. Re-send "
        "the message in clean UTF-8 Cyrillic. (" + str(len(hits))
        + " mangled pairs detected; first near: \"" + ctx[:60] + "\")\n"
    )
    sys.exit(2)
sys.exit(0)
PYEOF

# Propagate: 0=clean / nothing-to-check, 2=block (mojibake), anything else=fail open.
rc=$?
case $rc in
  0) exit 0 ;;
  2) exit 2 ;;
  *) echo "mojibake-guard: internal error (failing open), python exit=$rc" >&2; exit 0 ;;
esac
