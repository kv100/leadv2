#!/usr/bin/env bash
# run-all-triggers: leadv2-dispatch-code
# Fault injection is inside the real registry-query function. Exercise its
# consumers and the full dispatcher through a captured, offline worker adapter.
set -euo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${TEST_DIR}/.." && pwd)"
export REGISTRY_TEST_PLUGIN_ROOT="${PLUGIN_ROOT}"
python3 - <<'PY'
import os, pathlib, re, shutil, signal, subprocess, tempfile

plugin = pathlib.Path(os.environ['REGISTRY_TEST_PLUGIN_ROOT'])
sut = pathlib.Path(os.environ.get('REGISTRY_FAILURE_DISPATCH_BIN', str(plugin / 'scripts/leadv2-dispatch-code.sh')))
failures = 0

def check(label, actual, expected):
    global failures
    ok = actual == expected
    failures += not ok
    print(f'{"PASS" if ok else "FAIL"}: {label}: actual={actual!r} expected={expected!r}', flush=True)

def run(argv, cwd, env=None, limit=90):
    # Bound and reap the whole fixture process group, including grandchildren.
    proc = subprocess.Popen(argv, cwd=cwd, env=env, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True, start_new_session=True)
    try:
        out, err = proc.communicate(timeout=limit)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        out, err = proc.communicate()
        raise AssertionError(f'fixture timeout: {argv}\n{out}\n{err}')
    return proc.returncode, out, err

def function(text, name):
    found = re.findall(r'^' + re.escape(name) + r'\(\).*?^}', text, re.M | re.S)
    assert len(found) == 1, (name, len(found))
    return found[0]

with tempfile.TemporaryDirectory(prefix='registry-failure-') as tmp:
    root = pathlib.Path(tmp)
    copied = root / 'plugin'
    for sub in ('scripts', 'config'):
        shutil.copytree(plugin / sub, copied / sub)
    text = sut.read_text()
    legacy = re.search(r'^    _LADDER_IDS=\(([^)]+)\)', text, re.M)
    assert legacy, 'hardcoded legacy ladder anchor drift'
    check('fallback expectation matches hardcoded legacy ladder', legacy.group(1).split(), ['glm', 'codex', 'sonnet'])
    original = function(text, '_arm_launchable_arms')
    anchor = 'import importlib.util, sys\n'
    assert original.count(anchor) == 1, 'query-body injection anchor drift'
    # Nonzero with partial stdout proves the fallback discards failed output.
    broken = original.replace(anchor, anchor + "print('opus'); sys.exit(17)\n")
    faulted = text.replace(original, broken, 1)
    dispatch = copied / 'scripts/leadv2-dispatch-code.sh'
    dispatch.write_text(faulted)
    check('faulted dispatcher syntax', run(['bash', '-n', str(dispatch)], root)[0], 0)

    names = ('_arm_launchable_arms', '_normalize_v2_arm', '_filter_arms_to_dispatchable',
             '_adopt_v2_chain', '_append_ladder_fallback_tail')
    seam = root / 'seam.sh'
    seam.write_text('\n'.join(function(faulted, name) for name in names))
    preamble = '''set -uo pipefail
source "$1"
SCRIPT_DIR="$(dirname "$1")/plugin/scripts"
emit() { printf '%s\\n' "$*" >&2; }
kind=code; task_class=standard
'''
    rc, out, err = run(['bash', '-c', preamble + '_arm_launchable_arms t code', 'test', str(seam)], root)
    check('failed query status becomes usable fallback', rc, 0)
    check('failed query fallback VALUE (partial stdout discarded)', out, 'glm,codex,sonnet')
    check('failure diagnostic names fallback source', 'source=legacy' in err and 'reason=launch_registry_unavailable' in err, True)

    # This value assertion precedes telemetry assertions: deleting a capable
    # arm while preserving a nonempty chain must fail even if another launches.
    for site in ('initial', 'quota_filter', 'quota_gate'):
        script = preamble + '''candidate_arms=()
_adopt_v2_chain t "$2" codex,claude-sonnet,kimi
rc=$?
printf '%s:%s' "$rc" "${candidate_arms[*]}"
'''
        rc, out, err = run(['bash', '-c', script, 'test', str(seam), site], root)
        check(f'{site} survivor VALUE', out, '0:codex sonnet')
        false_drops = [line for line in err.splitlines()
                       if re.search(r'arm=(codex|sonnet)(?: |$)', line)
                       and 'reason=not_in_DISPATCHABLE_BUILD_ARMS' in line]
        check(f'{site} false legacy-member drop records', false_drops, [])
        check(f'{site} reason describes computed launchability set',
              'reason=not_in_DISPATCHABLE_BUILD_ARMS' in err, False)

    script = preamble + '''_ladder_policy_arms() { printf 'glm,codex,sonnet,kimi'; }
_LADDER_IDS=(glm codex sonnet kimi)
candidate_arms=(codex)
_append_ladder_fallback_tail t standard
printf '%s' "${candidate_arms[*]}"
'''
    check('fallback tail retains legacy members, excludes unknown',
          run(['bash', '-c', script, 'test', str(seam)], root)[1], 'codex glm sonnet')

    # A successful empty query is authoritative; only failure may fail open.
    empty = root / 'empty.sh'
    empty.write_text(seam.read_text().replace("print('opus'); sys.exit(17)", 'sys.exit(0)', 1))
    rc, out, err = run(['bash', '-c', preamble + '_arm_launchable_arms t code', 'test', str(empty)], root)
    check('successful empty registry VALUE/status', (rc, out), (0, ''))
    check('successful empty registry is not degraded', 'source=legacy' in err, False)
    healthy = root / 'healthy.sh'
    healthy.write_text(seam.read_text().replace("print('opus'); sys.exit(17)", "print('fable'); sys.exit(0)", 1))
    rc, out, err = run(['bash', '-c', preamble + '_arm_launchable_arms t plan', 'test', str(healthy)], root)
    check('successful registry VALUE is preserved', (rc, out), (0, 'fable'))
    check('successful registry names registry source', 'source=registry' in err and 'source=legacy' not in err, True)

    repo = root / 'repo'
    (repo / '.claude/ref').mkdir(parents=True)
    (repo / 'docs/leadv2/tasks').mkdir(parents=True)
    for args in (['init', '-q', '-b', 'main'], ['config', 'user.email', 'fixture@local'],
                 ['config', 'user.name', 'fixture'], ['-c', 'commit.gpgsign=false', 'commit', '--allow-empty', '-qm', 'fixture']):
        assert run(['git', *args], repo)[0] == 0
    shutil.copy2(plugin / 'config/leadv2-routing.yaml', repo / '.claude/ref/leadv2-routing.yaml')
    def stub(name, body):
        path = root / name
        path.write_text('#!/usr/bin/env bash\n' + body + '\n')
        path.chmod(0o755)
        return str(path)
    noop = stub('noop.sh', 'exit 0')
    poison = stub('poison.sh', 'echo "unexpected provider adapter" >&2; exit 99')
    quota = stub('quota.sh', '''printf '%s\\n' '{"glm":{"status":"ok","five_hour":{"pct":99},"weekly":{"pct":99}},"codex":{"status":"ok","binding_window":"primary","windows":[{"kind":"primary","used_percent":20}]},"anthropic":{"status":"ok","accounts":[{"active":true,"status":"ok","five_hour_pct":20,"seven_day_pct":20}]}}' ''')
    worker = stub('worker.sh', '''printf '%s\\n' "$@" > "$REGISTRY_CAPTURE"
printf 'PID=%s LABEL=fixture SESSION_ID=fixture\\n' "$REGISTRY_FIXTURE_PID"''')
    judge = stub('judge.sh', '''printf '%s' '{"complexity":"standard","estimate_source":"judge"}' ''')
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(('LEADV2_', 'CLAUDE_PROJECT_', 'GLM_POLICY_', 'DC_'))}
    env.update({
        'LEADV2_TEST_CONTEXT': '1', 'LEADV2_LANE_WORK_ROOT': str(repo),
        'CLAUDE_PROJECT_ROOT': str(repo), 'CLAUDE_PROJECT_DIR': str(repo), 'LEADV2_PROJECT_ROOT': str(repo),
        'LEADV2_STATE_ROOT': str(root / 'state'), 'LEADV2_DISPATCH_CACHE_DIR': str(root / 'cache'),
        'LEADV2_DISPATCH_LANE_WORKTREE_BIN': noop, 'LEADV2_JOURNAL_BIN': noop, 'LEADV2_EVENT_BIN': noop,
        'LEADV2_ROUTE_ARBITER_QUOTA_LIVE': quota, 'GLM_POLICY_QUOTA_LIVE': quota, 'LEADV2_QUOTA_LIVE': quota,
        'LEADV2_ROUTE_ARBITER_FREEPOOL_GATE': noop, 'LEADV2_ROUTE_ARBITER_STATE_FILE': str(root / 'arbiter'),
        'LEADV2_DISPATCH_SUBSESSION_BIN': worker, 'LEADV2_DISPATCH_CODEX_BIN': poison,
        'LEADV2_DISPATCH_GLM_BIN': poison, 'LEADV2_DISPATCH_KIMI_BIN': poison,
        'LEADV2_DISPATCH_FREEPOOL_BIN': poison, 'LEADV2_TASK_JUDGE_BIN': judge,
        'GLM_POLICY_RESOLVER': str(copied / 'scripts/lib/leadv2-glm-policy-resolve.py'),
        'LEADV2_ROUTING_YAML_PLUGIN_OVERRIDE': str(copied / 'config/leadv2-routing.yaml'),
        'REGISTRY_CAPTURE': str(root / 'worker.argv'), 'REGISTRY_FIXTURE_PID': str(os.getpid()),
        'LEADV2_ROUTER_V2': '0', 'LEADV2_EXCLUDED_ARMS': '__none__', 'LEADV2_LANE_SHAPE': 'off',
        'LEADV2_DISPATCH_SPAWN': '1',
    })
    for key in ('DISPATCH_E2E_GATE', 'DISPATCH_REVIEW_GATE', 'DISPATCH_ARCHITECT_GATE', 'REQUIRE_PHASES',
                'BURN_GOVERNOR', 'ARM_EARLY_VERDICT_S', 'PULSE_MODE', 'ARM_LANE_PULSE_WATCH',
                'SINGLE_LEAD_BEAT', 'DISPATCH_COST_ESTIMATE'):
        env['LEADV2_' + key] = '0'
    rc, out, err = run(['bash', str(dispatch), 'registry failure recovery probe', '--kind', 'code',
                        '--task-class', 'standard', '--pin-arm', 'sonnet', '--writes', 'src/fixture.py'], repo, env)
    argv = (root / 'worker.argv').read_text().splitlines() if (root / 'worker.argv').exists() else []
    model = argv[argv.index('--model') + 1] if '--model' in argv else None
    check('full dispatcher launched worker adapter VALUE (rc, model)', (rc, model), (0, 'sonnet'))
    if (rc, model) != (0, 'sonnet'):
        print(out + err, flush=True)
    check('full dispatcher confirms spawn', 'worker_spawned by=router model=sonnet' in out + err, True)
    print(f'SUMMARY: failures={failures}', flush=True)
    raise SystemExit(bool(failures))
PY
