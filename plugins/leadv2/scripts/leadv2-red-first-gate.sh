#!/usr/bin/env bash
# leadv2-red-first-gate.sh — RED-FIRST-GATE-01 R1.
#
# PROBLEM THIS SOLVES
#   A green test suite proves nothing if every assertion was already green
#   BEFORE the fix landed (tautology / wrong-target grep / stubbed context).
#   Three same-day product diffs (2026-07-30) shipped 16/16, 6/6, 25/25 green
#   suites over real defects — see mission docs/handoff/dispatch-fe1a5906/.
#
# THE SEAM (architect prepass §0)
#   Both persona-engine (tests/harness.sh _test_pass/_test_fail) and leadv2
#   (per-file pass()/fail()) print one of two label conventions on stdout:
#     "  PASS: <label>" / "  FAIL: <label> — <detail>"           (persona-engine)
#     "[TEST] PASS: <label>" / "[TEST] FAIL: <label>"             (leadv2)
#   One regex covers both. Run each changed/added test file twice — once
#   against pre-fix code (a disposable `git worktree add --detach` of <base>,
#   with the WORKING-TREE version of the test file copied in), once against
#   the real working tree — and diff the two label->outcome maps.
#
# CLASSIFICATION (per LABEL, not per file)
#   pre=FAIL  post=PASS  -> RED_PROVEN     not blocking (the goal)
#   pre=PASS  post=PASS  -> NOT_RED        BLOCKING (tautology), unless declared exempt
#   pre=absent post=PASS -> INCONCLUSIVE   not blocking ("could not run" != red)
#   post=FAIL (any pre)  -> DIFF_BROKEN    BLOCKING
#
# SUBCOMMANDS
#   probe  --task-id <id> --repo <path> [--repo <path> ...] [--base <ref>] [--json]
#          Writes docs/handoff/<task>/red-first-report.json + red-first-gate.log.
#          Exit: 0 all-clear (PASS) | 1 NOT_RED/DIFF_BROKEN present (BLOCK) |
#                2 setup/isolation failure (abort, nothing classified)
#   report --task-id <id>
#          Prints the human table from an existing red-first-report.json. Exit 0.
#
# NEVER mutates the working tree of a probed repo: no stash/reset --hard/clean.
# Isolation is `git worktree add --detach` (index/worktree untouched) and is
# PROVEN (worktree status clean + non-test-file shas match base) before any
# test runs; failure aborts rc=2 with the evidence in the log, never silently.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-"$0"}")" 2>/dev/null && pwd)"
PROJECT_ROOT="${LEADV2_PROJECT_ROOT:-${CLAUDE_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}}"
export LEADV2_PROJECT_ROOT="${PROJECT_ROOT}"
# shellcheck source=leadv2-helpers.sh
source "${SCRIPT_DIR}/leadv2-helpers.sh"
_lv2_load_paths
# shellcheck source=leadv2-temp.sh
source "${SCRIPT_DIR}/leadv2-temp.sh"
# leadv2-helpers.sh sets -e on source and that persists in this shell; this
# script's control flow deliberately continues past per-repo failures to
# accumulate setup_fail and choose its own exit code (0/1/2), so cancel it
# back out here. -u and pipefail (set above) stay in effect.
set +e

log() { printf -- '[red-first] %s\n' "$*" >&2; }

TEST_GLOB_REGEX='(^|/)tests?/.*\.(sh|py)$|(^|/)scripts/tests/.*\.sh$'
TIMEOUT_S="${LEADV2_RED_FIRST_TIMEOUT_S:-300}"

_rfg_sha1() {
  if command -v sha1sum >/dev/null 2>&1; then sha1sum "$1" 2>/dev/null | awk '{print $1}'
  else shasum -a 1 "$1" 2>/dev/null | awk '{print $1}'; fi
}
_rfg_sha1_stdin() {
  if command -v sha1sum >/dev/null 2>&1; then sha1sum 2>/dev/null | awk '{print $1}'
  else shasum -a 1 2>/dev/null | awk '{print $1}'; fi
}

# Portable timeout (macOS has no `timeout`): a python wrapper, mirroring the
# subprocess.Popen+communicate(timeout=) pattern already used by
# architect_prepass in leadv2-dispatch-code.sh.
_rfg_run_test() { # <script_abs_path> <cwd> <outfile> -> prints exit code on stdout
  python3 - "$1" "$2" "$3" "$TIMEOUT_S" <<'PY'
import os, subprocess, sys
script, cwd, outfile, timeout_s = sys.argv[1:5]
try:
    proc = subprocess.run(["bash", script], cwd=cwd, timeout=int(timeout_s),
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           text=True, env=os.environ.copy())
    open(outfile, "w").write(proc.stdout or "")
    print(proc.returncode)
except subprocess.TimeoutExpired as exc:
    out = exc.stdout if isinstance(exc.stdout, str) else (exc.stdout or b"").decode("utf-8", "replace")
    open(outfile, "w").write((out or "") + "\n[red-first] TIMEOUT after %ss\n" % timeout_s)
    print(124)
except FileNotFoundError:
    open(outfile, "w").write("[red-first] script not found: %s\n" % script)
    print(127)
PY
}

# newline-separated repo-relative paths: tracked AM diff + untracked-new, deduped
_rfg_changed_paths() { # <repo> <base>
  local repo="$1" base="$2"
  {
    git -C "$repo" diff --name-only --diff-filter=AM "$base" -- . 2>/dev/null
    git -C "$repo" status --porcelain --untracked-files=all 2>/dev/null \
      | awk '$1=="??"{ $0=substr($0,4); print }'
  } | sort -u
}

_rfg_test_files() { # <repo> <base> -> subset of changed paths matching test globs
  _rfg_changed_paths "$1" "$2" | grep -E "$TEST_GLOB_REGEX" || true
}

# Prove worktree isolation before any test runs. Appends evidence to <log>.
# Returns 0 ok / 1 fail. Never mutates $repo.
_rfg_prove_isolation() { # <repo> <base> <wt> <log> <non_test_files_str>
  local repo="$1" base="$2" wt="$3" log_file="$4" non_test_files="$5"
  local ok=1 status_out
  {
    printf -- '--- isolation proof: repo=%s base=%s worktree=%s ---\n' "$repo" "$base" "$wt"
    status_out="$(git -C "$wt" status --porcelain)"
    if [[ -z "$status_out" ]]; then
      printf -- 'PASS: worktree status --porcelain is empty\n'
    else
      printf -- 'FAIL: worktree status --porcelain not empty:\n%s\n' "$status_out"
      ok=0
    fi
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      git -C "$repo" cat-file -e "${base}:${f}" 2>/dev/null || continue
      local base_sha wt_sha work_sha
      base_sha="$(git -C "$repo" show "${base}:${f}" 2>/dev/null | _rfg_sha1_stdin)"
      if [[ -f "${wt}/${f}" ]]; then wt_sha="$(_rfg_sha1 "${wt}/${f}")"; else wt_sha="MISSING"; fi
      work_sha="$(_rfg_sha1 "${repo}/${f}")"
      if [[ "$wt_sha" == "$base_sha" ]]; then
        printf -- 'PASS: %s worktree copy matches base HEAD content (sha1 %s)\n' "$f" "${base_sha:0:12}"
      else
        printf -- 'FAIL: %s worktree copy (%s) does not match base (%s)\n' "$f" "${wt_sha:0:12}" "${base_sha:0:12}"
        ok=0
      fi
      if [[ "$work_sha" != "$base_sha" ]]; then
        if [[ "$wt_sha" != "$work_sha" ]]; then
          printf -- 'PASS: %s worktree (pre-fix) differs from working tree (post-fix) as expected\n' "$f"
        else
          printf -- 'FAIL: %s worktree copy equals working tree — pre-fix isolation not proven\n' "$f"
          ok=0
        fi
      fi
    done <<< "$non_test_files"
  } >> "$log_file"
  [[ "$ok" -eq 1 ]]
}

# Process-global (see comment at trap site): scratch dir + worktrees to remove
# on exit, regardless of which function frame is active when the process ends.
scratch=""
manifest=""
cleanup_pairs=()
_rfg_cleanup() {
  local pair repo wt
  for pair in "${cleanup_pairs[@]:-}"; do
    [[ -z "$pair" ]] && continue
    repo="${pair%%|*}"; wt="${pair#*|}"
    git -C "$repo" worktree remove --force "$wt" >/dev/null 2>&1 || true
  done
  [[ -n "$scratch" ]] && rm -rf "$scratch"
}

cmd_probe() {
  local task_id="" base="HEAD" json=0
  local -a repos=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --task-id) task_id="$2"; shift 2 ;;
      --repo) repos+=("$2"); shift 2 ;;
      --base) base="$2"; shift 2 ;;
      --json) json=1; shift ;;
      *) log "probe: unknown arg $1"; return 2 ;;
    esac
  done
  [[ -n "$task_id" ]] || { log "probe: --task-id required"; return 2; }
  (( ${#repos[@]} > 0 )) || { log "probe: at least one --repo required"; return 2; }

  local out_dir="${LEADV2_HANDOFF_DIR}/${task_id}"
  mkdir -p "$out_dir"
  local report_json="${out_dir}/red-first-report.json"
  local gate_log="${out_dir}/red-first-gate.log"
  : > "$gate_log"

  local lock="/tmp/leadv2-red-first-${task_id}.lock"
  exec 9>"$lock"
  if ! flock -n 9; then
    log "another probe in progress for ${task_id} (lock: ${lock})"
    return 1
  fi

  # NOT `local`: an EXIT trap fires after this function's frame is popped, so a
  # local referenced inside the trap would be unbound under `set -u`. These are
  # process-global by design — this script always runs as a one-shot process.
  scratch="$(lv2_mktemp_dir leadv2-red-first)" || { log "mktemp failed"; return 2; }
  manifest="${scratch}/manifest.jsonl"
  : > "$manifest"
  cleanup_pairs=()
  trap _rfg_cleanup EXIT

  local setup_fail=0
  for repo_arg in "${repos[@]}"; do
    local repo; repo="$(cd "$repo_arg" 2>/dev/null && pwd -P)"
    if [[ -z "$repo" ]]; then
      log "repo not found: $repo_arg"; setup_fail=1; continue
    fi
    log "=== repo: ${repo} (base=${base}) ==="
    local test_files; test_files="$(_rfg_test_files "$repo" "$base")"
    if [[ -z "$test_files" ]]; then
      log "no changed test files in ${repo} vs ${base} — nothing to probe"
      continue
    fi
    local all_changed non_test_files
    all_changed="$(_rfg_changed_paths "$repo" "$base")"
    non_test_files="$(comm -23 <(printf '%s\n' "$all_changed") <(printf '%s\n' "$test_files") 2>/dev/null || true)"

    local wt
    wt="${scratch}/wt-$(basename "$repo")-$$-${RANDOM}"
    if ! git -C "$repo" worktree add --detach "$wt" "$base" >>"$gate_log" 2>&1; then
      log "git worktree add failed for ${repo} — see ${gate_log}"
      setup_fail=1
      continue
    fi
    cleanup_pairs+=("${repo}|${wt}")

    if ! _rfg_prove_isolation "$repo" "$base" "$wt" "$gate_log" "$non_test_files"; then
      log "isolation NOT proven for ${repo} — see ${gate_log}"
      setup_fail=1
      continue
    fi
    log "isolation proven for ${repo}"

    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      local new_at_head="false"
      git -C "$repo" cat-file -e "${base}:${f}" 2>/dev/null || new_at_head="true"
      mkdir -p "${wt}/$(dirname "$f")"
      cp "${repo}/${f}" "${wt}/${f}"
      chmod +x "${wt}/${f}" 2>/dev/null || true

      local pre_out post_out rc_pre rc_post
      pre_out="${scratch}/$(basename "$repo")__$(echo "$f" | tr '/' '_').pre.txt"
      post_out="${scratch}/$(basename "$repo")__$(echo "$f" | tr '/' '_').post.txt"
      rc_pre="$(_rfg_run_test "${wt}/${f}" "$wt" "$pre_out")"
      log "pre-fix  ${repo}#${f}: rc=${rc_pre}"
      rc_post="$(_rfg_run_test "${repo}/${f}" "$repo" "$post_out")"
      log "post-fix ${repo}#${f}: rc=${rc_post}"

      python3 -c '
import json, sys
d = dict(repo=sys.argv[1], file=sys.argv[2], new_at_head=(sys.argv[3]=="true"),
         rc_pre=int(sys.argv[4]), rc_post=int(sys.argv[5]),
         pre_file=sys.argv[6], post_file=sys.argv[7], working_copy=sys.argv[8])
print(json.dumps(d))
' "$repo" "$f" "$new_at_head" "$rc_pre" "$rc_post" "$pre_out" "$post_out" "${repo}/${f}" >> "$manifest"
    done <<< "$test_files"
  done

  if [[ "$setup_fail" -eq 1 ]]; then
    log "setup/isolation failure — aborting, nothing classified (see ${gate_log})"
    return 2
  fi

  local ctx_yaml="${out_dir}/context.yaml"
  python3 - "$task_id" "$base" "$report_json" "$manifest" "$ctx_yaml" "$json" <<'PY'
import json, re, sys, datetime

task_id, base, report_path, manifest_path, ctx_path, want_json = sys.argv[1:7]
LABEL_RE = re.compile(r'^[ \t]*(\[TEST\][ \t]*)?(PASS|FAIL):[ \t]*(.*)$')

def parse(text):
    out = []
    for line in (text or "").splitlines():
        m = LABEL_RE.match(line)
        if not m:
            continue
        outcome = m.group(2)
        rest = m.group(3).strip()
        label = rest.split(' — ', 1)[0].strip() if ' — ' in rest else rest
        out.append((label, outcome))
    return out

def to_map(ordered):
    counts = {}
    m = {}
    order = []
    for label, outcome in ordered:
        counts[label] = counts.get(label, 0) + 1
        key = (label, counts[label])
        m[key] = outcome
        order.append(key)
    return m, order

def regression_only_labels_from_source(path):
    try:
        lines = open(path, errors="replace").read().splitlines()
    except OSError:
        return {}
    out = {}
    for i, line in enumerate(lines):
        s = line.strip()
        if not s.startswith('# red-first: regression-only'):
            continue
        reason = s.split('—', 1)[1].strip() if '—' in s else (s.split('-', 2)[-1].strip() if s.count('-') >= 2 else "")
        j = i + 1
        while j < len(lines) and not lines[j].strip():
            j += 1
        if j < len(lines):
            out[('__SOURCE_LINE__', j)] = (lines[j], reason)
    return out

def label_is_exempt(label, source_markers, ctx_regression_only):
    if label in ctx_regression_only:
        return True, "declared in context.yaml acceptance.regression_only"
    for (_, _), (src_line, reason) in source_markers.items():
        if label and label in src_line:
            return True, reason or "declared via # red-first: regression-only comment"
    return False, None

ctx_regression_only = []
try:
    import yaml
    doc = yaml.safe_load(open(ctx_path)) or {}
    ctx_regression_only = ((doc.get('acceptance') or {}).get('regression_only') or [])
except Exception:
    pass

entries = []
if manifest_path:
    for line in open(manifest_path):
        line = line.strip()
        if line:
            entries.append(json.loads(line))

repos = {}
totals = dict(tests_touched=0, labels=0, red_proven=0, not_red=0, inconclusive=0, diff_broken=0, regression_only=0)
blocking_labels = []

for e in entries:
    repo, f = e['repo'], e['file']
    pre_text = open(e['pre_file'], errors="replace").read() if e['pre_file'] else ""
    post_text = open(e['post_file'], errors="replace").read() if e['post_file'] else ""
    pre_map, _ = to_map(parse(pre_text))
    post_map, post_order = to_map(parse(post_text))
    source_markers = regression_only_labels_from_source(e['working_copy'])

    seen = set()
    label_entries = []
    counts = dict(red_proven=0, not_red=0, inconclusive=0, diff_broken=0, regression_only=0)
    for key in post_order:
        if key in seen:
            continue
        seen.add(key)
        label, ordinal = key
        post_outcome = post_map[key]
        pre_outcome = pre_map.get(key)
        if post_outcome == 'FAIL':
            verdict = 'DIFF_BROKEN'
        elif pre_outcome == 'FAIL':
            verdict = 'RED_PROVEN'
        elif pre_outcome == 'PASS':
            verdict = 'NOT_RED'
        else:
            verdict = 'INCONCLUSIVE'

        exempt, reason = label_is_exempt(label, source_markers, ctx_regression_only)
        if verdict == 'NOT_RED' and exempt:
            bucket = 'regression_only'
            blocking = False
        else:
            bucket = verdict.lower()
            blocking = verdict in ('NOT_RED', 'DIFF_BROKEN')
        counts[bucket] += 1
        display_label = label if ordinal == 1 else f"{label} (#{ordinal})"
        label_entries.append(dict(label=display_label, pre=pre_outcome, post=post_outcome,
                                   verdict=verdict, exempt=bool(exempt), reason=reason))
        if blocking:
            blocking_labels.append(dict(file=f, label=display_label, verdict=verdict, repo=repo))

    repos.setdefault(repo, {'repo': repo, 'files': []})
    repos[repo]['files'].append(dict(path=f, new_at_head=e['new_at_head'], labels=label_entries, counts=counts))
    totals['tests_touched'] += 1
    totals['labels'] += len(label_entries)
    for k in ('red_proven', 'not_red', 'inconclusive', 'diff_broken', 'regression_only'):
        totals[k] += counts[k]

verdict = 'BLOCK' if blocking_labels else 'PASS'
report = dict(task_id=task_id, base=base,
              generated_at=datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
              repos=list(repos.values()), totals=totals, verdict=verdict, blocking_labels=blocking_labels)

with open(report_path, 'w') as fh:
    json.dump(report, fh, indent=2)
    fh.write('\n')

if want_json == '1':
    print(json.dumps(report, indent=2))
else:
    print(f"=== red-first: {task_id} base={base} ===")
    print(f"tests_touched={totals['tests_touched']} labels={totals['labels']} "
          f"red_proven={totals['red_proven']} not_red={totals['not_red']} "
          f"inconclusive={totals['inconclusive']} diff_broken={totals['diff_broken']} "
          f"regression_only={totals['regression_only']}")
    for r in repos.values():
        for fobj in r['files']:
            print(f"  {r['repo']}#{fobj['path']} new_at_head={fobj['new_at_head']} "
                  f"counts={fobj['counts']}")
    if blocking_labels:
        print(f"BLOCKING ({len(blocking_labels)}):")
        for b in blocking_labels:
            print(f"  [{b['verdict']}] {b['repo']}#{b['file']} :: {b['label']}")
    print(f"verdict={verdict}")

sys.exit(1 if blocking_labels else 0)
PY
  return $?
}

cmd_report() {
  local task_id=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --task-id) task_id="$2"; shift 2 ;;
      *) log "report: unknown arg $1"; return 2 ;;
    esac
  done
  [[ -n "$task_id" ]] || { log "report: --task-id required"; return 2; }
  local report_json="${LEADV2_HANDOFF_DIR}/${task_id}/red-first-report.json"
  [[ -f "$report_json" ]] || { log "no report at ${report_json} — run probe first"; return 1; }
  python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
t = d["totals"]
task_id, base, verdict = d["task_id"], d["base"], d["verdict"]
print("=== red-first: {} base={} ===".format(task_id, base))
print("tests_touched={} labels={} red_proven={} not_red={} inconclusive={} diff_broken={} regression_only={}".format(
    t["tests_touched"], t["labels"], t["red_proven"], t["not_red"],
    t["inconclusive"], t["diff_broken"], t["regression_only"]))
for b in d["blocking_labels"]:
    print("  [{}] {}#{} :: {}".format(b["verdict"], b["repo"], b["file"], b["label"]))
print("verdict={}".format(verdict))
' "$report_json"
}

main() {
  local sub="${1:-}"
  [[ -n "$sub" ]] && shift || true
  case "$sub" in
    probe) cmd_probe "$@" ;;
    report) cmd_report "$@" ;;
    *) log "usage: leadv2-red-first-gate.sh {probe|report} ..."; return 2 ;;
  esac
}

main "$@"
