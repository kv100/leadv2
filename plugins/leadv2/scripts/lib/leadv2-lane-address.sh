#!/usr/bin/env bash
# lib/leadv2-lane-address.sh — resolve a lane's deliverables from either of its
# two names (founder task id / sig8), with the search path and coverage as data.
# Sourceable. Sets LA_* globals. Never prints.
#
# EXACT-ATTRIBUTION INVARIANT — inherited from leadv2-lane-liveness.sh's
# log_path consult (near :711, was :637 in the census brief; the function was
# renamed upstream but the invariant is unchanged): never glob docs/handoff/
# for the founder id and never grep dir contents for it. The pointer comes
# from a named field in a designated file — admission-receipt.yaml `task_id:`
# or lane-mission.md line 1 `^# <TID>` — or it does not happen. Banned as
# attribution sources (census §3c): review.diff, review.diff.repos,
# main-dirt.base, e2e-gate.log, e2e-gate.md, selfcheck.md, *.stream.jsonl,
# and the bodies of *.full.md / *.summary.md. A dispatch-*-shaped task_id is
# a self-reference, not a founder pointer (49 real ones exist on the main
# tree; the census brief's own retracted index died of the same disease).
#
# Three-valued on purpose (census §4c): found / none / unknown. `none` only
# when the scan was complete AND every consulted dispatch dir carried a
# pointer; otherwise a miss is `unknown`. Coercing either miss to a bare
# zero is the seven-incident bug this library exists to remove.

# Normalize any of: founder tid | bare sig8 | dispatch-<sig8>
# Echoes "tid <value>" or "sig8 <value>"; returns 1 on unusable input.
lane_address_normalize() {
  local q="$1"
  [[ -z "$q" ]] && return 1
  case "$q" in
    dispatch-[a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9])
      printf 'sig8 %s\n' "${q#dispatch-}" ;;
    [a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9])
      printf 'sig8 %s\n' "$q" ;;
    dispatch-*|*[!A-Za-z0-9._-]*)
      # anything else with a dash/uppercase shape is a founder tid, but a
      # malformed dispatch- prefix is not usable as either name
      case "$q" in
        dispatch-*) return 1 ;;
        *) printf 'tid %s\n' "$q" ;;
      esac ;;
    *) printf 'tid %s\n' "$q" ;;
  esac
}

# True if the value looks like a founder task id (not a sig8, not dispatch-*).
lane_address_is_founder_shaped() {
  case "$1" in
    ""|dispatch-*) return 1 ;;
    [a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9]) return 1 ;;
    *) return 0 ;;
  esac
}

# List deliverable files (*.full.md, *.summary.md) inside $1, one per line,
# prefixed by $2 (label prefix for the path). Unreadable dir -> LA_UNREADABLE.
lane_address_list_deliverables() {
  local dir="$1" pfx="$2" f b
  LA_UNREADABLE=""
  if [[ ! -d "$dir" ]]; then
    LA_DELIV_ABSENT=1 LA_DELIV_FILES=""
    return 0
  fi
  if [[ ! -r "$dir" || ! -x "$dir" ]]; then
    LA_UNREADABLE="$dir"
    LA_DELIV_ABSENT=0 LA_DELIV_FILES=""
    return 0
  fi
  LA_DELIV_FILES=""
  for f in "$dir"/*.full.md "$dir"/*.summary.md; do
    [[ -f "$f" ]] || continue
    b="${f##*/}"
    LA_DELIV_FILES="${LA_DELIV_FILES}${pfx}${b}"$'\n'
  done
  [[ -z "$LA_DELIV_FILES" ]] && LA_DELIV_ABSENT=1 || LA_DELIV_ABSENT=0
}

# Scan one docs/handoff root for pointer matches to $1 (tid) and $2 (sig8).
# Appends matching dispatch dir paths to LA_MATCH_DIRS (deduped), accumulates
# counters in LA_*_SEEN / LA_*_MATCH, and coverage counters in LA_COV_*.
# $3 = path label for matches ("main" or "wt/<name>").
lane_address_scan_handoff_root() {
  local tid="$1" sig8="$2" label="$3" root="$4" d receipt tidval h1 tok
  for d in "$root"/dispatch-*/; do
    [[ -d "$d" ]] || continue
    if [[ ! -r "$d" || ! -x "$d" ]]; then
      LA_UNREADABLE_DIRS="${LA_UNREADABLE_DIRS}${d}"$'\n'
      continue
    fi
    LA_DISPATCH_SEEN=$((LA_DISPATCH_SEEN+1))
    h1=""
    receipt="$d/admission-receipt.yaml"
    tidval=""
    if [[ -f "$receipt" && -r "$receipt" ]]; then
      LA_RECEIPT_SEEN=$((LA_RECEIPT_SEEN+1))
      tidval=$(sed -n 's/^task_id:[[:space:]]*//p' "$receipt" | head -1 | tr -d '"' )
      if lane_address_is_founder_shaped "$tidval"; then
        LA_RECEIPT_FOUNDER=$((LA_RECEIPT_FOUNDER+1))
      else
        case "$tidval" in
          dispatch-*) LA_RECEIPT_SELFREF=$((LA_RECEIPT_SELFREF+1)) ;;
        esac
      fi
      if [[ -n "$tid" && "$tidval" == "$tid" ]]; then
        LA_RECEIPT_MATCH=$((LA_RECEIPT_MATCH+1))
        case "$LA_MATCH_DIRS" in
          *"${d}"*) ;;
          *) LA_MATCH_DIRS="${LA_MATCH_DIRS}${label}|${d}"$'\n' ;;
        esac
      fi
    fi
    if [[ -f "$d/lane-mission.md" && -r "$d/lane-mission.md" ]]; then
      LA_MISSION_SEEN=$((LA_MISSION_SEEN+1))
      h1=$(head -1 "$d/lane-mission.md" 2>/dev/null)
      # line 1 only, first token after '# ' — anywhere else is prose (§3c)
      if [[ "$h1" =~ ^#[[:space:]]+([^[:space:]]+) ]]; then
        tok="${BASH_REMATCH[1]}"
        if lane_address_is_founder_shaped "$tok"; then
          LA_MISSION_H1_FOUNDER=$((LA_MISSION_H1_FOUNDER+1))
          if [[ -n "$tid" && "$tok" == "$tid" ]]; then
            LA_MISSION_MATCH=$((LA_MISSION_MATCH+1))
            case "$LA_MATCH_DIRS" in
              *"${d}"*) ;;
              *) LA_MATCH_DIRS="${LA_MATCH_DIRS}${label}|${d}"$'\n' ;;
            esac
          fi
        fi
      fi
    fi
    # coverage: does this dir hold a deliverable, and does it carry a pointer?
    lane_address_list_deliverables "$d" ""
    if [[ -z "$LA_UNREADABLE" && $LA_DELIV_ABSENT -eq 0 ]]; then
      LA_COV_HOLD=$((LA_COV_HOLD+1))
      if lane_address_is_founder_shaped "$tidval"; then
        LA_COV_POINTED=$((LA_COV_POINTED+1))
      else
        # mission H1 founder token also counts as a pointer
        if [[ "$h1" =~ ^#[[:space:]]+([^[:space:]]+) ]] \
           && lane_address_is_founder_shaped "${BASH_REMATCH[1]}"; then
          LA_COV_POINTED=$((LA_COV_POINTED+1))
        else
          LA_COV_UNATTR=$((LA_COV_UNATTR+1))
        fi
      fi
    fi
  done
}

# Main entry. Usage: lane_address_resolve <name> [--worktrees]
# Sets: LA_RESULT (found|none|unknown), LA_VIA, LA_TID, LA_SIG8,
# LA_MATCH_DIRS ("label|dir|" rows), LA_FOUND_ROWS (pre-formatted file rows),
# LA_COVERAGE_LINE, LA_REGISTRY_ROWS, LA_SEARCH_* strings, LA_REASON.
lane_address_resolve() {
  local query="$1"; shift || true
  local search_wt=0
  if [[ "${1:-}" == "--worktrees" ]]; then search_wt=1; fi

  LA_RESULT="" LA_VIA="" LA_TID="" LA_SIG8="" LA_REASON=""
  LA_MATCH_DIRS="" LA_FOUND_ROWS="" LA_UNREADABLE_DIRS=""
  LA_DISPATCH_SEEN=0 LA_RECEIPT_SEEN=0 LA_RECEIPT_FOUNDER=0 \
  LA_RECEIPT_SELFREF=0 LA_RECEIPT_MATCH=0
  LA_MISSION_SEEN=0 LA_MISSION_H1_FOUNDER=0 LA_MISSION_MATCH=0
  LA_COV_HOLD=0 LA_COV_POINTED=0 LA_COV_UNATTR=0
  LA_REGISTRY_ROWS=0 LA_REGISTRY_MATCH=0 LA_WT_ROOTS=0 LA_EPON_FILES="" LA_EPON_STATE=""

  local norm
  norm=$(lane_address_normalize "$query") || { LA_RESULT="usage"; return 3; }
  local kind="${norm%% *}" val="${norm#* }"
  if [[ "$kind" == "tid" ]]; then
    LA_TID="$val"
  else
    LA_SIG8="$val"
  fi

  local root="${PROJECT_ROOT:?PROJECT_ROOT must be set}"
  local handoff="$root/docs/handoff"

  # A1 — registry (live lanes only; 0 rows for every finished lane)
  local reg="$root/docs/leadv2/active.yaml" regpath=""
  if [[ -f "$reg" ]]; then
    if [[ -n "$LA_TID" ]]; then
      regpath=$(python3 - "$reg" "$LA_TID" <<'PY' 2>/dev/null || true
import sys
try:
    import yaml
    d = yaml.safe_load(open(sys.argv[1])) or {}
except Exception:
    sys.exit(0)
s = (d.get("sessions") or {}).get(sys.argv[2]) or {}
print(s.get("log_path") or "")
PY
)
    fi
    if [[ -n "$regpath" ]]; then
      LA_REGISTRY_ROWS=$((LA_REGISTRY_ROWS+1))
      case "$regpath" in
        *dispatch-[a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9]*)
          local sig="${regpath##*dispatch-}"; sig="${sig%%/*}"
          LA_SIG8="$sig" LA_REGISTRY_MATCH=1 LA_VIA="registry"
          ;;
      esac
    fi
  fi

  # A2 + A3 — field scan over dispatch dirs in the main handoff root
  lane_address_scan_handoff_root "$LA_TID" "$LA_SIG8" "main" "$handoff"
  if [[ $LA_RECEIPT_MATCH -gt 0 ]]; then LA_VIA="${LA_VIA:+$LA_VIA+}receipt"; fi
  if [[ $LA_MISSION_MATCH -gt 0 ]]; then LA_VIA="${LA_VIA:+$LA_VIA+}mission"; fi

  # sig8 query (or registry hit): the dispatch-named dir is itself exact
  if [[ -n "$LA_SIG8" ]]; then
    local sd="$handoff/dispatch-$LA_SIG8"
    if [[ -d "$sd" ]]; then
      case "$LA_MATCH_DIRS" in
        *"$sd"*) ;;
        *) LA_MATCH_DIRS="${LA_MATCH_DIRS}main|$sd"$'\n' ;;
      esac
      [[ -z "$LA_VIA" ]] && LA_VIA="sig8"
    fi
  fi

  # A4 — eponymous dir
  local epon="${handoff}/${LA_TID:-$LA_SIG8}"
  local epon_state="absent"
  if [[ -d "$epon" ]]; then
    lane_address_list_deliverables "$epon" "$epon/"
    if [[ -n "$LA_UNREADABLE" ]]; then
      epon_state="unreadable"
      LA_UNREADABLE_DIRS="${LA_UNREADABLE_DIRS}$epon"$'\n'
    elif [[ $LA_DELIV_ABSENT -eq 0 ]]; then
      epon_state="deliverables"
      LA_EPON_FILES="$LA_DELIV_FILES"
    else
      epon_state="present-no-deliverable"
    fi
  fi
  LA_EPON_STATE="$epon_state"

  # worktrees — depth 5 deliverables, census §2c; opt-in, never silent
  LA_WT_SEARCHED=0
  if [[ $search_wt -eq 1 && -d "$root/.claude/worktrees" ]]; then
    LA_WT_SEARCHED=1
    local wt wtname pre_dispatch pre_receipt pre_mission pre_h1f \
          pre_hold pre_pointed pre_unattr pre_seen pre_fnd pre_sref pre_rm pre_mm
    for wt in "$root"/.claude/worktrees/*/; do
      [[ -d "$wt/docs/handoff" ]] || continue
      wtname="${wt%/}"; wtname="${wtname##*/}"
      pre_seen=$LA_DISPATCH_SEEN; pre_receipt=$LA_RECEIPT_SEEN; pre_fnd=$LA_RECEIPT_FOUNDER
      pre_sref=$LA_RECEIPT_SELFREF; pre_rm=$LA_RECEIPT_MATCH
      pre_mission=$LA_MISSION_SEEN; pre_h1f=$LA_MISSION_H1_FOUNDER; pre_mm=$LA_MISSION_MATCH
      pre_hold=$LA_COV_HOLD; pre_pointed=$LA_COV_POINTED; pre_unattr=$LA_COV_UNATTR
      lane_address_scan_handoff_root "$LA_TID" "$LA_SIG8" "wt/$wtname" "$wt/docs/handoff"
      if [[ $LA_DISPATCH_SEEN -gt $pre_seen ]]; then LA_WT_ROOTS=$((LA_WT_ROOTS+1)); fi
    done
  fi

  # gather deliverable rows from every matched dir
  local row label dir files f sz ts
  while IFS='|' read -r label dir; do
    [[ -d "$dir" ]] || continue
    lane_address_list_deliverables "$dir" ""
    if [[ -n "$LA_UNREADABLE" ]]; then
      LA_RESULT="unknown"
      LA_REASON="$dir exists but listdir failed"
      return 2
    fi
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      local rel="" relf=""
      rel="${dir#"$root"/}"
      relf="${rel%/}/$f"
      case "$relf" in *"//"*) relf=$(printf "%s" "$relf" | tr -s "/" "/");; esac
      sz=$(wc -c < "$dir/$f" | tr -d ' ')
      ts=$(date -u -r "$dir/$f" +%FT%TZ 2>/dev/null || printf '?')
      LA_FOUND_ROWS="${LA_FOUND_ROWS}[$label]  $relf  ${sz}b  $ts"$'\n'
    done <<< "$LA_DELIV_FILES"
  done <<< "$LA_MATCH_DIRS"

  LA_COVERAGE_LINE="$LA_COV_HOLD dirs hold a deliverable; $LA_COV_POINTED carry a pointer; $LA_COV_UNATTR unattributable"

  # eponymous deliverables also count as found
  if [[ "$LA_EPON_STATE" == "deliverables" ]]; then
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      local eprel=""
      eprel="docs/handoff/${LA_TID:-$LA_SIG8}"
      sz=$(wc -c < "$epon/$f" | tr -d ' ')
      ts=$(date -u -r "$epon/$f" +%FT%TZ 2>/dev/null || printf '?')
      LA_FOUND_ROWS="${LA_FOUND_ROWS}[main/eponymous]  $eprel/$f  ${sz}b  $ts"$'\n'
    done <<< "$LA_EPON_FILES"
  fi

  local nfound
  nfound=$(printf '%s' "$LA_FOUND_ROWS" | grep -c . || true)

  if [[ "$LA_EPON_STATE" == "unreadable" ]]; then
    LA_RESULT="unknown"; LA_REASON="$epon exists but listdir failed"; return 2
  fi
  if [[ -n "$LA_UNREADABLE_DIRS" ]]; then
    LA_RESULT="unknown"
    LA_REASON="$(printf '%s' "$LA_UNREADABLE_DIRS" | head -1)exists but listdir failed"
    return 2
  fi
  if [[ "$nfound" -gt 0 ]]; then
    LA_RESULT="found"; LA_NFOUND=$nfound; return 0
  fi
  if [[ $LA_COV_UNATTR -gt 0 ]]; then
    LA_RESULT="unknown"
    LA_REASON="no pointer matched $query, but $LA_COV_UNATTR of $LA_COV_HOLD deliverable-holding dirs carry no pointer at all ($LA_COV_UNATTR unattributable)"
    return 2
  fi
  LA_RESULT="none"; LA_NFOUND=0
  return 1
}
