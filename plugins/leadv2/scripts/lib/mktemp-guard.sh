# Guard against mktemp -t without XXX in the template.
# This function is intended to be sourced in test scripts.
# It checks the script that sourced it (the test script) for any occurrence
# of mktemp -t (or mktemp -d -t) where the template argument does not contain XXX.
# If found, it prints an error and exits with status 1.

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
}