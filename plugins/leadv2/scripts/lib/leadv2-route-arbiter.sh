#!/usr/bin/env bash
# One live-window, config-driven arbiter shared by dispatch and review.
# Output is a single machine-readable line; non-zero means caller must fail open.

leadv2_route_arbiter_script_dir() {
  # Per-file installs symlink this library, while BASH_SOURCE preserves the
  # symlink spelling. Follow the chain portably before locating sibling files.
  local source="${BASH_SOURCE[0]}" link dir
  while [[ -h "$source" ]]; do
    dir="$(cd -P "$(dirname "$source")" && pwd)"
    link="$(readlink "$source")"
    [[ "$link" == /* ]] || link="$dir/$link"
    source="$link"
  done
  cd -P "$(dirname "$source")" && pwd
}

# ── _arb_fault_detail <arbiter-stdout> ────────────────────────────────────────
# DISPATCH-FAILS-OPEN-ON-NO-CAPABLE-CELL-01. Every caller that falls open when
# route_arbiter returns non-zero used to journal the rc ALONE:
#     arbiter_broken task=<sig> rc=68 reason=fail_open_to_ladder
# while the arbiter's own line said WHY:
#     arm=refuse model=none tier=none reason=no_capable_cell kind=code chain= ...
# Measured 2026-09-05 across every lane journal in this repo: rc=68 fired 4
# times (all one task, 2026-09-04T19:58..09-05T00:33) and not once was the
# missing capability recoverable afterwards -- the boundary dropped it. The
# fail-open itself is deliberate (a routing-config vocabulary gap must not
# become a hard refusal; leadv2-dispatch-code.sh:8141) and is NOT changed here.
# What changes is that it stops being silent.
#
# Lives in this lib because leadv2-dispatch-code.sh:587 and
# leadv2-dispatch-product-close.sh:33 both source it -- one owner, five
# readers, rather than the same parse copied a fifth time.
#
# Empty-safe by construction: an unparsable or empty stdout yields
# `arb_reason=unparsed`, never an empty token, so the journal line keeps a
# fixed shape for anything grepping it.
_arb_fault_detail() {  # <arbiter stdout> -> "arb_reason=<r> arb_kind=<k>"
  local _out="${1:-}" _r _k
  # grep -oE + head -1 is this codebase's idiom for token extraction (BSD sed
  # has no \| alternation, and a greedy sed s/.*reason=// takes the LAST token
  # on a line that carries several).
  _r="$(printf '%s\n' "${_out}" | grep -oE '(^| )reason=[^ ]+' | head -1 | sed 's/.*=//')"
  _k="$(printf '%s\n' "${_out}" | grep -oE '(^| )kind=[^ ]+' | head -1 | sed 's/.*=//')"
  printf 'arb_reason=%s arb_kind=%s' "${_r:-unparsed}" "${_k:-unknown}"
}

route_arbiter() { # <worker|reviewer> <task-descriptor-json>
  local role="${1:-}" descriptor="${2:-}" here routing live free_gate free_rc quota_json
  # ROUTE-ARBITER-DIES-SILENTLY-ON-LINUX-01, the bash half. The filed row named ONE
  # mute exit (python's `except: raise SystemExit(2)`); measuring it turned up four
  # more, right here -- every precondition below returned a bare number with zero
  # bytes on stdout AND stderr. The rc values are distinct and callers do branch on
  # them (leadv2-dispatch-code.sh journals arbiter_broken rc=<n>), but a human or a
  # suite reading the streams saw nothing at all, so "no arbiter available",
  # "routing config unreadable" and "the quota probe itself failed" were one
  # indistinguishable silence. Found by a suite case written for the python guard
  # that pointed the routing yaml at a missing file and got back nothing.
  # Codes are UNCHANGED -- only the silence goes.
  _arb_fatal() { printf '[route-arbiter] FATAL rc=%s reason=%s detail=%s\n' "$1" "$2" "$3" >&2; return "$1"; }
  [[ "$role" == worker || "$role" == reviewer ]] || _arb_fatal 64 bad_role "role='${role}' (expected worker|reviewer)" || return 64
  here="$(cd "$(leadv2_route_arbiter_script_dir)/.." && pwd)"
  # SONNET-WON-21-MEASURED-GLM-LINES-ON-0905-01 (hole 1, measured 2026-09-05):
  # 21 live decisions picked sonnet with glm MEASURED at 39-45% under an 80%
  # ceiling, and the shape does not reproduce on today's arbiter. It could not be
  # investigated, because a route_resolved line names no version of anything: not
  # the arbiter that ran, not the matrix it read. Today that cost a whole detour
  # -- the missing `kind=` token looked like proof that a stale plugin-cache copy
  # was live (0.1.0 there still carries `glm protected: false`), and refuting it
  # took a separate measurement. Hash the file that is ACTUALLY executing, which
  # is the only form that answers "canonical or someone else's copy" -- a git
  # revision would name the checkout, not the bytes, and worktrees and the plugin
  # cache are exactly where the two diverge.
  local _self_f _self_rev=""
  _self_f="$(leadv2_route_arbiter_script_dir)/$(basename "${BASH_SOURCE[0]}")"
  [[ -r "$_self_f" ]] && _self_rev="$( { shasum -a 256 "$_self_f" 2>/dev/null || sha256sum "$_self_f" 2>/dev/null; } | cut -c1-12)"
  routing="${LEADV2_ROUTE_ARBITER_ROUTING_YAML:-${here}/../config/leadv2-routing.yaml}"
  [[ -r "$routing" ]] || _arb_fatal 65 routing_yaml_unreadable "path='${routing}'" || return 65
  # T17 fix-round (H4): honour the repo's established quota-live seam name
  # (LEADV2_QUOTA_LIVE -- leadv2-burn-governor.sh, leadv2-glm-quota-gate.sh,
  # leadv2-main-model-check.sh) before falling to the arbiter-only spelling,
  # so a caller/test that stubs the common seam also stubs the arbiter.
  live="${LEADV2_ROUTE_ARBITER_QUOTA_LIVE:-${LEADV2_QUOTA_LIVE:-${here}/leadv2-quota-live.sh}}"
  [[ -x "$live" || -f "$live" ]] || _arb_fatal 66 quota_probe_missing "path='${live}'" || return 66
  # A single quota-live json invocation obtains GLM, Codex and Claude windows.
  # Its stderr used to go to /dev/null, so a probe that failed loudly arrived as a
  # bare rc 67 -- our own log lying zero about an error the probe had already
  # written down. Keep the redirect off the happy path's output, keep the message.
  local _q_err; _q_err="$(mktemp 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/arb-q.$$")"
  quota_json="$(bash "$live" json 2>"${_q_err}")" || {
    _arb_fatal 67 quota_probe_failed "probe='${live}' stderr='$(head -c 300 "${_q_err}" 2>/dev/null | tr '\n' ' ')'"
    rm -f "${_q_err}" 2>/dev/null
    return 67
  }
  rm -f "${_q_err}" 2>/dev/null
  free_gate="${LEADV2_ROUTE_ARBITER_FREEPOOL_GATE:-${here}/lib/leadv2-freepool-gate.sh}"
  free_rc=1
  free_reason=""
  if [[ -x "$free_gate" || -f "$free_gate" ]]; then
    # FREEPOOL-DEAD-ARM-LOOKS-LIKE-A-BUSY-ARM-01: the gate's refusal marker
    # (LEADV2_DISPATCH_REFUSED: arm_down|gate_broken|pin_drift) previously
    # died in ">/dev/null 2>&1", so "proxy dead" and "quota burnt" both
    # arrived as the same bare non-zero rc and rendered identically below as
    # util_freepool=100 — a dead arm read as a busy one for a full day
    # (2026-09-04). Capture the stderr, parse the named reason out of it,
    # and re-emit the arm_down case loudly: the arbiter's own stderr is what
    # lands in the dispatch journal a lead actually reads.
    free_err="$(bash "$free_gate" check 2>&1 >/dev/null)"; free_rc=$?
    free_reason="$(printf '%s\n' "${free_err}" | sed -n 's/.*LEADV2_DISPATCH_REFUSED:[[:space:]]*\([A-Za-z0-9._-]\{1,\}\).*/\1/p' | head -1)"
  fi
  if [[ "${free_reason}" == "arm_down" ]]; then
    # LOUD journal line — the one fact the lead must not have to reconstruct.
    # Not auto-restarting the proxy (founder scope 2026-09-04): name the fix,
    # do not perform it.
    printf '[route-arbiter] FREEPOOL ARM DOWN: gate refused arm_down (proxy unreachable) — NOT quota exhaustion; util_freepool=down on this line. Restart with: plugins/leadv2/scripts/freepool-proxy.sh start\n' >&2
  fi
  # FP-08 CAPABILITY-FLOOR: freepool's operator surface (config/freepool-arm.yaml)
  # carries `capability_floor: bulk_only|full`. bulk_only (the default, also when
  # the file/key is unreadable) holds freepool below codex/sonnet for Standard+
  # build work; `full` is the flip FP-04's quality gate will make. Env seam for
  # tests/hermeticity: LEADV2_ROUTE_ARBITER_FREEPOOL_CONFIG.
  freepool_config="${LEADV2_ROUTE_ARBITER_FREEPOOL_CONFIG:-${here}/../config/freepool-arm.yaml}"
  # W1-FORECAST-THE-SPEND-01 hermeticity — the read-direction twin of
  # TESTS-POLLUTE-REAL-JOURNAL-01. The forecast reads the SHARED events
  # journal, so a suite that did not stub it was getting the host's live p90
  # durations injected into its fixtures: measured 2026-09-09, three green
  # cases in test-route-arbiter.sh flipped (glm/glm-flash/sonnet acquired
  # arm_excluded=...:forecast from the real journal's 3.61h/5.52h p90s) and a
  # fourth died mid-suite when the forecast refusal's rc hit `set -e`. A test
  # subtree is exactly what lib/leadv2-test-context.sh already detects for the
  # WRITERS of shared state; the reader degrades the same way: in a test
  # context with no explicit LEADV2_ROUTE_ARBITER_EVENTS_JOURNAL the forecast
  # gets NO journal (journal_unavailable -> no refusal), never the host's
  # live one. An explicit override always wins — the forecast suites set it.
  # Production never sits under a */tests/ runner, so the live path is
  # byte-for-byte the old one.
  _ra_evt_journal="${LEADV2_ROUTE_ARBITER_EVENTS_JOURNAL:-}"
  if [[ -z "${_ra_evt_journal}" ]]; then
    source "${here}/lib/leadv2-test-context.sh" 2>/dev/null || true
    if command -v lv2_test_context >/dev/null 2>&1 && lv2_test_context; then
      _ra_evt_journal=""
    else
      _ra_evt_journal="${HOME}/.claude/cache/leadv2-events/leadv2.jsonl"
    fi
  fi
  ROUTE_ARBITER_SELF_REV="${_self_rev}" \
  ROUTE_ARBITER_ROLE="$role" ROUTE_ARBITER_DESCRIPTOR="$descriptor" \
  ROUTE_ARBITER_QUOTA="$quota_json" ROUTE_ARBITER_FREEPOOL_RC="$free_rc" \
  ROUTE_ARBITER_FREEPOOL_REASON="${free_reason}" \
  ROUTE_ARBITER_STATE_FILE="${LEADV2_ROUTE_ARBITER_STATE_FILE:-${TMPDIR:-/tmp}/leadv2-route-arbiter-last-arm}" \
  ROUTE_ARBITER_FAILURE_LEDGER="${LEADV2_ROUTE_ARBITER_FAILURE_LEDGER:-${HOME}/.claude/leadv2-state/leadv2/dispatch-ledger.jsonl}" \
  ROUTE_ARBITER_EVENTS_JOURNAL="${_ra_evt_journal}" \
  python3 - "$routing" <<'PY'
import json, os, re, sys, tempfile, math
# ROUTE-ARBITER-DIES-SILENTLY-ON-LINUX-01 (2026-09-05). These four loads shared one
# `except Exception: raise SystemExit(2)`, and a bare SystemExit(int) prints NOTHING:
# rc=2 with zero bytes on stdout AND stderr. That is indistinguishable from a crash,
# a missing interpreter and a refusal, so the measured Linux failure (identical call,
# rc=2, both streams empty, while macOS routed normally) started every investigation
# with no information at all -- and, because every arbiter-dependent suite runs
# through this call, it made those suites meaningless on Linux rather than red.
#
# The dominant cause is a DEPENDENCY, not a platform bug: macOS python3 ships PyYAML
# and a bare debian image does not, so `import yaml` raises here and the whole
# arbiter dies mute. Splitting the four loads costs nothing and turns a silent rc=2
# into a sentence naming which input could not be read. rc stays 2 -- callers already
# treat it as the fail-open-to-ladder signal (leadv2-dispatch-code.sh arbiter_broken)
# and changing it would change routing behaviour, which this fix must not do.
#
# 2026-09-09 second half of the same row: naming the dependency still left every
# arbiter-dependent CI suite (Linux) unable to route -- a loud refusal is better
# than a mute one, but it is still a refusal. PyYAML is now OPTIONAL: when it is
# missing, a strict stdlib YAML-SUBSET loader takes over (parse-or-refuse, never
# guess -- it raises on any construct outside the subset instead of approximating
# it). Both shipped configs (leadv2-routing.yaml, freepool-arm.yaml) are inside
# the subset; a future config that grows anchors/aliases/block-scalars gets a
# LOUD yaml_subset_unsupported naming the line, and installing python3-yaml
# restores full PyYAML. LEADV2_ROUTE_ARBITER_YAML_LOADER pins the choice:
# auto (default; PyYAML if importable, else subset) | pyyaml (demand the real
# dependency; pyyaml_missing stays a hard rc=2) | stdlib (force the subset even
# when PyYAML is present -- the differential-test seam that keeps the two
# loaders byte-identical on the real configs).
def _fatal(reason, detail, hint=''):
    sys.stderr.write('[route-arbiter] FATAL rc=2 reason=%s detail=%s%s\n'
                     % (reason, detail, (' hint=%s' % hint) if hint else ''))
    raise SystemExit(2)


class _YamlSubsetError(ValueError):
    pass


def _strip_comment(line):
    # '#' at start or after whitespace, OUTSIDE quotes. Both shipped configs
    # are verified to contain no '#' inside quoted scalars, so quote tracking
    # here is exact for them and conservative (refuses nothing valid) for
    # anything else that reaches this loader.
    q = None
    for i, ch in enumerate(line):
        if q:
            if ch == q:
                q = None
        elif ch in ('"', "'"):
            q = ch
        elif ch == '#' and (i == 0 or line[i - 1] in (' ', '\t')):
            return line[:i]
    return line


def _plain_scalar(tok, where):
    tok = tok.strip()
    if tok == '':
        raise _YamlSubsetError('%s: empty scalar' % where)
    if tok[0] in ('"', "'"):
        if len(tok) < 2 or tok[-1] != tok[0] or tok[0] in tok[1:-1]:
            raise _YamlSubsetError('%s: unsupported quoted scalar %r' % (where, tok))
        return tok[1:-1]
    if tok[0] in '{[,':
        raise _YamlSubsetError('%s: stray flow punctuation %r' % (where, tok))
    if tok in ('null', '~'):
        return None
    if tok == 'true':
        return True
    if tok == 'false':
        return False
    if re.match(r'^-?\d+$', tok):
        return int(tok)
    if re.match(r'^-?(\d+\.\d*|\.\d+)$', tok):
        return float(tok)
    for i, ch in enumerate(tok):
        # ':' is legal inside a plain scalar (urls) only when NOT followed by
        # space/EOL; ': ' here means an inline map we do not support.
        if ch == ':' and (i + 1 == len(tok) or tok[i + 1] == ' '):
            raise _YamlSubsetError('%s: unsupported inline mapping %r' % (where, tok))
        if ch in '{}[]':
            raise _YamlSubsetError('%s: flow punctuation in plain scalar %r' % (where, tok))
    return tok


def _split_flow(s, where):
    # top-level commas of a flow construct body (nesting/quotes respected)
    parts, depth, q, cur = [], 0, None, []
    for ch in s:
        if q:
            cur.append(ch)
            if ch == q:
                q = None
        elif ch in ('"', "'"):
            q = ch
            cur.append(ch)
        elif ch in '[{':
            depth += 1
            cur.append(ch)
        elif ch in ']}':
            depth -= 1
            cur.append(ch)
        elif ch == ',' and depth == 0:
            parts.append(''.join(cur))
            cur = []
        else:
            cur.append(ch)
    if q is not None or depth != 0:
        raise _YamlSubsetError('%s: unbalanced flow construct %r' % (where, s))
    if cur or parts:
        parts.append(''.join(cur))
    return parts


def _flow_value(s, where):
    s = s.strip()
    if s == '':
        raise _YamlSubsetError('%s: empty flow item' % where)
    if s[0] == '{' and s[-1] == '}':
        d = {}
        inner = s[1:-1].strip()
        if inner == '':
            return d
        for item in _split_flow(inner, where):
            if ':' not in item:
                raise _YamlSubsetError('%s: flow map item without colon %r' % (where, item))
            k, v = item.split(':', 1)
            k = k.strip()
            if not re.match(r'^[A-Za-z0-9_.-]+$', k):
                raise _YamlSubsetError('%s: non-plain flow key %r' % (where, k))
            v = v.strip()
            d[k] = _flow_value(v, where) if v else None
        return d
    if s[0] == '[' and s[-1] == ']':
        inner = s[1:-1].strip()
        if inner == '':
            return []
        return [_flow_value(p, where) for p in _split_flow(inner, where)]
    return _plain_scalar(s, where)


def _map_entry(content, ln):
    # 'key: value' / 'key:' -> (key, rest); refuses quoted/flow keys (the
    # shipped configs use none) and everything else loudly.
    q = None
    for i, ch in enumerate(content):
        if q:
            if ch == q:
                q = None
        elif ch in ('"', "'"):
            q = ch
        elif ch == ':' and (i + 1 == len(content) or content[i + 1] == ' '):
            key = content[:i].strip()
            if not re.match(r'^[A-Za-z0-9_.-]+$', key):
                raise _YamlSubsetError('line %d: unsupported key %r' % (ln, key))
            return key, content[i + 1:].strip()
    raise _YamlSubsetError('line %d: not a map entry %r' % (ln, content))


def _parse_map(lines, idx, indent):
    out = {}
    i = idx
    while i < len(lines):
        ind, content, ln = lines[i]
        if ind < indent:
            break
        if ind > indent:
            raise _YamlSubsetError('line %d: unexpected indent under mapping' % ln)
        if content.startswith('- ') or content == '-':
            raise _YamlSubsetError('line %d: list item where mapping entry expected' % ln)
        key, rest = _map_entry(content, ln)
        if rest == '':
            # block value on deeper lines, or a same-indent list (legal YAML,
            # used by model_rank:), else null
            if i + 1 < len(lines) and lines[i + 1][0] > ind:
                out[key], i = _parse_block(lines, i + 1, lines[i + 1][0])
                continue
            if i + 1 < len(lines) and lines[i + 1][0] == ind \
                    and (lines[i + 1][1] == '-' or lines[i + 1][1].startswith('- ')):
                out[key], i = _parse_list(lines, i + 1, ind)
                continue
            out[key] = None
            i += 1
            continue
        if rest[0] in ('&', '*', '!', '|', '>') or rest == '<<:' or rest.startswith('<<:'):
            raise _YamlSubsetError('line %d: unsupported construct %r (anchors/aliases/tags/block scalars/merge keys are outside the subset)' % (ln, rest))
        if rest[0] in ('{', '['):
            out[key] = _flow_value(rest, 'line %d' % ln)
            i += 1
            continue
        out[key] = _plain_scalar(rest, 'line %d' % ln)
        i += 1
    return out, i


def _parse_list(lines, idx, indent):
    out = []
    i = idx
    while i < len(lines):
        ind, content, ln = lines[i]
        if ind < indent or not (content.startswith('- ') or content == '-'):
            break
        if ind > indent:
            raise _YamlSubsetError('line %d: unexpected indent under sequence' % ln)
        rest = '' if content == '-' else content[2:].strip()
        if rest == '':
            if i + 1 < len(lines) and lines[i + 1][0] > ind:
                _v, i = _parse_block(lines, i + 1, lines[i + 1][0])
                out.append(_v)
            else:
                out.append(None)
                i += 1
        elif rest[0] in ('"', "'") or rest[0] in '{[':
            # quoted/flow item -- no inline map possible
            out.append(_flow_value(rest, 'line %d' % ln))
            i += 1
        else:
            try:
                key, vrest = _map_entry(rest, ln)
            except _YamlSubsetError:
                out.append(_flow_value(rest, 'line %d' % ln))
                i += 1
                continue
            if vrest == '' and not (i + 1 < len(lines) and lines[i + 1][0] >= ind + 2):
                out.append(None)
                i += 1
                continue
            # '- key: value' -- a mapping item; its continuation lines sit at
            # the column where the key starts (ind + 2). Synthesize the first
            # entry at that indent and let _parse_map own the rest.
            lines[i] = (ind + 2, rest, ln)
            val, i = _parse_map(lines, i, ind + 2)
            out.append(val)
    return out, i


def _parse_block(lines, idx, indent):
    if lines[idx][1] == '-' or lines[idx][1].startswith('- '):
        return _parse_list(lines, idx, indent)
    return _parse_map(lines, idx, indent)


def _stdlib_yaml_loads(text):
    lines = []
    for n, raw in enumerate(text.split('\n'), 1):
        lead = raw[:len(raw) - len(raw.lstrip(' '))]
        if '\t' in lead:
            raise _YamlSubsetError('line %d: tab in indentation' % n)
        line = _strip_comment(raw).rstrip()
        if not line.strip():
            continue
        ind = len(line) - len(line.lstrip(' '))
        content = line.strip()
        if content in ('---', '...'):
            raise _YamlSubsetError('line %d: multi-document marker %r' % (n, content))
        lines.append((ind, content, n))
    if not lines:
        return None
    val, idx = _parse_block(lines, 0, lines[0][0])
    if idx != len(lines):
        raise _YamlSubsetError('line %d: unexpected content after top-level block' % lines[idx][2])
    return val


class _Lv2StdlibYaml(object):
    # Drop-in for the two yaml.safe_load call sites below. PARSE-OR-REFUSE:
    # anything outside the verified subset raises _YamlSubsetError with the
    # line number -- this loader never approximates a construct.
    __name__ = 'leadv2-stdlib-yaml-subset'

    @staticmethod
    def safe_load(fh):
        return _stdlib_yaml_loads(fh.read())


_loader_mode = (os.environ.get('LEADV2_ROUTE_ARBITER_YAML_LOADER') or 'auto').strip().lower()
if _loader_mode not in ('auto', 'pyyaml', 'stdlib'):
    _fatal('yaml_loader_mode_invalid',
           "LEADV2_ROUTE_ARBITER_YAML_LOADER='%s' (expected auto|pyyaml|stdlib)" % _loader_mode)
_pyyaml_err = None
try:
    import yaml as _pyyaml_mod
except Exception as _e:
    _pyyaml_mod = None
    _pyyaml_err = _e
if _loader_mode == 'pyyaml' and _pyyaml_mod is None:
    _fatal('pyyaml_missing', '%s: %s' % (type(_pyyaml_err).__name__, _pyyaml_err),
           'install PyYAML (apt: python3-yaml, pip: pyyaml), or leave LEADV2_ROUTE_ARBITER_YAML_LOADER unset to allow the stdlib subset loader.')
if _pyyaml_mod is None or _loader_mode == 'stdlib':
    if _pyyaml_mod is None:
        sys.stderr.write('[route-arbiter] NOTE: PyYAML unavailable (%s: %s) -- strict stdlib YAML-subset loader active (parse-or-refuse). Install python3-yaml to restore full PyYAML.\n'
                         % (type(_pyyaml_err).__name__, _pyyaml_err))
    yaml = _Lv2StdlibYaml
else:
    yaml = _pyyaml_mod
try:
    data=yaml.safe_load(open(sys.argv[1])) or {}
except _YamlSubsetError as _e:
    _fatal('yaml_subset_unsupported', '%s path=%s' % (_e, (sys.argv[1] if len(sys.argv) > 1 else '<none>')),
           'this routing yaml uses constructs beyond the stdlib subset; install PyYAML (apt: python3-yaml, pip: pyyaml) to read it')
except Exception as _e:
    _fatal('routing_yaml_unreadable', '%s: %s path=%s' % (type(_e).__name__, _e, (sys.argv[1] if len(sys.argv) > 1 else '<none>')))
try:
    d=json.loads(os.environ['ROUTE_ARBITER_DESCRIPTOR'])
except Exception as _e:
    _fatal('descriptor_unreadable', '%s: %s' % (type(_e).__name__, _e))
try:
    q=json.loads(os.environ['ROUTE_ARBITER_QUOTA'])
except Exception as _e:
    _fatal('quota_unreadable', '%s: %s' % (type(_e).__name__, _e))
role=os.environ['ROUTE_ARBITER_ROLE']; free_ok=os.environ.get('ROUTE_ARBITER_FREEPOOL_RC')=='0'
# FREEPOOL-DEAD-ARM-LOOKS-LIKE-A-BUSY-ARM-01: the gate's named refusal reason
# (arm_down|gate_broken|pin_drift), parsed upstream from the gate's stderr
# marker. This is the difference between "dead" and "busy": pct below stays a
# NUMBER (sort/capped semantics unchanged — a dead freepool must still lose
# selection), but the RENDERING below turns arm_down into the word `down` so
# the decision line can never present a dead arm as a 100%-busy one.
free_reason=str(os.environ.get('ROUTE_ARBITER_FREEPOOL_REASON') or '').strip()
# T17 fix-round (C1): normalize kind to the matrix vocabulary. Real callers
# pass fanout-class-funnel / backlog-pump (now first-class matrix entries,
# see config/leadv2-routing.yaml) plus the abstract code|docs|review|plan|
# audit|safety set. Any OTHER value (a future caller, a typo) falls open to
# `code` rather than refusing -- this is a second, defensive layer under the
# matrix rows, never the caller's only path to a capable cell.
KNOWN_KINDS={'code','docs','review','plan','audit','safety','fanout-class-funnel','backlog-pump','build','recon'}
# ROUTING-EVERY-SPAWN-THROUGH-THE-ARBITER-01 (founder 2026-09-04): the lead-facing
# spelling is `work_kind` -- task-judge.sh already emits build|review|diagnose|docs
# under that key. `kind` stays accepted for the existing dispatch-code callers.
# `build` folds onto the existing `code` cells, so build routing is unchanged by
# construction. `recon` (read-only exploration) is a first-class kind with its own
# cheap matrix rows (config/leadv2-routing.yaml), not a code branch.
kind=str(d.get('work_kind') or d.get('kind') or 'code').lower()
# ARBITER-UNKNOWN-BECOMES-A-DEFAULT-IN-FIVE-DECISIONS-01 (D5): an unrecognised
# work_kind is coerced to 'code' so routing still happens -- but the decision
# line then PRINTS kind=code, so a wrong value looks like a right one and the
# journal cannot be used to find the mismatch. This is live, not theoretical:
# leadv2-task-judge.sh:200 really emits work_kind='diagnose', and 'diagnose' is
# not in KNOWN_KINDS, so every diagnose task has been routing as ordinary code.
# Same treatment the SIZE vocabulary already got at :137/:666 (`size_unmapped`):
# keep the fail-open coercion, and say out loud that it happened.
kind_unmapped = None if kind in KNOWN_KINDS else kind
if kind not in KNOWN_KINDS: kind='code'
MATRIX_KIND={'build':'code'}  # recon keeps its own name -- it has its own rows
mkind=MATRIX_KIND.get(kind,kind)
# T17 fix-round (M1): the full --task-class vocabulary is six values
# (trivial|light|standard|heavy|strategic|bulk, dispatch-code.sh usage line
# 5350); the matrix only expresses three buckets. Map every real value
# instead of silently coercing an unrecognized one to 'standard' -- a
# 'strategic' task was landing on the freepool bucket (the cheapest 'bulk'
# cell) before this fix, the opposite of intent.
SIZE_MAP={'standard':'standard','heavy':'heavy','bulk':'bulk','trivial':'standard','light':'standard','strategic':'heavy'}
size_raw=str(d.get('size',d.get('task_class','standard'))).lower()
size_unmapped = None if size_raw in SIZE_MAP else size_raw
size=SIZE_MAP.get(size_raw,'standard')
# ARMS-ADMISSION-01: `protected` alone (the lane-protected/--protected signal)
# means "this LANE writes production code under a protected path" -- it must
# NOT ban an untrusted arm from work that writes nothing dangerous (review,
# audit, plan/discovery). safety/publish/ui_judgment stay a HARD requirement
# regardless of kind -- those are about the CONTENT being touched, not the
# lane. `require_trusted` folds both into the cell filter below; `protected`
# itself is kept (unchanged name/shape) for the existing output/journal callers.
_prot_flag=bool(d.get('protected'))
_hard_flag=any(bool(d.get(k)) for k in ('safety','publish','ui_judgment'))
protected=_prot_flag or _hard_flag
# recon is read-only exploration: it never writes production code, so the
# protected-lane rule must not ban a cheap untrusted arm from it.
writes_prod = kind not in ('review','audit','plan','recon')
require_trusted = _hard_flag or (_prot_flag and writes_prod)
allowed_raw=d.get('allowed_arms')
allowed={str(a) for a in allowed_raw} if isinstance(allowed_raw, list) else None
def num(x):
    try:return float(x)
    except:return None
# CLASSIFIER-MUST-SEE-QUOTA-AND-RESET-DATE-01 (founder, 2026-09-03): the arbiter
# previously scored ONLY the raw used-pct of a provider's binding window --
# capped()/util() below never looked at WHEN that window resets, so "85%
# burned, resets in 20 minutes" and "85% burned, resets in 4 days" produced the
# identical verdict (switch away). leadv2-quota-read.py already computes
# hours_to_reset per window (normalize_window/with_window_truth, T1,
# leadv2-quota-read.py:113-142) and ships it inside the same JSON this arbiter
# already fetches from quota-live -- glm/codex/anthropic each publish their own
# reset_iso already (kimi is not a live build arm -- config/leadv2-routing.yaml
# marks it `dispatch: false` -- so it carries no reset to read). No new fetcher
# needed; window_period_hours/window_reset below only READ that existing field.
#
# Wait-vs-switch threshold: 10% of the WINDOW'S OWN period. Argued from the
# two live period shapes (5h burst window, 7d/168h weekly window), not picked
# -- CODEX-TIER-100-NO-BURST-WINDOW-01 (founder, 2026-09-06): codex no longer HAS
# a 5h burst window; its live probe reports a single 168h weekly window. Both
# shapes below still exist (glm and anthropic keep a 5h window), so the threshold
# argument stands as written -- but for codex only the 7d arm applies, which means
# an over-ceiling codex is now waited on for up to 16.8h instead of switched away
# from. That consequence is tracked as its own backlog row; this note does NOT say
# the wait is capped, because it is not.
# free-hand -- it reproduces both founder examples exactly:
#   20 min left on a 5h window  (0.1*5h=30min)  -> 20<=30  -> WAIT
#   4 days left on a 7d window  (0.1*168h=16.8h) -> 96>16.8 -> SWITCH
# A window whose own reset cannot be read (absent/malformed reset_iso) degrades
# to that window's FULL period as hours_to_reset -- a named, defensible default
# that is always > the 10% threshold, so an unknown reset always reads as "far"
# and can never fabricate an imminent wait. Never a silent zero.
#
# CLASSIFIER-MUST-SEE-QUOTA-AND-RESET-DATE-01 fix-round item 1: an unknown
# window NAME must NOT degrade the same way as an unknown RESET. The two are
# opposite-direction failures. An unreadable reset defaults to the window's
# own (known) full period -- always "far", so it can only ever push us to
# switch, never fabricate a wait. But an unknown NAME has no known period at
# all: silently assuming DEFAULT_PERIOD_HOURS=168h (the old behaviour, now
# removed) made every genuinely SHORT unknown window look like a 168h window,
# so its threshold became 16.8h and a real 20-minute-to-reset window read as
# "near" and WAITED on an over-ceiling provider instead of switching away --
# the harmful direction, because it holds a burnt provider in the chain.
# Fix: window_period_hours() returns None for an unknown name (no
# limit_window_seconds either), and window_reset() reports period_hours=None
# with reset_basis='unknown_window' (never 'default_full_period', which means
# a DIFFERENT case: a known period, unreadable reset). near_reset_wait()
# already treats period_hours is None as False, so an unknown window name
# switches away -- exactly the pre-change behaviour -- and reset_basis
# surfaces which of the two unknowns produced the verdict.
WAIT_FRACTION_OF_PERIOD=0.10
WINDOW_PERIOD_HOURS={'five_hour':5.0,'weekly':168.0,'seven_day':168.0}
def window_period_hours(name, window):
    lws=num((window or {}).get('limit_window_seconds'))
    if lws is not None: return lws/3600.0
    return WINDOW_PERIOD_HOURS.get(name)
def window_reset(name, window):
    period=window_period_hours(name, window)
    h=num((window or {}).get('hours_to_reset'))
    if period is None: return h, None, 'unknown_window'
    if h is not None: return h, period, 'live'
    return period, period, 'default_full_period'
# D14 store: filled by util() when a provider's headroom was read from only
# SOME of its windows. Printed on the decision line; never consulted by the
# routing choice, so this records the fact without changing any outcome.
_partial_windows={}
# W1-FORECAST-THE-SPEND-01 store: every READABLE window per provider, filled
# by util() beside _partial_windows. The binding (worst-pct) window alone
# cannot answer "does the next task fit" -- the 5h window can be the tighter
# container while weekly binds on pct -- so the forecast below needs them all.
_allwin={}
def util(provider):
    # T17 fix-round (C3): a provider whose probe is broken/unknown must be
    # PESSIMISTIC (maximally capped), never the cheapest-looking arm. The old
    # `return 0.0` on status!='ok' made a dead probe sort to the front of
    # every cost/util comparison and win selection forever -- reproduced 3/3
    # in the round-1 review with every real arm healthy. freepool is
    # unaffected: its own gate (free_ok) already encodes this correctly.
    # FP-08 fix-round (H1): the capability floor does NOT live here. util() is
    # a quota number; the selector ranks by EFFECTIVE COST first (the sort's
    # dominant key below). The previous attempt raised util_freepool by +50
    # here, which only tie-breaks against glm (same cost tier) and does
    # nothing against codex (cost 3..7) or sonnet (cost 5) -- falsified by the
    # round-1 live probe (freepool still selected with util_freepool=50).
    # The demotion now happens on the effective cost, right before the sort.
    empty={'pct':0.0,'unknown':False,'hours_to_reset':None,'period_hours':None,'reset_basis':'n/a','usable_now':None}
    if provider=='freepool':
        return dict(empty, pct=(0.0 if free_ok else 100.0),
                    status=('ok' if free_ok else ('down' if free_reason=='arm_down' else (free_reason or 'unknown'))))
    x=q.get('anthropic' if provider=='claude' else provider,{})
    if provider!='claude' and x.get('status')!='ok': return dict(empty, pct=100.0, unknown=True)
    if provider=='glm':
        windows={k:(x.get(k) or {}) for k in ('five_hour','weekly')}; pct_key='pct'
    elif provider=='codex':
        if x.get('limit_reached'): return dict(empty, pct=100.0)
        ws=x.get('windows') or []
        windows={(w.get('kind') or 'w%d'%i):w for i,w in enumerate(ws)}; pct_key='used_percent'
    else:
        # ARBITER-DECISION-LOGIC-CENSUS-01: the `active` flag names which
        # account CREDENTIAL the session resolved to -- it is not proof that
        # account's probe succeeded. Measured 2026-09-04: the active-flagged
        # max_20x entry read http 401 (status=unknown, every pct null) while
        # a DIFFERENT, non-active max_20x entry for the same account_label
        # carried the real, freshly-probed pct. The old code took `a` from
        # the active flag unconditionally, so a broken active credential fed
        # nulls into every window below and this function returned the
        # optimistic `empty` (pct=0.0) at line ~181 -- "claude is free" -- while
        # a probed 72%/48% sat one field over, unread. Prefer the active
        # account only when it actually reports ok; otherwise fall back to a
        # DIFFERENT account with status=='ok' -- same account_label first (the
        # true measurement for the account we believe we're using), then any
        # ok account, before ever falling to the pessimistic unknown branch
        # C3 already established for a fully-broken provider.
        accounts=x.get('accounts') or [{}]
        active=next((z for z in accounts if z.get('active')), None)
        ok_accounts=[z for z in accounts if z.get('status')=='ok']
        if active is not None and active.get('status')=='ok':
            a=active
        elif ok_accounts:
            label=(active or {}).get('account_label')
            a=next((z for z in ok_accounts if z.get('account_label')==label), ok_accounts[0])
        else:
            # Consume classify_account_state's producer field. A usage failure
            # alone never grants this state: absent/unknown keeps the penalty.
            unmetered=[z for z in accounts if z.get('account_state')=='unmetered']
            if unmetered:
                return dict(empty, pct=100.0, account_state='unmetered',
                            priced_from='configured_allowance_conservative')
            return dict(empty, pct=100.0, unknown=True)
        windows={'five_hour':(a.get('five_hour') or {'pct':a.get('five_hour_pct'),'reset_iso':a.get('five_hour_reset_iso')}),
                 'seven_day':(a.get('seven_day') or {'pct':a.get('seven_day_pct'),'reset_iso':a.get('seven_day_reset_iso')})}
        pct_key='pct'
    # The BINDING (worst-case, highest-used) window decides both the pct AND
    # -- new -- travels its own reset/period with it, so a provider with two
    # windows never borrows one window's pct with a DIFFERENT window's clock.
    best_name,best_pct,best_window=None,None,None
    # D14: a window whose pct is unreadable is SKIPPED, so "the binding window"
    # below means "the worst of the windows we could read", not "the worst
    # window". With weekly unreadable and five_hour at 10%, this function says
    # 10% and nothing anywhere says weekly was never consulted. The skip stays
    # (refusing on one unreadable window would bench a provider we can partly
    # see), but the fact is recorded and printed -- unknown is a third value,
    # and a third value that only lives in a local variable is not one.
    _skipped=[]
    for name,w in windows.items():
        p=num((w or {}).get(pct_key))
        if p is None: _skipped.append(name); continue
        if best_pct is None or p>best_pct: best_name,best_pct,best_window=name,p,w
    if best_pct is not None and _skipped:
        _partial_windows.setdefault(provider, sorted(_skipped))
    # ARBITER-UNKNOWN-BECOMES-A-DEFAULT-IN-FIVE-DECISIONS-01: windows existed but
    # not one carried a number. That is the instrument failing to answer, exactly
    # like `status != ok` (:14) and "no ok account" (:260) -- both of which return
    # pct=100 unknown=True. This branch alone returned `empty`, i.e. pct=0.0 with
    # unknown=FALSE: "this provider is completely free, and we are sure of it".
    # Three exits of one function answered the same not-knowing three different
    # ways. Returning unknown here is safe now precisely because unknown no longer
    # means capped (:349): the arm stays in the candidate set and is demoted by
    # UNKNOWN_PROBE_PENALTY, so this cannot resurrect the `all_arms_capped`
    # deaths -- it only stops a silent provider from outranking a measured one.
    if best_pct is None: return dict(empty, pct=100.0, unknown=True)
    # W1-FORECAST-THE-SPEND-01: stash every window whose pct was READABLE
    # (same skip rule as the binding loop above) for the spend forecast.
    _aw=[]
    for _n,_w in windows.items():
        _p2=num((_w or {}).get(pct_key))
        if _p2 is not None: _aw.append((_n,_p2,_w))
    if _aw: _allwin.setdefault(provider,_aw)
    h,period,basis=window_reset(best_name,best_window)
    # ARBITER-QUOTA-IS-A-CLIFF-NOT-A-GRADIENT-01: carry the BINDING window's
    # usable_now (remaining percentage-points per hour, produced upstream by
    # leadv2-quota-read.py:135 as remaining/max(hours,1)). Same window that
    # decides pct, so the rate and the level can never come from two clocks.
    return {'pct':best_pct,'unknown':False,'hours_to_reset':h,'period_hours':period,'reset_basis':basis,
            'usable_now':(best_window or {}).get('usable_now')}
_uraw={p:util(p) for p in ('glm','codex','claude','freepool')}
u={p:_uraw[p]['pct'] for p in _uraw}; unk={p:_uraw[p]['unknown'] for p in _uraw}
usable={p:_uraw[p].get('usable_now') for p in _uraw}
def near_reset_wait(provider):
    info=_uraw[provider]; h=info.get('hours_to_reset'); period=info.get('period_hours')
    if h is None or period is None: return False
    return h <= (period * WAIT_FRACTION_OF_PERIOD)
# W1-FORECAST-THE-SPEND-01 (founder order 2026-09-09, PRE-WAVES-PLAN §1.4):
# the arbiter read the windows (util/window_reset/near_reset_wait above) but
# never asked whether the task it is about to dispatch FITS what is left --
# at util=59% it dispatched work able to push the five-hour window past 100%
# before its reset (live 2026-09-09: util_claude=59 reset_claude=54.48h_live,
# weekly binding, the 5h window free to be overdrawn). This block adds the
# missing half: an EXPECTED SPEND, compared against the REMAINDER of every
# readable window of the candidate provider -- every window, not just the
# binding one, because that live case is a NON-binding window being the
# dangerous one.
#
# The estimate is MEASURED, never a free-hand constant:
#   expected_hours = p90 of wall-clock spawn->terminal durations of that
#     provider's arms, read from the SAME events journal failure memory
#     already reads (ROUTE_ARBITER_EVENTS_JOURNAL: worker_spawned/
#     worker_terminal rows; live 2026-09-09: claude n=189 p90=5.52h,
#     glm n=196 p90=3.61h, codex n=51 p90=6.46h). Below FORECAST_MIN_ROWS
#     joined rows there is no basis and the check is skipped LOUDLY
#     (forecast_basis=no_history): refusing dispatch on zero evidence is not
#     a forecast. An explicit descriptor `expected_hours` (a caller that
#     knows better, a pinned long task, or a test) overrides the journal
#     (basis=descriptor).
# The window translation is a definition, not a constant: a rolling window
# of period P sustains exactly 100/P pct-points per hour (burn more on
# average and it is over the window forever), so a task expected to run H
# hours costs H/P*100 pct-points of that window at the sustainable rate --
# H=3h is 60 pct-points of a 5h window and 1.8 of a 168h one. The
# descriptor's size/duration_class/write_set_files ride as provenance tokens
# only: journal rows carry no class and no write-set, so keying the estimate
# on them would be a guess dressed as a measurement.
# Fit rule: forecast <= remainder on EVERY readable window. A failing window
# whose own reset is within WAIT_FRACTION_OF_PERIOD of ITS OWN period reuses
# the existing wait-vs-switch rule (0.5h for a 5h window, 16.8h for codex's
# single weekly window per CODEX-TIER-100-NO-BURST-WINDOW-01) and the
# provider WAITS (stays eligible, wait_applied=) instead of switching; a far
# reset switches (stage `forecast`); when every eligible arm fails the fit
# the arbiter refuses loudly: rc=3, reason=forecast_exceeds_window, naming
# the window, its remainder and the forecast. Rollback is one flag:
# LEADV2_ARBITER_SPEND_FORECAST=0.
FORECAST_ON=os.environ.get('LEADV2_ARBITER_SPEND_FORECAST','1')!='0'
FORECAST_MIN_ROWS=3
def _arm_to_provider(a):
    # Same prefix families leadv2-cost-flush.sh's _cost_provider_for_model
    # already maps -- derived, not reinvented.
    a=str(a or '').lower()
    if a.startswith(('opus','sonnet','haiku','fable','claude')): return 'claude'
    if a.startswith('glm'): return 'glm'
    if a.startswith(('codex','gpt')): return 'codex'
    return None
def _journal_durations():
    # -> ({provider: [hours...]}, status ok|unavailable). A terminal is
    # attributed to the LAST spawn of its task at or before it -- the same
    # attribution rule read_failure_memory uses: one journal, one rule.
    evt=os.environ.get('ROUTE_ARBITER_EVENTS_JOURNAL') or ''
    import datetime
    def _ts(s):
        try: return datetime.datetime.strptime(s,'%Y-%m-%dT%H:%M:%SZ')
        except Exception: return None
    try:
        by_task={}; terms=[]
        with open(evt) as _f:
            for _l in _f:
                try: r=json.loads(_l)
                except Exception: continue
                k=r.get('kind')
                if k=='worker_spawned':
                    by_task.setdefault(str(r.get('task') or ''),[]).append((str(r.get('ts') or ''), str(r.get('arm') or '')))
                elif k=='worker_terminal':
                    terms.append((str(r.get('ts') or ''), str(r.get('task') or '')))
    except Exception:
        return {}, 'unavailable'
    for _lst in by_task.values(): _lst.sort()
    terms.sort()
    out={}
    for tts,task in terms:
        _lst=by_task.get(task) or []
        prev=None
        for sts,arm in _lst:
            if sts<=tts: prev=(sts,arm)
            else: break
        if prev is None: continue
        t,s=_ts(tts),_ts(prev[0])
        if t is None or s is None: continue
        h=(t-s).total_seconds()/3600.0
        if h<0 or h>=720: continue   # clock garbage or a wedged week: neither is a forecast
        p=_arm_to_provider(prev[1])
        if p: out.setdefault(p,[]).append(h)
    return out,'ok'
def _p90(xs):
    xs=sorted(xs)
    if not xs: return None
    return xs[max(0,int(math.ceil(0.9*len(xs)))-1)]
_fc_durs={}; _fc_jstat='off'
if FORECAST_ON: _fc_durs,_fc_jstat=_journal_durations()
_fc_cache={}
def _expected_hours_for(provider):
    if provider in _fc_cache: return _fc_cache[provider]
    _e=num(d.get('expected_hours'))
    if _e is not None and _e>0:
        r=(_e,'descriptor')
    elif _fc_jstat=='unavailable':
        r=(None,'journal_unavailable')
    elif _fc_jstat!='ok':
        r=(None,'no_history')
    else:
        xs=(_fc_durs.get(provider) or [])
        if len(xs)>=FORECAST_MIN_ROWS:
            r=(_p90(xs),'journal:provider=%d'%len(xs))
        else:
            al=[_h for _v in _fc_durs.values() for _h in _v]
            r=(_p90(al),'journal:all=%d'%len(al)) if len(al)>=FORECAST_MIN_ROWS else (None,'no_history')
    _fc_cache[provider]=r
    return r
_forecast_view={}; _forecast_block={}; _forecast_wait=[]; _forecast_skipped={}
def _forecast_check(provider):
    # One view per provider: the estimate's hours+basis, every failing
    # window, the worst of them, and whether ALL failures reset soon (the
    # wait rule needs every failing window near -- a far failure is not
    # rescued by a near one).
    if provider not in _allwin: return None
    hours,basis=_expected_hours_for(provider)
    if hours is None: return {'hours':None,'basis':basis,'fails':[],'worst':None,'near_all':False}
    fails=[]
    for name,pct,w in _allwin[provider]:
        h,period,_why=window_reset(name,w)
        if period is None or period<=0:
            _forecast_skipped[provider]='unknown_period:%s'%name
            continue
        fc=hours/period*100.0
        rem=100.0-pct
        if fc > rem:  # fit-vs-remainder (W1-FORECAST-THE-SPEND-01 mutation anchor)
            fails.append({'window':name,'remaining':rem,'forecast':fc,'hours':hours,
                          'period':period,
                          'near':(h is not None and h<=period*WAIT_FRACTION_OF_PERIOD)})
    worst=None
    for f in fails:
        if worst is None or (f['forecast']-f['remaining'])>(worst['forecast']-worst['remaining']): worst=f
    return {'hours':hours,'basis':basis,'fails':fails,'worst':worst,
            'near_all':bool(fails) and all(f['near'] for f in fails)}
def _forecast_refuse():
    # The loud refusal: names the window, its remainder and the forecast that
    # exceeded it. rc=3 is the caller's hard-refusal code (the same code
    # all_arms_capped uses) -- a task that fits no arm's window must not fall
    # open to a ladder that would dispatch it anyway.
    _p,_w=sorted(_forecast_block.items(), key=lambda kv: -(kv[1]['forecast']-kv[1]['remaining']))[0]
    _record('refuse','none','none','forecast_exceeds_window')
    print('arm=refuse model=none tier=none reason=forecast_exceeds_window kind=%s window=%s remaining=%.1fpct forecast=%.1fpct forecast_hours=%.2fh forecast_basis=%s chain= %s%s%s%s%s' % (kind,_w['window'],_w['remaining'],_w['forecast'],_w['hours'],_forecast_view[_p]['basis'],ufmt(),_outage,_fm_tok,_excl_render(),_rev_tok))
    raise SystemExit(3)
if FORECAST_ON:
    for _p in ('glm','codex','claude'):
        _v=_forecast_check(_p)
        if _v is None: continue
        _forecast_view[_p]=_v
        if _v['fails']:
            _forecast_block[_p]=_v['worst']
            if _v['near_all']: _forecast_wait.append(_p)
# FP-08 fix-round (M1): the floor keys on the RAW --task-class, not the
# SIZE_MAP-folded bucket. trivial|light ("simple") fold into the 'standard'
# matrix cell for CAPABILITY lookups but must stay freepool-eligible, and
# bulk is exempt by design; strategic folds into 'heavy' and IS floored.
# FP-06 (founder ask 2026-08-28): capability_floor knob -- bulk_only (the
# default) preserves the FP-08 rule verbatim; full removes the floor so
# freepool is rank-eligible for Standard/Heavy build work. Precedence:
# env FREEPOOL_CAPABILITY_FLOOR > freepool-arm.yaml capability_floor >
# default. An unrecognized value at either layer falls through to the next
# layer -- fail toward today's floored behavior, never silently unfloored.
floor_mode='bulk_only'; floor_mode_src='default'
_env_mode=str(os.environ.get('FREEPOOL_CAPABILITY_FLOOR','') or '').strip().lower()
if _env_mode in ('bulk_only','full'):
    floor_mode=_env_mode; floor_mode_src='env'
else:
    try:
        _arm_cfg_path=os.environ.get('FREEPOOL_ARM_CONFIG') or os.path.join(os.path.dirname(os.path.abspath(sys.argv[1])),'freepool-arm.yaml')
        _arm_cfg=yaml.safe_load(open(_arm_cfg_path)) or {}
        _yaml_mode=str((_arm_cfg.get('capability_floor') if isinstance(_arm_cfg,dict) else None) or '').strip().lower()
        if _yaml_mode in ('bulk_only','full'):
            floor_mode=_yaml_mode; floor_mode_src='yaml'
    except Exception:
        pass
# FREEPOOL-MUST-ACTUALLY-GET-WORK-01: the FP-08 floor still protects
# strategic production work, but a dispatcher-proven tests/docs-only lane is
# mechanical verification work and must compete at its real cost. Missing the
# descriptor flag is conservative: test_only defaults false and the floor
# remains exactly as before.
test_only=bool(d.get('test_only'))
floor_applies = (size_raw in ('standard','heavy','strategic') and mkind == 'code' and not test_only) if floor_mode=='bulk_only' else False
def ufmt():
    # FREEPOOL-DEAD-ARM-LOOKS-LIKE-A-BUSY-ARM-01: a DOWN freepool renders as
    # the word `down`, never as the number 100 — one number must not carry
    # two facts. Other gate refusals (gate_broken/pin_drift) keep their
    # numeric pct and are named by the freepool_gate= token on the line.
    util_part=' '.join('util_%s=%s' % (p, 'unmetered' if _uraw[p].get('account_state')=='unmetered' else 'unknown_capped' if unk[p] else ('down' if (p=='freepool' and _uraw['freepool'].get('status')=='down') else '%d'%u[p])) for p in ('glm','codex','claude','freepool'))
    reset_part=' '.join('reset_%s=%s' % (p, ('%.2fh_%s' % (_uraw[p]['hours_to_reset'], _uraw[p]['reset_basis'])) if _uraw[p].get('hours_to_reset') is not None else 'n/a') for p in ('glm','codex','claude','freepool'))
    return util_part + ' ' + reset_part
ceil=((data.get('router_v2') or {}).get('quota_ceilings') or {})
def over_ceiling(provider):
    if provider=='freepool': return not free_ok
    key='claude' if provider=='claude' else provider
    c=(ceil.get(key) or {}).get('review_pct' if role=='reviewer' else 'work_pct',100)
    return u[provider] >= float(c)
# CLASSIFIER-MUST-SEE-QUOTA-AND-RESET-DATE-01: an over-ceiling provider whose
# binding window resets within the wait threshold is NOT excluded -- the task
# waits on it (it stays in `ok` and competes on cost as before, so it is only
# picked again if it is still cheapest) instead of being forced to switch to a
# pricier arm minutes before its own quota would have refreshed anyway. A
# provider that is over ceiling with a FAR reset is unaffected: still capped,
# still switches, exactly today's behaviour.
_waited=[p for p in ('glm','codex','claude') if over_ceiling(p) and near_reset_wait(p)]
# W1-FORECAST-THE-SPEND-01: a forecast-blocked provider whose every failing
# window resets within WAIT_FRACTION_OF_PERIOD of its own period waits too --
# same token, same semantics, one wait rule rather than a second one.
_waited += [p for p in _forecast_wait if p not in _waited]
def capped(provider):
    # ARBITER-REMEMBERS-FAILURES-01 edit B (founder 2026-09-05): `unknown` is a
    # THIRD state, never a synonym for "busy". util() already returns pct=100.0
    # WITH unknown=True when a provider's probe did not answer (the status!='ok'
    # line and the claude branch's no-ok-account fall-through), and `unk` has
    # carried that flag ever since -- but it entered the SELECTION nowhere, so a
    # broken measurer rendered identically to an exhausted quota. Measured
    # 2026-09-04/05: util_codex=unknown_capped in 122 of 143 decisions, codex out
    # for a day, and six lanes killed by `reason=all_arms_capped` when what
    # actually failed was the instrument. An unknown arm is therefore NOT capped
    # -- it stays in the candidate set and is instead DEMOTED on effective cost
    # (UNKNOWN_PROBE_PENALTY below), so it ranks strictly after every arm whose
    # headroom we actually measured and is picked only when the alternative is
    # refusing the work outright. Rejected alternatives: "skip it" is today's bug
    # verbatim; "take it as free" would spend a genuinely burnt provider on the
    # strength of a failed reading.
    if unk.get(provider) or _uraw[provider].get('account_state')=='unmetered': return False
    if over_ceiling(provider) and near_reset_wait(provider):
        return False
    return over_ceiling(provider)
cells=((data.get('router_v2') or {}).get('capability_matrix') or [])
# T17 fix-round (C1): split the config-vocabulary gap ("no cell matches kind/
# size/protected" -- a routing.yaml drift, never a real refusal) from the
# capacity gap ("every matching cell is over its quota ceiling" -- a true
# refusal). The old code raised the same SystemExit(3)/all_arms_capped for
# both, so a config typo like the fanout-class-funnel/backlog-pump miss
# above produced an honest-looking `reason=all_arms_capped util_glm=10` line
# while glm sat at 10% -- a false statement about the world. The caller
# (leadv2-dispatch-code.sh) only special-cases rc=3 all_arms_capped as a
# hard refusal (exit 4); any other non-zero rc already falls open to the
# ladder, so no caller-side change is needed for the split itself.
complexity=str(d.get('complexity','unknown')).lower()
duration_class=str(d.get('duration_class','unknown')).lower()
# ARBITER-SCORING-DESIGN-01 step 1: NEW descriptor key, provenance of `complexity`
# (judge|flag|heuristic|unknown -- design.md §5.1). Absent from an
# older/unpatched caller renders as 'unknown' -> conf 0.0, the cautious default.
complexity_source=str(d.get('complexity_source','unknown')).lower()
# POOL-IS-COMPUTED-AFTER-THE-ARM-IS-CHOSEN-01 (2026-09-07): the single-line
# `capable=` comprehension above is retired. It folded FOUR different facts
# (kind/size fit, trust, caller admissibility) into one silent set, and the
# caller fed it the ladder SUFFIX from an already-resolved arm -- so a pinned
# fable read `requested_arm_incapable ... arm_excluded=fable:not_allowed`
# while fable was not incapable, only never in the room. Eligibility is now
# built as an ordered, TYPED stage list (see _stages below), and `capable` is
# what survives the pre-budget stages.
# GLM-NEVER-WINS-THE-ARBITER-01 (measured 2026-09-05): `reason=cheapest_capable
# chain=sonnet` is a TRUE statement about a candidate set of ONE, and it reads
# exactly like "the cheap arms were considered and lost on price". On 2026-09-03
# the whole glm family was removed by require_trusted BEFORE any price was
# compared -- glm carried `protected: false` in the matrix until GLM-DOES-ANY-
# WORK-01 flipped it on 2026-09-04 -- and the line said nothing about it. The
# defect was therefore filed against the wrong filter twice (task_class Light,
# floor_mode) while the real cutter printed no token at all.
#
# Only TWO clauses of the comprehension above can drop a cell that already fits
# the work's kind AND size: require_trusted and the caller's `allowed` list.
# Those are the silent ones, and those are the ones named here. A kind/size
# mismatch is deliberately NOT reported -- most cells miss on it by design, and
# `kind_unmapped=`/`size_unmapped=` already cover the vocabulary case.
#
# Selection is untouched: this re-reads the same cells and decides nothing.
_fit=[c for c in cells if mkind in c.get('kinds',[]) and size in c.get('sizes',[])]
# POOL-IS-COMPUTED-AFTER-THE-ARM-IS-CHOSEN-01 (2026-09-07): the two-valued
# _arm_excluded map (untrusted|not_allowed) is replaced by an ordered stage
# list, one entry per matrix arm that fits kind/size -- not_in_pool,
# not_launchable, untrusted, capped, forecast, failure_memory, price_ratio --
# joined
# with '+' when several apply, so an operator reads "never eligible" vs
# "never tested" vs "tested and lost" off one line:
#   not_in_pool    -- outside the hard set (arm_pool), the caller's policy
#                     bound (allowed_arms = the when:-class eligible arms),
#                     or the default-auction boundary (matrix cell
#                     pool_default: false -- opus only: it shares the lead's
#                     own account window; explicit pool/pin still reach it).
#   not_launchable -- outside launchable_arms, the caller-side launch-
#                     capability seam (stubbed to the DISPATCHABLE_*_ARMS
#                     sets until sibling lane ARMS-CANNOT-LAUNCH-THEMSELVES-01
#                     lands the registry; do not fork a second registry).
#   untrusted      -- require_trusted and no fitting cell is protected.
_arm_cells={}
for _c in _fit: _arm_cells.setdefault(_c.get('arm'),[]).append(_c)
# requested_arm is parsed HERE now (it used to be parsed further down, after
# the failure memory): the pin participates in pool construction, not just
# the final filter -- an explicit pin overrides the policy/default pool
# boundary (cost policy is exactly what a pin exists to override) but never
# the matrix, launchability, trust or budget.
requested_arm=str(d.get('requested_arm') or '').strip()
arm_pool_raw=d.get('arm_pool')
arm_pool=({str(a).strip() for a in arm_pool_raw if str(a).strip()} if isinstance(arm_pool_raw,list) else None)
launchable_raw=d.get('launchable_arms')
launchable=({str(a).strip() for a in launchable_raw if str(a).strip()} if isinstance(launchable_raw,list) else None)
def _pool_contains(arm):
    if arm_pool is not None: return arm in arm_pool
    if requested_arm and arm==requested_arm: return True
    if allowed is not None: return arm in allowed
    return any(c.get('pool_default',True) is not False for c in _arm_cells.get(arm,[]))
_STAGE_ORDER=['not_in_pool','not_launchable','untrusted','capped','forecast','failure_memory','price_ratio']
_stages={}
def _stage_add(arm,stage):
    _s=_stages.setdefault(arm,[])
    if stage not in _s: _s.append(stage)
for _a in _arm_cells:
    if not _pool_contains(_a): _stage_add(_a,'not_in_pool')
    if launchable is not None and _a not in launchable: _stage_add(_a,'not_launchable')
    if require_trusted and not any(c.get('protected',False) for c in _arm_cells[_a]): _stage_add(_a,'untrusted')
# W1-FORECAST-THE-SPEND-01: the fit verdict is its own typed stage -- a
# forecast-blocked provider with a far reset is switched away exactly like a
# capped one, and a pinned request for such an arm is refused by the pin
# block below through the very same _stages it already consults.
if FORECAST_ON:
    for _a in _arm_cells:
        _pv=next((c.get('provider') for c in _arm_cells[_a]),None)
        if _forecast_block.get(_pv) and _pv not in _forecast_wait:
            _stage_add(_a,'forecast')
def _excl_render():
    # Rendered in the canonical stage order regardless of the order stages
    # were appended in (failure_memory is evaluated before capped, but the
    # token contract is: not_in_pool, not_launchable, untrusted, capped,
    # forecast, failure_memory, price_ratio).
    if not _stages: return ''
    return ' arm_excluded=%s' % ','.join('%s:%s' % (a,'+'.join(sorted(_stages[a],key=_STAGE_ORDER.index))) for a in sorted(_stages))
capable=[c for c in _fit if c.get('arm') not in _stages]
# ...and the pair that makes any of this re-derivable a week later: which BYTES
# of arbiter ran, and which BYTES of matrix it read. Absent only when the digest
# could not be taken, which is itself the honest third value.
_arb_rev=os.environ.get('ROUTE_ARBITER_SELF_REV') or ''
try:
    import hashlib
    _routing_rev=hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest()[:12]
except Exception:
    _routing_rev=''
_rev_tok=((' arb_rev=%s' % _arb_rev) if _arb_rev else '')+((' matrix_rev=%s' % _routing_rev) if _routing_rev else '')
# ARBITER-REMEMBERS-FAILURES-01 edit A (founder 2026-09-05) -- the arbiter must
# remember which arms already failed THIS task.
#
# What was wrong: selection was `reason=cheapest_capable` and nothing else. The
# arbiter kept no record of outcomes, so an arm that had already come up and died
# without writing a line was named again on the next request, at the same cost, by
# construction. Live 2026-09-04/05: GUARDS-SELF-DISABLE-ON-THE-EMPTY-WRITE-SET-01
# went to glm twice with nothing to show and the third resolve said glm again. The
# "glm failed twice -> sonnet" rule existed in prose and in no code path.
#
# What counts as a failure -- the distinction the whole edit turns on. A failure
# is: THE SPAWN HAPPENED AND NO WORK CAME BACK. A refusal BEFORE the spawn is not
# the arm's fault and must never ban it -- writeset_pending/overlap/conflict (the
# registry window), duplicate_task_signature, all_arms_capped, plan_source_absent,
# undiffable_write_set, unscoped_lane_work: each of those is the lane's or the
# gate's shape, and banning a healthy arm for them is how an arm is lost to
# someone else's breakage. Quality rejections (e2e_regression, review_verdict_fail,
# review_dod_fail) are excluded for the opposite reason: work DID come back and was
# judged bad -- a different question from "this arm cannot produce here". The list
# is therefore an ALLOW-list: an unrecognized cause is never counted as a failure.
#
# Where the counter lives: no sixth store. Two journals that already exist carry
# between them exactly what is needed, and neither carries it alone --
#   ~/.claude/leadv2-state/leadv2/dispatch-ledger.jsonl : task_sig + terminal +
#     cause + ts, but NO arm;
#   ~/.claude/cache/leadv2-events/leadv2.jsonl : worker_spawned rows with arm +
#     task + ts (and arm_refused rows, which name the arm directly).
# So a ledger failure at time T for signature S is attributed to the arm of the
# LAST worker_spawned for S at or before T. Measured over the live journals on
# 2026-09-05: 113 ledger failures attribute to an arm, and 12 task signatures show
# one arm failing twice or more (a605eb2a gave codex FOUR turns). 71 older failures
# have no surviving spawn row -- the events file is a rotating cache -- and those
# simply do not count, which is the conservative direction.
#
# Key: `d['task']`, which leadv2-dispatch-code.sh already fills with sig8 (the
# mission-content signature, dispatch-code line ~8038) -- the SAME key the
# duplicate_task_signature guard uses. No new field, no caller change. The three
# fallback descriptors (bench-fallback, exit76, advisory) and the reviewer
# descriptor do not carry it; those journal failure_memory=absent_key and route
# exactly as before rather than pretending the memory answered zero.
#
# An unreadable journal is NOT zero failures. If either journal cannot be read the
# status is `unavailable`: nothing is banned (banning on no evidence is its own
# failure mode) but the decision line SAYS SO, so a lead reading the journal can
# tell "this arm has a clean record here" from "we could not look".
FAILURE_BAN_THRESHOLD_DEFAULT=2
ARM_FAILURE_CAUSES_DEFAULT={
    'no_work:arm_produced_nothing','no_work:empty_diff','dead:crashed_unfinished',
    'dead:timeout','dead:empty_response','dead:worker_died_with_session',
    'dead:no_verdict_marker','dead:review_body_lost'}
_fm_cfg=((data.get('router_v2') or {}).get('failure_memory') or {})
if not isinstance(_fm_cfg, dict): _fm_cfg={}
try: fm_threshold=int(_fm_cfg.get('threshold', FAILURE_BAN_THRESHOLD_DEFAULT))
except (TypeError, ValueError): fm_threshold=FAILURE_BAN_THRESHOLD_DEFAULT
if fm_threshold < 1: fm_threshold=FAILURE_BAN_THRESHOLD_DEFAULT
_cfg_causes=_fm_cfg.get('arm_failure_causes')
arm_failure_causes=({str(x).strip() for x in _cfg_causes if str(x).strip()}
                    if isinstance(_cfg_causes, list) and _cfg_causes
                    else set(ARM_FAILURE_CAUSES_DEFAULT))
task_sig=str(d.get('task') or '').strip()
_fm_unmapped={}; _fm_open={}; _fm_accounted=[]
def read_failure_memory(sig):
    # -> (counts_by_arm, status). status is one of:
    #   absent_key  -- this caller passed no task signature; nothing to look up
    #   unavailable -- a journal could not be read; UNKNOWN, never "zero"
    #   no_history  -- journals read fine, this signature has no failures
    #   ok          -- journals read fine and this signature has failures
    if not sig: return {}, 'absent_key'
    evt=os.environ.get('ROUTE_ARBITER_EVENTS_JOURNAL') or ''
    led=os.environ.get('ROUTE_ARBITER_FAILURE_LEDGER') or ''
    spawns=[]; counts={}; evt_ok=False; led_ok=False
    try:
        with open(evt) as _f:
            for _l in _f:
                try: r=json.loads(_l)
                except Exception: continue
                if str(r.get('task') or '')!=sig: continue
                a=str(r.get('arm') or '')
                if not a: continue
                k=r.get('kind')
                if k=='worker_spawned': spawns.append((str(r.get('ts') or ''), a))
                elif k=='arm_refused': counts[a]=counts.get(a,0)+1
        evt_ok=True
    except Exception:
        evt_ok=False
    spawns.sort()
    try:
        with open(led) as _f:
            for _l in _f:
                try: r=json.loads(_l)
                except Exception: continue
                if str(r.get('task_sig') or '')!=sig: continue
                ts=str(r.get('ts') or '')
                # every terminal row for this signature counts as ACCOUNTED FOR,
                # whether or not the vocabulary has a name for it -- otherwise an
                # unmapped death would also read as "nobody recorded anything",
                # and the two halves of this defect would be indistinguishable.
                _fm_accounted.append(ts)
                _tc='%s:%s' % (r.get('terminal'), r.get('cause'))
                # TERMINALIZER-DOES-NOT-RECORD-A-SILENT-DEATH-01 (2026-09-05), half one:
                # a terminal row is CONSIDERED only when its terminal:cause appears in
                # arm_failure_causes -- a hand-kept list in the yaml. Measured on the live
                # ledger the same day: 1374 rows, 188 visible to this list, and 305 rows
                # carrying a death it has no name for (dead:e2e_regression 215,
                # dead:all_arms_unavailable 75, dead:review_dod_fail 9,
                # dead:review_verdict_fail 5), while dead:worker_died_with_session -- one
                # of the eight names in the list -- has exactly ONE row in all 1374.
                # Some of those exclusions are right (all_arms_unavailable is nobody's
                # fault) and some are argued (a lane killed by its own e2e regression is
                # the arm's work); deciding which is a change to the vocabulary, and the
                # vocabulary lives in config/leadv2-routing.yaml. What this file can do is
                # stop the drift from being invisible: skipping stays, the skip is NAMED.
                if _tc not in arm_failure_causes:
                    if str(r.get('terminal') or '') in ('dead','no_work'):
                        _fm_unmapped[_tc]=_fm_unmapped.get(_tc,0)+1
                    continue
                arm=None
                for _sts,_a in spawns:
                    if _sts<=ts: arm=_a
                if arm: counts[arm]=counts.get(arm,0)+1
            # half two, the defect as filed: a worker that spawned and then died
            # without anyone recording a terminal. Measured on signature b5abfcfd
            # (2026-09-04): glm spawned and the ledger holds 24 rows for that
            # signature, every one of them refused:* -- refusals from BEFORE the
            # spawn, which by construction are not the arm's fault. The memory
            # therefore answered no_history for an arm that had just failed twice.
            # This does NOT claim death: a spawn with no terminal may simply still
            # be running. It reports the fact and lets the reader judge, which is
            # the whole difference between an unknown and a zero.
            _fm_seen=sorted(_fm_accounted)
            for _sts,_a in spawns:
                if not any(_t>=_sts for _t in _fm_seen):
                    _fm_open[_a]=_fm_open.get(_a,0)+1
        led_ok=True
    except Exception:
        led_ok=False
    if not (evt_ok and led_ok): return {}, 'unavailable'
    return counts, ('ok' if counts else 'no_history')
failure_counts, failure_memory = read_failure_memory(task_sig)
failure_banned={a:n for a,n in failure_counts.items() if n>=fm_threshold}
failure_dropped=[]
if failure_banned:
    _kept=[c for c in capable if c.get('arm') not in failure_banned]
    if _kept:
        failure_dropped=sorted({c.get('arm') for c in capable if c.get('arm') in failure_banned})
        for _fb in failure_dropped: _stage_add(_fb,'failure_memory')
        capable=_kept
    else:
        # Every capable cell is a repeat offender. Refusing here would turn a
        # memory into a deadlock, so the ban yields -- and says that it yielded.
        failure_memory='exhausted'
_fm_tok=' failure_memory=%s' % failure_memory
# Both tokens are absent when there is nothing to say -- which is also what makes
# them falsifiable: a signature whose whole history the vocabulary knows, and whose
# every spawn was accounted for, must carry neither.
_fm_tok += (' failure_unmapped=%s' % ','.join('%s:%d' % (c, n) for c, n in sorted(_fm_unmapped.items()))) if _fm_unmapped else ''
_fm_tok += (' spawn_unaccounted=%s' % ','.join('%s:%d' % (a, n) for a, n in sorted(_fm_open.items()))) if _fm_open else ''
if failure_dropped:
    _fm_tok += ' failure_banned=%s' % ','.join('%s:%d' % (a, failure_banned[a]) for a in failure_dropped)
elif failure_memory=='exhausted':
    _fm_tok += ' failure_banned=none_left:%s' % ','.join('%s:%d' % (a,n) for a,n in sorted(failure_banned.items()))
# Edit B's outage token: a broken INSTRUMENT is named separately from a burnt
# quota, so `all_arms_capped` can never again absorb a probe failure silently.
_probe_outage=[p for p in ('glm','codex','claude','freepool') if unk.get(p)]
_outage=(' probe_outage=%s' % ','.join(_probe_outage)) if _probe_outage else ''
# ROUTING-EVERY-SPAWN-THROUGH-THE-ARBITER-01: the decision journal is the
# enforcement-side record. The spawn gate (PreToolUse Agent) distinguishes
# "consulted, decision=X" from "no decision" by the PRESENCE of a fresh,
# arm!=refuse record for the spawn's subtype -- the predicate is the absence
# of a record, never a name list of subtypes/models/providers.
import time
def _record(arm, model, tier, reason):
    try:
        _jf_path=os.environ.get('LEADV2_ROUTE_ARBITER_DECISIONS_FILE') or os.path.join(os.environ.get('TMPDIR','/tmp'),'leadv2-route-arbiter-decisions.jsonl')
        os.makedirs(os.path.dirname(_jf_path) or '.',exist_ok=True)
        if os.path.exists(_jf_path) and os.path.getsize(_jf_path)>262144:
            try:
                with open(_jf_path) as _old: _lines=_old.readlines()
                with open(_jf_path,'w') as _new: _new.writelines(_lines[len(_lines)//2:])
            except Exception:
                pass
        _rec={'ts':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),'ts_epoch':int(time.time()),
              'role':role,'work_kind':kind,'subtype':str(d.get('subtype','')),
              'model_requested':str(d.get('model_requested','')),'arm':arm,'model':model,
              'tier':tier,'reason':reason,'task':str(d.get('task',''))[:200],
              'failure_memory':failure_memory,
              'arb_rev':_arb_rev,'matrix_rev':_routing_rev,
              'failure_banned':{a:failure_banned[a] for a in failure_dropped},
              'probe_outage':list(_probe_outage),
              'requested_arm':requested_arm,
              'arm_excluded':{a:'+'.join(sorted(_stages.get(a,[]),key=_STAGE_ORDER.index)) for a in sorted(_stages)}}
        with open(_jf_path,'a') as _jf: _jf.write(json.dumps(_rec)+'\n')
    except Exception:
        pass
# EXPLICIT-ARM-REQUEST-01 (founder, via Leadmain, 2026-09-07): a caller asking
# "run this on <arm> specifically" (the founder's own "думать должны Astra и
# Fable" directive is the live case) had NO legal path to a decision the
# leadv2-spawn-arbiter-gate hook would record and pass -- `model_requested`
# was already read into _record()'s journal row above but nothing ever
# CONSULTED it (grepped: zero other references in this file before this
# edit). A denial with no reachable "yes" is not a check, it is a switch that
# is always off -- the same shape as the false-green corpus this arbiter is
# now the acceptance tool for, just inverted (there the vote never reaches
# the deciding logic; here the deciding logic has no route to "approved" at
# all). Fixed by making `requested_arm` a real input: if the requested arm
# has a capability_matrix cell that fits this task's kind/size/trust/allowed
# filter (the exact same `capable` list every other decision is drawn from --
# no separate, softer rule for the explicit path), it wins outright and is
# recorded with its own reason so the journal shows this was a directed pick,
# not an auction. If the requested arm has NO such cell, or every matching
# cell is capped, this REFUSES (does not silently fall through to the
# auction) -- the negative-control half: asking for an arm on work it was
# never declared capable of must fail, or "explicit choice" is actually
# "obeys any request", which is worse than no path at all.
if requested_arm:
    # EXPLICIT-ARM-REQUEST-01 + POOL-IS-COMPUTED-AFTER-THE-ARM-IS-CHOSEN-01:
    # a pin is honoured or refused HONESTLY, never silently substituted.
    # requested_arm_incapable is RESERVED for the one case where it is true --
    # this kind/size has NO capability_matrix cell for the arm at all. Every
    # other refusal names the exact stage that removed it (not_in_pool,
    # not_launchable, untrusted, capped, forecast, failure_memory), so the operator
    # reads WHICH filter fired off the one line, and a perfectly capable arm
    # is never again called incapable.
    if requested_arm not in _arm_cells:
        _record('refuse','none','none','requested_arm_incapable')
        print('arm=refuse model=none tier=none reason=requested_arm_incapable kind=%s requested_arm=%s chain= %s%s%s%s%s' % (kind,requested_arm,ufmt(),_outage,_fm_tok,_excl_render(),_rev_tok))
        raise SystemExit(69)
    _pin_prov=next((c.get('provider') for c in _arm_cells[requested_arm]),None)
    if capped(_pin_prov): _stage_add(requested_arm,'capped')
    _pin_stages=_stages.get(requested_arm,[])
    if _pin_stages:
        _pin_reason='requested_arm_%s' % _pin_stages[0]
        _pin_rc=70 if _pin_stages==['capped'] else 69
        _record('refuse','none','none',_pin_reason)
        print('arm=refuse model=none tier=none reason=%s kind=%s requested_arm=%s chain= %s%s%s%s%s' % (_pin_reason,kind,requested_arm,ufmt(),_outage,_fm_tok,_excl_render(),_rev_tok))
        raise SystemExit(_pin_rc)
# T17 fix-round (C1) split, extended: no_capable_cell means the vocabulary
# cannot express this work at all (no _fit cell, or the bound pool names no
# arm that fits). When arms DO fit but every one was removed by a pool/
# launch/trust stage, that is a different fact -- the matrix knows them, the
# pool did not want them -- and gets its own reason. rc stays 68 for both:
# callers fail open to the ladder crash-fallback, unchanged.
_bound_pool=arm_pool if arm_pool is not None else (allowed if allowed is not None else set(_arm_cells))
if not _fit or not (_bound_pool & set(_arm_cells)):
    _record('refuse','none','none','no_capable_cell')
    print('arm=refuse model=none tier=none reason=no_capable_cell kind=%s chain= %s%s%s%s%s' % (kind,ufmt(),_outage,_fm_tok,_excl_render(),_rev_tok))
    raise SystemExit(68)
if not capable:
    # W1-FORECAST-THE-SPEND-01: a pool the fit check emptied ALONE is a real
    # capacity refusal -- pool_empty would dress it up as a vocabulary gap.
    # Scope: _arm_cells is the WHOLE matrix (freepool carries not_in_pool and
    # no forecast stage of its own), so the all() must range over the BOUND
    # pool -- the arms this dispatch actually asked for. Measured: with the
    # all() over _arm_cells, case (a) of test-route-arbiter-spend-forecast.sh
    # could never reach the loud refusal because freepool:not_in_pool always
    # failed the conjunction first.
    _fc_pool=_bound_pool & set(_arm_cells)
    if FORECAST_ON and _forecast_block and _fc_pool and \
            all('forecast' in _stages.get(_a,[]) for _a in _fc_pool):
        _forecast_refuse()
    _record('refuse','none','none','pool_empty_all_excluded')
    print('arm=refuse model=none tier=none reason=pool_empty_all_excluded kind=%s chain= %s%s%s%s%s' % (kind,ufmt(),_outage,_fm_tok,_excl_render(),_rev_tok))
    raise SystemExit(68)
ok=[c for c in capable if not capped(c.get('provider'))]
for _cap_a in sorted({c.get('arm') for c in capable if capped(c.get('provider'))}):
    _stage_add(_cap_a,'capped')
# W1-FORECAST-THE-SPEND-01: the fit filter runs AFTER the capped filter so a
# capped-empty pool keeps its exact all_arms_capped meaning; an arm the fit
# removed alone is named by its stage, and a pool the fit emptied alone gets
# the loud forecast refusal instead of a silent fall-open to the ladder.
if FORECAST_ON and _forecast_block:
    _ok_fc=[c for c in ok if not (_forecast_block.get(c.get('provider')) and c.get('provider') not in _forecast_wait)]
    if _ok_fc: ok=_ok_fc
    elif ok: _forecast_refuse()
if requested_arm:
    ok=[c for c in ok if c.get('arm')==requested_arm]
if not ok:
    _record('refuse','none','none','all_arms_capped')
    print('arm=refuse model=none tier=none reason=all_arms_capped kind=%s chain= %s%s%s%s%s' % (kind,ufmt(),_outage,_fm_tok,_excl_render(),_rev_tok))
    raise SystemExit(3)
# FP-08 fix-round (H1): demote freepool in the dimension the selector ACTUALLY
# ranks by -- effective cost, the sort's dominant key. +100 clears the whole
# real cost range (max real cost: opus 9), so a floored freepool sorts after
# codex (3..7) and sonnet (5) yet stays in the chain as the last-resort
# fallback if every capable arm later benches. Demoted rank is only APPLIED
# when freepool is actually in the candidate set; otherwise the task never
# contended for it and no floor token is emitted.
floor_reason = '%s/%s' % (size_raw, kind) if (floor_applies and any(c.get('arm')=='freepool' for c in ok)) else ''
# COMPLEXITY-ESTIMATOR-IS-OFF-01 (Critical #3, "who does it"): data-driven
# cost penalty, same mechanism the freepool floor above already uses (a cost
# bump on the sort's dominant key), so a complex/long task naturally sorts
# past a cell whose config marks it too cheap for that shape of work. Config-
# only -- router_v2.complexity_penalty absent or empty is a no-op (today's
# behavior, byte-identical). Never a hardcoded arm name: rules match cell
# `tags` (e.g. cheap/mechanical/bulk/background), which config already uses
# to describe glm-flash/freepool/glm above.
# ARBITER-SCORING-DESIGN-01 step 1 (additive, gated, default OFF): a graduated
# lexicographic capability-fit key, replacing the flat +100 ban above with a
# four-position demotion (0=fits, 1..3=short by that many steps -- never
# "banned", a short arm stays in the chain). docs/handoff/
# F1-ARBITER-SCORING-20260907/design.md §4/§6 in persona-engine
# (f88e15c3c/e678b4eb2) is the source of every name and constant below; this
# block is a verbatim port of §6's decision function into the arbiter's own
# variable names. FIT_MODE off|shadow|on: 'off' (the default, matching
# capability_fit.enabled: false) leaves every pick byte-identical to today --
# complexity_penalty_rules below is unchanged and ok.sort() still sorts on
# _cost_key alone -- while fit_bucket()/fit_pick=/fit_differs= are still
# computed and printed on every decision line (the shadow comparison, so the
# rollout can be measured before Step 4 flips it live). 'on' makes the sort
# use _fit_key instead and zeroes out the legacy complexity_penalty_rules (one
# mechanism live at a time, never both). Rollback from any state is the single
# env flip LEADV2_ARBITER_CAPABILITY_FIT=off.
_cf=((data.get('router_v2') or {}).get('capability_fit') or {})
FIT_MODE=os.environ.get('LEADV2_ARBITER_CAPABILITY_FIT') or ('on' if _cf.get('enabled') else 'off')
CX_ORD=_cf.get('complexity_ordinal') or {'trivial':1.0,'simple':2.0,'standard':3.0,'complex':4.0}
SRC_CONF=_cf.get('source_confidence') or {'judge':0.9,'flag':0.7,'heuristic':0.4,'unknown':0.0}
PRIOR=float(_cf.get('prior', 3.0)); SLACK=float(_cf.get('slack', 0.5)); CAP_DEFAULT=float(_cf.get('cap_default', 3.0))

cx=CX_ORD.get(complexity)                                        # None for 'unknown' or off-vocabulary
complexity_unmapped=None if (complexity in CX_ORD or complexity == 'unknown') else complexity
conf=float(SRC_CONF.get(complexity_source, 0.0)) if cx is not None else 0.0
if cx is None:            req_eff=PRIOR
elif cx >= PRIOR:         req_eff=cx                              # confidence never discounts a demanding estimate
else:                     req_eff=conf*cx + (1.0-conf)*PRIOR      # ...and only proportionally trusts a cheap one

_cap_defaulted=[]
def cap(c):
    v=c.get('capability')
    if v is None: _cap_defaulted.append(c.get('arm')); return CAP_DEFAULT
    try: return float(v)
    except (TypeError, ValueError): _cap_defaulted.append(c.get('arm')); return CAP_DEFAULT
def fit_bucket(c):
    short=req_eff - cap(c) - SLACK
    return 0 if short <= 0 else int(math.ceil(short))

complexity_penalty_rules=([] if FIT_MODE == 'on' else ((data.get('router_v2') or {}).get('complexity_penalty') or []))
def complexity_penalty(c):
    total=0.0
    tags=set(c.get('tags') or [])
    for rule in complexity_penalty_rules:
        if not isinstance(rule, dict):
            continue
        want_complexity=set(rule.get('complexities') or [])
        want_duration=set(rule.get('duration_classes') or [])
        penalize_tags=set(rule.get('penalize_tags') or [])
        if want_complexity and complexity not in want_complexity:
            continue
        if want_duration and duration_class not in want_duration:
            continue
        if penalize_tags and not (tags & penalize_tags):
            continue
        try:
            total += float(rule.get('penalty', 0))
        except (TypeError, ValueError):
            continue
    return total
# ARBITER-REMEMBERS-FAILURES-01 edit B: the demotion for an unmeasured arm rides
# on effective cost -- the sort's dominant key -- exactly like the freepool floor
# above, because that is the only dimension the selector actually ranks by. 50
# clears the whole real cost range (max real cost: opus 9), so ANY arm with a live
# reading outranks ANY arm whose probe failed; and it stays below the freepool
# capability floor (+100), so an unmeasured arm loses to nothing except a
# deliberately floored one.
UNKNOWN_PROBE_PENALTY=50.0
# ARBITER-QUOTA-IS-A-CLIFF-NOT-A-GRADIENT-01 (founder request, 2026-09-05),
# W1-GRANULARITY-CONTINUOUS-HEADROOM-01 (founder order 2026-09-10, PRE-WAVES-PLAN
# §1.6: "the buckets ARE the dumbness"). The gradient started life (2026-09-05)
# as the router_v2.headroom_weights STEP TABLE -- four rows whose third
# (min_usable_now: 0 -> 0.4) swallowed almost the whole range: the live arbiter
# line on 2026-09-10 read headroom_priced=claude:0.4,codex:0.4,glm:0.4, three
# providers in ONE basket, the gradient blind between them, raw cost deciding.
# The inputs were continuous all along and ecost already divided by the weight,
# so the table quantised information that arrived unquantised -- it added no
# intelligence, it threw away the runway number. It is now ONE monotone bounded
# ramp inside headroom_weight, and the config key is deleted (a live config
# carrying a dead key is a lie to the reader):
#
#     weight(u) = 0.2 + 0.8 * min(u, 8) / 8        (u = usable_now)
#
# a clipped linear ramp: w(0)=0.2, w(8)=1.0, flat 1.0 above 8, held at the 0.2
# floor for degenerate u<0. The EDGES are the table's edges (1.0 and 0.2), so
# behaviour at the extremes does not move; between them there are no steps. The
# ramp passes exactly 0.4 at u=2 -- the weight the old 0-row handed to the
# entire [0,2) range -- so a hand burning 1.9/h now prices 0.39, not 0.4.
#
# The semantics the table encoded are kept: `usable_now` is remaining
# percentage-points per HOUR (leadv2-quota-read.py:135); there (router-v2,
# argmax) the weight MULTIPLIES a quality score, here (argmin) the same weight
# DIVIDES the base cost -- less runway per hour => effectively dearer. At EQUAL
# headroom every weight is equal, so the pre-gradient ordering is preserved by
# construction.
#
# Deliberately narrow, and the narrowness is the safety argument:
#   * only the arm's own `cost` is scaled. The freepool capability floor, the
#     unknown-probe penalty and the complexity penalty are ADDED afterwards, so a
#     gradient can never dilute a refusal another line already decided.
#   * a provider whose probe failed keeps weight 1.0. It already carries
#     UNKNOWN_PROBE_PENALTY; pricing it twice for one fact is the error this
#     session has been naming all day.
#   * a readable provider with no usable_now field also keeps 1.0 -- a metadata
#     gap is not evidence of scarcity -- but it is NAMED (headroom_unknown=), per
#     the standing rule that unknown is a third value and must be loud.
#   * an unmetered account is charged the ramp's floor, w(0)=0.2: configured
#     matrix cost at the least generous point of the ramp, no fabricated
#     usage/reset rate, no unknown penalty -- exactly the 0.2 the table's null
#     row used to hand out. As before, it is applied silently to the price and
#     named loudly elsewhere (claude_account_state=unmetered,
#     claude_priced_from=configured_allowance_conservative), never journalled
#     into headroom_priced.
#   * CONTINUITY ONLY RANKS, IT NEVER REFUSES (§1.6 boundary, half the
#     assignment). Ceilings (over_ceiling), the near-reset wait, the
#     kill-switch, protected exclusions and the forecast refusal are cliffs
#     BEFORE this gradient ever runs, and they stay cliffs: a human must be able
#     to predict a refusal without running the arbiter. Smoothness is confined
#     to the ranking key.
# Rollback is one flag: LEADV2_ARBITER_HEADROOM_GRADIENT=0 restores the cliff.
_HEADROOM_W_MIN=0.2; _HEADROOM_W_MAX=1.0; _HEADROOM_U_SAT=8.0
_HEADROOM_ON=(os.environ.get('LEADV2_ARBITER_HEADROOM_GRADIENT','1')!='0')
_headroom_unknown={}; _headroom_priced={}
def _headroom_ramp(un):
    # One formula, both clips explicit: monotone non-decreasing, bounded
    # [_HEADROOM_W_MIN, _HEADROOM_W_MAX], no steps. Mutation control: a stepped
    # basket re-introduced here must redden the separation case of
    # tests/test-headroom-continuous.sh.
    _u=min(un,_HEADROOM_U_SAT)
    return max(_HEADROOM_W_MIN, min(_HEADROOM_W_MAX, _HEADROOM_W_MIN + (_HEADROOM_W_MAX-_HEADROOM_W_MIN)*_u/_HEADROOM_U_SAT))
def headroom_weight(provider):
    if not _HEADROOM_ON: return 1.0
    if _uraw[provider].get('account_state')=='unmetered':
        # Configured matrix cost, charged at the least generous point of the
        # ramp (its floor). No fabricated usage/reset rate or unknown penalty.
        return _HEADROOM_W_MIN
    if unk.get(provider):
        _headroom_unknown[provider]='probe'; return 1.0
    un=usable.get(provider)
    if un is None:
        _headroom_unknown[provider]='no_usable_now'; return 1.0
    try: un=float(un)
    except (TypeError, ValueError):
        _headroom_unknown[provider]='unreadable'; return 1.0
    _w=_headroom_ramp(un)
    if _w != 1.0: _headroom_priced[provider]=_w
    return _w
def ecost(c):
    _w=headroom_weight(c.get('provider'))
    _base=float(c.get('cost',999))/(_w if _w > 0 else 1.0)
    return _base + (100.0 if (floor_applies and c.get('arm')=='freepool') else 0.0) + (UNKNOWN_PROBE_PENALTY if unk.get(c.get('provider')) else 0.0) + complexity_penalty(c)
# ARBITER-SCORING-DESIGN-01 step 1: _cost_order/_fit_order/fit_differs are
# ALWAYS computed, in every FIT_MODE, so the shadow comparison exists before
# the sort is ever flipped to use it (§9's validation plan reads this off the
# decision line, not off a live pick change). Only which key actually SORTS
# `ok` depends on FIT_MODE.
_cost_key=lambda c:(ecost(c),u[c['provider']],c['arm'],c.get('tier',''))
_fit_key=lambda c:(fit_bucket(c),) + _cost_key(c)
_cost_order=sorted(ok, key=_cost_key)                       # today's order, always computed (shadow baseline)
ok.sort(key=_fit_key if FIT_MODE == 'on' else _cost_key)
_fit_order=sorted(ok, key=_fit_key)                         # the new order, always computed (shadow token)
# design.md §6's literal pseudocode compares only ['arm'], but capability_matrix
# gives codex three cells (volume/standard/top) sharing one arm name, and §9.2's
# own table (rows "codex/vol (glm capped) -> codex/std" and "haiku (glm capped)
# -> codex/vol or codex/std") requires exactly that within-arm tier swap to read
# as differs=1. An arm-only compare silently prints differs=0 for those two rows
# (verified red before this fix: tests/test-router-v2-capability-fit.sh rows 4/5)
# -- so identity here is (arm, tier), matching what the decision line already
# prints as two separate tokens.
_id=lambda c:(c['arm'], c.get('tier',''))
fit_differs=bool(ok) and (_id(_fit_order[0]) != _id(_cost_order[0]))
complexity_penalty_active = any(complexity_penalty(c) > 0 for c in ok)  # :846 semantics kept for FIT_MODE != 'on'
seen=set(); chain=[]
for c in ok:
    if c['arm'] not in seen: chain.append(c['arm']); seen.add(c['arm'])
state=os.environ['ROUTE_ARBITER_STATE_FILE']
# FP-08 fix-round (H2): the state file is a JSON object (arm + task stamp +
# floor bookkeeping) since 3ffef47, but this anti-sticky reader still did a
# bare .strip() and compared it against arm names -- `last` never matched any
# arm, alternatives[0]==ok[0] always, and T17 arm rotation was silently off
# (caught red by test-route-arbiter.sh case (d) on the merged tree). Parse the
# object; any unparseable/legacy-bare file rotates (last='').
last=''
try: last=(json.load(open(state)) or {}).get('arm','') or ''
except Exception: last=''
# Anti-stickiness is stronger than a static lowest-utilization preference:
# when an equally-priced alternative exists, do not spend the same arm twice.
# Price comparison is on EFFECTIVE cost so a floored freepool never counts as
# the same price tier as an unfloored cost-1 arm.
price=ecost(ok[0]); alternatives=[c for c in ok if ecost(c)==price and c['arm']!=last]
w=alternatives[0] if alternatives else ok[0]
# POOL-IS-COMPUTED-AFTER-THE-ARM-IS-CHOSEN-01: every arm that survived all
# exclusion stages and still did not win is named price_ratio -- it was IN
# the pool, launchable, trusted and uncapped, and lost on effective cost.
# Without this token those arms were invisible, and a one-arm chain read as
# "nothing cheaper exists" when the truth was "nothing cheaper was allowed".
for _loser in sorted({c['arm'] for c in ok} - {w['arm']}):
    _stage_add(_loser,'price_ratio')
# EFFORT-IS-NOT-WIRED-01: resolve effort from the SAME winning cell `w`, in
# the SAME call that picked the arm -- never a second decision. Data-driven
# (config/leadv2-routing.yaml router_v2.effort_matrix), never a name literal.
#
# SMART-ARBITER-01 / EFFORT-FOLLOWS-THE-ARM-NOT-THE-TASK-01 (founder
# 2026-09-04): the old lookup let the WINNING ARM's tags decide effort --
# glm-flash won a standard build on cost and its `cheap`/`mechanical` tags
# then forced effort=low (43 live build decisions at effort=low,
# 2026-09-03/04; the founder named exactly this outcome). Circular: B was
# derived from A's outcome instead of the task's own properties. Rows are
# now TWO PHASES: a row keyed ONLY on task-descriptor properties
# (kinds/sizes/complexity/duration_class/protected/default -- `protected`
# stays the TASK flag, exactly as before) is evaluated FIRST; rows that key
# on the arm too (`tags`) are a FALLBACK consulted only when no task row
# matched. Config order is preserved within each phase, and a task-keyed row
# ANYWHERE in the matrix outranks any arm-keyed row -- so a yaml edit alone
# (no script change) still retunes every outcome, the anti-hardcoding
# property test-effort-routing.sh case (6) grades.
TASK_EFFORT_KEYS={'kinds','sizes','complexity','duration_class','protected','default'}
def _effort_row_is_task_keyed(row):
    return set(row.keys()) <= (TASK_EFFORT_KEYS | {'effort'})
def _effort_row_matches(row):
    if row.get('default'): return True
    if 'tags' in row:
        if not (set(row.get('tags') or []) & set(w.get('tags') or [])): return False
    if 'kinds' in row and mkind not in (row.get('kinds') or []): return False
    if 'sizes' in row and size not in (row.get('sizes') or []): return False
    if 'complexity' in row and complexity not in (row.get('complexity') or []): return False
    if 'duration_class' in row and duration_class not in (row.get('duration_class') or []): return False
    if 'protected' in row and bool(row['protected']) != protected: return False
    return True
_effort_rows=((data.get('router_v2') or {}).get('effort_matrix') or [])
_task_rows=[r for r in _effort_rows if _effort_row_is_task_keyed(r)]
_arm_rows=[r for r in _effort_rows if not _effort_row_is_task_keyed(r)]
effort='medium'
for _row in (_task_rows+_arm_rows):
    if _effort_row_matches(_row):
        effort = _row.get('effort', 'medium'); break
# FP-08 fix-round (M3/L1/L2): atomic write (same-dir tempfile + os.replace),
# task-stamped, fd closed -- the old `json.dump(..., open(state,'w'))` inside
# `try/except: pass` leaked the fd and, on a failed write, silently left the
# PREVIOUS run's state on disk to be attributed to this task by any reader.
# `task` lets a reader validate provenance; json is already imported at the
# top of this heredoc (the inner `import json` is gone).
try:
    _sdir=os.path.dirname(state) or '.'
    os.makedirs(_sdir,exist_ok=True)
    _fd,_tmp=tempfile.mkstemp(dir=_sdir,prefix='.route-arbiter-',suffix='.tmp')
    try:
        with os.fdopen(_fd,'w') as _sf:
            json.dump({'arm':w['arm'],'task':str(d.get('task','')),'floor_applied':bool(floor_reason),'floor_reason':floor_reason}, _sf)
        os.replace(_tmp,state)
    except BaseException:
        try: os.unlink(_tmp)
        except OSError: pass
        raise
except Exception: pass
# T17 fix-round (H1): emit the chain with the anti-sticky PICK first, then
# the remaining cost-ordered arms. The spawn loop (leadv2-dispatch-code.sh)
# iterates candidate_arms in order starting at index 0 -- before this fix
# `chain=` was a pure cost sort that never varied, so `arm=` (the rotation
# pick) was a value no spawn ever corresponded to and anti-stickiness never
# affected which arm actually ran.
rotated=[w['arm']]+[a for a in chain if a != w['arm']]
_extra = (' size_unmapped=%s' % size_unmapped) if size_unmapped else ''
# D5, same shape as size_unmapped above: `kind=` prints the COERCED value, so
# without this token a diagnose task is indistinguishable in the journal from a
# task that really was code.
_extra += (' kind_unmapped=%s' % kind_unmapped) if kind_unmapped else ''
# D14: headroom read from only SOME of a provider's windows -- the number on
# this line is the worst of what we could READ, not the worst window.
_extra += (' partial_windows=%s' % ','.join('%s:%s' % (p, '|'.join(w)) for p, w in sorted(_partial_windows.items()))) if _partial_windows else ''
# D16: a provider absent from quota_ceilings silently gets ceiling 100, i.e. it
# can never be capped. The default stays (adding a ceiling for a provider nobody
# configured would bench it on no evidence) -- but the winner riding an
# unconfigured ceiling is named, so `not capped` stops meaning two things.
_extra += (' ceiling_default=%s' % w['provider']) if (w.get('provider') and not (ceil.get(w['provider']) or ceil.get(w['arm']))) else ''
# ARBITER-QUOTA-IS-A-CLIFF-NOT-A-GRADIENT-01: the gradient is the only thing in
# this file that changes WHICH arm wins, so the winner's price must be readable
# back off the line -- weight, the number it came from, and, when it could not be
# priced, why. headroom_unknown= is the loud third value; it means "charged at
# 1.0 because we do not know", never "plenty".
_hw_w = headroom_weight(w.get('provider')) if (_HEADROOM_ON and w.get('provider')) else None
_extra += (' headroom_w=%s' % ('%g' % _hw_w)) if _hw_w is not None else ''
_extra += (' usable_now=%s' % ('%g' % float(usable.get(w['provider'])))) if (_hw_w is not None and usable.get(w['provider']) is not None and not unk.get(w['provider'])) else ''
_extra += (' headroom_unknown=%s' % _headroom_unknown[w['provider']]) if (_hw_w is not None and w['provider'] in _headroom_unknown) else ''
# headroom_w= alone answers "what did the WINNER cost"; it cannot answer "why is
# the winner not the cheapest arm", because the arm that lost is the one that got
# priced. headroom_priced= names every candidate provider whose cost was scaled at
# all, so a moved choice can be read straight off the line. Absent when nothing
# was priced -- which is also the control that keeps the assertion honest.
_extra += (' headroom_priced=%s' % ','.join('%s:%g' % (p_, w_) for p_, w_ in sorted(_headroom_priced.items()))) if _headroom_priced else ''
# ...and the same fact on the winner's line, where it answers the question the
# 09-03 evidence could not: was the chain short because nothing cheaper exists,
# or because a policy filter emptied it before the price was read. Absent when
# nothing was filtered -- that absence is the paired control.
_extra += ' claude_account_state=%s claude_probe_penalty=%g claude_priced_from=%s' % (
    _uraw['claude'].get('account_state', 'unknown' if unk['claude'] else 'ok'),
    UNKNOWN_PROBE_PENALTY if unk['claude'] else 0.0,
    _uraw['claude'].get('priced_from', 'unknown_probe_penalty' if unk['claude'] else 'measured'))
_extra += _excl_render()
_extra += _rev_tok
# FP-08 fix-round (H1/H3): the floor journal rides on the arbiter's OWN output
# line for THIS invocation (never a cross-run state file a stale read could
# misattribute), as explicit tokens -- not a Python bool printed raw, which
# rendered `True` and never matched dispatch-code's `== "true"` comparison
# (round-1 H3, the journal line was unreachable dead code).
_floor = (' floor_applied=1 floor_reason=%s' % floor_reason) if floor_reason else ''
_fmode = ' floor_mode=%s floor_mode_source=%s test_only=%d' % (floor_mode, floor_mode_src, 1 if test_only else 0)
# COMPLEXITY-ESTIMATOR-IS-OFF-01 (Critical #3): name the estimate that fed
# this decision -- absent from the descriptor (an older/unpatched caller)
# renders as "unknown", never a blank/missing token.
_complexity = ' complexity=%s duration_class=%s' % (complexity, duration_class)
# CLASSIFIER-MUST-SEE-QUOTA-AND-RESET-DATE-01: name the winning arm's own
# remaining budget and reset distance on the SAME line the arm was picked on
# -- a decision that cannot be read back from the journal did not happen.
_w_info=_uraw.get(w.get('provider'), {})
if _w_info.get('account_state')=='unmetered':
    _w_remaining='unmetered'
elif _w_info.get('unknown'):
    _w_remaining='unknown'
elif _w_info.get('pct') is None:
    _w_remaining='n/a'
else:
    _w_remaining='%.1f' % (100.0 - _w_info['pct'])
_w_reset=('%.2fh' % _w_info['hours_to_reset']) if _w_info.get('hours_to_reset') is not None else 'n/a'
_quota = ' remaining=%s reset_in=%s reset_basis=%s' % (_w_remaining, _w_reset, _w_info.get('reset_basis','n/a'))
# W1-FORECAST-THE-SPEND-01: the winner's own forecast rides the decision
# line -- what was expected, from which basis, against which window's
# remainder. Absent entirely when the check is off
# (LEADV2_ARBITER_SPEND_FORECAST=0); a loud forecast_basis=no_history /
# journal_unavailable when on but without a basis -- the third value, never a
# silent zero.
_forecast_tok=''
if FORECAST_ON:
    _wp=w.get('provider')
    if _wp in _forecast_view:
        _v=_forecast_view[_wp]
        if _v['hours'] is None:
            _forecast_tok=' forecast_basis=%s'%_v['basis']
        else:
            _forecast_tok=' forecast_hours=%.2fh forecast_basis=%s'%(_v['hours'],_v['basis'])
            if _v['worst'] is not None:
                _forecast_tok+=' forecast_window=%s forecast_remaining=%.1fpct forecast_pct=%.1fpct'%(_v['worst']['window'],_v['worst']['remaining'],_v['worst']['forecast'])
                if _wp in _forecast_wait: _forecast_tok+=' forecast_wait=1'
    else:
        _forecast_tok=' forecast_basis=no_windows'
    _ws=num(d.get('write_set_files'))
    if _ws is not None: _forecast_tok+=' forecast_ws=%g'%_ws
    _forecast_tok+=' forecast_class=%s/%s'%(size,duration_class)
_wait = (' wait_applied=%s' % ','.join(_waited)) if _waited else ''
# FREEPOOL-DEAD-ARM-LOOKS-LIKE-A-BUSY-ARM-01: name ANY gate refusal on the
# decision line itself -- this line is what the dispatcher journals verbatim
# (route_resolved ... util_glm=... tail), so the freepool verdict travels
# with every decision, not only the ones a human re-derives by hand.
_gate = (' freepool_gate=%s' % free_reason) if (free_reason and not free_ok) else ''
# A complexity rule only changes the selector through effective cost.  Say so
# when it is active: `cheapest_capable` alone would hide that cheaper tagged
# cells were deliberately demoted for this estimate.
# ARBITER-SCORING-DESIGN-01 step 1: 'capability_fit' only fires when the mode
# is actually 'on' AND the fit key changed the winner vs pure cost -- same
# discipline as complexity_penalty above (:994-997), never claimed while off.
reason = ('explicit_requested_capable' if requested_arm else
          'capability_fit' if (FIT_MODE == 'on' and fit_differs) else
          'complexity_penalty' if complexity_penalty_active else 'cheapest_capable')
_complexity_policy = (' complexity_policy=%s' % ('capability_fit' if FIT_MODE == 'on' else
                                                  ('penalty' if complexity_penalty_active else 'none')))
_record(w['arm'],w['model'],w.get('tier','standard'),reason)
# ROUTING-EVERY-SPAWN-THROUGH-THE-ARBITER-01: the decision line names the kind
# it routed for -- a decision that cannot be read back is not a decision.
# UNION 2026-09-04 (RECOVER-TWELVE-CONFLICTED-BRANCHES-01), third union of this
# print line: HEAD contributed kind=/_quota/_wait/_gate/_record, the branch
# contributed the variable reason (complexity_penalty) and complexity_policy=.
# ARBITER-SCORING-DESIGN-01 step 1 (§7.3/§9.2): the shadow comparison rides on
# every decision line, in every FIT_MODE -- fit_pick=/fit_differs= are the
# tokens §9's validation plan reads to prove Step 3's shadow run before Step 4
# ever flips the sort. cap_default=/complexity_unmapped= mirror the existing
# kind_unmapped=/size_unmapped= discipline: a loud third value, never silent.
_fit_tok = (' complexity_source=%s conf=%.1f req_eff=%.1f fit_mode=%s fit_pick=%s fit_differs=%d fit_bucket=%s%s%s' %
            (complexity_source, conf, req_eff, FIT_MODE, (_fit_order[0]['arm'] if ok else ''), int(fit_differs),
             ','.join('%s:%d' % (c['arm'], fit_bucket(c)) for c in ok),
             (' cap_default=%s' % ','.join(sorted(set(_cap_defaulted)))) if _cap_defaulted else '',
             (' complexity_unmapped=%s' % complexity_unmapped) if complexity_unmapped else ''))
print('arm=%s kind=%s model=%s tier=%s effort=%s reason=%s chain=%s %s%s%s%s%s%s%s%s%s%s%s%s%s' % (w['arm'],kind,w['model'],w.get('tier','standard'),effort,reason,','.join(rotated),ufmt(),_extra,_floor,_fmode,_complexity,_complexity_policy,_quota,_wait,_gate,_outage,_fm_tok,_fit_tok,_forecast_tok))
PY
}

# ROUTING-EVERY-SPAWN-THROUGH-THE-ARBITER-01: CLI consult entry. The lib stays
# source-only for its existing callers (dispatch-code, product-close); invoked
# directly it consults the arbiter and prints the decision line, which the
# spawn gate's way-forward text hands to the lead:
#   bash .../lib/leadv2-route-arbiter.sh worker '{"work_kind":"recon","size":"standard","subtype":"Explore","task":"map auth flow"}'
if [[ "${BASH_SOURCE[0]}" == "${0}" && ( "${1:-}" == worker || "${1:-}" == reviewer ) ]]; then
  route_arbiter "$1" "${2:-{\}}"; exit $?
fi
