# Guard against mktemp forms that break on one platform but not the other.
# This function is intended to be sourced in test scripts.
# It checks the script that sourced it (the test script) for two independent
# defects; on either it prints an error and exits with status 1:
#
#   1. `mktemp -t <name>` where the template contains no XXX at all.
#      BSD accepts it; GNU coreutils (CI/Docker Linux hosts) refuses the
#      template, prints to stderr and returns an empty path, so every
#      downstream path built from it resolves against the filesystem root.
#
#   2. A bare template (no -t on the line) whose LAST run of 3+ X's is
#      followed by more characters in the same shell word, e.g.
#      `mktemp /tmp/foo-XXXXXX.json`. BSD mktemp does not substitute such a
#      template -- it returns it LITERALLY and creates that exact fixed
#      shared name, so the second caller at that site gets rc=1 and an
#      empty path, and "$p/subdir/file" becomes "/subdir/file". GNU
#      coreutils substitutes correctly, so the defect is macOS-only -- but
#      this check still fires on every platform, because the code is
#      written on macOS and every lane runs there. BSD does not
#      substitute; GNU does. Scan ported from persona-engine
#      tests/unit/test-mktemp-suffixed-template.sh
#      (MKTEMP-SUFFIXED-TEMPLATE-RETURNS-A-LITERAL-PATH-01, green on main).
#      Lines carrying -t are skipped here: under -t, BSD ignores the
#      embedded X's and appends its own random component
#      (sp.XXXXXX.json.NGFyn6qEKz), so the file really is unique -- that
#      verdict is test-mktemp-guard.sh R4 and must stay silent.

# Flag a word iff its LAST maximal X-run (>=3 X's) is followed by more
# shell-word characters. grep -boE 'X{3,}' can only ever match whole maximal
# runs and prefixes each match with its byte offset. Do NOT replace the
# final-run test with the naive `X{3,}[A-Za-z0-9._-]`: X is in that class,
# so it matches the FOURTH X of a run and flags every template, portable
# ones included.
_mkg_flag_word() {
    local w="$1" last off m
    last="$(printf '%s' "$w" | grep -boE 'X{3,}' | tail -1)"
    [[ -n "$last" ]] || return 1     # no X-run >= 3: not our pattern
    off="${last%%:*}"
    m="${last#*:}"
    # Final-run test -- MUTATION-CONTROL TARGET (test-mktemp-guard.sh R10).
    (( off + ${#m} == ${#w} )) || return 0
    return 1
}

# Split a line into shell words. Only separators that cannot appear INSIDE a
# template word are replaced; $ { } : - . stay in-word so
# ${TMPDIR:-/tmp}/foo-XXXXXX.json survives as one token. read -ra splits
# without pathname expansion.
_mkg_tokens() {
    local s="$1"
    s="${s//;/ }"; s="${s//|/ }"; s="${s//&/ }"; s="${s//(/ }"; s="${s//)/ }"
    s="${s//\"/ }"; s="${s//\'/ }"; s="${s//</ }"; s="${s//>/ }"; s="${s//\`/ }"
    local _t=()
    read -ra _t <<< "$s"
    printf '%s\n' "${_t[@]:-}"
}

mktemp_guard() {
    # The script that sourced us is in ${BASH_SOURCE[1]}
    local script="${BASH_SOURCE[1]}"
    # If we cannot read the script, skip the check (should not happen)
    if [[ ! -r "$script" ]]; then
        return 0
    fi

    # Look for any line with mktemp -t (with possible spaces and other flags) that is not a comment.
    # We use grep to find lines that contain mktemp followed by -t (with possible spaces and flags in between)
    # We want to catch both mktemp -t and mktemp -d -t, etc.
    # We skip lines that are comments (starting with # after optional spaces).
    local line
    line=$(grep -E '\bmktemp\b([^#]*[[:space:]])?-t([[:space:]]|$)' "$script" | grep -vE '^[[:space:]]*#' | head -1 || true)
    if [[ -n "$line" ]]; then
        # Remove everything up to and including the -t flag (and any spaces after it)
        local rest
        rest=$(echo "$line" | sed 's/.*-t[[:space:]]*//')
        # The template is the first word in the rest
        local template
        template=$(echo "$rest" | awk '{print $1}')

        # Check if the template contains XXX
        if [[ ! "$template" =~ XXX ]]; then
            echo "Error: $script contains mktemp -t without XXX in template: $template" >&2
            echo "Debug: line='$line'" >&2
            echo "Debug: rest='$rest'" >&2
            exit 1
        fi
    fi

    # Detection 2: bare suffixed template (only lines that do NOT carry -t,
    # which keeps this check disjoint from detection 1 and from R4). Every
    # command below sits in an exempt context (|| / && / if / while-cond) or
    # is followed by || true, so a caller's `set -e` is never tripped on the
    # clean path -- that is R5, a historic bug this guard must not relearn:
    # a while whose body last failed returns nonzero and kills the caller.
    local bline tok t_flag
    while IFS= read -r bline; do
        [[ "$bline" == *XXX* ]] || continue
        t_flag=0
        while IFS= read -r tok; do
            [[ "$tok" == "-t" ]] && t_flag=1
        done < <(_mkg_tokens "$bline") || true
        (( t_flag )) && continue
        while IFS= read -r tok; do
            [[ -n "$tok" ]] || continue
            [[ "$tok" == \#* ]] && break
            [[ "$tok" == "mktemp" ]] && continue
            if _mkg_flag_word "$tok"; then
                echo "Error: $script contains a bare mktemp template whose X-run is not final: $tok" >&2
                echo "Debug: line='$bline'" >&2
                echo "BSD does not substitute; GNU does. BSD mktemp returns this template" >&2
                echo "LITERALLY and creates the fixed shared name, so the second caller at" >&2
                echo "that site gets rc=1 and an empty path -- \"\$p/subdir/file\" resolves against /." >&2
                exit 1
            fi
        done < <(_mkg_tokens "$bline") || true
    done < <(grep 'mktemp' "$script" | grep -vE '^[[:space:]]*#' || true) || true

    return 0
}