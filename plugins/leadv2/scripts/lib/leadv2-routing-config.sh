#!/usr/bin/env bash
# leadv2-routing-config.sh — the ONE resolver for the router-registry config.
# PLUGIN-REPO-CARRIES-A-SHADOW-ROUTING-CONFIG-01 (row 85e7878c), 2026-09-10.
#
# Before this file, the path <root>/.claude/ref/leadv2-routing.yaml was
# rebuilt with private fallback chains in nine readers, and a tenant file
# SUBSTITUTED the canonical registry (plugins/leadv2/config/
# leadv2-routing.yaml) wholesale. In the plugin repo the tenant file was a
# hand-made copy 229 lines behind canonical and its capability_matrix lacked
# `capability:`, so orders written into canonical did not act on plugin lanes
# -- reproduced three times before this fix. Every reader now resolves here;
# after the change, grep for '.claude/ref/leadv2-routing.yaml' over
# plugins/leadv2/scripts (outside tests/) finds only this file and comments.
#
# leadv2_routing_config_path [<root>]   -> stdout: the config path to read
#   rc=0  resolved. Which tier, in order:
#     1. $LEADV2_ROUTING_YAML readable  -> printed AS-IS (explicit operator/
#        test override; NOT merged -- every pre-existing user of this seam
#        passes a complete config and hermetic suites depend on exact bytes).
#        Unset/unreadable descends, as all pre-2026-09-10 readers did.
#     2. <root>/.claude/ref/leadv2-routing.yaml exists -> tenant DELTA merged
#        over the canonical registry by leadv2-routing-merge.py; the
#        MATERIALIZED merged file is printed. Mappings inherit missing keys;
#        lists REPLACE entirely (a tenant must be able to remove a ladder
#        row, not only add one). The merge writes one journal line to stderr
#        per build (cache miss) naming canonical, tenant and overridden-key
#        count -- the old substitution was silent, which is why it survived.
#     3. canonical as-is: ${LEADV2_ROUTING_YAML_PLUGIN_OVERRIDE:-<this lib>/
#        ../../config/leadv2-routing.yaml}, else ${LEADV2_CANONICAL_ROOT:-
#        $HOME/Projects/leadv2}/plugins/leadv2/config/leadv2-routing.yaml.
#        Byte-for-byte the pre-2026-09-10 behaviour of a repo with no tenant
#        file (all three live tenant repos) -- unchanged on purpose.
#   rc=1  the tenant file exists but does not parse (or no canonical to merge
#         against): LOUD refusal naming the file(s) on stderr. Never a silent
#         fallback to canonical -- a silent fallback is the substitution
#         defect seen from the other side.
#   rc=2  nothing anywhere (no readable env override, no tenant, no canonical).
#   rc=3  no root: neither argument nor PROJECT_ROOT. A caller that resolves
#         before PROJECT_ROOT is defined gets a named refusal, not PWD luck.
#
# Cache: the merged file is keyed by the CONTENT checksums of both inputs and
# written under ${LEADV2_ROUTING_CONFIG_CACHE_DIR:-${TMPDIR:-/tmp}/
# leadv2-routing-merged}/, published atomically (temp + rename in the merge
# tool), so dispatch calling this dozens of times per run rebuilds nothing
# and two concurrent builders cannot interleave. The brief asked for an
# mtime-keyed cache; content checksums are used instead because `stat`'s
# mtime is second-granularity and a fixture editing one same-size cell within
# that second would read a stale merge -- content identity has no such hole
# and invalidates on any real change. Repeated calls inside one process are
# additionally memoized (same root + same override env).

_LEADV2_ROUTING_CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Canonical registry candidates, plugin-local first (same discipline the
# pre-2026-09-10 dispatch/product-close fallbacks used), canonical-root copy
# second for consumer-farm source paths that lack a config sibling.
_leadv2_routing_config_canonical() {  # -> stdout path (may not exist), rc=1 none
  local _c="${LEADV2_ROUTING_YAML_PLUGIN_OVERRIDE:-${_LEADV2_ROUTING_CONFIG_DIR}/../../config/leadv2-routing.yaml}"
  if [[ -f "${_c}" ]]; then printf '%s' "${_c}"; return 0; fi
  _c="${LEADV2_CANONICAL_ROOT:-${HOME}/Projects/leadv2}/plugins/leadv2/config/leadv2-routing.yaml"
  if [[ -f "${_c}" ]]; then printf '%s' "${_c}"; return 0; fi
  return 1
}

leadv2_routing_config_path() {
  local _root="${1:-${PROJECT_ROOT:-}}"
  if [[ -z "${_root}" ]]; then
    printf '[leadv2-routing-config] REFUSE: no project root (pass one or set PROJECT_ROOT) -- resolving a routing config without a root reads some arbitrary repo'"'"'s tenant file\n' >&2
    return 3
  fi

  local _env="${LEADV2_ROUTING_YAML:-}"
  local _memo_key="${_root}|${_env}|${LEADV2_ROUTING_YAML_PLUGIN_OVERRIDE:-}"
  if [[ -n "${LEADV2_ROUTING_CONFIG_MEMO_PATH:-}" \
     && "${LEADV2_ROUTING_CONFIG_MEMO_KEY:-}" == "${_memo_key}" ]]; then
    printf '%s' "${LEADV2_ROUTING_CONFIG_MEMO_PATH}"
    return 0
  fi

  # Tier 1: explicit override, as-is (see contract above).
  if [[ -n "${_env}" && -r "${_env}" ]]; then
    LEADV2_ROUTING_CONFIG_MEMO_PATH="${_env}"
    LEADV2_ROUTING_CONFIG_MEMO_KEY="${_memo_key}"
    printf '%s' "${_env}"
    return 0
  fi

  local _tenant="${_root}/.claude/ref/leadv2-routing.yaml"
  local _canonical=""
  _canonical="$(_leadv2_routing_config_canonical)" || _canonical=""

  if [[ -f "${_tenant}" ]]; then
    if [[ -z "${_canonical}" ]]; then
      printf '[leadv2-routing-config] REFUSE: tenant routing yaml exists but no canonical registry found to merge against (tenant=%s)\n' "${_tenant}" >&2
      return 1
    fi
    local _cache_dir="${LEADV2_ROUTING_CONFIG_CACHE_DIR:-${TMPDIR:-/tmp}/leadv2-routing-merged}"
    local _ck _out
    _ck="$( { cksum "${_canonical}"; cksum "${_tenant}"; } | cksum | cut -d' ' -f1)"
    _out="${_cache_dir}/${_ck}.yaml"
    if [[ ! -s "${_out}" ]]; then
      # ONE merge call -- the mutation-control anchor for this file swaps this
      # line back to tenant-substitutes-canonical and the main suite fixture
      # goes red. Keep exactly one matchable invocation.
      python3 "${_LEADV2_ROUTING_CONFIG_DIR}/leadv2-routing-merge.py" "${_canonical}" "${_tenant}" "${_out}" >&2 || return 1
    fi
    LEADV2_ROUTING_CONFIG_MEMO_PATH="${_out}"
    LEADV2_ROUTING_CONFIG_MEMO_KEY="${_memo_key}"
    printf '%s' "${_out}"
    return 0
  fi

  # Tier 3: no tenant file -> clean canonical, unchanged bytes.
  if [[ -n "${_canonical}" ]]; then
    LEADV2_ROUTING_CONFIG_MEMO_PATH="${_canonical}"
    LEADV2_ROUTING_CONFIG_MEMO_KEY="${_memo_key}"
    printf '%s' "${_canonical}"
    return 0
  fi
  return 2
}
