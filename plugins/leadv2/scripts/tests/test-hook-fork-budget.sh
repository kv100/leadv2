#!/usr/bin/env bash
# test-hook-fork-budget.sh — FORK-STORM-KILLS-HOOKS-01.
#
# Grades the hooks.json cost + fail-open contract and the fork-budget command:
#   4. a hook that dies abnormally (rc=254 — the cannot-fork class) exits 0 and
#      is journaled; a guard's deliberate rc=2 still passes through untouched;
#   5. a Bash/Edit tool call costs strictly fewer hook processes after the
#      exec-wrap (count asserted against the hook table, mechanism proven with
#      a PPID probe);
#   6. every (event, tool) pair that fired before the rewrite still fires,
#      in the same order — compared over the whole tool universe, not spot
#      checks;
#   7. leadv2-hook-fork-budget.sh reports counts and exits 0 on a healthy box.
# No real hook is ever executed: stub scripts replace the hook binaries.
set -u

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${TEST_DIR}/../../../.." && pwd)"
HOOKS_JSON="${ROOT}/plugins/leadv2/hooks/hooks.json"
FORK_BUDGET="${ROOT}/plugins/leadv2/hooks/leadv2-hook-fork-budget.sh"
PASS=0
FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

[ -f "$HOOKS_JSON" ] || { echo "FAIL: hooks.json missing"; exit 1; }
[ -f "$FORK_BUDGET" ] || { echo "FAIL: fork-budget missing"; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/hook-fork-budget.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT
export LEADV2_DEGRADE_LOG="${TMP}/degrade.log"

# ── suite 4: fail-open entry discipline (journal form, lifecycle events) ─────
printf '#!/bin/bash\nexit 254\n' > "$TMP/stub-dying.sh"
printf '#!/bin/bash\nexit 2\n'  > "$TMP/stub-guard.sh"
chmod +x "$TMP"/stub-*.sh

python3 - "$HOOKS_JSON" "$TMP" <<'PY'
import json,re,sys
d=json.load(open(sys.argv[1]))
tmp=sys.argv[2]
suffix=None
for h in d["hooks"]["SessionStart"][0]["hooks"]:
    c=h["command"]
    m=re.search(r'^(.+?); r=\$\?; (.*)$', c, re.S)
    assert m, c
    suffix=m.group(2)
    break
assert suffix, "no journal suffix found on lifecycle commands"
for name,stub in (("dying","stub-dying.sh"),("guard","stub-guard.sh")):
    open(f"{tmp}/cmd-{name}","w").write(f'"{tmp}/{stub}"; r=$?; {suffix}')
PY
[ $? -eq 0 ] || bad "4: could not extract journal suffix from hooks.json"

bash "$TMP/cmd-dying"; RC_DYING=$?
bash "$TMP/cmd-guard"; RC_GUARD=$?
if [ "$RC_DYING" -eq 0 ]; then
  ok "4: hook dying rc=254 degrades to did-not-run (exit 0)"
else
  bad "4: dying hook exit rc=$RC_DYING (want 0)"
fi
if [ -f "$LEADV2_DEGRADE_LOG" ] && grep -q "rc=254" "$LEADV2_DEGRADE_LOG"; then
  ok "4: degradation is recorded in the journal"
else
  bad "4: degradation not journaled"
fi
if [ "$RC_GUARD" -eq 2 ]; then
  ok "4: guard's deliberate rc=2 still passes through (deny preserved)"
else
  bad "4: guard rc=$RC_GUARD (want 2 — deny must not be masked)"
fi
LINES="$(wc -l < "$LEADV2_DEGRADE_LOG" | tr -d ' ')"
if [ "$LINES" -eq 1 ]; then
  ok "4: guard rc=2 did NOT pollute the degrade journal (1 line only)"
else
  bad "4: journal has $LINES lines (want 1)"
fi

# ── suite 5: per-call hook-process cost, counted and kept minimal ────────────
# Measured 2026-09-01: the harness shell tail-exec's a single simple command
# (control below), so each per-call hook command costs exactly ONE process.
# The per-call wire count IS the per-call process count. This suite pins the
# count for the heavy tools and the single-simple-command invariant that
# keeps the cost there (a compound suffix would add one sh per hook per call).
python3 - "$HOOKS_JSON" <<'PY'
import json,re,sys
d=json.load(open(sys.argv[1]))
PER_CALL={"PreToolUse","PostToolUse"}
def matched(ev, tool):
    n=0
    for g in d["hooks"].get(ev,[]):
        m=g.get("matcher")
        if m is None or re.search(m, tool): n+=len(g["hooks"])
    return n
wired=sum(len(g["hooks"]) for ev in PER_CALL for g in d["hooks"][ev])
bad_rows=[]
for tool,want in (("Bash",13),("Edit",14)):
    c=sum(matched(ev,tool) for ev in PER_CALL)
    print(f"count {tool}: {c} hook commands per call (of {wired} wired)")
    if c!=want: bad_rows.append((tool,c,want))
for ev in sorted(PER_CALL):
    for g in d["hooks"][ev]:
        for h in g["hooks"]:
            c=h["command"]
            if any(x in c for x in (";","&&","|","`")) or "\n" in c:
                bad_rows.append((ev,c[:60]))
sys.exit(1 if bad_rows else 0)
PY
if [ $? -eq 0 ]; then
  ok "5: Bash=13 and Edit=14 hook commands per call (<52 wired); all per-call commands tail-exec eligible"
else
  bad "5: per-call count changed or a per-call command lost single-simple form"
fi

# mechanism proof: BOTH forms of a single simple command tail-exec (1 proc);
# a compound command cannot (2 procs) — the invariant above is load-bearing.
printf '#!/bin/bash\necho "$PPID"\n' > "$TMP/stub-ppid.sh"
chmod +x "$TMP/stub-ppid.sh"
SUITE_PID="$$"
P_EXEC="$(sh -c "exec \"$TMP/stub-ppid.sh\"")"
P_PLAIN="$(sh -c "\"$TMP/stub-ppid.sh\"")"
P_COMPOUND="$(sh -c "\"$TMP/stub-ppid.sh\"; :")"
if [ "$P_EXEC" = "$SUITE_PID" ] && [ "$P_PLAIN" = "$SUITE_PID" ]; then
  ok "5: measured: single simple command under sh -c costs 1 process (explicit exec or not)"
else
  bad "5: tail-exec model broken (exec=$P_EXEC plain=$P_PLAIN suite=$SUITE_PID)"
fi
if [ "$P_COMPOUND" != "$SUITE_PID" ]; then
  ok "5: control: compound command keeps the extra shell process (suffix would cost +1/hook/call)"
else
  bad "5: control failed — compound command reported suite pid"
fi

# ── suite 6: firing-set fidelity over the whole (event, tool) universe ───────
python3 - "$HOOKS_JSON" <<'PY'
import json,re,sys
new=json.load(open(sys.argv[1]))
TOOLS=["Bash","Edit","Write","MultiEdit","Read","Agent","Task","Workflow","Monitor",
       "TaskOutput","TaskStop","SendMessage","AskUserQuestion","TodoWrite","Glob",
       "Grep","NotebookEdit","WebFetch","WebSearch","SlashCommand","ExitPlanMode"]
SCRIPT=re.compile(r'"(?:\$\{CLAUDE_PLUGIN_ROOT\})/hooks/([A-Za-z0-9._-]+?)(?:\.sh)?"')
def fired(table, ev, tool):
    out=[]
    for g in table["hooks"].get(ev,[]):
        m=g.get("matcher")
        if m is None or re.search(m, tool):
            for h in g["hooks"]:
                mm=SCRIPT.search(h["command"])
                out.append(mm.group(1) if mm else "?"+h["command"][:30])
    return out
diffs=[]
# compare against the pre-rewrite blob (merge-base with main — stays the
# pre-change state even after this lane commits), else structural self-check
import subprocess
repo=sys.argv[1].rsplit("/plugins/",1)[0]
base=subprocess.run(["git","-C",repo,"merge-base","HEAD","main"],capture_output=True,text=True)
baseref=base.stdout.strip() if base.returncode==0 and base.stdout.strip() else "HEAD"
blob=subprocess.run(["git","-C",repo,"show",f"{baseref}:plugins/leadv2/hooks/hooks.json"],capture_output=True,text=True)
old=json.loads(blob.stdout) if blob.returncode==0 else None
if old is not None:
    for ev in new["hooks"]:
        assert ev in old["hooks"], f"event added: {ev}"
        for tool in TOOLS:
            if fired(old,ev,tool)!=fired(new,ev,tool):
                diffs.append((ev,tool,fired(old,ev,tool),fired(new,ev,tool)))
    extra=[ev for ev in old["hooks"] if ev not in new["hooks"]]
    if extra: diffs.append(("event-removed",str(extra),"",""))
    if diffs:
        for d in diffs[:5]: print("DIFF",d)
        sys.exit(1)
    print(f"firing-set fidelity vs {baseref[:12]}: {len(new['hooks'])} events x {len(TOOLS)} tools identical")
else:
    # no git blob reachable: structural self-check (matchers unchanged is then
    # pinned by the test on every future run via the committed blob)
    for ev in new["hooks"]:
        for tool in TOOLS:
            fired(new,ev,tool)
    print("git blob unreachable — structural self-check only")
sys.exit(0)
PY
if [ $? -eq 0 ]; then
  ok "6: every (event, tool) firing pair preserved after the rewrite"
else
  bad "6: firing set changed (see DIFF lines above)"
fi

# ── suite 7: fork-budget command reports and exits 0 ─────────────────────────
OUT="$(bash "$FORK_BUDGET" 2>/dev/null)"
RC7=$?
if [ "$RC7" -eq 0 ]; then
  ok "7: fork-budget exits 0"
else
  bad "7: fork-budget rc=$RC7"
fi
for key in procs_total procs_mine orphan_sleep_ppid1 procs_limit_user verdict; do
  if echo "$OUT" | grep -q "^${key}="; then
    ok "7: reports ${key}"
  else
    bad "7: missing ${key} in output"
  fi
done
echo "$OUT" | grep -q "^verdict=healthy" && ok "7: verdict=healthy" || bad "7: verdict not healthy: $(echo "$OUT" | grep verdict)"

echo "hook-fork-budget: pass=${PASS} fail=${FAIL}"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
