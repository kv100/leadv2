#!/usr/bin/env bash
# run-all-triggers: leadv2-block-fg-dispatch
# e433cf64f4f0 (GUARDS-REFUSE-REAL-WORK): leadv2-block-fg-dispatch matched a
# dispatch-launcher path anywhere in the command BYTES -- including inside a
# quoted argument. `scripts/task-add.sh "…leadv2-dispatch-code.sh…"` (a backlog
# row whose TEXT names the script) was blocked twice, for describing the thing
# rather than running it. Round 2 of the hook fixed the plain shape (segment
# head check); the INTERPRETER branch still scanned every token after
# bash/sh/zsh via shlex -- which strips quotes -- so
#   bash scripts/task-add.sh "…fix leadv2-dispatch-code.sh…"
# still matched the quoted prose as if it were the script path. Round 3 makes
# the interpreter branch look only at what the interpreter executes: the script
# token (first non-flag) or the -c payload, re-parsed as a command. This suite
# pins that behaviour, both directions, with mutants inside the matcher body.
#
# Case 1 (allow): commands that merely MENTION a launcher path -- quoted arg
#   (plain and interpreter-prefixed: the exact incident), grep, git log,
#   non-shell script args -- must pass the hook (rc==0).
# Case 2 (block): commands that EXECUTE a launcher in the foreground -- direct
#   path, script slot after bash, -c payload, -lc compound payload, source --
#   must be blocked (rc==2, BLOCKED on stderr).
# Case 3 (allowed-by-design): trailing &, run_in_background=true, --help,
#   status subcommand keep passing even for real launchers.
# Case 4 (mutant h-mut-1): matcher reverted to whole-segment text match ->
#   case 1's assertions would be RED (the mention is blocked again).
# Case 5 (mutant h-mut-2): matcher weakened to never see a launcher ->
#   case 2's assertions would be RED (a real foreground dispatch passes).
#
# Harness: the real hook, fed PreToolUse-shaped JSON on stdin, in a scratch
# copy so the mutants never touch the live file (D1-401 idiom; anchors are
# exact-once, informational count only -- a drifted anchor no-ops the replace
# and the mutant cases redden on their own assertions).
set -euo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${TEST_DIR}/.." && pwd)"
export FGGUARD_PLUGIN_ROOT="${PLUGIN_ROOT}"
python3 - <<'PY'
import json, os, pathlib, shutil, subprocess, sys, tempfile

plugin = pathlib.Path(os.environ['FGGUARD_PLUGIN_ROOT'])
hook_src = plugin / 'hooks' / 'leadv2-block-fg-dispatch.sh'
failures = 0

def check(label, ok, detail=''):
    global failures
    if not ok:
        failures += 1
    print(f'{"PASS" if ok else "FAIL"}: {label}' + (f' -- {detail}' if detail and not ok else ''), flush=True)

# Anchors INSIDE the python matcher body embedded in the hook (is_launcher_exec).
ANCHOR_HEAD = '    if head in GUARDED:  # direct exec of a guarded launcher'
ANCHOR_TOKENIZE = '    toks = q_tokens(seg)'
MUT_TEXT_MATCH = '    if any(g in seg for g in GUARDED):  # MUTANT h-mut-1: text match'
MUT_NEVER_LAUNCHER = '    return False  # MUTANT h-mut-2: never a launcher'

def hook_copy(dest, mutant=None):
    dest.mkdir(parents=True, exist_ok=True)
    text = hook_src.read_text()
    print(f'[TEST] anchor counts (informational): head={text.count(ANCHOR_HEAD)} tokenize={text.count(ANCHOR_TOKENIZE)}', flush=True)
    if mutant == 'h-mut-1':
        text = text.replace(ANCHOR_HEAD, MUT_TEXT_MATCH, 1)
    elif mutant == 'h-mut-2':
        text = text.replace(ANCHOR_TOKENIZE, MUT_NEVER_LAUNCHER, 1)
    p = dest / 'leadv2-block-fg-dispatch.sh'
    p.write_text(text)
    return p

def invoke(hook, command, rib=None):
    payload = {'tool_input': {'command': command}}
    if rib is not None:
        payload['tool_input']['run_in_background'] = rib
    proc = subprocess.run(['bash', str(hook)], input=json.dumps(payload),
                          capture_output=True, text=True, timeout=60,
                          env={'PATH': os.environ['PATH']})
    return proc.returncode, proc.stderr

with tempfile.TemporaryDirectory(prefix='fgguard-reads-') as tmp:
    root = pathlib.Path(tmp)

    live = hook_copy(root / 'live')
    check('bash -n live hook copy', subprocess.run(['bash', '-n', str(live)],
          capture_output=True).returncode == 0)

    # ── Case 1 (allow): mentions are not executions ──────────────────────────
    mentions = [
        ('plain quoted mention (the row text)',
         'scripts/task-add.sh "row e433cf64f4f0: fix the guard that blocks text mentions of leadv2-dispatch-code.sh"'),
        ('interpreter + quoted mention (the incident shape)',
         'bash scripts/task-add.sh "row e433: fix matcher in plugins/leadv2/scripts/leadv2-dispatch-code.sh"'),
        ('sh + single-quoted mention',
         "sh scripts/task-add.sh 'see leadv2-codex-session-runner.sh notes'"),
        ('grep over the launcher file',
         'grep -n undiffable plugins/leadv2/scripts/leadv2-dispatch-code.sh'),
        ('git log naming a launcher',
         'git log --oneline -3 -- plugins/leadv2/scripts/leadv2-fanout.sh'),
        ('non-shell script + mention arg',
         'python3 scripts/backlog.py add "audit leadv2-fanout.sh and glm-coder.sh"'),
    ]
    for label, cmd in mentions:
        rc, err = invoke(live, cmd)
        check(f'mention allowed: {label}', rc == 0, f'rc={rc} err={err[:200]}')

    # ── Case 2 (block): real foreground executions ───────────────────────────
    execs = [
        ('direct guarded path',
         'plugins/leadv2/scripts/leadv2-dispatch-code.sh --task t1 --kind product'),
        ('bash + script slot',
         'bash scripts/leadv2-fanout.sh --task t1 --writes a,b'),
        ('bash -c payload',
         'bash -c "leadv2-dispatch-code.sh --task t1"'),
        ('bash -lc compound payload',
         'bash -lc "cd /x && leadv2-fanout.sh --task t1"'),
        ('source',
         'source plugins/leadv2/scripts/leadv2-fanout.sh'),
    ]
    for label, cmd in execs:
        rc, err = invoke(live, cmd)
        check(f'exec blocked: {label}', rc == 2 and 'BLOCKED' in err, f'rc={rc} err={err[:120]}')

    # ── Case 3 (allowed-by-design): backgrounding and read-only verbs ───────
    allowed = [
        ('trailing &', 'plugins/leadv2/scripts/leadv2-fanout.sh --task t1 &', None),
        ('run_in_background=true', 'plugins/leadv2/scripts/leadv2-fanout.sh --task t1', True),
        ('--help', 'bash scripts/leadv2-dispatch-code.sh --help', None),
        ('status subcommand', 'bash scripts/leadv2-dispatch-code.sh status', None),
    ]
    for label, cmd, rib in allowed:
        rc, err = invoke(live, cmd, rib=rib)
        check(f'by-design allowed: {label}', rc == 0, f'rc={rc} err={err[:120]}')

    # ── Case 4 (mutant h-mut-1: text match) must redden case 1 ──────────────
    m1 = hook_copy(root / 'mut1', mutant='h-mut-1')
    rc, err = invoke(m1, 'scripts/task-add.sh "mentions leadv2-dispatch-code.sh in prose"')
    check('mut1 text-match blocks the mention (case1 assertions would be RED)',
          rc == 2 and 'BLOCKED' in err, f'rc={rc}')
    rc, _ = invoke(m1, "sh scripts/task-add.sh 'see leadv2-codex-session-runner.sh notes'")
    check('mut1 text-match blocks the sh+mention shape too', rc == 2, f'rc={rc}')

    # ── Case 5 (mutant h-mut-2: never a launcher) must redden case 2 ────────
    m2 = hook_copy(root / 'mut2', mutant='h-mut-2')
    rc, err = invoke(m2, 'plugins/leadv2/scripts/leadv2-dispatch-code.sh --task t1 --kind product')
    check('mut2 real foreground dispatch passes (case2 assertions would be RED)',
          rc == 0, f'rc={rc} err={err[:120]}')
    rc, _ = invoke(m2, 'bash scripts/leadv2-fanout.sh --task t1')
    check('mut2 interpreter dispatch passes too', rc == 0, f'rc={rc}')

    print(f'SUMMARY: failures={failures}', flush=True)
    raise SystemExit(bool(failures))
PY
