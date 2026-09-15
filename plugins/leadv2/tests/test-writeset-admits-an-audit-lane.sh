#!/usr/bin/env bash
# run-all-triggers: leadv2-dispatch-code leadv2-dispatch-product-close
# WRITESW-AUDIT-EXEMPT (GUARDS-REFUSE-REAL-WORK, row 63848744ac73): an audit/
# design lane whose ENTIRE deliverable is a document was refused twice with
# dispatch_refused reason=undiffable_write_set because its honest write set
# names only docs/handoff/ (or docs/leadv2/) paths, and the lead dodged the
# guard by moving the deliverable to docs/reference/ -- a workaround, not a
# shape. The distinguishing SIGNAL is the validated lane deliverable
# declaration (--lane-deliverable 'report:<path>' / a LANE_DELIVERABLE: mission
# line): a lane that declared its document is the audit shape, and the close
# gate's kind=report branch certifies that file. A build lane that quietly
# produced nothing reviewable declares nothing and is still refused.
#
# Case A (fix): declared report lane + doc-only handoff write set DISPATCHES,
#   with a loud write_set_undiffable_exempt decision (never a silent pass).
# Case A2 (fix, other tree): docs/leadv2-only set with a declaration also
#   dispatches -- the guard refused both trees, so both must be exemptible.
# Case B (guard stands): NO declaration + doc-only set -> refused PRE-SPAWN,
#   worker adapter never runs, remedy names --lane-deliverable.
# Case B2 (fail-closed signal): an UNPARSABLE declaration (diff:...) does not
#   exempt -- only an exactly-parsable report: declaration is the signal.
# Case E (close end): product-close with the same declaration does NOT bounce
#   undiffable_write_set -- it proceeds into the kind=report certification
#   branch (here honestly blocked report_missing, proving the branch engaged).
# Cases C/D (mutants inside _undiffable_writes_guard's body, D1-401 idiom):
#   wr-mut-1 disables the exemption -> case A's assertions would be RED (the
#   row-63848744ac73 defect is back); wr-mut-2 drops the refusal -> case B's
#   assertions would be RED (nothing certifiable dispatches).
#
# Harness: the real dispatcher end to end through a captured offline worker
# adapter (same shape as test-handoff-only-write-set-is-refused-early.sh).
set -euo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${TEST_DIR}/.." && pwd)"
export WRITESW_PLUGIN_ROOT="${PLUGIN_ROOT}"
python3 - <<'PY'
import os, pathlib, re, shutil, signal, subprocess, sys, tempfile

plugin = pathlib.Path(os.environ['WRITESW_PLUGIN_ROOT'])
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

# Anchors INSIDE _undiffable_writes_guard's body. The exemption if carries a
# # wr-exempt tail so it can never collide with the satisfier's lookalike at
# dispatch-code.sh:4420; exact-once replacement, informational count only
# (under a leadv2-mutation-control.sh run the copied dispatcher is already
# sed-mutated, and a drifted anchor makes the replace() no-op -> the mutant
# cases run unmutated and redden on their own assertions).
WR_PRED = '  [[ ${bad_n} -gt 0 && ${good_n} -eq 0 ]] || return 0'
WR_EXEMPT_IF = '  if [[ -n "${LANE_DELIVERABLE_DECL:-}" ]] && lv2_deliverable_parse "${LANE_DELIVERABLE_DECL}" >/dev/null; then  # wr-exempt'
MUT_DISABLE_EXEMPTION = '  if false; then  # MUTANT wr-mut-1: exemption disabled'
MUT_DROP_REFUSAL = '  return 0  # MUTANT wr-mut-2: refusal dropped'

def copy_plugin(dest, mutant=None):
    for sub in ('scripts', 'config', 'tests'):
        src = plugin / sub
        if src.is_dir():
            shutil.copytree(src, dest / sub)
    dispatch = dest / 'scripts' / 'leadv2-dispatch-code.sh'
    text = dispatch.read_text()
    print(f'[TEST] anchor counts (informational): pred={text.count(WR_PRED)} exempt_if={text.count(WR_EXEMPT_IF)}', flush=True)
    if mutant is not None:
        if mutant == 'wr-mut-1':
            dispatch.write_text(text.replace(WR_EXEMPT_IF, MUT_DISABLE_EXEMPTION, 1))
        else:
            dispatch.write_text(text.replace(WR_PRED, MUT_DROP_REFUSAL, 1))
    for bash in ('bash', '/bin/bash'):
        rc, _, _ = run([bash, '-n', str(dispatch)], dest)
        check(f'{bash} -n dispatcher (mutant={mutant})', rc == 0)
    return dispatch

with tempfile.TemporaryDirectory(prefix='writesw-audit-') as tmp:
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
        worker = stub(case / 'worker.sh', '''printf '%s\\n' "$@" > "$WRITESW_CAPTURE"
printf 'PID=%s LABEL=fixture SESSION_ID=fixture\\n' "$WRITESW_HARNESS_PID"''')
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
            'WRITESW_CAPTURE': str(case / 'worker.argv'),
            # the printed PID must belong to a LIVE process (the harness), or the
            # dispatcher's liveness probe reads the adapter as already dead.
            'WRITESW_HARNESS_PID': str(os.getpid()),
            'LEADV2_ROUTER_V2': '0', 'LEADV2_EXCLUDED_ARMS': '__none__', 'LEADV2_LANE_SHAPE': 'off',
            'LEADV2_DISPATCH_SPAWN': '1',
        })
        for key in ('DISPATCH_E2E_GATE', 'DISPATCH_REVIEW_GATE', 'DISPATCH_ARCHITECT_GATE', 'REQUIRE_PHASES',
                    'BURN_GOVERNOR', 'ARM_EARLY_VERDICT_S', 'PULSE_MODE',
                    'DISPATCH_COST_ESTIMATE'):
            env['LEADV2_' + key] = '0'
        argv = ['bash', str(copied / 'scripts/leadv2-dispatch-code.sh'),
                f'audit lane admission probe {tag}', '--kind', 'code',
                '--task-class', 'standard', '--pin-arm', 'sonnet']
        if writes is not None:
            argv += ['--writes', writes]
        if deliverable is not None:
            argv += ['--lane-deliverable', deliverable]
        rc, out, err = run(argv, repo, env)
        combined = out + err
        capture = case / 'worker.argv'
        argv_lines = capture.read_text().splitlines() if capture.exists() else []
        return {'rc': rc, 'out': out, 'err': err, 'combined': combined,
                'argv': argv_lines, 'repo': repo, 'case': case}

    def exempt_decs(res):
        # decision lines carry task=; the refusal REMEDY prose also names the
        # exemption word, so require the decision shape, not the bare token.
        return [ln for ln in res['combined'].splitlines()
                if 'write_set_undiffable_exempt' in ln and 'task=' in ln]

    # ── Case A (fix): declared audit lane + doc-only handoff set dispatches ──
    rA = dispatch_case('cA-declared-audit', 'docs/handoff/dispatch-wrA/report.md',
                       deliverable='report:docs/handoff/dispatch-wrA/report.md')
    check('caseA declared audit lane dispatches (rc==0)', rA['rc'] == 0, f"rc={rA['rc']}")
    check('caseA exemption decision is loud (reason=report_deliverable)',
          any('reason=report_deliverable' in ln for ln in exempt_decs(rA)), '; '.join(exempt_decs(rA))[:400])
    check('caseA worker launched (capture exists)', '--model' in rA['argv'])
    check('caseA no undiffable refusal', 'undiffable_write_set' not in rA['combined'])

    # ── Case A2 (fix, other tree): docs/leadv2-only set + declaration ────────
    rA2 = dispatch_case('cA2-leadv2-tree', 'docs/leadv2/tasks/wrA2-notes.md',
                        deliverable='report:docs/handoff/dispatch-wrA2/report.md')
    check('caseA2 docs/leadv2-only declared set dispatches (rc==0)', rA2['rc'] == 0, f"rc={rA2['rc']}")
    check('caseA2 exemption decision present', len(exempt_decs(rA2)) >= 1)

    # ── Case B (guard stands): NO declaration -> still refused pre-spawn ────
    rB = dispatch_case('cB-undeclared-build', 'docs/handoff/dispatch-wrB/report.md')
    check('caseB undeclared doc-only set refused (rc==2)', rB['rc'] == 2, f"rc={rB['rc']}")
    check('caseB refusal reason VALUE',
          'LEADV2_DISPATCH_REFUSED: undiffable_write_set' in rB['out'] + rB['err'])
    check('caseB decision line stage=pre_spawn',
          any('dispatch_refused reason=undiffable_write_set' in ln and 'stage=pre_spawn' in ln
              for ln in rB['combined'].splitlines()))
    check('caseB worker adapter NEVER RAN (no capture file)', rB['argv'] == [])
    check('caseB remedy names the declaration channel', '--lane-deliverable' in rB['err'])

    # ── Case B2 (fail-closed signal): unparsable declaration does not exempt ─
    rB2 = dispatch_case('cB2-bad-decl', 'docs/handoff/dispatch-wrB2/report.md',
                        deliverable='diff:src/fixture.py')
    check('caseB2 unknown-kind declaration still refused (rc==2)', rB2['rc'] == 2, f"rc={rB2['rc']}")
    check('caseB2 no exemption decision', exempt_decs(rB2) == [])

    # ── Case C (mutant wr-mut-1: exemption disabled) must redden case A ─────
    rC = dispatch_case('cC-mut-exemption-off', 'docs/handoff/dispatch-wrC/report.md',
                       mutant='wr-mut-1', deliverable='report:docs/handoff/dispatch-wrC/report.md')
    check('mut1 declared audit lane refused again (caseA assertions would be RED)',
          'LEADV2_DISPATCH_REFUSED: undiffable_write_set' in rC['out'] + rC['err'])
    check('mut1 worker never ran', rC['argv'] == [])

    # ── Case D (mutant wr-mut-2: refusal dropped) must redden case B ────────
    rD = dispatch_case('cD-mut-refusal-off', 'docs/handoff/dispatch-wrD/report.md', mutant='wr-mut-2')
    check('mut2 undeclared doc-only set dispatches (caseB assertions would be RED)',
          'undiffable_write_set' not in rD['out'] + rD['err'] and rD['argv'] != [],
          f"rc={rD['rc']}")

    # ── Case E (close end): same declaration must not bounce at close ───────
    close_case = root / 'cE-close-end'
    close_case.mkdir(parents=True)
    crepo = close_case / 'repo'
    crepo.mkdir(parents=True)
    for args in (['init', '-q', '-b', 'main'], ['config', 'user.email', 'fixture@local'],
                 ['config', 'user.name', 'fixture'],
                 ['-c', 'commit.gpgsign=false', 'commit', '--allow-empty', '-qm', 'fixture']):
        assert run(['git', *args], crepo)[0] == 0
    tid = 'wrE'
    run(['bash', str(plugin / 'scripts/leadv2-lane-worktree.sh'), 'ensure', tid, 'standard'], crepo,
        env={'PATH': os.environ['PATH'], 'LEADV2_PROJECT_ROOT': str(crepo), 'HOME': os.environ.get('HOME', '/tmp')})
    cwt = crepo / '.claude/worktrees' / tid
    check('caseE lane worktree ensured', cwt.is_dir())
    resolver = stub(close_case / 'resolver.py',
                    '#!/usr/bin/env python3\nprint("reviewer=codex")\nprint("pool=codex")\nprint("refusal=")\n')
    codex_stub = stub(close_case / 'codex.sh',
                      'printf \'REVIEW_VERDICT: PASS\\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\\n\'\nexit 0\n')
    cenv = {'PATH': os.environ['PATH'], 'HOME': os.environ.get('HOME', '/tmp'),
            'CLAUDE_PROJECT_ROOT': str(crepo), 'LEADV2_PROJECT_ROOT': str(crepo),
            'LEADV2_DISPATCH_CACHE_DIR': str(close_case / 'cache'),
            'LEADV2_DISPATCH_LANE_WRITES': f'docs/handoff/dispatch-wrEsig01/report.md',
            'LEADV2_DISPATCH_LANE_DELIVERABLE': 'report:docs/handoff/dispatch-wrEsig01/report.md',
            'LEADV2_LANE_WORK_ROOT': str(cwt),
            'LEADV2_GLM_POLICY_RESOLVER': resolver, 'LEADV2_DISPATCH_CODEX_BIN': codex_stub,
            'LEADV2_TEST_CONTEXT': '1'}
    rcE, outE, errE = run(['bash', str(plugin / 'scripts/leadv2-dispatch-product-close.sh'),
                           str(crepo), 'wrEsig01', 'sonnet', '', '0', '1', tid], crepo, cenv, limit=180)
    gate = crepo / 'docs/handoff/dispatch-wrEsig01/review-gate.md'
    gate_text = gate.read_text() if gate.exists() else ''
    check('caseE close did NOT bounce undiffable_write_set',
          'undiffable_write_set' not in gate_text and 'undiffable_write_set' not in outE + errE,
          gate_text[:200])
    check('caseE close engaged the kind=report certification branch',
          'kind: report' in gate_text or 'kind=report' in outE + errE, gate_text[:200])
    check('caseE exemption decision on the close side',
          any('write_set_undiffable_exempt' in ln for ln in (outE + errE).splitlines()))

    print(f'SUMMARY: failures={failures}', flush=True)
    raise SystemExit(bool(failures))
PY
