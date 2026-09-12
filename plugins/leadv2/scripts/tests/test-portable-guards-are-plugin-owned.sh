#!/usr/bin/env bash
# tests/test-portable-guards-are-plugin-owned.sh — GUARDS-ARE-NOT-IN-THE-PLUGIN-01
#
# Acceptance suite for moving the 11 portable guard hooks out of
# persona-engine into the plugin tree. Proves three things:
#
#   C1  each of the 11 exists + executable under plugins/leadv2/hooks/, and
#       persona-engine's .claude/hooks/<name> is a symlink whose stored target
#       is the canonical ~/Projects/leadv2 path and whose resolved content is
#       byte-identical to the copy in the plugin tree this suite ships in.
#   C2  every script persona-engine's settings.json registers still resolves
#       to a readable file — the move broke nothing.
#   C3  getmany-followup-bot's settings.json registers all 11 under
#       ${CLAUDE_PLUGIN_ROOT}/hooks/ at the right events, and each named file
#       exists in the plugin tree.
#
# Negative controls: --selftest builds scratch fixtures and re-runs this same
# suite against each mutation, requiring RED: symlink pointed at a scratch
# copy (C1), byte drift between link target and plugin copy (C1), dangling
# symlink target (C1), registered script with no file (C2), getmany
# registration naming a nonexistent file (C3), correct file under the wrong
# event (C3), plus a pristine green control.
#
# PENDING semantics: when run from a lane worktree (this suite's plugin root
# is NOT the canonical checkout), the canonical symlink targets may not exist
# until the lane lands — reported as PENDING, not FAIL. Run from the canonical
# checkout (strict mode, roots resolve to the same dir) a dangling target or
# drifted content is a FAIL.
#
# Run: bash scripts/tests/test-portable-guards-are-plugin-owned.sh [--selftest]
# run-all-triggers: leadv2-bash-hook-dispatcher scheduled-decisions-inject anti-silence-pulse-detector mojibake-guard pending-questions-inject session-start-safe-pull lane-lesson-capture-hook leadv2-phase-pulse-sync

set -uo pipefail

SCRIPT_TESTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEF_PLUGIN_HOOKS="$(cd "${SCRIPT_TESTS}/../../hooks" && pwd)"
DEF_PERSONA="/Users/kostiantyn.vlasenko/Projects/persona-engine"
DEF_GETMANY="/Users/kostiantyn.vlasenko/Projects/getmany-followup-bot"
DEF_CANON_HOOKS="/Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2/hooks"

PLUGIN_HOOKS="${G01_PLUGIN_HOOKS:-$DEF_PLUGIN_HOOKS}"
PERSONA="${G01_PERSONA:-$DEF_PERSONA}"
GETMANY="${G01_GETMANY:-$DEF_GETMANY}"
CANON_HOOKS="${G01_CANONICAL_HOOKS:-$DEF_CANON_HOOKS}"

# bash-guard: allow
GUARD_NAMES="leadv2-bash-hook-dispatcher.sh scheduled-decisions-inject.sh anti-silence-pulse-detector.sh mojibake-guard.sh pending-questions-inject.sh session-start-safe-pull.sh lane-lesson-capture-hook.sh leadv2-phase-pulse-sync.sh"

# event each guard must be registered under in getmany-followup-bot
event_for() {
  case "$1" in
    leadv2-bash-hook-dispatcher.sh)       echo "PreToolUse" ;;
    scheduled-decisions-inject.sh)        echo "SessionStart" ;;
    session-start-safe-pull.sh)           echo "SessionStart" ;;
    anti-silence-pulse-detector.sh)       echo "UserPromptSubmit" ;;
    pending-questions-inject.sh)          echo "UserPromptSubmit" ;;
    mojibake-guard.sh)                    echo "Stop" ;;
    lane-lesson-capture-hook.sh)          echo "PostToolUse" ;;
    leadv2-phase-pulse-sync.sh)           echo "PostToolUse" ;;
    *) echo "UNKNOWN" ;;
  esac
}

PASS=0; FAIL=0; PENDING=0; KNOWN=0
# Registrations already broken BEFORE this move (dangling persona-engine
# symlink to a file deleted from the plugin in 517bc13c), PLUS
# docs-truth-inject.sh (DOCS-TRUTH-GATE-HAS-NO-SUBJECT-01, 2026-09-12): its
# only subject (docs/leadv2/open-threads-rules.md) was retired whole, the hook
# and its plugin file are deleted, but persona-engine's .claude/settings.json
# (off-limits to this task) and getmany-followup-bot's .claude/settings.json
# (a third, out-of-scope repo) still name it under
# ${CLAUDE_PROJECT_DIR}/.claude/hooks/ and ${CLAUDE_PLUGIN_ROOT}/hooks/
# respectively. Counted, printed, never laundered into a pass -- a follow-up
# must still edit both settings.json files to drop the dead registration.
KNOWN_BROKEN="${G01_KNOWN_BROKEN:-leadv2-supervisor-mode-reinject.sh docs-truth-inject.sh}"
ok()   { PASS=$((PASS+1)); echo "PASS   $*"; }
bad()  { FAIL=$((FAIL+1)); echo "FAIL   $*" >&2; }
pend() { PENDING=$((PENDING+1)); echo "PENDING $*"; }

# strict (dangling = FAIL) when this suite's plugin root IS the canonical tree
STRICT="${G01_STRICT:-0}"
plug_real="$(readlink -f "$PLUGIN_HOOKS" 2>/dev/null || true)"
canon_real="$(readlink -f "$CANON_HOOKS" 2>/dev/null || true)"
if [ "$STRICT" != "1" ] && [ -n "$plug_real" ] && [ "$plug_real" = "$canon_real" ]; then STRICT=1; fi

# --- C1: plugin owns the 11; persona-engine holds symlinks to them ---------
check_c1() {
  local n link
  for n in $GUARD_NAMES; do
    if [ ! -f "$PLUGIN_HOOKS/$n" ]; then bad "C1 $n: no plugin copy at $PLUGIN_HOOKS/$n"; continue; fi
    if [ ! -x "$PLUGIN_HOOKS/$n" ]; then bad "C1 $n: plugin copy not executable"; fi
    link="$PERSONA/.claude/hooks/$n"
    if [ ! -L "$link" ]; then bad "C1 $n: $link is not a symlink"; continue; fi
    if [ "$(readlink "$link")" != "$CANON_HOOKS/$n" ]; then
      bad "C1 $n: link target '$(readlink "$link")' != canonical $CANON_HOOKS/$n"
      continue
    fi
    if [ -f "$link" ]; then
      if ! cmp -s "$PLUGIN_HOOKS/$n" "$link"; then
        bad "C1 $n: content drift between plugin copy and symlink target"
      elif [ ! -x "$link" ]; then
        bad "C1 $n: symlink target resolves but is not executable"
      else
        ok "C1 $n: plugin-owned, symlinked, byte-identical"
      fi
    elif [ "$STRICT" = "1" ]; then
      bad "C1 $n: dangling symlink (canonical target missing, strict mode)"
    else
      pend "C1 $n: canonical target not landed yet ($CANON_HOOKS/$n)"
    fi
  done
}

# --- C2: every registered persona-engine script still resolves -------------
check_c2() {
  local settings="$PERSONA/.claude/settings.json"
  if [ ! -r "$settings" ]; then bad "C2: cannot read $settings"; return; fi
  local paths t
  t="$(mktemp)"
  python3 - "$PERSONA" "$settings" >"$t" <<'PY' || { bad "C2: settings parse failed"; rm -f "$t"; return; }
import json, os, re, sys
root, path = sys.argv[1], sys.argv[2]
d = json.load(open(path))
for ev, arr in d.get("hooks", {}).items():
    for m in arr:
        for hk in m.get("hooks", []):
            cmd = hk.get("command", "")
            mm = re.search(r'[^"\s]+\.(?:sh|py)\b', cmd)
            if not mm:
                continue
            p = mm.group(0).replace("${CLAUDE_PROJECT_DIR}", root)
            if p.startswith("~/"):
                p = os.path.expanduser(p)
            print(p)
PY
  # bash-guard: allow
  local seen="" p
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    case " $seen " in *" $p "*) continue ;; esac
    seen="$seen $p"
    local base="${p##*/}"
    if [ -r "$p" ]; then ok "C2 resolves: ${p#$PERSONA/}"
    elif case " $KNOWN_BROKEN " in *" $base "*) true ;; *) false ;; esac; then
      KNOWN=$((KNOWN+1)); echo "KNOWN-BROKEN (pre-existing, deleted upstream in 517bc13c): $p"
    else bad "C2 BROKEN registration: $p"; fi
  done < <(sort -u "$t")
  rm -f "$t"
}

# --- C3: getmany registers the 11 under ${CLAUDE_PLUGIN_ROOT}/hooks/ -------
check_c3() {
  local settings="$GETMANY/.claude/settings.json"
  if [ ! -r "$settings" ]; then bad "C3: cannot read $settings"; return; fi
  local rows t
  t="$(mktemp)"
  for n in $GUARD_NAMES; do echo "$n $(event_for "$n")"; done >"$t"
  local missing
  missing="$(python3 - "$GETMANY" "$settings" "$t" <<'PY'
import json, sys
root, path, rows = sys.argv[1], sys.argv[2], sys.argv[3]
want = {}
for line in open(rows):
    name, ev = line.split()
    want[name] = ev
d = json.load(open(path))
have = {}
for ev, arr in d.get("hooks", {}).items():
    for m in arr:
        for hk in m.get("hooks", []):
            cmd = hk.get("command", "")
            for name in want:
                tok = "${CLAUDE_PLUGIN_ROOT}/hooks/" + name
                if tok in cmd:
                    have[name] = ev
for name, ev in sorted(want.items()):
    if name not in have:
        print("C3 %s: no registration under ${CLAUDE_PLUGIN_ROOT}/hooks/" % name)
    elif have[name] != ev:
        print("C3 %s: registered under %s, expected %s" % (name, have[name], ev))
PY
)"
  if [ -n "$missing" ]; then
    while IFS= read -r line; do bad "$line"; done <<<"$missing"
  else
    local n
    for n in $GUARD_NAMES; do ok "C3 $n: registered under $(event_for "$n")"; done
  fi
  rm -f "$t"
}

# --- C3b: every ${CLAUDE_PLUGIN_ROOT}/hooks/ file getmany names exists -----
check_c3b() {
  local settings="$GETMANY/.claude/settings.json" t ghost
  t="$(mktemp)"
  python3 - "$settings" >"$t" <<'PY'
import json, re, sys
d = json.load(open(sys.argv[1]))
for ev, arr in d.get("hooks", {}).items():
    for m in arr:
        for hk in m.get("hooks", []):
            cmd = hk.get("command", "")
            for mm in re.finditer(r'\$\{CLAUDE_PLUGIN_ROOT\}/hooks/([^"\s]+\.sh)', cmd):
                print(mm.group(1))
PY
  while IFS= read -r ghost; do
    [ -n "$ghost" ] || continue
    if [ -f "$PLUGIN_HOOKS/$ghost" ]; then ok "C3b file exists: $ghost"
    elif case " $KNOWN_BROKEN " in *" $ghost "*) true ;; *) false ;; esac; then
      KNOWN=$((KNOWN+1)); echo "KNOWN-BROKEN (retired hook, getmany registration not in this task's scope): $ghost"
    else bad "C3b getmany registers $ghost but plugin ships no such file"; fi
  done < <(sort -u "$t")
  rm -f "$t"
}

# --- selftest: scratch fixtures + negative controls -------------------------
run_suite_env() { # plugin_hooks persona getmany canon strict
  G01_PLUGIN_HOOKS="$1" G01_PERSONA="$2" G01_GETMANY="$3" G01_CANONICAL_HOOKS="$4" \
    G01_STRICT="$5" bash "$0" 2>&1
}
# bash-guard: allow
build_fixture() { # $1=scratch root: plug/hooks, canon/hooks, persona, getmany
  local s="$1" n
  mkdir -p "$s/plug/hooks" "$s/canon/hooks" "$s/persona/.claude/hooks" "$s/getmany/.claude"
  for n in $GUARD_NAMES; do
    cp "$DEF_PLUGIN_HOOKS/$n" "$s/plug/hooks/$n";  chmod 755 "$s/plug/hooks/$n"
    cp "$DEF_PLUGIN_HOOKS/$n" "$s/canon/hooks/$n";  chmod 755 "$s/canon/hooks/$n"
    ln -s "$s/canon/hooks/$n" "$s/persona/.claude/hooks/$n"
  done
  printf '%s\n' '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"${CLAUDE_PROJECT_DIR}/.claude/hooks/mojibake-guard.sh"}]}],"PreToolUse":[{"hooks":[{"type":"command","command":"${CLAUDE_PROJECT_DIR}/.claude/hooks/leadv2-bash-hook-dispatcher.sh"}]}]}}' >"$s/persona/.claude/settings.json"
  python3 - "$s/getmany/.claude/settings.json" <<'PY'
import json, sys
out = sys.argv[1]
names = "leadv2-bash-hook-dispatcher.sh scheduled-decisions-inject.sh anti-silence-pulse-detector.sh mojibake-guard.sh pending-questions-inject.sh session-start-safe-pull.sh lane-lesson-capture-hook.sh leadv2-phase-pulse-sync.sh".split()
ev = {"leadv2-bash-hook-dispatcher.sh":"PreToolUse","scheduled-decisions-inject.sh":"SessionStart",
      "session-start-safe-pull.sh":"SessionStart",
      "anti-silence-pulse-detector.sh":"UserPromptSubmit",
      "pending-questions-inject.sh":"UserPromptSubmit",
      "mojibake-guard.sh":"Stop","lane-lesson-capture-hook.sh":"PostToolUse",
      "leadv2-phase-pulse-sync.sh":"PostToolUse"}
hooks = {}
for n in names:
    hooks.setdefault(ev[n], []).append({"hooks":[{"type":"command",
        "command":"\"${CLAUDE_PLUGIN_ROOT}/hooks/%s\"" % n}]})
json.dump({"hooks":hooks}, open(out,"w"), indent=2)
PY
}
# bash-guard: allow
selftest() {
  local SCR nc_pass=0 nc_fail=0 out rc sn strict
  SCR="$(mktemp -d /tmp/g01-selftest.XXXXXX)"
  trap 'rm -rf "$SCR"' RETURN
  for sn in green scratch-copy drift dangling ghost-reg getmany-ghost wrong-event; do
    build_fixture "$SCR/$sn"
    strict=0
    case "$sn" in
      scratch-copy) rm "$SCR/$sn/persona/.claude/hooks/session-start-safe-pull.sh"
        printf '# mutated copy\n' >"$SCR/$sn/mutated.sh"
        ln -s "$SCR/$sn/mutated.sh" "$SCR/$sn/persona/.claude/hooks/session-start-safe-pull.sh" ;;
      drift) printf '# drifted bytes\n' >>"$SCR/$sn/canon/hooks/pending-questions-inject.sh" ;;
      dangling) rm "$SCR/$sn/canon/hooks/mojibake-guard.sh"; strict=1 ;;
      ghost-reg) python3 -c "
import json
p='$SCR/$sn/persona/.claude/settings.json'
d=json.load(open(p)); d['hooks']['Stop'][0]['hooks'].append({'type':'command','command':'\${CLAUDE_PROJECT_DIR}/.claude/hooks/ghost-guard.sh'})
json.dump(d,open(p,'w'),indent=2)" ;;
      getmany-ghost) python3 -c "
import json
p='$SCR/$sn/getmany/.claude/settings.json'
d=json.load(open(p)); d['hooks']['SessionStart'][0]['hooks'].append({'type':'command','command':'\"\${CLAUDE_PLUGIN_ROOT}/hooks/ghost-guard.sh\"'})
json.dump(d,open(p,'w'),indent=2)" ;;
      wrong-event) python3 -c "
import json
p='$SCR/$sn/getmany/.claude/settings.json'
d=json.load(open(p)); ent=d['hooks'].pop('Stop'); d['hooks'].setdefault('SessionStart',[]).extend(ent)
json.dump(d,open(p,'w'),indent=2)" ;;
    esac
    # bash-guard: allow
    out="$(run_suite_env "$SCR/$sn/plug/hooks" "$SCR/$sn/persona" "$SCR/$sn/getmany" "$SCR/$sn/canon/hooks" "$strict")"; rc=$?
    if [ "$sn" = green ]; then
      if [ "$rc" = 0 ]; then echo "NC-PASS green-control: pristine fixture stays GREEN"; nc_pass=$((nc_pass+1))
      else echo "NC-FAIL green-control: rc=$rc"; printf '%s\n' "$out" | grep -E 'FAIL|SUMMARY' | head -5; nc_fail=$((nc_fail+1)); fi
    else
      if [ "$rc" != 0 ] && printf '%s\n' "$out" | grep -q 'FAIL'; then echo "NC-PASS $sn: mutated fixture goes RED"; nc_pass=$((nc_pass+1))
      else echo "NC-FAIL $sn: want RED, rc=$rc"; printf '%s\n' "$out" | grep -E 'FAIL|SUMMARY' | head -5; nc_fail=$((nc_fail+1)); fi
    fi
  done
  echo "SELFTEST: pass=$nc_pass fail=$nc_fail"
  [ "$nc_fail" = 0 ]
}

if [ "${1:-}" = "--selftest" ]; then selftest; exit $?; fi
check_c1; check_c2; check_c3; check_c3b
echo "SUMMARY: pass=$PASS fail=$FAIL pending=$PENDING known-broken=$KNOWN strict=$STRICT"
[ "$FAIL" = 0 ]
# bash-guard: allow
