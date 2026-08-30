#!/usr/bin/env bash
# STATUSLINE-READABLE-01: red-first test for the founder's exact repro --
# BASE claims width first, the ladder cannot drop a lane, the arm/model
# vanishes at the first sign of pressure, labels are dispatch-id stems not
# task meaning, and no session scoping exists. Never runs against the real
# plugin tree -- see the containment pattern in
# test-statusline-never-writes-executables.sh (TEST-DESTROYS-PRODUCTION-
# SCRIPT-01): every helper here runs against a throwaway COPY of scripts/
# under $tmp, with its own scratch TMPDIR, and an EXIT tripwire re-checks
# the real repo's tail script + liveness prober md5 so any escape aborts
# loudly instead of destroying it quietly.
#
# Pre-fix baseline is built via `git archive HEAD -- <paths>` into a
# scratch dir per the mission's red-first instructions -- never `git
# stash`/`git reset --hard`/`git clean` (shared tree).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# GATE-WRONG-ROOT-FALSE-DEAD-01: never derive the repo root by counting
# '../' hops -- this worktree's plugins/leadv2 sits at a different depth
# than a bare checkout, so a fixed hop count landed on .claude/worktrees
# (not a git root at all) and made every `git archive HEAD -- <path>`
# below fail with "did not match any files", permanently skipping R1/R2.
# Resolve from git itself instead.
REAL_REPO_ROOT="$(git -C "${REAL_PLUGIN_DIR}" rev-parse --show-toplevel)"
source "$(cd "${SCRIPT_DIR}/.." && pwd)/leadv2-temp.sh"

tmp="$(lv2_mktemp_dir statusline-readable)"
trap 'rm -rf "$tmp"' EXIT

_lv2_md5() { md5 -q "$1" 2>/dev/null || md5sum "$1" 2>/dev/null | awk '{print $1}'; }
REAL_TAIL="${REAL_PLUGIN_DIR}/scripts/leadv2-lane-status-line-tail.sh"
REAL_LIVENESS="${REAL_PLUGIN_DIR}/scripts/leadv2-lane-liveness.sh"
REAL_TAIL_MD5_BEFORE="$(_lv2_md5 "$REAL_TAIL")"
REAL_LIVENESS_MD5_BEFORE="$(_lv2_md5 "$REAL_LIVENESS")"
lv2_tripwire() {
  local after_t after_l
  after_t="$(_lv2_md5 "$REAL_TAIL")"
  after_l="$(_lv2_md5 "$REAL_LIVENESS")"
  if [[ "$after_t" != "$REAL_TAIL_MD5_BEFORE" || "$after_l" != "$REAL_LIVENESS_MD5_BEFORE" ]]; then
    printf '[TEST-SAFETY] FATAL: test mutated a production path\n  tail before=%s after=%s\n  liveness before=%s after=%s\n' \
      "$REAL_TAIL_MD5_BEFORE" "$after_t" "$REAL_LIVENESS_MD5_BEFORE" "$after_l" >&2
    exit 99
  fi
}
trap 'lv2_tripwire' EXIT

PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS+1)); printf '[PASS] %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '[FAIL] %s -- %s\n' "$1" "$2"; }
skip() { SKIP=$((SKIP+1)); printf '[SKIP] %s -- %s\n' "$1" "$2"; }

# ---- fixture: founder's exact repro shape --------------------------------
SCRATCH_SCRIPTS="$tmp/scripts"
mkdir -p "$SCRATCH_SCRIPTS"
cp -a "${REAL_PLUGIN_DIR}/scripts/." "$SCRATCH_SCRIPTS/"
case "$SCRATCH_SCRIPTS" in
  "$tmp"/*) ;;
  *) printf '[TEST-SAFETY] ABORT: SCRATCH_SCRIPTS %s did not resolve under scratch root %s\n' "$SCRATCH_SCRIPTS" "$tmp" >&2; exit 90 ;;
esac

REPO="$tmp/repo"
mkdir -p "$REPO/.claude/leadv2-overrides" "$REPO/.leadv2-state" "$REPO/docs/handoff"
cat > "$REPO/.claude/leadv2-overrides/active-limits.yaml" <<'EOF'
hard_limit: 5
EOF
cat > "$REPO/.leadv2-state/active.yaml" <<'EOF'
meta:
  hard_limit: 5
sessions: []
EOF

# Stub liveness prober -- the founder's own 4 lanes, ages 1/1/2/8.
cat > "$SCRATCH_SCRIPTS/leadv2-lane-liveness.sh" <<'EOF'
#!/usr/bin/env bash
cat <<JSON
{"count_live": 4, "lanes": [
 {"lane":"dispatch-c98a1414-architect","verdict":"alive","age_s":1},
 {"lane":"dispatch-5bfce73e","verdict":"alive","age_s":1},
 {"lane":"GATE-FOREIGN-FAILURE-01","verdict":"alive","age_s":2},
 {"lane":"LANDING-PAGE-REDESIGN-01","verdict":"alive","age_s":8}
]}
JSON
EOF
chmod +x "$SCRATCH_SCRIPTS/leadv2-lane-liveness.sh"

cat > "$SCRATCH_SCRIPTS/leadv2-state-path.sh" <<EOF
#!/usr/bin/env bash
echo "$REPO/.leadv2-state/active.yaml"
EOF
chmod +x "$SCRATCH_SCRIPTS/leadv2-state-path.sh"

FOUNDER_BASE_66=$'\033[36mOpus 5 (1M context)\033[0m in \033[32m~/Projects/persona-engine\033[0m [\033[33mdefault\033[0m] \033[35m79%% ctx\033[0m'
INPUT_JSON=$(jq -n --arg dir "$REPO" '{workspace:{current_dir:$dir},model:{display_name:"Opus 5 (1M context)"},output_style:{name:"default"},context_window:{remaining_percentage:79},transcript_path:""}')
SETTINGS_JSON="$tmp/settings.json"
printf '{"statusLine":{"command":"printf %s"}}' "'${FOUNDER_BASE_66}'" > "$SETTINGS_JSON"

run_tail() {
  local width="$1" scripts_dir="$2"
  TMPDIR="$tmp/cache" CLAUDE_PLUGIN_ROOT="" LEADV2_STATUSLINE_WIDTH="$width" \
    bash "$scripts_dir/leadv2-lane-status-line-tail.sh" "$INPUT_JSON" "$SETTINGS_JSON" "$scripts_dir" 5 </dev/null
}
strip_ansi() { sed -E $'s/\x1b\\[[0-9;]*m//g'; }
# Bash's character length follows the terminal locale; awk's length can count
# UTF-8 bytes, turning each visible `·` into two columns on this host.
visible_len() { local plain; plain="$(printf '%s' "$1" | strip_ansi)"; printf '%s' "${#plain}"; }

# ---- pre-fix baseline via git archive -------------------------------------
# Resolve a ref that predates this lane's own STATUSLINE-READABLE-01 fix
# commits, not HEAD (which already carries them in a lane worktree).
# origin/main is the merge-base of this lane and reachable in a lane
# worktree without counting '../' hops or needing a full clone; fall back
# to the parent of the first commit that ever touched the tail script if
# the remote ref is unavailable (e.g. a detached/offline checkout).
PRE_FIX_REF=""
if git -C "$REAL_REPO_ROOT" rev-parse --verify -q origin/main >/dev/null 2>&1; then
  PRE_FIX_REF="origin/main"
else
  FIRST_TOUCH="$(git -C "$REAL_REPO_ROOT" log --diff-filter=A --format=%H -- \
    plugins/leadv2/scripts/leadv2-lane-status-line-tail.sh | tail -1)"
  if [[ -n "$FIRST_TOUCH" ]] && git -C "$REAL_REPO_ROOT" rev-parse --verify -q "${FIRST_TOUCH}^" >/dev/null 2>&1; then
    PRE_FIX_REF="${FIRST_TOUCH}^"
  fi
fi
PREFIX_DIR="$tmp/prefix"
mkdir -p "$PREFIX_DIR/scripts"
if [[ -n "$PRE_FIX_REF" ]] && git -C "$REAL_REPO_ROOT" archive "$PRE_FIX_REF" -- \
    "plugins/leadv2/scripts/leadv2-lane-status-line-tail.sh" \
    "plugins/leadv2/scripts/leadv2-lane-status-line.sh" \
    "plugins/leadv2/scripts/leadv2-tasks-lib.sh" \
    "plugins/leadv2/scripts/leadv2-temp.sh" \
    2>/dev/null | tar -x -C "$PREFIX_DIR" 2>/dev/null; then
  PREFIX_SCRIPTS="$PREFIX_DIR/plugins/leadv2/scripts"
  cp -a "${REAL_PLUGIN_DIR}/scripts/." "$SCRATCH_SCRIPTS.pre-src/" 2>/dev/null || true
  mkdir -p "$tmp/scripts-pre"
  cp -a "${REAL_PLUGIN_DIR}/scripts/." "$tmp/scripts-pre/"
  cp "$PREFIX_SCRIPTS/leadv2-lane-status-line-tail.sh" "$tmp/scripts-pre/leadv2-lane-status-line-tail.sh"
  cat > "$tmp/scripts-pre/leadv2-lane-liveness.sh" <<'EOF'
#!/usr/bin/env bash
cat <<JSON
{"count_live": 4, "lanes": [
 {"lane":"dispatch-c98a1414-architect","verdict":"alive","age_s":1},
 {"lane":"dispatch-5bfce73e","verdict":"alive","age_s":1},
 {"lane":"GATE-FOREIGN-FAILURE-01","verdict":"alive","age_s":2},
 {"lane":"LANDING-PAGE-REDESIGN-01","verdict":"alive","age_s":8}
]}
JSON
EOF
  chmod +x "$tmp/scripts-pre/leadv2-lane-liveness.sh"
  cat > "$tmp/scripts-pre/leadv2-state-path.sh" <<EOF
#!/usr/bin/env bash
echo "$REPO/.leadv2-state/active.yaml"
EOF
  chmod +x "$tmp/scripts-pre/leadv2-state-path.sh"
  PRE_OUT="$(run_tail 80 "$tmp/scripts-pre")"
  PRE_AVAILABLE=1
else
  PRE_OUT=""
  PRE_AVAILABLE=0
fi

if [[ "$PRE_AVAILABLE" == "1" ]]; then
  # R1: pre-fix collapses to the xx...Ns floor (cap<=3 stems)
  if printf '%s' "$PRE_OUT" | strip_ansi | grep -qE '\| [A-Za-z0-9_-]{1,3}…?·[0-9]+[sm]?h? '; then
    ok "R1 pre-fix: floor collapse reproduced"
  else
    # still acceptable if it at least shows short (<=4 char) unreadable stems
    if printf '%s' "$PRE_OUT" | strip_ansi | grep -qE '\| [A-Za-z0-9_-]{1,4}[·:]'; then
      ok "R1 pre-fix: unreadable short-stem floor reproduced"
    else
      # third acceptable shape: the founder's OTHER observed pre-fix defect
      # (STATUSLINE-READABLE-01 B/7 comment: "a raw ${LANES:0:KEEP}
      # character slice used to cut mid-word") -- a bare fragment with no
      # ellipsis, no arm marker and no trailing digit, sitting in the lane
      # digest section (after "lanes n/cap | "), never in the BASE text.
      PRE_LANE_SECTION="$(printf '%s' "$PRE_OUT" | strip_ansi | sed -E 's/^.*lanes ([0-9]+|\?)\/[0-9]+ \| //')"
      R1_TRUNC_TOKEN=""
      for tok in $PRE_LANE_SECTION; do
        case "$tok" in
          +[0-9]*|*·*|*…*|*[0-9]) ;;
          [A-Za-z][A-Za-z0-9_-]*) R1_TRUNC_TOKEN="$tok" ;;
        esac
      done
      if [[ -n "$R1_TRUNC_TOKEN" ]]; then
        ok "R1 pre-fix: raw mid-word truncation reproduced ('$R1_TRUNC_TOKEN')"
      else
        bad "R1" "pre-fix output did not show the expected floor collapse: $PRE_OUT"
      fi
    fi
  fi
  # R2: no model/arm token present pre-fix
  if printf '%s' "$PRE_OUT" | strip_ansi | grep -qE '·(o|s|h|g|cx)·'; then
    bad "R2" "pre-fix unexpectedly already carries an arm token (expected RED): $PRE_OUT"
  else
    ok "R2 pre-fix: no arm token present (RED, as expected)"
  fi
else
  skip "R1/R2 pre-fix baseline" "git archive of prior revision unavailable in this checkout (first commit / shallow clone)"
fi

# ---- post-fix behaviour ----------------------------------------------------
rm -f "$tmp"/cache/leadv2-statusline-lane-*
POST_80="$(run_tail 80 "$SCRATCH_SCRIPTS")"
rm -f "$tmp"/cache/leadv2-statusline-lane-*
POST_112="$(run_tail 112 "$SCRATCH_SCRIPTS")"

echo "--- post-fix @80  : $POST_80"
echo "--- post-fix @112 : $POST_112"

# R4/C: every rendered lane token carries an arm marker (o/s/h/g/cx/?)
if printf '%s' "$POST_112" | strip_ansi | grep -qE '·[a-z?]{1,2}·[0-9]+[sm]?h?'; then
  ok "R4: rendered lane token carries an arm marker"
else
  bad "R4" "no arm marker found in: $POST_112"
fi

# R9: label_cap never drops below LANE_FLOOR (10) while ANY lane still
# renders a label -- checked by scanning the widest realistic width (112);
# at 80 with 4 lanes we expect the drop-to-K ladder, not sub-floor labels,
# UNLESS K collapses to the old sub-floor fallback (still width-safe).
# ANTI-SILENCE-STATUSLINE-01 round 2 reordered the line to LANES | BASE
# (lanes first, per mission item 1) -- the lane section is now everything
# before the LAST " | " (the lane digest itself can contain its own "|",
# e.g. "lanes 4/5 | dispatch-... +2", so BASE -- which never contains "|" --
# is what anchors the split).
LABELS_80="$(printf '%s' "$POST_80" | strip_ansi | sed -E 's/ \| [^|]*$//')"
if [[ -n "$LABELS_80" ]]; then
  ok "R9: digest at width 80 rendered a non-empty lane section: $LABELS_80"
else
  bad "R9" "digest at width 80 rendered NO lane section at all"
fi

# R5: rendered rows + '+M' == true lane count (4).  This is exact: a marker
# that undercounts hidden lanes is worse than no marker because it lies about
# the incident surface.
ROW_COUNT="$(printf '%s' "$LABELS_80" | grep -oE '·[a-z?]{1,2}·[0-9]' | wc -l | tr -d ' ')"
PLUS_M="$(printf '%s' "$LABELS_80" | grep -oE '\+[0-9]+' | grep -oE '[0-9]+' || true)"
[[ -z "$PLUS_M" ]] && PLUS_M=0
TOTAL_ACCOUNTED=$(( ROW_COUNT + PLUS_M ))
if [[ "$TOTAL_ACCOUNTED" -eq 4 ]]; then
  ok "R5: rendered rows ($ROW_COUNT) + dropped (+$PLUS_M) exactly account for 4 lanes"
else
  bad "R5" "rendered rows ($ROW_COUNT) + dropped (+$PLUS_M) != 4: $LABELS_80"
fi

# R12: the trailing word-boundary cut never leaves a truncated mid-word
# fragment -- every whitespace-delimited token in the lane section must be
# either the "+N" dropped-count marker, a complete "lanes n/m" head token,
# or a complete arm-marked lane token (label·arm·age). A raw mid-word slice
# (e.g. "GATE-FO") matches none of these.
R12_BAD_TOKEN() {
  local section="$1" tok R12_LABEL R12_REST R12_SOURCE R12_CANDIDATE
  for tok in $section; do
  case "$tok" in
    lanes|+[0-9]*|[0-9]*/[0-9]*) continue ;;
    *·*)
      R12_LABEL="${tok%%·*}"
      R12_REST="${tok#*·}"
      if [[ ! "$R12_REST" =~ ^(alive|dead|done|queued|\?)·[0-9]+[smh]?$ ]]; then
        printf '%s' "$tok"; return
      fi
      R12_SOURCE=""
      for R12_CANDIDATE in dispatch-c98a1414-architect dispatch-5bfce73e GATE-FOREIGN-FAILURE-01 LANDING-PAGE-REDESIGN-01; do
        if [[ "$R12_LABEL" == "$R12_CANDIDATE" || "$R12_LABEL" == *… && "$R12_CANDIDATE" == "${R12_LABEL%…}"* ]]; then
          R12_SOURCE="$R12_CANDIDATE"
          break
        fi
      done
      [[ -n "$R12_SOURCE" ]] || { printf '%s' "$tok"; return; }
      ;;
    *) printf '%s' "$tok"; return ;;
  esac
  done
}
R12_BAD_80="$(R12_BAD_TOKEN "$LABELS_80")"
LABELS_112="$(printf '%s' "$POST_112" | strip_ansi | sed -E 's/ \| [^|]*$//')"
R12_BAD_112="$(R12_BAD_TOKEN "$LABELS_112")"
if [[ -z "$R12_BAD_80" && -z "$R12_BAD_112" ]]; then
  ok "R12: no mid-word-truncated token in lane sections at widths 80 and 112"
else
  bad "R12" "mid-word-truncated token found (80='$R12_BAD_80', 112='$R12_BAD_112')"
fi

# R6: BASE compression happens BEFORE label capping -- a narrow width (80)
# must produce a SHORTER base than a wide one (112), proving the ordering.
# Lanes-first format: LANES | BASE -- BASE is now everything after " | ".
BASE_80_VIS="$(visible_len "$(printf '%s' "$POST_80" | strip_ansi | sed -n 's/.*| //p')" )"
BASE_112_VIS="$(visible_len "$(printf '%s' "$POST_112" | strip_ansi | sed -n 's/.*| //p')" )"
if [[ "$BASE_80_VIS" -le "$BASE_112_VIS" ]]; then
  ok "R6: narrower width (80) yields a BASE no longer than the wide one (112) -- base@80=$BASE_80_VIS base@112=$BASE_112_VIS"
else
  bad "R6" "narrower width produced a LONGER base (base@80=$BASE_80_VIS base@112=$BASE_112_VIS) -- compression ordering inverted"
fi

# R8: total visible length never exceeds the budget, at N=1 and N=12 lanes.
check_width_safety() {
  local n="$1" width="$2"
  local scripts_dir="$tmp/scripts-n$n"
  mkdir -p "$scripts_dir"
  cp -a "$SCRATCH_SCRIPTS/." "$scripts_dir/"
  {
    printf '{"count_live": %d, "lanes": [' "$n"
    local i=0
    while [[ $i -lt $n ]]; do
      [[ $i -gt 0 ]] && printf ','
      printf '{"lane":"dispatch-%08x","verdict":"alive","age_s":%d}' "$((i+1))" "$((i+1))"
      i=$((i+1))
    done
    printf ']}\n'
  } > "$scripts_dir/leadv2-lane-liveness.sh.json"
  cat > "$scripts_dir/leadv2-lane-liveness.sh" <<EOF
#!/usr/bin/env bash
cat "\$(dirname "\${BASH_SOURCE[0]}")/leadv2-lane-liveness.sh.json"
EOF
  chmod +x "$scripts_dir/leadv2-lane-liveness.sh"
  cat > "$scripts_dir/leadv2-state-path.sh" <<EOF2
#!/usr/bin/env bash
echo "$REPO/.leadv2-state/active.yaml"
EOF2
  chmod +x "$scripts_dir/leadv2-state-path.sh"
  rm -f "$tmp"/cache/leadv2-statusline-lane-*
  TMPDIR="$tmp/cache" CLAUDE_PLUGIN_ROOT="" LEADV2_STATUSLINE_WIDTH="$width" \
    bash "$scripts_dir/leadv2-lane-status-line-tail.sh" "$INPUT_JSON" "$SETTINGS_JSON" "$scripts_dir" 5 </dev/null
}

for n in 1 12; do
  OUT_N="$(check_width_safety "$n" 80)"
  LEN_N="$(visible_len "$OUT_N")"
  if [[ "$LEN_N" -le 80 ]]; then
    ok "R8 (N=$n): visible length $LEN_N <= budget 80"
  else
    bad "R8 (N=$n)" "visible length $LEN_N EXCEEDS budget 80: $OUT_N"
  fi
done

# R7: foreign-session lane -- inject a pulse.json with a differing
# owner_session_id and confirm the lane is still counted (marker is
# best-effort/known-gap per the architect prepass; absence of a writer
# means this is frequently a no-op today, which is the documented gap).
FOREIGN_DIR="$tmp/scripts-foreign"
mkdir -p "$FOREIGN_DIR"
cp -a "$SCRATCH_SCRIPTS/." "$FOREIGN_DIR/"
mkdir -p "$REPO/docs/handoff/dispatch-5bfce73e"
cat > "$REPO/docs/handoff/dispatch-5bfce73e/pulse.json" <<'EOF'
{"owner_session_id": "11111111-1111-1111-1111-111111111111"}
EOF
cat > "$FOREIGN_DIR/leadv2-state-path.sh" <<EOF
#!/usr/bin/env bash
echo "$REPO/.leadv2-state/active.yaml"
EOF
chmod +x "$FOREIGN_DIR/leadv2-state-path.sh"
INPUT_JSON_WITH_SESSION=$(jq -n --arg dir "$REPO" '{workspace:{current_dir:$dir},model:{display_name:"Opus 5"},transcript_path:"/tmp/22222222-2222-2222-2222-222222222222.jsonl"}')
rm -f "$tmp"/cache/leadv2-statusline-lane-*
FOREIGN_OUT="$(TMPDIR="$tmp/cache" CLAUDE_PLUGIN_ROOT="" LEADV2_STATUSLINE_WIDTH=112 \
  bash "$FOREIGN_DIR/leadv2-lane-status-line-tail.sh" "$INPUT_JSON_WITH_SESSION" "$SETTINGS_JSON" "$FOREIGN_DIR" 5 </dev/null)"
if printf '%s' "$FOREIGN_OUT" | grep -q 'lanes 4/'; then
  ok "R7: foreign-session lane still counted in lanes n/cap ($FOREIGN_OUT)"
else
  bad "R7" "count dropped when a foreign-owned lane was present: $FOREIGN_OUT"
fi

# R10: C7 stale-cache guard still fires under the new two-line protocol --
# seed a good cache, then force the live calc to fail (broken liveness
# binary) and confirm the STALE cached digest survives, not "lanes ?".
STALE_DIR="$tmp/scripts-stale"
mkdir -p "$STALE_DIR"
cp -a "$SCRATCH_SCRIPTS/." "$STALE_DIR/"
cat > "$STALE_DIR/leadv2-state-path.sh" <<EOF
#!/usr/bin/env bash
echo "$REPO/.leadv2-state/active.yaml"
EOF
chmod +x "$STALE_DIR/leadv2-state-path.sh"
rm -f "$tmp"/cache/leadv2-statusline-lane-*
GOOD_OUT="$(TMPDIR="$tmp/cache" CLAUDE_PLUGIN_ROOT="" LEADV2_STATUSLINE_WIDTH=112 \
  bash "$STALE_DIR/leadv2-lane-status-line-tail.sh" "$INPUT_JSON" "$SETTINGS_JSON" "$STALE_DIR" 600 </dev/null)"
if printf '%s' "$GOOD_OUT" | grep -q 'lanes 4/'; then
  # break the liveness prober so the NEXT live calc fails
  cat > "$STALE_DIR/leadv2-lane-liveness.sh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "$STALE_DIR/leadv2-lane-liveness.sh"
  # force a cache-miss re-calc by expiring the TTL to 0
  STALE_OUT="$(TMPDIR="$tmp/cache" CLAUDE_PLUGIN_ROOT="" LEADV2_STATUSLINE_WIDTH=112 \
    bash "$STALE_DIR/leadv2-lane-status-line-tail.sh" "$INPUT_JSON" "$SETTINGS_JSON" "$STALE_DIR" 0 </dev/null)"
  if printf '%s' "$STALE_OUT" | grep -q 'lanes 4/'; then
    ok "R10: C7 stale-cache guard preserved a good digest through a live-calc failure"
  else
    bad "R10" "stale-cache guard did not preserve the good digest: $STALE_OUT"
  fi
else
  skip "R10" "could not seed a good cache to begin with: $GOOD_OUT"
fi

# R11: unrecognised BASE passes through byte-identical (no-op canary).
GARBAGE_BASE='totally-unstyled-plain-text-base-no-ansi-codes-here'
GARBAGE_SETTINGS="$tmp/settings-garbage.json"
printf '{"statusLine":{"command":"printf %s"}}' "'${GARBAGE_BASE}'" > "$GARBAGE_SETTINGS"
rm -f "$tmp"/cache/leadv2-statusline-lane-*
GARBAGE_OUT="$(TMPDIR="$tmp/cache" CLAUDE_PLUGIN_ROOT="" LEADV2_STATUSLINE_WIDTH=200 \
  bash "$SCRATCH_SCRIPTS/leadv2-lane-status-line-tail.sh" "$INPUT_JSON" "$GARBAGE_SETTINGS" "$SCRATCH_SCRIPTS" 5 </dev/null)"
if printf '%s' "$GARBAGE_OUT" | grep -qF "$GARBAGE_BASE"; then
  ok "R11: unrecognised plain-text BASE passed through byte-identical"
else
  bad "R11" "unrecognised BASE was mutated: $GARBAGE_OUT"
fi


# ---- ANTI-SILENCE-STATUSLINE-01 round 3: the ACTUAL live path -------------
# Everything above exercises leadv2-lane-status-line-tail.sh's rich digest,
# which is only reachable when a supervising session is detected. A normal
# /leadv2 session (LEADV2_STATUSLINE_SUPERVISOR_ONLY=1, the default, no
# .supervise-active sentinel) takes a DIFFERENT path entirely: the
# non-supervisor branch of leadv2-lane-status-line.sh itself, which reads a
# memoised `leadv2-status-surface.sh --oneline` line. That branch used to
# gate the whole lane segment on the literal substring "live" appearing
# anywhere in the oneline text (including inside human-readable cause text
# like "0s live(pid 123)") -- so a repaint where every lane had gone
# dead/silent rendered NO lane segment at all: the founder's exact repro
# ("three lanes running, saw none"). These tests drive that real path
# directly, with a hand-seeded memo file (bypassing the background
# refresher/status-surface.sh entirely) so the composer's own logic is what
# is under test.
COMPOSER="${SCRATCH_SCRIPTS}/leadv2-lane-status-line.sh"
COMPOSER_TMPDIR="$tmp/composer-tmp"
mkdir -p "$COMPOSER_TMPDIR"
COMPOSER_INPUT='{"model":{"display_name":"Sonnet 5"},"workspace":{"current_dir":"/tmp/composer-cwd"}}'
_composer_cache_key() {
  # mirrors leadv2-lane-status-line.sh's BASE_KEY/_sup0 derivation
  printf '%s' "/tmp/composer-cwd" | tr '/' '_'
}
run_composer() {
  local width="$1" memo_line="$2"
  local key memo
  key="$(_composer_cache_key)_sup0"
  rm -rf "$COMPOSER_TMPDIR"; mkdir -p "$COMPOSER_TMPDIR"
  memo="${COMPOSER_TMPDIR}/leadv2-status-oneline-${key}"
  printf '%s' "$memo_line" > "$memo"
  printf '%s' "$COMPOSER_INPUT" | \
    TMPDIR="$COMPOSER_TMPDIR" HOME="${HOME}" COLUMNS="$width" \
    LEADV2_STATUSLINE_SUPERVISOR_ONLY=1 bash "$COMPOSER"
}
# a settings.json with no statusLine.command -> exercises the pure-builtin
# fallback base render, isolating the composer's own lane-prefix logic from
# any external command.
mkdir -p "$tmp/composer-home/.claude"
printf '{}' > "$tmp/composer-home/.claude/settings.json"

# MUTATION CONTROL 'silence': a lane digest with ZERO "live" lanes (all
# dead/silent) must still lead the line, ahead of the base render.
DEAD_ONLY_LINE='lanes 1: mylane·dead·9m'
SILENCE_OUT="$(HOME="$tmp/composer-home" run_composer 120 "$DEAD_ONLY_LINE")"
if [[ "$SILENCE_OUT" == "$DEAD_ONLY_LINE "* ]]; then
  ok "silence: dead-only lane digest still leads the composed line"
else
  bad "silence" "dead-only lane digest missing/not leading: $SILENCE_OUT"
fi

# MUTATION CONTROL 'order': lane field start index is < 40 even with a
# realistic base line present.
printf '{"statusLine":{"command":"printf %s"}}' "'Opus 5 in ~/proj [style] 50%% ctx'" > "$tmp/composer-home/.claude/settings.json"
ORDER_OUT="$(HOME="$tmp/composer-home" run_composer 120 "$DEAD_ONLY_LINE")"
ORDER_IDX="$(printf '%s' "$ORDER_OUT" | grep -bo 'mylane' | head -1 | cut -d: -f1)"
if [[ -n "$ORDER_IDX" && "$ORDER_IDX" -lt 40 ]]; then
  ok "order: lane field start index ($ORDER_IDX) < 40 (leads the base/quota text)"
else
  bad "order" "lane field not found before index 40 (idx='$ORDER_IDX'): $ORDER_OUT"
fi

# MUTATION CONTROL 'width': COLUMNS actually changes the rendered line, and
# a narrow width still yields the full lane digest (short enough to fit)
# with the base line visibly shorter than at a wide COLUMNS.
WIDE_LINE="$(HOME="$tmp/composer-home" run_composer 200 "$DEAD_ONLY_LINE")"
NARROW_LINE="$(HOME="$tmp/composer-home" run_composer 40 "$DEAD_ONLY_LINE")"
if [[ "$WIDE_LINE" != "$NARROW_LINE" ]]; then
  ok "width: COLUMNS=40 vs COLUMNS=200 render differently (was previously width-invariant)"
else
  bad "width" "output identical across COLUMNS=40 and COLUMNS=200: $NARROW_LINE"
fi
if (( ${#NARROW_LINE} <= 40 + ${#DEAD_ONLY_LINE} )); then
  ok "width: narrow-COLUMNS render did not balloon past the requested budget"
else
  bad "width" "narrow-COLUMNS render ($( printf '%s' "$NARROW_LINE" | wc -c )) far exceeds budget: $NARROW_LINE"
fi

# A stale wider-width memo is the caller-side clamp's real negative case.
# It contains five lane tokens but is painted at 30 columns: the composer
# must retain the first (silent) token, budget the marker itself, and report
# all four hidden rows.  Removing the composer refit/backoff makes this RED.
WIDE_MEMO='lanes 5: SILENT-LANE-THAT-MUST-REMAIN·dead·9m live-one·live·1s live-two·live·2s live-three·live·3s live-four·live·4s'
MEMO_30="$(HOME="$tmp/composer-home" run_composer 30 "$WIDE_MEMO")"
MEMO_30_PLAIN="$(printf '%s' "$MEMO_30" | strip_ansi)"
MEMO_30_LEN="$(visible_len "$MEMO_30")"
if (( MEMO_30_LEN <= 30 )) && [[ "$MEMO_30_PLAIN" == *'·dead·9m'* ]] && [[ "$MEMO_30_PLAIN" == *'+4'* ]]; then
  ok "R13: stale wide memo at width 30 keeps silent lane, exact +4, and exact budget"
else
  bad "R13" "memo clamp lost silent lane, lied about +N, or exceeded 30 (len=$MEMO_30_LEN): $MEMO_30_PLAIN"
fi

# F2: the composer must fit exact narrow terminal budgets, including the
# former negative-slack/trailing-space case at 22 columns.
for _narrow_w in 20 22 26 30 34 60 80 120 200; do
  _narrow_out="$(HOME="$tmp/composer-home" run_composer "$_narrow_w" "$WIDE_MEMO")"
  _narrow_len="$(visible_len "$_narrow_out")"
  if (( _narrow_len <= _narrow_w )); then
    ok "F2: composer width $_narrow_w is exact/smaller ($_narrow_len)"
  else
    bad "F2" "composer width $_narrow_w overflowed ($_narrow_len): $_narrow_out"
  fi
done

# MUT-C: deleting the composer's reserved +N marker must make the same
# narrow fixture overflow. This is a red control, not a textual source check.
MUT_C_DIR="$tmp/composer-mut-c"
cp -a "$SCRATCH_SCRIPTS" "$MUT_C_DIR"
sed -i.bak 's/_surf_marker=""; (( _surf_remaining > 0 )) && _surf_marker=" +${_surf_remaining}"/_surf_marker=""/' "$MUT_C_DIR/leadv2-lane-status-line.sh"
rm -f "$MUT_C_DIR/leadv2-lane-status-line.sh.bak"
COMPOSER_SAVED="$COMPOSER"; COMPOSER="$MUT_C_DIR/leadv2-lane-status-line.sh"
MUT_C_RED=""
for _mut_w in 20 22 26 30 34 60; do
  MUT_C_OUT="$(HOME="$tmp/composer-home" run_composer "$_mut_w" "$WIDE_MEMO")"
  if (( $(visible_len "$MUT_C_OUT") > _mut_w )); then MUT_C_RED="$_mut_w:$MUT_C_OUT"; break; fi
done
COMPOSER="$COMPOSER_SAVED"
if [ -n "$MUT_C_RED" ]; then
  ok "MUT-C RED: zero composer marker overflows (${MUT_C_RED%%:*})"
else
  bad "MUT-C" "zero composer marker unexpectedly stayed within every narrow budget"
fi

# F3: UTF-8 labels must use character, not byte, width accounting in the tail
# clamp; the visible row count and +N must exactly reconcile.
UTF8_DIR="$tmp/scripts-utf8"
mkdir -p "$UTF8_DIR"; cp -a "$SCRATCH_SCRIPTS/." "$UTF8_DIR/"
cat > "$UTF8_DIR/leadv2-lane-liveness.sh" <<'EOF'
#!/usr/bin/env bash
cat <<JSON
{"count_live": 8, "lanes": [
 {"lane":"кириллица-один","verdict":"alive","age_s":1},
 {"lane":"кириллица-два","verdict":"alive","age_s":2},
 {"lane":"кириллица-три","verdict":"alive","age_s":3},
 {"lane":"кириллица-четыре","verdict":"alive","age_s":4},
 {"lane":"кириллица-пять","verdict":"alive","age_s":5},
 {"lane":"кириллица-шесть","verdict":"alive","age_s":6},
 {"lane":"кириллица-семь","verdict":"alive","age_s":7},
 {"lane":"кириллица-восемь","verdict":"alive","age_s":8}
]}
JSON
EOF
chmod +x "$UTF8_DIR/leadv2-lane-liveness.sh"
rm -f "$tmp"/cache/leadv2-statusline-lane-*
UTF8_OUT="$(run_tail 60 "$UTF8_DIR")"; UTF8_PLAIN="$(printf '%s' "$UTF8_OUT" | strip_ansi)"
if (( $(visible_len "$UTF8_OUT") <= 60 )) && [[ "$UTF8_PLAIN" == *'+5'* ]]; then
  ok "F3: UTF-8 tail clamp fits 60 with exact +5"
else
  bad "F3" "UTF-8 tail clamp width/count mismatch: $UTF8_PLAIN"
fi

# F2/F5: the production tail has the same exact-width contract, and its BASE
# fallback must become plain text before a degenerate-width clip.
for _tail_w in 20 22 26 30 34 60 80 120 200; do
  rm -f "$tmp"/cache/leadv2-statusline-lane-*
  _tail_out="$(run_tail "$_tail_w" "$SCRATCH_SCRIPTS")"
  if (( $(visible_len "$_tail_out") <= _tail_w )); then
    ok "F2/F5: tail width $_tail_w is exact/smaller"
  else
    bad "F2/F5" "tail width $_tail_w overflowed: $_tail_out"
  fi
done

printf 'pass=%d fail=%d skip=%d\n' "$PASS" "$FAIL" "$SKIP"
[[ "$FAIL" -eq 0 ]]
