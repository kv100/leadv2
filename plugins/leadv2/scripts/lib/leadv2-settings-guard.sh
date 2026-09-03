#!/usr/bin/env bash
# leadv2-settings-guard.sh — pure predicate, sourceable by both the installer
# and its test suite (mirrors the GUARD_LIB / plugin_script_classify sourcing
# idiom in leadv2-repo-install.sh).
#
# INSTALLER-WRITES-ENV-INTO-A-TRACKED-SETTINGS-FILE-01 (2026-09-03): the
# installer used to append the LEADV2_* env block straight into
# .claude/settings.json with no tracked-ness check. In a repo where that file
# is a committed, shared file (measured: ~/MythicalGames/m3) that leaked one
# developer's absolute paths and plugin routing knobs to the whole team. This
# predicate is the defense-in-depth check run immediately before ANY write to
# a settings file, whichever file the caller is about to touch.
#
# No globals, no side effects, no output on stdout — exit code only.

leadv2_path_is_tracked() { # <repo-root> <relpath>  -- exit 0 tracked, 1 not
  local repo="$1" relpath="$2"
  git -C "$repo" ls-files --error-unmatch -- "$relpath" >/dev/null 2>&1
}
