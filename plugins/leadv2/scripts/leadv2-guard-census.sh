#!/usr/bin/env bash
# leadv2-guard-census.sh — GUARDS-MUST-PROVE-THEY-FIRE-01
#
# One table, read not diagnosed: guard · event · state · last ran ·
# last fired · fixture proven?
#
# States are DERIVED from runtime behaviour, never declared:
#   not-wired        absent from hooks.json for every event
#   missing          wired in hooks.json but no file in the hook dir
#   never-ran        wired, zero `ran` evidence anywhere
#   ran-never-fired  executes (journal or fixture observation), never reached
#                    its own fire path
#   disabled         fixture drives it: flag off => no block, flag on => block
#                    (behaviourally derived, never grepped from source)
#   fires-log-only   reached its fire path, emitted output, did not block
#                    (the promise-guard shape)
#   blocking         reached its fire path and blocks (exit 2 or
#                    decision:block JSON) — in the journal or proven by fixture
#   bail:<reason>    could not complete (timeout / exited without a verdict) —
#                    recorded with its reason, never silently absent
#
#   Runner-side kinds (GUARD-CENSUS-IS-WRONG-01 round 2): the dispatcher's
#   `verdict pass` row (guard ran, emitted nothing contract-shaped) is
#   ran-only evidence and never a fire; `verdict inject` (stdout
#   hookSpecificOutput/additionalContext JSON) IS a fire; deny-JSON verdicts
#   count as blocking. Kind = the guard's CONTRACT, never its chatter.
#
# Fixture doctrine (same as mutation-testing a suite): a guard that has never
# been SHOWN to fire is exactly as trustworthy as a test never shown to go
# red. Every fixture drives its guard into the fire path and declares
# GV_FIX_EXPECT; observed != expected is a REGRESSION, printed loudly, exit 1.
#
# This script never mutates the hook tree and never writes to the journal it
# reads: live journals are opened read-only, fixture runs get their own
# sandbox journal (LEADV2_GUARD_VERDICT_DIR).
#
# Bash 3.2 only (no mapfile); every ${arr[@]} guarded under set -u.

set -uo pipefail

SCRIPT_ABS="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_ABS/.." && pwd)"

HOOKS_JSON="$PLUGIN_ROOT/hooks/hooks.json"
HOOK_DIR="$PLUGIN_ROOT/hooks"
JOURNAL_DIR="${CLAUDE_PROJECT_DIR:-$HOME}/.claude/cache/guard-verdicts"
FIXTURES_DIR=""
GV_LIB="$PLUGIN_ROOT/hooks/lib/leadv2-guard-verdict.sh"
TIMEOUT_S="6"
SANDBOX_DIR=""
FORMAT="table"
# Capability parity: fixture runs strip the operator's env, but a guard's
# python deps (PyYAML etc.) often live in the USER site-packages, which is
# HOME-keyed. Carry it explicitly or a fixture failure means the deps
# vanished, not that the guard cannot fire.
GV_PY_SITE="$(python3 -c 'import site; print(site.getusersitepackages())' 2>/dev/null || true)"

usage() { echo "usage: $0 [--hooks-json P] [--hook-dir P] [--journal-dir P] [--fixtures-dir P] [--gv-lib P] [--timeout S] [--sandbox-dir P] [--format table|tsv]" >&2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --hooks-json)  HOOKS_JSON="${2:?}"; shift 2 ;;
    --hook-dir)    HOOK_DIR="${2:?}"; shift 2 ;;
    --journal-dir) JOURNAL_DIR="${2:?}"; shift 2 ;;
    --fixtures-dir) FIXTURES_DIR="${2:?}"; shift 2 ;;
    --gv-lib)      GV_LIB="${2:?}"; shift 2 ;;
    --timeout)     TIMEOUT_S="${2:?}"; shift 2 ;;
    --sandbox-dir) SANDBOX_DIR="${2:?}"; shift 2 ;;
    --format)      FORMAT="${2:?}"; shift 2 ;;
    -h|--help)     usage; exit 0 ;;
    *)             usage; exit 64 ;;
  esac
done

[ -f "$HOOKS_JSON" ] || { echo "census: hooks.json not found: $HOOKS_JSON" >&2; exit 66; }
[ -d "$HOOK_DIR" ]   || { echo "census: hook dir not found: $HOOK_DIR" >&2; exit 66; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/guard-census.XXXXXX")"
if [ -n "$SANDBOX_DIR" ]; then
  SBX="$SANDBOX_DIR"
  mkdir -p "$SBX"
else
  SBX="$TMP/sandbox"
  mkdir -p "$SBX"
fi
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

# ---------------------------------------------------------------------------
# 1. Who is wired, to what events (structural config, not behaviour — the
#    wiring claim lives in hooks.json and is checked, not believed).
# ---------------------------------------------------------------------------
WIRED="$TMP/wired.tsv"
# jq's ltrimstr/split(" ")[0]/rtrimstr("\"") pipeline used to assume the
# first shell word IS the guard filename with a clean trailing quote. Many
# hooks.json entries are `"…/leadv2-x.sh"; r=$?; if …` (degrade-log wrapper) —
# no space before the `";`, so rtrimstr("\"") never matches and the guard
# name comes out with a literal trailing `";`, sending it to "missing".
# capture() on the first .sh token is layout-independent: it finds the name
# wherever it sits in the command string.
jq -r '.hooks | to_entries[] | .key as $e | .value[] | .hooks[]? |
       [(.command // "" | capture("(?<n>[A-Za-z0-9_.-]+\\.sh)"; "").n // ""), $e]
       | @tsv' "$HOOKS_JSON" 2>/dev/null | awk -F'\t' '$1 != ""' | sort -u > "$WIRED"

# ---------------------------------------------------------------------------
# 1b. Dispatcher follow-through. A guard invoked only from inside another
#     guard's MANIFEST (e.g. leadv2-bash-pre-dispatch.sh routing Bash-command
#     guards by regex) is invisible to hooks.json — it never appears as a
#     top-level entry. Any hook script that defines a `MANIFEST='script|trigger
#     ...'` variable (the leadv2-bash-pre-dispatch.sh convention) is followed:
#     every script named on the left of a `|` in that block is wired to the
#     SAME event(s) the dispatcher itself is wired to.
# ---------------------------------------------------------------------------
DISPATCHED="$TMP/dispatched.tsv"
: > "$DISPATCHED"
for dsp in "$HOOK_DIR"/*.sh; do
  [ -e "$dsp" ] || continue
  grep -q '^MANIFEST=' "$dsp" 2>/dev/null || continue
  dname="$(basename "$dsp")"
  devents="$(awk -F'\t' -v g="$dname" '$1==g { print $2 }' "$WIRED")"
  [ -n "$devents" ] || continue
  # Extract the MANIFEST='...' single-quoted block (may span multiple lines)
  # and pull the script name preceding each `|`.
  awk '/^MANIFEST=/{p=1; sub(/^MANIFEST='"'"'/,""); print; next}
       p{print; if ($0 ~ /'"'"'$/){p=0}}' "$dsp" \
    | sed "s/'$//" \
    | while IFS='|' read -r sub _rest; do
        sub="$(printf '%s' "$sub" | tr -d '\n')"
        case "$sub" in *.sh)
          while IFS= read -r ev; do
            [ -n "$ev" ] || continue
            printf '%s\t%s\n' "$sub" "$ev" >> "$DISPATCHED"
          done <<EOF
$devents
EOF
        ;; esac
      done
done
if [ -s "$DISPATCHED" ]; then
  cat "$DISPATCHED" >> "$WIRED"
  sort -u -o "$WIRED" "$WIRED"
fi

# ---------------------------------------------------------------------------
# 2. Live journal evidence (read-only). `ran` rows and fire rows.
#    Round 2 (GUARD-CENSUS-IS-WRONG-01): the journal is read ONCE per run
#    into a per-guard summary — the old code rescanned the full journal with
#    one awk per class per guard (3 full scans × every guard). Rotated
#    generations (.1, .2, written by the dispatcher's cap) hold older rows;
#    ISO timestamps sort lexicographically, so a per-guard max across all
#    three files is the true latest.
#
#    Kind semantics (round-2 contract, matches the dispatcher's records):
#    `verdict pass` is ran-only evidence — a guard that exits 0 with only
#    stderr chatter did nothing, and must never count as a fire.
#    `verdict inject` (stdout hookSpecificOutput/additionalContext JSON) IS a
#    fire — the guard reached its inject path. `verdict block` and deny-JSON
#    blocks count as blocking fires.
#
#    Legacy journals (guards that predate the verdict lib) are mapped in so
#    their existing runtime evidence is not thrown away: last line of the
#    file is inspected, a fire is a line matching --legacy-fire-re, and a
#    match on --legacy-logonly-re marks that fire log-only (e.g. promise-guard
#    journals `"verdict":"fired"` with `"block_mode":"0"`).
# ---------------------------------------------------------------------------
JTSV="$JOURNAL_DIR/journal.tsv"
JLAST="$TMP/jlast.tsv"
: > "$JLAST"
_lv2_jfiles=""
for _lv2_jf in "$JTSV" "$JTSV.1" "$JTSV.2"; do
  [ -f "$_lv2_jf" ] && _lv2_jfiles="$_lv2_jfiles $_lv2_jf"
done
if [ -n "$_lv2_jfiles" ]; then
  # shellcheck disable=SC2086 — deliberate word split of journal paths
  awk -F'\t' '
    $4=="ran" || $4=="verdict" || $4=="bail" {
      seen[$2]=1; if ($1 > ran[$2]) ran[$2] = $1 }
    $4=="verdict" && $5 ~ /^block/ {
      seen[$2]=1; if ($1 > blk[$2]) blk[$2] = $1 }
    $4=="verdict" && $5 ~ /^(log|inject)/ {
      seen[$2]=1; if ($1 > lg[$2])  lg[$2]  = $1 }
    END { for (g in seen)
            printf "%s\t%s\t%s\t%s\n", g, ran[g], blk[g], lg[g] }' $_lv2_jfiles \
    > "$JLAST" 2>/dev/null
fi
jcol() { # $1 guard  $2 col (2=last-ran 3=last-block-fire 4=last-log/inject-fire)
  awk -F'\t' -v g="$1" -v c="$2" '$1==g { printf "%s", $c }' "$JLAST" 2>/dev/null
}
live_last_ran()   { jcol "$1" 2; }
live_last_block() { jcol "$1" 3; }
live_last_log()   { jcol "$1" 4; }

LEGACY_RE="$TMP/legacy.tsv"
: > "$LEGACY_RE"
legacy_map() { # $1 guard  $2 path  $3 fire-re  $4 logonly-re
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$LEGACY_RE"
}
# promise-guard: the 423-"would have blocked" journal (log-only rollout).
legacy_map "leadv2-promise-guard.sh" "$HOME/.claude/leadv2-promise-guard.jsonl" \
  '"verdict": ?"fired"' '"block_mode": ?"0"'

legacy_scan() { # $1 guard -> sets L_RAN L_FIRED L_LOGFIRE
  L_RAN=""; L_FIRED=""; L_LOGFIRE=""
  local row path fire logonly last
  row="$(awk -F'\t' -v g="$1" '$1==g' "$LEGACY_RE")"
  [ -n "$row" ] || return 0
  path="$(printf '%s' "$row" | cut -f2)"
  fire="$(printf '%s' "$row" | cut -f3)"
  logonly="$(printf '%s' "$row" | cut -f4)"
  [ -f "$path" ] || return 0
  last="$(tail -n 1 "$path" 2>/dev/null)"
  [ -n "$last" ] || return 0
  L_RAN="$(stat -f '%Sm' -t '%Y-%m-%dT%H:%M:%SZ' "$path" 2>/dev/null)"
  if printf '%s' "$last" | grep -qE "$fire"; then
    if printf '%s' "$last" | grep -qE "$logonly"; then
      L_LOGFIRE="$L_RAN"
    else
      L_FIRED="$L_RAN"
    fi
  fi
  return 0
}

# ---------------------------------------------------------------------------
# 3. Fixture runs — the proof a guard CAN fire. Fixture contract
#    (fixtures/*.fixture.sh, pure assignments):
#      GV_FIX_GUARD=leadv2-x.sh
#      GV_FIX_STDIN='<hook payload JSON>'
#      GV_FIX_EXPECT=block|log|nap|disabled|bail-timeout
#      GV_FIX_ENV='VAR=1 VAR2=2'       (env for the primary observation run)
#      GV_FIX_ARM_ENV='VAR=1'          (only for EXPECT=disabled: the arming run)
#      GV_FIX_PRE='shell snippet'      (optional, runs in the sandbox first;
#                                       $LEADV2_SANDBOX holds the sandbox path)
#      GV_FIX_CWD='$LEADV2_SANDBOX/proj'  (optional working dir for the guard)
#      GV_FIX_HOME='$LEADV2_SANDBOX/home' (optional HOME; default sandbox/home)
# ---------------------------------------------------------------------------
run_guard_once() { # $1 guard  $2 env-words(""=none)  $3 home  $4 cwd  ; rc -> $SBX/rc
  local gp="$1" arm="$2" ghome="${3:-$HOME}" gcwd="${4:-$PWD}"
  # env -i: a fixture run is a controlled experiment — the census operator's
  # own LEADV2_* flags (e.g. LEADV2_LEAD_GUARD=1 from settings.json) must not
  # leak in and turn a "disabled" derivation into a phantom "blocking".
  {
    (
      cd "$gcwd" || exit 127
      if [ -n "$arm" ]; then
        # shellcheck disable=SC2086 — arm is deliberate VAR=VAL words
        env -i PATH="$PATH" HOME="$ghome" TMPDIR="${TMPDIR:-/tmp}" PYTHONPATH="$GV_PY_SITE" \
          ${arm} LEADV2_GUARD_VERDICT_DIR="$SBX" LEADV2_GUARD_VERDICT_LIB="$GV_LIB" \
          "$gp" < "$SBX/in" > "$SBX/out" 2> "$SBX/err" &
      else
        env -i PATH="$PATH" HOME="$ghome" TMPDIR="${TMPDIR:-/tmp}" PYTHONPATH="$GV_PY_SITE" \
          LEADV2_GUARD_VERDICT_DIR="$SBX" LEADV2_GUARD_VERDICT_LIB="$GV_LIB" \
          "$gp" < "$SBX/in" > "$SBX/out" 2> "$SBX/err" &
      fi
      local gpid=$!
      ( sleep "$TIMEOUT_S"; kill -9 "$gpid" 2>/dev/null ) &
      local wpid=$!
      wait "$gpid"
      local rc=$?
      kill "$wpid" 2>/dev/null
      wait "$wpid" 2>/dev/null
      printf '%s' "$rc" > "$SBX/rc"
    )
  } 2> /dev/null
  return 0
}

classify_observation() { # $1 guard  -> sets CLS from $SBX/{rc,out,err}
  local guard="$1" rc out err
  rc="$(cat "$SBX/rc" 2>/dev/null || echo 127)"
  out="$(cat "$SBX/out" 2>/dev/null)"
  err="$(cat "$SBX/err" 2>/dev/null)"
  CLS="nap"
  # Round 2: a permissionDecision deny|block JSON (the close-ritual-guard /
  # codex-round-cap shape: deny verdict, exit 0) IS a block — same contract
  # class as decision:block + exit 2, never demoted to a log fire.
  case "$out" in
    *'"decision"'*'"block"'*|*'"permissionDecision"'*'"deny"'*|*'"permissionDecision"'*'"block"'*) CLS="block" ;;
  esac
  [ "$rc" -eq 2 ] && CLS="block"
  if [ "$rc" -eq 137 ]; then
    CLS="bail-timeout"
    # A kill -9 skips the guard's own EXIT trap, so the census records the
    # bail with its reason itself — never silently absent. One file per
    # guard: fixtures share the sandbox and must not clobber each other.
    printf 'census-recorded\tbail\ttimeout-after-%ss\n' "$TIMEOUT_S" \
      >> "$SBX/census-bail.$guard.tsv"
  elif [ "$CLS" != "block" ] && [ -n "$out$err" ]; then
    CLS="log"
  fi
  return 0
}

fixture_expect_ok() { # $1 expect  $2 observed-class  $3 proven-disabled(0/1)
  case "$1" in
    block)        [ "$2" = "block" ] ;;
    log)          [ "$2" = "log" ] ;;
    nap)          [ "$2" = "nap" ] ;;
    bail-timeout) [ "$2" = "bail-timeout" ] ;;
    disabled)     [ "$3" -eq 1 ] ;;
    *) return 1 ;;
  esac
}

REGRESSIONS=0
PROVEN=0
FIXTURED=0

run_fixture_file() { # $1 fixture path  $2 guard name
  local f="$1" guard="$2" payload expect fenv arm pre ghome gcwd cls1 cls2 provdis ok
  eval "$( . "$f"; printf 'payload=%q\nexpect=%q\nfenv=%q\narm=%q\npre=%q\nghome=%q\ngcwd=%q\n' \
    "${GV_FIX_STDIN:-}" "${GV_FIX_EXPECT:-}" "${GV_FIX_ENV:-}" "${GV_FIX_ARM_ENV:-}" \
    "${GV_FIX_PRE:-}" "${GV_FIX_HOME:-}" "${GV_FIX_CWD:-}" )"
  # Fixtures may reference the per-run sandbox as $LEADV2_SANDBOX.
  payload="${payload//\$LEADV2_SANDBOX/$SBX}"
  fenv="${fenv//\$LEADV2_SANDBOX/$SBX}"
  arm="${arm//\$LEADV2_SANDBOX/$SBX}"
  pre="${pre//\$LEADV2_SANDBOX/$SBX}"
  ghome="${ghome//\$LEADV2_SANDBOX/$SBX}"
  gcwd="${gcwd//\$LEADV2_SANDBOX/$SBX}"
  [ -n "$ghome" ] || ghome="$SBX/home"; mkdir -p "$ghome"
  [ -n "$gcwd" ] || gcwd="$PWD"
  FIXTURED=$((FIXTURED + 1))
  printf '%s' "$payload" > "$SBX/in"
  : > "$SBX/out"; : > "$SBX/err"
  [ -n "$pre" ] && ( cd "$SBX" && LEADV2_SANDBOX="$SBX" eval "$pre" ) 2>/dev/null
  run_guard_once "$HOOK_DIR/$guard" "$fenv" "$ghome" "$gcwd"
  classify_observation "$guard"
  # Log-only guards may leave no output at all — their fire record is a
  # journal row written to their own legacy journal. With the fixture's
  # sandboxed HOME that row is readable and proves the fire path was reached
  # (the promise-guard shape: `verdict":"fired"` + `"block_mode":"0"`).
  local row lpath lfire llog last slpath
  while IFS="$(printf '\t')" read -r _lg lpath lfire llog; do
    [ "$_lg" = "$guard" ] || continue
    # The fixture ran under a sandboxed HOME — remap the journal path.
    slpath="${lpath/#$HOME/$ghome}"
    [ -f "$slpath" ] || continue
    last="$(tail -n 1 "$slpath" 2>/dev/null)"
    if printf '%s' "$last" | grep -qE "$lfire"; then CLS="log"; fi
  done < "$LEGACY_RE"
  cls1="$CLS"
  provdis=0
  if [ "$expect" = "disabled" ]; then
    [ -n "$arm" ] || { echo "REGRESSION: fixture $f expects disabled but sets no GV_FIX_ARM_ENV" >&2; REGRESSIONS=$((REGRESSIONS + 1)); return 0; }
    run_guard_once "$HOOK_DIR/$guard" "$arm" "$ghome" "$gcwd"
    classify_observation "$guard"
    cls2="$CLS"
    if [ "$cls1" != "block" ] && [ "$cls2" = "block" ]; then provdis=1; fi
    CLS="disabled"
    cls1="disabled"
  fi
  ok=0
  fixture_expect_ok "$expect" "$cls1" "$provdis" && ok=1
  if [ "$ok" -eq 1 ]; then
    PROVEN=$((PROVEN + 1))
    printf '%s' "$cls1" > "$TMP/fxcls.$guard"
  else
    REGRESSIONS=$((REGRESSIONS + 1))
    echo "REGRESSION: $guard — fixture no longer makes it fire (expected $expect, observed $cls1); this is the signal that would have caught idle-lead-guard." >&2
    printf 'REGRESSION' > "$TMP/fxcls.$guard"
  fi
  return 0
}

if [ -n "$FIXTURES_DIR" ] && [ -d "$FIXTURES_DIR" ]; then
  for f in "$FIXTURES_DIR"/*.fixture.sh; do
    [ -e "$f" ] || continue
    eval "$( . "$f"; printf 'fguard=%q\n' "${GV_FIX_GUARD:-}" )"
    [ -n "${fguard:-}" ] || { echo "census: fixture $f sets no GV_FIX_GUARD" >&2; exit 65; }
    if [ ! -x "$HOOK_DIR/$fguard" ]; then
      echo "REGRESSION: fixture $f targets $fguard which is not executable in $HOOK_DIR" >&2
      REGRESSIONS=$((REGRESSIONS + 1))
      continue
    fi
    run_fixture_file "$f" "$fguard"
  done
fi

# ---------------------------------------------------------------------------
# 4. Assemble the table.
# ---------------------------------------------------------------------------
UNIVERSE="$TMP/universe.txt"
{
  awk -F'\t' '{ print $1 }' "$WIRED"
  find "$HOOK_DIR" -maxdepth 1 -name '*.sh' -exec basename {} \;
} | sort -u > "$UNIVERSE"

ROWS="$TMP/rows.tsv"
: > "$ROWS"
while IFS= read -r g; do
  [ -n "$g" ] || continue
  events="$(awk -F'\t' -v g="$g" '$1==g { e = e sep $2; sep="," } END { printf "%s", e }' "$WIRED")"
  wired=0
  [ -n "$events" ] && wired=1

  if [ "$wired" -eq 0 ]; then
    state="not-wired"; rank=8
  elif [ ! -f "$HOOK_DIR/$g" ]; then
    state="missing"; rank=2
  else
    legacy_scan "$g"
    lran="$L_RAN"; lblock="$L_FIRED"; llog="$L_LOGFIRE"
    jran="$(live_last_ran "$g")"
    jblock="$(live_last_block "$g")"
    jlog="$(live_last_log "$g")"
    fxcls=""
    [ -f "$TMP/fxcls.$g" ] && fxcls="$(cat "$TMP/fxcls.$g")"

    last_ran="$(printf '%s\n%s\n%s' "$jran" "$lran" "" | sort -r | head -1)"
    last_fired="$(printf '%s\n%s\n%s\n%s\n%s' "$jblock" "$jlog" "$lblock" "$llog" "" | sort -r | head -1)"

    # Founder view (round-1 brief §4): the guard's env flag and its default,
    # read mechanically off the source (first ${LEADV2_X:-0|1} expansion) —
    # a pointer for the founder, never a behavioural claim. Guards without a
    # flag knob run unconditionally: `always`.
    dflt="-"
    if [ -f "$HOOK_DIR/$g" ]; then
      dflt="$(grep -oE '\$\{LEADV2_[A-Za-z0-9_]+:-[01]\}' "$HOOK_DIR/$g" 2>/dev/null \
        | grep -vE 'TRACE|DEBUG' | head -1)"
      [ -n "$dflt" ] || dflt="always"
    fi

    if [ "$fxcls" = "bail-timeout" ]; then
      state="bail:timeout"; rank=1
    elif [ -n "$jblock" ] || [ -n "$lblock" ] || [ "$fxcls" = "block" ]; then
      state="blocking"; rank=7
    elif [ -n "$jlog" ] || [ -n "$llog" ] || [ "$fxcls" = "log" ]; then
      state="fires-log-only"; rank=6
    elif [ "$fxcls" = "disabled" ]; then
      state="disabled"; rank=5
    elif [ -n "$jran" ] || [ -n "$lran" ] || [ "$fxcls" = "nap" ]; then
      state="ran-never-fired"; rank=4
    else
      state="never-ran"; rank=3
    fi
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$rank" "$g" "${events:--}" "$state" \
    "${last_ran:--}" "${last_fired:--}" "${dflt:--}" >> "$ROWS"
done < "$UNIVERSE"

OUT="$TMP/final.tsv"
CANDS="$TMP/candidates.tsv"
: > "$OUT"; : > "$CANDS"
NOW_S="$(date -u +%s)"
while IFS="$(printf '\t')" read -r rank g events state lran lfired dflt; do
  fixcol="no"
  if [ -f "$TMP/fxcls.$g" ]; then
    v="$(cat "$TMP/fxcls.$g")"
    case "$v" in
      REGRESSION) fixcol="REGRESSION" ;;
      *) fixcol="yes" ;;
    esac
  fi
  # last-fired-days (round-1 brief §4): whole days since the last fire,
  # `-` when the guard has never fired. Parsed on BSD date (this repo's
  # platform); an unparseable timestamp degrades to `-`, never an error.
  fired_days="-"
  case "$lfired" in
    -|"") ;;
    *)
      ts_s="$(date -ju -f '%Y-%m-%dT%H:%M:%SZ' "$lfired" +%s 2>/dev/null || echo "")"
      case "${ts_s:-}" in
        ''|*[!0-9]*) ;;
        *) fired_days=$(( (NOW_S - ts_s) / 86400 )) ;;
      esac
      ;;
  esac
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$rank" "$g" "$events" "$state" \
    "$lran" "$lfired" "$dflt" "$fired_days" "$fixcol" >> "$OUT"
  # Candidates to delete (round-1 brief §4): wired, file present, no fixture
  # proof, and no fire in the last 30 days (or never). Listed for the
  # founder's decision — this census never deletes or disables anything.
  case "$state" in
    not-wired|missing|bail:*) ;;
    *)
      stale=0
      if [ "$lfired" = "-" ]; then stale=1
      else
        case "$fired_days" in
          -|"") ;;
          *) [ "$fired_days" -gt 30 ] && stale=1 ;;
        esac
      fi
      if [ "$stale" -eq 1 ] && [ "$fixcol" = "no" ]; then
        printf '%s\t%s\t%s\t%s\n' "$g" "$state" "$lfired" "$dflt" >> "$CANDS"
      fi
      ;;
  esac
done < "$ROWS"

TOTAL="$(wc -l < "$OUT" | tr -d ' ')"
if [ "$FORMAT" = "tsv" ]; then
  cat "$OUT"
else
  echo "GUARD CENSUS — GUARDS-MUST-PROVE-THEY-FIRE-01 ($(date -u '+%Y-%m-%dT%H:%M:%SZ'))"
  echo "guards: $TOTAL | fixtures run: $FIXTURED | fixture-proven: $PROVEN | regressions: $REGRESSIONS"
  echo "(dead first: regressions, bails, missing, not-wired, never-ran — the top of this table is where the failures live)"
  printf '%-42s %-16s %-17s %-21s %-21s %-32s %-9s %s\n' GUARD EVENT STATE LAST-RAN LAST-FIRED DEFAULT FIRE-DAYS FIXTURE
  sort -t "$(printf '\t')" -k1,1n -k2,2 "$OUT" | while IFS="$(printf '\t')" read -r rank g events state lran lfired dflt fdays fixcol; do
    printf '%-42s %-16s %-17s %-21s %-21s %-32s %-9s %s\n' "$g" "${events:--}" "$state" "$lran" "$lfired" "$dflt" "$fdays" "$fixcol"
  done
  if [ -s "$CANDS" ]; then
    echo ""
    echo "CANDIDATES TO DELETE — wired, no fixture proof, no fire in 30 days (founder decides; never auto-deleted):"
    while IFS="$(printf '\t')" read -r cg cstate clfired cdflt; do
      printf '  %-42s %-17s last-fired=%-21s %s\n' "$cg" "$cstate" "${clfired:--}" "$cdflt"
    done < "$CANDS"
  fi
fi

if [ "$REGRESSIONS" -gt 0 ]; then
  echo "CENSUS FAIL: $REGRESSIONS fixture regression(s) — guards that cannot be made to fire." >&2
  exit 1
fi
exit 0
