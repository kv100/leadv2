# Round 5 render proof

Focused renderer suite:

```text
pass=43 fail=0 skip=0
```

F5 (`leadv2-lane-status-line.sh:311-313`, `_surf_clip_plain`): the BASE clip
is word-boundary aware, never a raw byte slice — narrow composer renders now
end each BASE fragment on `…`, never mid-word. Live probe against the
production composer (`WIDE_MEMO`, model `Opus 5 (1M context)`) at the exact
widths where the old byte slice used to cut "Opus 5 (1M context)" into `O`,
`Opu`, `Opus 5 `:

```text
w=22: lanes 5: …·dead·9m +4
w=24: lanes 5: …·dead·9m +4
w=26: lanes 5: …·dead·9m +4
w=28: lanes 5: …·dead·9m +4 Opus…
w=30: lanes 5: …·dead·9m +4 Opus 5…
w=32: lanes 5: …·dead·9m +4 Opus 5…
w=34: lanes 5: …·dead·9m +4 Opus 5 (1M…
```

Every fragment above 27 chars is a complete word plus `…`; none is a
mid-word byte cut. At width 20 (narrower than any complete BASE word fits)
the composer drops BASE entirely rather than emit a fragment:

```text
lanes 5: …·dead·9m
```

The changed-scope selector unions `HEAD~1..HEAD`, staged, and unstaged paths,
so control-plane residue cannot suppress committed statusline-suite selection.
Round 5 additionally makes a changed `test-*.sh` file self-select even when
the production file it locks did not also change this run (`tests/run-all.sh`).
