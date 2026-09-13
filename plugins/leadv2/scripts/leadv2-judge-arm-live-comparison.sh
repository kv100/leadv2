#!/usr/bin/env bash
# Re-run the live GLM-vs-Haiku judge comparison without stubbing either arm.
# The result directory is intentionally explicit: committed evidence is
# reproducible, while later probes can be directed to a scratch directory.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(git -C "${SCRIPT_DIR}/../../.." rev-parse --show-toplevel)"
JUDGE_BIN="${SCRIPT_DIR}/leadv2-task-judge.sh"
CORPUS="${PROJECT_ROOT}/docs/handoff/JUDGE-ARM-LIVE-COMPARISON/corpus.json"
OUTPUT_DIR=""
TIMEOUT_SEC="${LEADV2_JUDGE_TIMEOUT_SEC:-90}"
OUTER_TIMEOUT_SEC="${LEADV2_JUDGE_COMPARISON_OUTER_TIMEOUT_SEC:-210}"
OVERWRITE=0

usage() {
  cat <<'USAGE'
Usage: leadv2-judge-arm-live-comparison.sh --output-dir <directory> [options]

Runs the real task judge for every corpus mission through both requested arms.
The manifest's self_consistency=true missions receive a second invocation per
arm.  Each result row includes the exact invocation, stderr, stdout, parsed
verdict, requested arm, and audited observed judge_arm.

Options:
  --output-dir DIR     Destination for results.jsonl and report.md (required)
  --corpus FILE        Corpus JSON (default: committed comparison corpus)
  --timeout-sec N      Per-transport timeout passed to the judge (default: 90)
  --outer-timeout-sec N  Wall-clock cap for one judge invocation (default: 210)
  --overwrite          Replace results.jsonl and report.md if they exist
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir) OUTPUT_DIR="${2:-}"; shift 2 ;;
    --corpus) CORPUS="${2:-}"; shift 2 ;;
    --timeout-sec) TIMEOUT_SEC="${2:-}"; shift 2 ;;
    --outer-timeout-sec) OUTER_TIMEOUT_SEC="${2:-}"; shift 2 ;;
    --overwrite) OVERWRITE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "${OUTPUT_DIR}" ]] || { usage >&2; exit 2; }
[[ -x "${JUDGE_BIN}" ]] || { printf 'judge is not executable: %s\n' "${JUDGE_BIN}" >&2; exit 2; }
[[ -r "${CORPUS}" ]] || { printf 'corpus is unreadable: %s\n' "${CORPUS}" >&2; exit 2; }
[[ "${TIMEOUT_SEC}" =~ ^[1-9][0-9]*$ ]] || { printf 'invalid --timeout-sec\n' >&2; exit 2; }
[[ "${OUTER_TIMEOUT_SEC}" =~ ^[1-9][0-9]*$ ]] || { printf 'invalid --outer-timeout-sec\n' >&2; exit 2; }

python3 - "${CORPUS}" "${PROJECT_ROOT}" <<'PY'
import json, os, sys

corpus_path, root = sys.argv[1:]
try:
    rows = json.load(open(corpus_path, encoding="utf-8"))
except Exception as exc:
    raise SystemExit(f"invalid corpus JSON: {exc}")
if not isinstance(rows, list) or len(rows) < 10:
    raise SystemExit("corpus must be a JSON list with at least ten missions")
ids = set()
self_checks = 0
for row in rows:
    if not isinstance(row, dict):
        raise SystemExit("every corpus entry must be an object")
    required = ("id", "mission", "rationale", "expected_complexity")
    if any(not row.get(k) for k in required) or "self_consistency" not in row:
        raise SystemExit(f"incomplete corpus entry: {row!r}")
    if row["id"] in ids:
        raise SystemExit(f"duplicate corpus id: {row['id']}")
    ids.add(row["id"])
    if row["expected_complexity"] not in {"trivial", "simple", "standard", "complex"}:
        raise SystemExit(f"invalid expected_complexity for {row['id']}")
    path = os.path.join(root, row["mission"])
    if not os.path.isfile(path):
        raise SystemExit(f"mission not found: {row['mission']}")
    self_checks += bool(row["self_consistency"])
if self_checks < 3:
    raise SystemExit("at least three corpus missions must request self consistency")
PY

mkdir -p "${OUTPUT_DIR}"
RESULTS="${OUTPUT_DIR}/results.jsonl"
REPORT="${OUTPUT_DIR}/report.md"
if [[ ${OVERWRITE} -ne 1 ]] && { [[ -e "${RESULTS}" ]] || [[ -e "${REPORT}" ]]; }; then
  printf 'refusing to overwrite existing evidence; pass --overwrite: %s\n' "${OUTPUT_DIR}" >&2
  exit 2
fi
: > "${RESULTS}"

timeout_bin=""
if command -v gtimeout >/dev/null 2>&1; then
  timeout_bin="gtimeout"
elif command -v timeout >/dev/null 2>&1; then
  timeout_bin="timeout"
fi

record_one() { # id mission rationale expected arm repeat
  local id="$1" mission_rel="$2" rationale="$3" expected="$4" arm="$5" repeat="$6"
  local mission="${PROJECT_ROOT}/${mission_rel}"
  local cache stdout stderr started ended rc=0
  cache="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-judge-compare-cache.XXXXXX")"
  stdout="$(mktemp "${TMPDIR:-/tmp}/leadv2-judge-compare-stdout.XXXXXX")"
  stderr="$(mktemp "${TMPDIR:-/tmp}/leadv2-judge-compare-stderr.XXXXXX")"
  started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'judge mission=%s requested_arm=%s repeat=%s\n' "${id}" "${arm}" "${repeat}" >&2
  if [[ -n "${timeout_bin}" ]]; then
    env LEADV2_JUDGE_ARM="${arm}" LEADV2_JUDGE_CACHE_DIR="${cache}" \
      LEADV2_JUDGE_TIMEOUT_SEC="${TIMEOUT_SEC}" LEADV2_ROUTER_V2=0 \
      "${timeout_bin}" "${OUTER_TIMEOUT_SEC}" bash "${JUDGE_BIN}" --mission-file "${mission}" \
      < /dev/null >"${stdout}" 2>"${stderr}" || rc=$?
  else
    env LEADV2_JUDGE_ARM="${arm}" LEADV2_JUDGE_CACHE_DIR="${cache}" \
      LEADV2_JUDGE_TIMEOUT_SEC="${TIMEOUT_SEC}" LEADV2_ROUTER_V2=0 \
      bash "${JUDGE_BIN}" --mission-file "${mission}" < /dev/null >"${stdout}" 2>"${stderr}" || rc=$?
  fi
  ended="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  python3 - "${RESULTS}" "${id}" "${mission_rel}" "${rationale}" "${expected}" "${arm}" "${repeat}" \
    "${started}" "${ended}" "${rc}" "${JUDGE_BIN}" "${mission}" "${cache}" "${TIMEOUT_SEC}" "${OUTER_TIMEOUT_SEC}" \
    "${stdout}" "${stderr}" <<'PY'
import json, pathlib, sys
(results, mission_id, mission, rationale, expected, arm, repeat, started, ended, rc,
 judge, mission_abs, cache, timeout, outer_timeout, stdout_path, stderr_path) = sys.argv[1:]
stdout = pathlib.Path(stdout_path).read_text(encoding="utf-8", errors="replace")
stderr = pathlib.Path(stderr_path).read_text(encoding="utf-8", errors="replace")
verdict = None
parse_error = None
try:
    verdict = json.loads(stdout)
except Exception as exc:
    parse_error = str(exc)
observed = verdict.get("judge_arm") if isinstance(verdict, dict) else None
row = {
    "schema_v": 1,
    "mission_id": mission_id,
    "mission": mission,
    "rationale": rationale,
    "expected_complexity": expected,
    "requested_arm": arm,
    "repeat": int(repeat),
    "started_at": started,
    "ended_at": ended,
    "return_code": int(rc),
    "invocation": (
        f"LEADV2_JUDGE_ARM={arm} LEADV2_JUDGE_CACHE_DIR={cache} "
        f"LEADV2_JUDGE_TIMEOUT_SEC={timeout} LEADV2_ROUTER_V2=0 "
        f"timeout={outer_timeout}s bash {judge} --mission-file {mission_abs}"
    ),
    "stdout": stdout,
    "stderr": stderr,
    "verdict": verdict,
    "parse_error": parse_error,
    "observed_judge_arm": observed,
}
with open(results, "a", encoding="utf-8") as handle:
    handle.write(json.dumps(row, sort_keys=True) + "\n")
PY
  rm -rf "${cache}" "${stdout}" "${stderr}"
}

while IFS=$'\t' read -r id mission rationale expected self_consistency; do
  for arm in glm haiku; do
    record_one "${id}" "${mission}" "${rationale}" "${expected}" "${arm}" 1
  done
  if [[ "${self_consistency}" == "true" ]]; then
    for arm in glm haiku; do
      record_one "${id}" "${mission}" "${rationale}" "${expected}" "${arm}" 2
    done
  fi
done < <(python3 - "${CORPUS}" <<'PY'
import json, sys
for row in json.load(open(sys.argv[1], encoding="utf-8")):
    fields = (row["id"], row["mission"], row["rationale"], row["expected_complexity"], str(bool(row["self_consistency"])).lower())
    if any("\t" in value or "\n" in value for value in fields):
        raise SystemExit("corpus fields may not contain tabs/newlines")
    print("\t".join(fields))
PY
)

python3 - "${CORPUS}" "${RESULTS}" "${REPORT}" <<'PY'
import collections, json, pathlib, sys

corpus = json.load(open(sys.argv[1], encoding="utf-8"))
rows = [json.loads(line) for line in pathlib.Path(sys.argv[2]).read_text(encoding="utf-8").splitlines() if line]
report_path = pathlib.Path(sys.argv[3])

def succeeded(row):
    if not isinstance(row, dict):
        return False
    verdict = row.get("verdict")
    return (row["return_code"] == 0 and isinstance(verdict, dict)
            and verdict.get("estimate_source") == "judge"
            and row.get("observed_judge_arm") == row["requested_arm"])

def compact_verdict(row):
    if not isinstance(row, dict):
        return "NOT REACHED"
    verdict = row.get("verdict")
    return json.dumps(verdict, sort_keys=True) if isinstance(verdict, dict) else "NO VALID VERDICT"

by_key = {(r["mission_id"], r["requested_arm"], r["repeat"]): r for r in rows}
baseline = []
for item in corpus:
    glm = by_key.get((item["id"], "glm", 1))
    haiku = by_key.get((item["id"], "haiku", 1))
    baseline.append((item, glm, haiku))

comparisons = []
for item, glm, haiku in baseline:
    if succeeded(glm) and succeeded(haiku):
        gv, hv = glm["verdict"], haiku["verdict"]
        comparisons.append((item, glm, haiku, gv["complexity"] != hv["complexity"],
                            {k for k in set(gv) & set(hv) if k != "complexity" and gv[k] != hv[k]}))

self_pairs = []
for item in corpus:
    if not item["self_consistency"]:
        continue
    for arm in ("glm", "haiku"):
        first = by_key.get((item["id"], arm, 1))
        second = by_key.get((item["id"], arm, 2))
        self_pairs.append((item, arm, first, second,
                           succeeded(first) and succeeded(second)
                           and first["verdict"]["complexity"] == second["verdict"]["complexity"]))

failure_counts = {}
for arm in ("glm", "haiku"):
    attempted = [r for r in rows if r["requested_arm"] == arm]
    failures = [r for r in attempted if not succeeded(r)]
    failure_counts[arm] = (len(failures), len(attempted))

class_disagreements = [x for x in comparisons if x[3]]
nonclass_disagreements = [x for x in comparisons if not x[3] and x[4]]
confidence_disagreements = [x for x in comparisons if "confidence" in x[4]]

lines = [
    "# GLM vs Haiku live judge comparison",
    "",
    "## Re-run command",
    "",
    f"```bash\nbash plugins/leadv2/scripts/leadv2-judge-arm-live-comparison.sh --output-dir {report_path.parent} --overwrite\n```",
    "",
    "The harness invokes the real judge, never a stub. It allocates a fresh temporary cache per call, so repeat 2 cannot be a cache hit. `results.jsonl` records each command, return code, stdout, stderr, parsed full envelope, and the envelope's audited `judge_arm`.",
    "",
    "## Corpus",
    "",
    "| ID | Mission | Why included | Reader baseline | Self-consistency |",
    "| --- | --- | --- | --- | --- |",
]
for item in corpus:
    lines.append(f"| {item['id']} | `{item['mission']}` | {item['rationale']} | {item['expected_complexity']} | {str(item['self_consistency']).lower()} |")

lines += ["", "## All live verdicts", ""]
for row in rows:
    lines += [
        f"### {row['mission_id']} — requested `{row['requested_arm']}`, repeat {row['repeat']}",
        "",
        "Invocation:",
        "```bash", row["invocation"], "```",
        f"Return code: `{row['return_code']}`; observed `judge_arm`: `{row.get('observed_judge_arm')}`.",
        "",
        "stdout:", "```json", row["stdout"].rstrip() or "<empty>", "```",
    ]
    if row["stderr"]:
        lines += ["stderr:", "```text", row["stderr"].rstrip(), "```"]

lines += ["", "## Reliability", ""]
for arm, (failed, attempted) in failure_counts.items():
    lines.append(f"- `{arm}`: {failed}/{attempted} failures ({failed / attempted:.1%}). A failure is a non-zero exit, unparsable output, fallback envelope, or a `judge_arm` other than the requested arm.")
lines += ["", "## Self-consistency before cross-arm interpretation", ""]
for item, arm, first, second, consistent in self_pairs:
    status = "consistent" if consistent else "INCONSISTENT OR NOT REACHED"
    lines.append(f"- `{item['id']}` / `{arm}`: {status}; run 1 = `{compact_verdict(first)}`, run 2 = `{compact_verdict(second)}`.")
pair_total = len(self_pairs)
pair_good = sum(bool(x[4]) for x in self_pairs)
lines.append(f"- Complexity self-consistency: {pair_good}/{pair_total} requested arm/mission pairs.")

lines += ["", "## Cross-arm agreement", ""]
eligible = len(comparisons)
lines.append(f"- Comparable baseline pairs: {eligible}/{len(corpus)} (both requested arms produced a real judge envelope).")
lines.append(f"- Material complexity-class disagreements: {len(class_disagreements)}/{eligible}.")
lines.append(f"- Other-envelope disagreements with the same complexity: {len(nonclass_disagreements)}/{eligible}.")
lines.append(f"- Confidence-only disagreements: {len(confidence_disagreements)}/{eligible}. The current TaskEstimate schema emitted no `confidence` key where it was absent; all present fields remain in the raw envelopes above.")
if class_disagreements:
    lines += ["", "### Material disagreements", ""]
    for item, glm, haiku, _, _ in class_disagreements:
        expected = item["expected_complexity"]
        gc, hc = glm["verdict"]["complexity"], haiku["verdict"]["complexity"]
        if gc == expected and hc != expected:
            adjudication = "GLM matches the declared reader baseline"
        elif hc == expected and gc != expected:
            adjudication = "Haiku matches the declared reader baseline"
        elif gc == expected and hc == expected:
            adjudication = "both match the reader baseline (not possible for a class disagreement)"
        else:
            adjudication = "neither matches the declared reader baseline"
        lines += [f"- `{item['id']}`: GLM `{gc}` vs Haiku `{hc}`; reader baseline `{expected}` — {adjudication}."]
else:
    lines += ["", "No material complexity-class disagreement was observed among comparable pairs."]

glm_failed, glm_attempted = failure_counts["glm"]
haiku_failed, haiku_attempted = failure_counts["haiku"]
if glm_failed or eligible < len(corpus) or pair_good < pair_total or class_disagreements:
    decision = "Set the default to haiku: GLM has not demonstrated reliable equivalent complexity classification across this corpus."
    default = "haiku"
else:
    decision = "Keep GLM as the default: it had zero measured failures, 100% comparable-pair coverage, full self-consistency, and zero material complexity disagreements."
    default = "glm"
lines += ["", "## Decision", "", f"**Measured default: `{default}`.** {decision}", ""]
lines.append(f"Evidence: GLM failure rate {glm_failed}/{glm_attempted}; Haiku failure rate {haiku_failed}/{haiku_attempted}; complexity disagreements {len(class_disagreements)}/{eligible}; self-consistency {pair_good}/{pair_total}.")
lines.append("")
lines.append("The fallback path is not counted as an arm success: a GLM request with `judge_arm=haiku_fallback` is a GLM transport failure, while the emitted fallback envelope remains preserved above for diagnosis.")
report_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY

printf 'wrote %s and %s\n' "${RESULTS}" "${REPORT}"
