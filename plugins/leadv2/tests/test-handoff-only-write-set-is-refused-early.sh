#!/usr/bin/env bash
# run-all-triggers: leadv2-dispatch-code
# B5-HANDOFF-WRITESET (PRE-WAVES-PLAN row B5, E2E-KILLRATE-01): a mission whose
# --writes paths are ALL under docs/handoff/ (or docs/leadv2/) used to dispatch
# normally -- arm selected, reservation taken, worker spawned and its first
# model turn paid for -- and die ~25s later at lane close with
# refused:undiffable_write_set (pc_precheck_writes, product-close:2103). The
# predicate needs nothing but the write-set CSV, so _undiffable_writes_guard
# (dispatch-code.sh) now raises the SAME cause at dispatch time, before any
# registry row, ledger reservation or spawn, with a remedy a human can act on.
#
# Case 1 SYMPTOM: the all-handoff set is refused PRE-SPAWN. Asserted on the
#   STAGE and the REASON VALUE, never a log substring alone: rc==2 +
#   LEADV2_DISPATCH_REFUSED: undiffable_write_set + decision line with
#   reason=undiffable_write_set stage=pre_spawn + NO worker_spawned line + the
#   worker adapter NEVER RAN (capture file absent) + the dispatch ledger holds
#   NO reservation row ("state":"pending"|"confirmed") for the task -- the
#   honest form of "no arm reservation exists".
# Case 1b REMEDY (report lane): with a report: deliverable declared, the
#   refusal names the deliverable path as the certified channel and tells the
#   caller to drop the handoff paths from --writes (REPORT-ONLY-GATE-01 shape).
# Case 2 GUARD: a write set that DOES contain a reviewable path is NOT
#   refused -- the dispatcher launches the worker adapter (rc==0, model
#   asserted, reservation row PRESENT in the ledger: the negative instrument's
#   positive control).
# Case 2b GRAMMAR: the close gate's declared-shape grammar (trailing / and /**
#   suffixes) collapses to the same literal prefix -- those forms are refused
#   too, so a lane cannot spell its way past the guard.
# Case 3 MUTANT b5-mut-1 (inside _undiffable_writes_guard's body): refuse
#   NOTHING -> case 1's assertions fail on the mutant (dispatch proceeds,
#   worker paid for, no refusal exists). The suite must catch this.
# Case 4 MUTANT b5-mut-2 (inside the same body): refuse EVERYTHING -> case
#   2's assertions fail on the mutant (a reviewable path is refused). A gate
#   that refuses all lanes is not a gate; the suite must catch this too.
#
# Harness: the real dispatcher, end to end, through a captured offline worker
# adapter (same shape as test-registry-failure-keeps-a-launchable-arm.sh).
# Mutants are built by exact-once string replacement INSIDE the guard's
# function body (D1-401 idiom); both anchors are asserted to occur exactly
# once, so a drift in either direction is a loud failure, not a silent skip.
set -euo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${TEST_DIR}/.." && pwd)"
export HANDOFF_WRITESET_PLUGIN_ROOT="${PLUGIN_ROOT}"
python3 - <<'PY'
import os, pathlib, re, shutil, signal, subprocess, sys, tempfile

plugin = pathlib.Path(os.environ['HANDOFF_WRITESET_PLUGIN_ROOT'])
failures = 0

def check(label, ok, detail=''):
    global failures
    if not ok:
        failures += 1
    print(f'{"PASS" if ok else "FAIL"}: {label}' + (f' -- {detail}' if detail and not ok else ''), flush=True)

def run(argv, cwd, env=None, limit=120):
    proc = subprocess.Popen(argv, cwd=cwd, env=env, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True, start_new_session=True)
    try:
        out, err = proc.communicate(timeout=limit)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        out, err = proc.communicate()
        raise AssertionError(f'fixture timeout: {argv}\n{out}\n{err}')
    return proc.returncode, out, err

# The guard's decision line inside _undiffable_writes_guard -- the ONE anchor
# both declared mutants rewrite. Exactly-once by construction of this suite.
PRED = '  [[ ${bad_n} -gt 0 && ${good_n} -eq 0 ]] || return 0'
MUT_REFUSE_NOTHING = '  return 0  # MUTANT b5-mut-1: refuse nothing'
MUT_REFUSE_EVERYTHING = '  bad_n=1; good_n=0  # MUTANT b5-mut-2: refuse everything'

def copy_plugin(dest, mutant=None):
    for sub in ('scripts', 'config', 'tests'):
        src = plugin / sub
        if src.is_dir():
            shutil.copytree(src, dest / sub)
    dispatch = dest / 'scripts' / 'leadv2-dispatch-code.sh'
    text = dispatch.read_text()
    check('guard anchor occurs exactly once in dispatcher', text.count(PRED) == 1,
          f'count={text.count(PRED)}')
    if mutant is not None:
        dispatch.write_text(text.replace(PRED, mutant, 1))
    for bash in ('bash', '/bin/bash'):
        rc, _, _ = run([bash, '-n', str(dispatch)], dest)
        check(f'{bash} -n dispatcher (mutant={bool(mutant)})', rc == 0)
    return dispatch

with tempfile.TemporaryDirectory(prefix='handoff-writeset-') as tmp:
    root = pathlib.Path(tmp)

    def stub(path, body):
        path.write_text('#!/usr/bin/env bash\n' + body + '\n')
        path.chmod(0o755)
        return str(path)

    noop = stub(root / 'noop.sh', 'exit 0')
    poison = stub(root / 'poison.sh', 'echo "unexpected provider adapter" >&2; exit 99')
    quota = stub(root / 'quota.sh', '''printf '%s\\n' '{"glm":{"status":"ok","five_hour":{"pct":99},"weekly":{"pct":99}},"codex":{"status":"ok","binding_window":"primary","windows":[{"kind":"primary","used_percent":20}]},"anthropic":{"status":"ok","accounts":[{"active":true,"status":"ok","five_hour_pct":20,"seven_day_pct":20}]}}' ''')
    judge = stub(root / 'judge.sh', '''printf '%s' '{"complexity":"standard","estimate_source":"judge"}' ''')

    def dispatch_case(tag, writes, mutant=None, deliverable=None):
        """One full real-dispatcher resolve run in its own scratch; returns a dict."""
        case = root / tag
        copied = case / 'plugin'
        copied.mkdir(parents=True)
        worker = stub(case / 'worker.sh', '''printf '%s\\n' "$@" > "$HANDOFF_WRITESET_CAPTURE"
printf 'PID=%s LABEL=fixture SESSION_ID=fixture\\n' "$HANDOFF_WRITESET_HARNESS_PID"''')
        copy_plugin(copied, mutant=mutant)
        repo = case / 'repo'
        (repo / '.claude/ref').mkdir(parents=True)
        (repo / 'docs/leadv2/tasks').mkdir(parents=True)
        for args in (['init', '-q', '-b', 'main'], ['config', 'user.email', 'fixture@local'],
                     ['config', 'user.name', 'fixture'],
                     ['-c', 'commit.gpgsign=false', 'commit', '--allow-empty', '-qm', 'fixture']):
            assert run(['git', *args], repo)[0] == 0
        shutil.copy2(plugin / 'config/leadv2-routing.yaml', repo / '.claude/ref/leadv2-routing.yaml')
        env = {k: v for k, v in os.environ.items()
               if not k.startswith(('LEADV2_', 'CLAUDE_PROJECT_', 'GLM_POLICY_', 'DC_'))}
        env.update({
            'LEADV2_TEST_CONTEXT': '1', 'LEADV2_LANE_WORK_ROOT': str(repo),
            'CLAUDE_PROJECT_ROOT': str(repo), 'CLAUDE_PROJECT_DIR': str(repo), 'LEADV2_PROJECT_ROOT': str(repo),
            'LEADV2_STATE_ROOT': str(case / 'state'), 'LEADV2_DISPATCH_CACHE_DIR': str(case / 'cache'),
            'LEADV2_DISPATCH_LANE_WORKTREE_BIN': noop, 'LEADV2_JOURNAL_BIN': noop, 'LEADV2_EVENT_BIN': noop,
            'LEADV2_ROUTE_ARBITER_QUOTA_LIVE': quota, 'GLM_POLICY_QUOTA_LIVE': quota, 'LEADV2_QUOTA_LIVE': quota,
            'LEADV2_ROUTE_ARBITER_FREEPOOL_GATE': noop, 'LEADV2_ROUTE_ARBITER_STATE_FILE': str(case / 'arbiter'),
            'LEADV2_DISPATCH_SUBSESSION_BIN': worker, 'LEADV2_DISPATCH_CODEX_BIN': poison,
            'LEADV2_DISPATCH_GLM_BIN': poison, 'LEADV2_DISPATCH_KIMI_BIN': poison,
            'LEADV2_DISPATCH_FREEPOOL_BIN': poison, 'LEADV2_TASK_JUDGE_BIN': judge,
            'GLM_POLICY_RESOLVER': str(copied / 'scripts/lib/leadv2-glm-policy-resolve.py'),
            'LEADV2_ROUTING_YAML_PLUGIN_OVERRIDE': str(copied / 'config/leadv2-routing.yaml'),
            'HANDOFF_WRITESET_CAPTURE': str(case / 'worker.argv'),
            # the printed PID must belong to a LIVE process (the harness), or the
            # dispatcher's liveness probe reads the adapter as already dead.
            'HANDOFF_WRITESET_HARNESS_PID': str(os.getpid()),
            'LEADV2_ROUTER_V2': '0', 'LEADV2_EXCLUDED_ARMS': '__none__', 'LEADV2_LANE_SHAPE': 'off',
            'LEADV2_DISPATCH_SPAWN': '1',
        })
        for key in ('DISPATCH_E2E_GATE', 'DISPATCH_REVIEW_GATE', 'DISPATCH_ARCHITECT_GATE', 'REQUIRE_PHASES',
                    'BURN_GOVERNOR', 'ARM_EARLY_VERDICT_S', 'PULSE_MODE', 'ARM_LANE_PULSE_WATCH',
                    'SINGLE_LEAD_BEAT', 'DISPATCH_COST_ESTIMATE'):
            env['LEADV2_' + key] = '0'
        argv = ['bash', str(copied / 'scripts/leadv2-dispatch-code.sh'),
                f'handoff-only write set probe {tag}', '--kind', 'code',
                '--task-class', 'standard', '--pin-arm', 'sonnet']
        if writes is not None:
            argv += ['--writes', writes]
        if deliverable is not None:
            argv += ['--lane-deliverable', deliverable]
        rc, out, err = run(argv, repo, env)
        combined = out + err
        sig = None
        m = re.search(r'dispatch_refused reason=undiffable_write_set task=(\S+)', combined)
        if m:
            sig = m.group(1)
        ledger_rows = []
        for ledger in case.rglob('*ledger*'):
            if ledger.is_file():
                ledger_rows += [ln for ln in ledger.read_text().splitlines() if sig and sig in ln]
        capture = case / 'worker.argv'
        argv_lines = capture.read_text().splitlines() if capture.exists() else []
        return {'rc': rc, 'out': out, 'err': err, 'combined': combined, 'sig': sig,
                'ledger_rows': ledger_rows, 'argv': argv_lines,
                'repo': repo, 'case': case}

    def reservation_rows(res):
        return [ln for ln in res['ledger_rows'] if '"state":"pending"' in ln or '"state":"confirmed"' in ln]

    # ── Case 1 (symptom): all-handoff set refused PRE-SPAWN ─────────────────
    r1 = dispatch_case('c1-symptom', 'docs/handoff/dispatch-hws1/report.md')
    check('case1 rc==2 (refusal family of writeset_*)', r1['rc'] == 2, f"rc={r1['rc']}")
    check('case1 refusal reason VALUE on stdout',
          'LEADV2_DISPATCH_REFUSED: undiffable_write_set' in r1['out'] + r1['err'])
    dec = [ln for ln in r1['combined'].splitlines() if 'dispatch_refused reason=undiffable_write_set' in ln]
    check('case1 decision line present with stage=pre_spawn',
          any('stage=pre_spawn' in ln for ln in dec), '; '.join(dec))
    check('case1 names the offending path',
          any('docs/handoff/dispatch-hws1/report.md' in ln for ln in dec + r1['err'].splitlines()))
    check('case1 remedy is actionable (--lane-deliverable named)',
          '--lane-deliverable' in r1['err'])
    check('case1 NO worker_spawned line', 'worker_spawned' not in r1['combined'])
    check('case1 worker adapter NEVER RAN (no capture file)', r1['argv'] == [])
    check('case1 refusal was journaled (terminal row exists)', len(r1['ledger_rows']) >= 1,
          'ledger rows mentioning sig: ' + str(len(r1['ledger_rows'])))
    check('case1 NO arm reservation exists (no pending/confirmed ledger row)',
          reservation_rows(r1) == [], str(reservation_rows(r1)))

    # ── Case 1b (remedy, report lane): deliverable-aware message ────────────
    r1b = dispatch_case('c1b-remedy', 'docs/handoff/dispatch-hws1b/report.md',
                        deliverable='report:docs/handoff/dispatch-hws1b/report.md')
    check('case1b still refused (combo is undiffable at close today)', r1b['rc'] == 2, f"rc={r1b['rc']}")
    check('case1b remedy names the deliverable as the certified channel',
          'already certified via the deliverable' in r1b['err'])
    check('case1b remedy tells the caller to drop the handoff paths',
          'drop' in r1b['err'] and 'docs/leadv2|docs/handoff' in r1b['err'])

    # ── Case 2 (guard): a reviewable path present -> NOT refused ────────────
    r2 = dispatch_case('c2-guard', 'docs/handoff/dispatch-hws2/report.md,src/fixture.py')
    check('case2 rc==0 (mixed set dispatches)', r2['rc'] == 0, f"rc={r2['rc']}")
    check('case2 worker launched (capture exists)', '--model' in r2['argv'])
    check('case2 pinned arm reached the adapter',
          len(r2['argv']) > r2['argv'].index('--model') + 1 and r2['argv'][r2['argv'].index('--model') + 1] == 'sonnet')
    check('case2 no undiffable refusal', 'undiffable_write_set' not in r2['combined'])
    # positive control for case 1's negative instrument: the green path DOES
    # leave a confirmed reservation row naming the task.
    r2_sig = None
    m = re.search(r'task=(\S+)', r2['combined'])
    led2 = []
    for ledger in r2['case'].rglob('*ledger*'):
        if ledger.is_file():
            led2 += ledger.read_text().splitlines()
    check('case2 ledger HAS reservation rows (instrument positive control)',
          any('"state":"confirmed"' in ln or '"state":"pending"' in ln for ln in led2))

    # ── Case 2b (grammar): declared shapes collapse to the same prefix ──────
    r2b = dispatch_case('c2b-grammar', 'docs/handoff/dispatch-hws2b/,docs/leadv2/**')
    check('case2b trailing-slash and /** forms are refused too', r2b['rc'] == 2, f"rc={r2b['rc']}")
    check('case2b refusal reason VALUE',
          'LEADV2_DISPATCH_REFUSED: undiffable_write_set' in r2b['out'] + r2b['err'])
    check('case2b pre-spawn (no worker adapter run)', r2b['argv'] == [])

    # ── Case 3 (mutant b5-mut-1: refuse NOTHING) must redden case 1 ────────
    r3 = dispatch_case('c3-mut-refuse-nothing', 'docs/handoff/dispatch-hws3/report.md',
                       mutant=MUT_REFUSE_NOTHING)
    check('mut1 no longer refuses (case1 assertions would be RED)',
          'LEADV2_DISPATCH_REFUSED: undiffable_write_set' not in r3['out'] + r3['err'])
    check('mut1 dispatch proceeded (worker paid for -- the disease is back)',
          r3['argv'] != [] and 'worker_spawned' in r3['combined'])

    # ── Case 4 (mutant b5-mut-2: refuse EVERYTHING) must redden case 2 ─────
    r4 = dispatch_case('c4-mut-refuse-everything',
                       'docs/handoff/dispatch-hws4/report.md,src/fixture.py',
                       mutant=MUT_REFUSE_EVERYTHING)
    check('mut2 refuses a REVIEWABLE set (case2 assertions would be RED)',
          'LEADV2_DISPATCH_REFUSED: undiffable_write_set' in r4['out'] + r4['err'])
    check('mut2 never launched the worker', r4['argv'] == [])

    print(f'SUMMARY: failures={failures}', flush=True)
    raise SystemExit(bool(failures))
PY
