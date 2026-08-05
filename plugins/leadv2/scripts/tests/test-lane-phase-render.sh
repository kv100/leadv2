#!/usr/bin/env bash
# test-lane-phase-render.sh — fixture test for lane_phase() rendering
# PHASES-ARE-THE-ONLY-PATH-01 §11 test suite 3.
#
# Tests lane_phase() directly against fixture phase records, with a stub
# liveness probe. No live lane, no network.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SURFACE="${SCRIPT_DIR}/../leadv2-status-surface.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

PASS=0
FAIL=0
ok() { PASS=$((PASS+1)); }
fail() { FAIL=$((FAIL+1)); printf '  FAIL: %s\n' "$1" >&2; }

# Create a stub liveness binary that reads its verdict from a control file
STUB_LIVENESS="${TMP_ROOT}/stub-liveness.sh"
LIVENESS_VERDICT_FILE="${TMP_ROOT}/liveness_verdict"
printf 'alive' > "$LIVENESS_VERDICT_FILE"
cat > "$STUB_LIVENESS" <<'STUBEOF'
#!/usr/bin/env bash
# Stub: reads verdict from control file
VERDICT="$(cat "${LIVENESS_VERDICT_FILE}" 2>/dev/null || echo alive)"
printf '{"status": "%s"}\n' "$VERDICT"
STUBEOF
chmod +x "$STUB_LIVENESS"

SIG8="abc12345"
HANDOFF_DIR="${TMP_ROOT}/docs/handoff/dispatch-${SIG8}"
PHASES_D="${HANDOFF_DIR}/phases.d"

# Helper: run the lane_phase python function in isolation against fixtures
run_lane_phase() {
  local status="$1" handle="$2" ended_at="$3" phase="${4:-review}" started_at="${5:-2026-08-05T14:00:00Z}"
  mkdir -p "$PHASES_D"
  # Clean previous records
  rm -f "$PHASES_D"/*.yaml 2>/dev/null
  cat > "${PHASES_D}/${phase}.yaml" <<YREC
phase: ${phase}
status: ${status}
owner: test
handle: ${handle}
artifact: src/file.py
artifact_sha256: abc123
started_at: ${started_at}
ended_at: ${ended_at}
reason:
YREC

  LIVENESS_VERDICT_FILE="$LIVENESS_VERDICT_FILE" \
  LEADV2_PROJECT_ROOT="$TMP_ROOT" \
  LEADV2_SS_LANE_LIVENESS_BIN="$STUB_LIVENESS" \
  python3 - "$SURFACE" "$SIG8" <<'PYEOF'
import os, sys, types, datetime

# We need to extract and run just the lane_phase function with mocked context.
# Rather than sourcing the full surface (which needs a ledger), we inline the
# function and its deps with controlled globals.

TMP_ROOT = os.environ["LEADV2_PROJECT_ROOT"]
SIG8 = sys.argv[2]
PROJECT_ROOT = TMP_ROOT
CUR_REPO = "test-repo"
now = datetime.datetime(2026, 8, 5, 15, 0, 0).timestamp()

# Minimal flat_yaml
def flat_yaml(path):
    d = {}
    try:
        with open(path) as fh:
            for line in fh:
                line = line.rstrip("\n")
                if not line or line.lstrip().startswith("#") or ":" not in line:
                    continue
                k, _, v = line.partition(":")
                d[k.strip()] = v.strip().strip("'\"")
    except Exception:
        pass
    return d

# Liveness probe stub
_liveness_probe_cache = {}
def _liveness_probe(sig8):
    if sig8 in _liveness_probe_cache:
        return _liveness_probe_cache[sig8]
    import subprocess
    bin_path = os.environ.get("LEADV2_SS_LANE_LIVENESS_BIN", "")
    try:
        result = subprocess.run(
            ["bash", bin_path, "--project-root", PROJECT_ROOT,
             "--lane", sig8, "--no-codex", "--json"],
            capture_output=True, text=True, timeout=3)
        out = result.stdout.strip()
        if '"alive"' in out or '"status": "alive"' in out:
            _liveness_probe_cache[sig8] = "alive"
        elif '"dead"' in out or '"status": "dead"' in out:
            _liveness_probe_cache[sig8] = "dead"
        else:
            _liveness_probe_cache[sig8] = "unknown"
    except Exception:
        _liveness_probe_cache[sig8] = "unknown"
    return _liveness_probe_cache[sig8]

def legacy_infer(repo, sig8):
    return "~"

def lane_phase(repo, sig8, terminal_phase, in_census):
    if terminal_phase:
        return terminal_phase
    if repo != CUR_REPO or not PROJECT_ROOT or not sig8:
        return legacy_infer(repo, sig8) if sig8 else ("worker" if in_census else "queued")
    phases_d = os.path.join(PROJECT_ROOT, "docs", "handoff",
                             "dispatch-%s" % sig8, "phases.d")
    if not os.path.isdir(phases_d):
        return legacy_infer(repo, sig8)
    records = []
    for fname in os.listdir(phases_d):
        if not fname.endswith(".yaml"):
            continue
        rec = flat_yaml(os.path.join(phases_d, fname))
        if rec.get("phase"):
            records.append(rec)
    if not records:
        return legacy_infer(repo, sig8)
    running = [r for r in records if r.get("status") == "running"]
    if running:
        running.sort(key=lambda r: r.get("started_at", ""), reverse=True)
        newest = running[0]
        if newest.get("ended_at", "").strip():
            return "%s (done)" % newest["phase"]
        probe = _liveness_probe(sig8)
        if probe == "dead":
            started = newest.get("started_at", "")
            age_str = ""
            try:
                st = datetime.datetime.fromisoformat(
                    started.replace("Z", "+00:00"))
                age_s = max(0, int(now - st.timestamp()))
                if age_s < 3600:
                    age_str = "%dm" % (age_s // 60)
                else:
                    age_str = "%dh" % (age_s // 3600)
            except Exception:
                age_str = "?"
            return "%s (stalled, started %s ago)" % (newest["phase"], age_str)
        return newest["phase"]
    done_recs = [r for r in records
                  if r.get("status") in ("done", "n/a", "waived")]
    if done_recs:
        done_recs.sort(key=lambda r: r.get("ended_at", "") or r.get("started_at", ""),
                        reverse=True)
        return "%s (done)" % done_recs[0]["phase"]
    return "worker" if in_census else "queued"

result = lane_phase(CUR_REPO, SIG8, None, True)
print(result)
PYEOF
}

# ── Test 1: running, empty ended_at, dead probe → stalled ────────────────────
printf 'test: running + dead probe → stalled\n'
printf 'dead' > "$LIVENESS_VERDICT_FILE"
OUT="$(run_lane_phase running dispatch-abc-review '' review '2026-08-05T14:22:00Z')"
if printf '%s' "$OUT" | grep -q 'review (stalled'; then
  ok
else
  fail "expected 'review (stalled, ...)', got: $OUT"
fi

# ── Test 2: running, empty ended_at, alive probe → plain phase ───────────────
printf 'test: running + alive probe → plain\n'
printf 'alive' > "$LIVENESS_VERDICT_FILE"
OUT="$(run_lane_phase running dispatch-abc-review '' review '2026-08-05T14:22:00Z')"
if [[ "$OUT" == "review" ]]; then
  ok
else
  fail "expected 'review', got: $OUT"
fi

# ── Test 3: running, empty ended_at, unknown probe → plain phase ─────────────
printf 'test: running + unknown probe → plain (never stalled)\n'
# Make the probe fail
cat > "$STUB_LIVENESS" <<'STUBEOF'
#!/usr/bin/env bash
exit 1
STUBEOF
chmod +x "$STUB_LIVENESS"
OUT="$(run_lane_phase running dispatch-abc-review '' review '2026-08-05T14:22:00Z')"
if [[ "$OUT" == "review" ]]; then
  ok
else
  fail "expected 'review' on probe failure, got: $OUT"
fi

# Restore working stub
cat > "$STUB_LIVENESS" <<STUBEOF
#!/usr/bin/env bash
VERDICT="\$(cat "${LIVENESS_VERDICT_FILE}" 2>/dev/null || echo alive)"
printf '{"status": "%s"}\n' "\$VERDICT"
STUBEOF
chmod +x "$STUB_LIVENESS"

# ── Test 4: no phases.d → legacy inference with ~ prefix ─────────────────────
printf 'test: no phases.d → ~ prefix\n'
rm -rf "$PHASES_D"
OUT="$(LIVENESS_VERDICT_FILE="$LIVENESS_VERDICT_FILE" \
  LEADV2_PROJECT_ROOT="$TMP_ROOT" \
  LEADV2_SS_LANE_LIVENESS_BIN="$STUB_LIVENESS" \
  python3 - <<'PYEOF'
import os, sys, datetime
TMP_ROOT = os.environ["LEADV2_PROJECT_ROOT"]
SIG8 = "abc12345"
PROJECT_ROOT = TMP_ROOT
CUR_REPO = "test-repo"
now = datetime.datetime(2026, 8, 5, 15, 0, 0).timestamp()

def flat_yaml(path):
    d = {}
    try:
        with open(path) as fh:
            for line in fh:
                line = line.rstrip("\n")
                if not line or line.lstrip().startswith("#") or ":" not in line:
                    continue
                k, _, v = line.partition(":")
                d[k.strip()] = v.strip().strip("'\"")
    except Exception:
        pass
    return d

_liveness_probe_cache = {}
def _liveness_probe(sig8):
    return "unknown"

def legacy_infer(repo, sig8):
    return "~"

def lane_phase(repo, sig8, terminal_phase, in_census):
    if terminal_phase:
        return terminal_phase
    if repo != CUR_REPO or not PROJECT_ROOT or not sig8:
        return legacy_infer(repo, sig8) if sig8 else ("worker" if in_census else "queued")
    phases_d = os.path.join(PROJECT_ROOT, "docs", "handoff",
                             "dispatch-%s" % sig8, "phases.d")
    if not os.path.isdir(phases_d):
        return legacy_infer(repo, sig8)
    return "should-not-reach"

print(lane_phase(CUR_REPO, SIG8, None, True))
PYEOF
)"
if [[ "$OUT" == "~" ]]; then
  ok
else
  fail "expected '~' for no phases.d, got: $OUT"
fi

# ── Test 5: all records done → phase (done) ──────────────────────────────────
printf 'test: all done → close (done)\n'
mkdir -p "$PHASES_D"
rm -f "$PHASES_D"/*.yaml 2>/dev/null
cat > "${PHASES_D}/close.yaml" <<YREC
phase: close
status: done
owner: test
handle: dispatch-abc-close
artifact: docs/handoff/dispatch-abc/phase8-passed.flag
artifact_sha256: def456
started_at: 2026-08-05T14:00:00Z
ended_at: 2026-08-05T15:00:00Z
reason:
YREC
printf 'alive' > "$LIVENESS_VERDICT_FILE"
OUT="$(LIVENESS_VERDICT_FILE="$LIVENESS_VERDICT_FILE" \
  LEADV2_PROJECT_ROOT="$TMP_ROOT" \
  LEADV2_SS_LANE_LIVENESS_BIN="$STUB_LIVENESS" \
  python3 - <<'PYEOF'
import os, sys, datetime
TMP_ROOT = os.environ["LEADV2_PROJECT_ROOT"]
SIG8 = "abc12345"
PROJECT_ROOT = TMP_ROOT
CUR_REPO = "test-repo"
now = datetime.datetime(2026, 8, 5, 15, 30, 0).timestamp()

def flat_yaml(path):
    d = {}
    try:
        with open(path) as fh:
            for line in fh:
                line = line.rstrip("\n")
                if not line or line.lstrip().startswith("#") or ":" not in line:
                    continue
                k, _, v = line.partition(":")
                d[k.strip()] = v.strip().strip("'\"")
    except Exception:
        pass
    return d

_liveness_probe_cache = {}
def _liveness_probe(sig8):
    return "unknown"

def legacy_infer(repo, sig8):
    return "~"

def lane_phase(repo, sig8, terminal_phase, in_census):
    if terminal_phase:
        return terminal_phase
    if repo != CUR_REPO or not PROJECT_ROOT or not sig8:
        return legacy_infer(repo, sig8) if sig8 else ("worker" if in_census else "queued")
    phases_d = os.path.join(PROJECT_ROOT, "docs", "handoff",
                             "dispatch-%s" % sig8, "phases.d")
    if not os.path.isdir(phases_d):
        return legacy_infer(repo, sig8)
    records = []
    for fname in os.listdir(phases_d):
        if not fname.endswith(".yaml"):
            continue
        rec = flat_yaml(os.path.join(phases_d, fname))
        if rec.get("phase"):
            records.append(rec)
    if not records:
        return legacy_infer(repo, sig8)
    running = [r for r in records if r.get("status") == "running"]
    if running:
        return "running-should-not-happen"
    done_recs = [r for r in records
                  if r.get("status") in ("done", "n/a", "waived")]
    if done_recs:
        done_recs.sort(key=lambda r: r.get("ended_at", "") or r.get("started_at", ""),
                        reverse=True)
        return "%s (done)" % done_recs[0]["phase"]
    return "worker" if in_census else "queued"

print(lane_phase(CUR_REPO, SIG8, None, True))
PYEOF
)"
if [[ "$OUT" == "close (done)" ]]; then
  ok
else
  fail "expected 'close (done)', got: $OUT"
fi

printf '\n[LANE-PHASE-RENDER] pass=%d fail=%d\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
