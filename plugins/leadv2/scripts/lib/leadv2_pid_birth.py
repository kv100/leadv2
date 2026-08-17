"""leadv2_pid_birth.py — ONE pid-birth rule, ONE inode (BROAD-STATUS-RENDERER-01 D4).

`ps -o lstart=` on Darwin right-pads and uses a DOUBLE interior space for
single-digit days ("Sun Aug  3 ..."). That form leaked into stored birth
values (the pre-fix leadv2-active-registry.sh writer), and every reader that
compared a stored birth against a live one with anything other than a full
whitespace collapse declared every live lane recycled ("pid birth mismatch
(reuse)"). Three hand-rolled copies of the comparison existed; this module
is the replacement for all of them.

Import contract (R4): readers inside heredocs do

    sys.path.insert(0, os.path.join(script_dir, "lib"))
    from leadv2_pid_birth import norm_birth, pid_birth_of, birth_matches

and MUST fall back to an inline `" ".join(str(v).split())` when the import
fails (a drifted `.claude/scripts/` copy without `lib/`) — degrade, never
crash a status probe.
"""

import subprocess


def norm_birth(v):
    """Collapse ALL whitespace runs (edges + Darwin double interior space).

    Falsy passthrough: an unknown stays unknown, never becomes "".
    """
    if not v:
        return v
    return " ".join(str(v).split())


def pid_birth_of(pid):
    """Live `ps -o lstart=` for pid, normalised; None on any failure."""
    try:
        r = subprocess.run(
            ["ps", "-o", "lstart=", "-p", str(pid)],
            capture_output=True, text=True, timeout=5,
        )
    except Exception:
        return None
    return norm_birth(r.stdout.strip()) or None


def birth_matches(stored, live):
    """True unless BOTH births are known AND differ.

    Unknown on either side -> True: a missing fact must never declare a live
    worker dead (R3 — a wrong comparison turns every lane red in SwiftBar).
    """
    s, l = norm_birth(stored), norm_birth(live)
    if not s or not l:
        return True
    return s == l
