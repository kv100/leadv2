#!/usr/bin/env bash
# Real-guard fixture: leadv2-context-glossary-close.sh — ADVISORY by contract:
# a close-style commit in a project with CONTEXT.md and a staged diff adding
# `class Foo:` prints the domain-modeling reminder on STDERR, exit 0
# (GV_FIX_EXPECT=log — a fire that never blocks).
GV_FIX_GUARD="leadv2-context-glossary-close.sh"
GV_FIX_PRE='mkdir -p "$LEADV2_SANDBOX/proj"
cd "$LEADV2_SANDBOX/proj"
git init -q .
git config user.email fix@example.com
git config user.name fix
printf "%s\n" "CONTEXT" > CONTEXT.md
printf "%s\n" "class Foo:" > new_model.py
git add new_model.py'
GV_FIX_STDIN='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"chore: close GLOSS-1\""},"cwd":"$LEADV2_SANDBOX/proj"}'
GV_FIX_CWD='$LEADV2_SANDBOX/proj'
GV_FIX_EXPECT="log"
