#!/usr/bin/env bash
# run-all-triggers: leadv2-dispatch-product-close leadv2-glm-policy-resolve
# Offline end-to-end close gate: real resolver, real refusal/fallback loop,
# fake quota transport and launchers. Assertions grade identities and counts.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 - "${HERE}/../scripts" <<'PY'
import importlib.util
import json
import os
import re
from pathlib import Path
import subprocess
import sys
import tempfile

scripts = Path(sys.argv[1]).resolve()
spec = importlib.util.spec_from_file_location("policy", scripts / "lib/leadv2-glm-policy-resolve.py")
policy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(policy)
failures = []

def check(name, actual, expected):
    good = actual == expected
    print(f"{'PASS' if good else 'FAIL'}: {name}: actual={actual!r} expected={expected!r}", flush=True)
    if not good:
        failures.append(name)

def run(args, **kwargs):
    return subprocess.run(args, text=True, capture_output=True, timeout=40, **kwargs)

def script(path, body):
    path.write_text('#!/usr/bin/env bash\nset -eu\n' + body)
    path.chmod(0o755)
    return str(path)

with tempfile.TemporaryDirectory(prefix="review-unknown-") as tmp:
    base = Path(tmp)
    bindir = base / "bin"
    bindir.mkdir()
    # BSD mktemp without a template can ignore TMPDIR in sandboxed sessions.
    script(bindir / "mktemp", 'if [[ $# == 0 ]]; then exec /usr/bin/mktemp "$TMPDIR/tmp.XXXXXX"; fi\nexec /usr/bin/mktemp "$@"\n')
    lockouts = base / "lockouts"
    lockouts.mkdir()
    os.environ["LEADV2_QUOTA_LOCKOUT_DIR"] = str(lockouts)
    quota_calls = base / "quota-calls"
    quota = script(base / "quota.sh", '''
printf '%s\\n' "$1" >> "$QUOTA_CALLS"
case "$1" in
  glm) printf '{"status":"ok","five_hour":{"pct":80},"weekly":{"pct":70}}\\n' ;;
  codex) printf '{"status":"ok","binding_window":"primary","windows":[{"kind":"primary","used_percent":100}]}\\n' ;;
  anthropic) printf '{"status":"ok","accounts":[{"active":true,"status":"unknown","http":401}]}\\n' ;;
  *) exit 99 ;;
esac
''')
    os.environ["QUOTA_CALLS"] = str(quota_calls)
    # Deliberately use the transport, not injected percentages, for the GLM
    # invariant. Skipping live_glm_pct must fail on the quota call count.
    quota_calls.write_text("")
    result = policy.resolve_review_pool(
        {"codex_quota_gate": {"review_arm_order": ["glm", "fable"]}},
        "codex", quota, signals={"protected_path": True})
    check("GLM selected after quota check", result["reviewer"], "glm")
    check("GLM quota calls before selection", quota_calls.read_text().splitlines().count("glm"), 1)
    for author in ("codex", "glm", "fable", "opus", "sonnet"):
        other = "fable" if author != "fable" else "opus"
        result = policy.resolve_review_pool(
            {"codex_quota_gate": {"review_arm_order": [author, other]}},
            author, pcts={"codex": 10, "glm": 10, "anthropic": 10})
        check(f"resolver excludes author {author}", result["reviewer"], other)
    # Known hot usage and lockouts remain refusals; none is an unknown.
    result = policy.resolve_review_pool({}, "codex", pcts={"glm": 99, "anthropic": 99},
                                        signals={"protected_path": True})
    check("known hot pool has no reviewer", result["reviewer"], "")
    (lockouts / "quota-lockout-anthropic.json").write_text(json.dumps({"locked_until_epoch": 200}))
    result = policy.resolve_review_pool({}, "codex", pcts={"glm": 99, "anthropic": None},
        signals={"protected_path": True}, now_epoch=100,
        ladder_providers={a: "anthropic" for a in ("fable", "opus", "sonnet")})
    check("locked unknown pool has no reviewer", result["reviewer"], "")
    (lockouts / "quota-lockout-anthropic.json").unlink()

    # Exercise the actual consumer predicate, including forged markers for
    # arms that are never allowed to take the checked-unknown route.
    close_source = (scripts / "leadv2-dispatch-product-close.sh").read_text()
    admission = re.search(r"(?m)^_pc_review_entry_eligible\(\).*?^}", close_source, re.S).group(0)
    for entry, author, rc in (("glm:unknown:quota_checked", "codex", 1),
                              ("kimi:unknown:quota_checked", "codex", 1),
                              ("fable:unknown:", "codex", 1),
                              ("fable:unknown:quota_checked", "fable", 1),
                              ("sonnet:ok:10", "sonnet", 1),
                              ("fable:unknown:quota_checked", "codex", 0)):
        got = run(["bash", "-c", admission + '\nAUTHOR="$1"; _pc_review_entry_eligible "$2"',
                   "test", author, entry])
        check(f"consumer {entry} author={author} admission rc", got.returncode, rc)

    for author, expected, rejected in (("codex", "fable", ""), ("codex", "opus", "fable"),
                                       ("codex", "sonnet", "fable,opus"),
                                       ("fable", "opus", ""), ("sonnet", "fable", "")):
        root = base / f"{author}-{expected}"
        root.mkdir()
        for args in (["init", "-q"], ["config", "user.email", "test@local"],
                     ["config", "user.name", "test"]):
            assert run(["git", *args], cwd=root).returncode == 0
        (root / "file.txt").write_text("baseline\n")
        assert run(["git", "add", "file.txt"], cwd=root).returncode == 0
        assert run(["git", "commit", "-qm", "baseline"], cwd=root).returncode == 0
        (root / "file.txt").write_text("changed\n")
        calls = root / "calls"
        calls.write_text("")
        quota_calls.write_text("")
        glm = script(root / "glm.sh", '''
printf 'glm\\n' >> "$LAUNCH_CALLS"
printf '[glm-quota-gate] LEADV2_DISPATCH_REFUSED: quota_gate\\n' >&2
exit 1
''')
        arch = script(root / "arch.sh", '''
while [[ $# -gt 0 ]]; do
  if [[ "$1" == --model ]]; then arm="$2"; printf '%s\\n' "$arm" >> "$LAUNCH_CALLS"; break; fi
  shift
done
case ",$REJECT_ARMS," in *",$arm,"*) printf 'LEADV2_DISPATCH_REFUSED: quota_gate\\n' >&2; exit 1 ;; esac
printf 'REVIEW_VERDICT: PASS\\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\\nOffline reviewer checked the fixture diff and found no issues.\\n'
''')
        poison = script(root / "poison.sh", 'printf "unexpected\\n" >> "$LAUNCH_CALLS"\nexit 99\n')
        arbiter = root / "arbiter.sh"
        arbiter.write_text('route_arbiter() { printf "arm=glm chain=glm,fable,opus,sonnet\\n"; }\n')
        routing = root / "routing.yaml"
        routing.write_text('''routing:
  glm_policy:
    codex_quota_gate:
      review_arm_order: [codex, glm, kimi, fable, opus, sonnet]
''')
        # Strip inherited routing/test overrides. All mutable stores point at
        # this scratch repo. No live launcher, quota transport or arbiter runs.
        env = {k: v for k, v in os.environ.items() if not k.startswith(("LEADV2_", "GLM_POLICY_", "CLAUDE_"))}
        env.update({
            "PATH": str(bindir) + os.pathsep + os.environ["PATH"],
            "TMPDIR": str(root), "LEADV2_TEST_CONTEXT": "1", "LEADV2_PROJECT_ROOT": str(root), "PROJECT_ROOT": str(root),
            "CLAUDE_PROJECT_ROOT": str(root), "LEADV2_CANONICAL_ROOT": str(root),
            "LEADV2_DISPATCH_CACHE_DIR": str(root / "cache"),
            "LEADV2_QUOTA_LOCKOUT_DIR": str(lockouts), "LEADV2_JOURNAL_BIN": "/bin/true",
            "LEADV2_DISPATCH_LEDGER_BIN": "/bin/true", "LEADV2_DISPATCH_BIN": "/bin/true",
            "LEADV2_GLM_POLICY_RESOLVER": str(scripts / "lib/leadv2-glm-policy-resolve.py"),
            "LEADV2_ROUTING_YAML": str(routing), "GLM_POLICY_QUOTA_LIVE": quota,
            "LEADV2_ROUTE_ARBITER_LIB": str(arbiter), "LEADV2_REVIEW_ENGINE": "0",
            "LEADV2_DISPATCH_GLM_BIN": glm, "LEADV2_DISPATCH_ARCHITECT_BIN": arch,
            "LEADV2_DISPATCH_CODEX_BIN": poison, "LEADV2_DISPATCH_KIMI_BIN": poison,
            "LEADV2_DISPATCH_OMP_BIN": poison, "LEADV2_E2E_OWNERSHIP": "0",
            "QUOTA_CALLS": str(quota_calls), "LAUNCH_CALLS": str(calls), "REJECT_ARMS": rejected,
        })
        proc = run(["bash", str(scripts / "leadv2-dispatch-product-close.sh"),
                    str(root), "unknown01", author, "", "0", "1", ""], cwd=root, env=env)
        gate_path = root / "docs/handoff/dispatch-unknown01/review-gate.md"
        gate = gate_path.read_text() if gate_path.exists() else ""
        fields = dict(line.split(": ", 1) for line in gate.splitlines() if ": " in line)
        check(f"close {author} launcher identities", calls.read_text().splitlines(), ["glm"] + (rejected.split(",") if rejected else []) + [expected])
        check(f"close {author} reviewer identity", fields.get("reviewer"), expected)
        check(f"close {author} gate status", fields.get("status"), "pass")
        check(f"close {author} exit", proc.returncode, 0)
        check(f"close {author} GLM quota checked", quota_calls.read_text().splitlines().count("glm") >= 1, True)
        if proc.returncode:
            print(proc.stdout[-1500:] + proc.stderr[-2500:], flush=True)

print(f"RESULT: {len(failures)} failures", flush=True)
sys.exit(bool(failures))
PY
