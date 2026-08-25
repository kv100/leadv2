#!/bin/bash
# leadv2-native-pulse.sh — event-driven founder pulse for the Codex lead.
# CODEX-PULSE-HOOK-02. Registered as the SECOND PreToolUse entry and as the
# second SubagentStart/Stop entry (--force). It never emits a permission
# decision and exits 0 on every path: a pulse must not be able to deny a tool
# call or break the lead. Codex fires hooks only on lead activity, so the
# cadence is "at most one pulse per 60s of lead activity", never a wall-clock
# timer; pulse.log gaps are gaps in lead activity, not lost pulses.
#
# Env contract (all LEADV2_*, test seams via mktemp dirs):
#   LEADV2_CODEX_PULSE_STATE       state dir + pulse.log (default $ROOT/.native-pulse)
#   LEADV2_CODEX_PULSE_MIN_SECONDS cadence floor; 0 = emit on every call (default 60)
#   LEADV2_CODEX_PULSE_INJECT      1 = print rendered line as additionalContext (default 0:
#                                  the step-0 probe could not confirm Codex renders
#                                  hook-injected additionalContext from a second
#                                  PreToolUse entry — docs/evidence/codex-native-pulse-probe.md)
#   LEADV2_NATIVE_AGENT_REGISTRY   reused verbatim from the lifecycle hook
#   LEADV2_CODEX_PULSE_REPO_ROOT   repo root for the status producers (test seam)
set -u
FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1
ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
STATE="${LEADV2_CODEX_PULSE_STATE:-$ROOT/.native-pulse}"
REGISTRY="${LEADV2_NATIVE_AGENT_REGISTRY:-$ROOT/.native-agent-registry}"
REPO_ROOT="${LEADV2_CODEX_PULSE_REPO_ROOT:-}"
if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT="$(cd "$ROOT/../../../../../" 2>/dev/null && pwd)" || REPO_ROOT=""
fi
MIN_SECONDS="${LEADV2_CODEX_PULSE_MIN_SECONDS:-60}"
INJECT="${LEADV2_CODEX_PULSE_INJECT:-0}"

STATE="$STATE" REGISTRY="$REGISTRY" REPO_ROOT="$REPO_ROOT" \
MIN_SECONDS="$MIN_SECONDS" INJECT="$INJECT" FORCE="$FORCE" python3 - <<'PY'
import hashlib, json, os, re, subprocess, tempfile, time

state = os.environ['STATE']; registry = os.environ['REGISTRY']
repo_root = os.environ['REPO_ROOT']
try: min_seconds = float(os.environ['MIN_SECONDS'] or 0)
except Exception: min_seconds = 60.0
inject = os.environ['INJECT'] == '1'; force = os.environ['FORCE'] == '1'
now = time.time(); iso = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(now))

def load_last():
    try:
        with open(os.path.join(state, 'last.json'), encoding='utf-8') as f:
            d = json.load(f)
        return d if isinstance(d, dict) and 'digest' in d and 'emitted_epoch' in d else None
    except Exception:
        return None

def stats_sig(path):
    try:
        st = os.stat(path)
        return '%d:%d' % (st.st_mtime_ns, st.st_size)
    except Exception:
        return '?'

def cheap_sig():
    parts = []
    try:
        for name in sorted(os.listdir(registry)):
            if name.endswith('.json'):
                parts.append(name + '=' + stats_sig(os.path.join(registry, name)))
    except Exception:
        parts.append('?')
    if repo_root:
        parts.append('active=' + stats_sig(os.path.join(repo_root, 'docs/leadv2/active.yaml')))
    return hashlib.sha256('|'.join(parts).encode()).hexdigest()

def agent_ids():
    ids = []
    try:
        for name in sorted(os.listdir(registry)):
            if not name.endswith('.json'):
                continue
            try:
                with open(os.path.join(registry, name), encoding='utf-8') as f:
                    ids.append(str(json.load(f).get('agent_id', '?')))
            except Exception:
                ids.append('?')
    except Exception:
        pass
    return ids

def surface_line():
    script = os.path.join(repo_root, 'plugins/leadv2/scripts/leadv2-status-surface.sh') if repo_root else ''
    if not repo_root or not (os.path.isfile(script) or os.access(script, os.X_OK)):
        return '?'
    try:
        r = subprocess.run(['bash', script, '--oneline'], capture_output=True, text=True, timeout=5)
        out = (r.stdout or '').strip()
        return out if r.returncode == 0 and out else '?'
    except Exception:
        return '?'

try:
    last = load_last()
    # R3: short-circuit before the expensive lane scan when nothing cheap
    # (registry files, active.yaml) moved and the cadence window is still open.
    if not force and last is not None and min_seconds > 0:
        if cheap_sig() == last.get('cheap') and now - float(last['emitted_epoch']) < min_seconds:
            raise SystemExit

    ids = agent_ids(); surface = surface_line()
    if repo_root:
        active_sig = stats_sig(os.path.join(repo_root, 'docs/leadv2/active.yaml'))
    else:
        active_sig = '?'
    digest = hashlib.sha256(('\n'.join(ids) + '\n' + surface + '\n' + active_sig).encode()).hexdigest()

    if force:
        reason = 'lifecycle'
    elif last is None or digest != last['digest']:
        reason = 'changed'
    elif now - float(last['emitted_epoch']) >= min_seconds:
        reason = 'cadence'
    else:
        raise SystemExit

    m = re.search(r'lanes (\d+)', surface)
    if m:
        lanes = m.group(1)
    elif surface == '?':
        lanes = '?'
    else:
        lanes = '0'
    tm = re.search(r'lanes \d+: (\S+)', surface)
    task = tm.group(1) if tm else '-'
    line = '%s pulse agents=%d lanes=%s task=%s reason=%s' % (iso, len(ids), lanes, task, reason)

    os.makedirs(state, exist_ok=True)
    with open(os.path.join(state, 'pulse.log'), 'a', encoding='utf-8') as f:
        f.write(line + '\n')
    record = {'version': 1, 'digest': digest, 'cheap': cheap_sig(), 'emitted_at': iso, 'emitted_epoch': now}
    fd, tmp = tempfile.mkstemp(prefix='.native-pulse.', dir=state)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as f:
            json.dump(record, f, sort_keys=True, separators=(',', ':')); f.write('\n')
        os.replace(tmp, os.path.join(state, 'last.json'))
    finally:
        try: os.unlink(tmp)
        except FileNotFoundError: pass
    if inject:
        print(json.dumps({'hookSpecificOutput': {'hookEventName': 'PreToolUse', 'additionalContext': line}}))
except SystemExit:
    pass
except Exception:
    pass
PY
exit 0
