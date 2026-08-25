# leadv2 tmux statusline (CODEX-TMUX-STATUSLINE-01)

Opt-in persistent visual surface for leadv2 status: the **bottom status bar of
tmux**. Nothing is installed until you run the statusline installer; the
normal codex-lead `install.sh` never mutates a tmux config.

## What the bar shows

The wrapper `plugins/leadv2/codex-lead/statusline/leadv2-tmux-status.sh`
renders the same line `codex-lead/leadv2-codex-status.sh` produces — provider
quota burn (`cc %·reset · cx %·reset · glm %·reset`), active lane count, first
active task — one compact line at the right end of tmux's bottom bar:

```
cc 32%/7d/4d12h · cx 97%/wk/6d14h · glm 99%/wk/6d16h | lanes 2 | task FIX-42
```

Behavioural contract:

- **Fast / non-blocking.** tmux calls the wrapper via `#()` every
  `status-interval` (the generated conf sets 15s). The wrapper keeps a file
  cache (TTL 20s, override with `LEADV2_STATUSLINE_TTL`, contract window
  15-30s). A fresh cache is a plain `cat`; a stale one triggers exactly one
  bounded refresh; writes are atomic (tmp + `mv`), so a concurrent tick never
  reads a partial line.
- **Fail-open.** If the underlying status script fails, the wrapper serves the
  last good cached line (stale-while-error); with no cache at all it renders
  the compact fallback `leadv2 ?`. It always exits 0 — a non-zero exit would
  blank the bar until the next tick.

## Install

Default (assets only, touches no tmux config):

```sh
bash plugins/leadv2/codex-lead/statusline/install-tmux-statusline.sh
```

This generates `$XDG_CONFIG_HOME/leadv2/tmux-statusline.conf` (default
`~/.config/leadv2/tmux-statusline.conf`) and prints the activation command.
Activate for the running server — no restart, no shell prompt hacks:

```sh
tmux source-file ~/.config/leadv2/tmux-statusline.conf
```

To make it persistent across tmux servers, add the managed include explicitly
(the installer never guesses your config path):

```sh
bash plugins/leadv2/codex-lead/statusline/install-tmux-statusline.sh \
  --tmux-conf ~/.tmux.conf
```

That appends (idempotently, with a `.bak` backup on change) one
sentinel-delimited block:

```
# BEGIN leadv2 tmux statusline (managed by plugins/leadv2/codex-lead/statusline/install-tmux-statusline.sh)
source-file '/home/you/.config/leadv2/tmux-statusline.conf'
# END leadv2 tmux statusline
```

Everything outside the block is preserved byte-identically; re-running the
installer replaces only the block. Paths with spaces are safe: the generated
conf quotes the `#()` payload (`'#("/path with spaces/leadv2-tmux-status.sh")'`
— tmux hands the content to `sh`, the double quotes keep it one word), and the
`source-file` path is single-quoted. No eval anywhere.

### Note on status-right

The generated conf sets `status-right` (and `status-interval` 15,
`status-right-length` 100). Sourcing it **replaces** any previous `status-right`
for that server; uninstall does not remember your old value.

## Uninstall

```sh
# strips the managed block from the config you name (only that block)
bash plugins/leadv2/codex-lead/statusline/uninstall-tmux-statusline.sh \
  --tmux-conf ~/.tmux.conf

# always also removes our own assets: generated conf + status cache
```

Then reload and restore the bar you want:

```sh
tmux source-file ~/.tmux.conf
tmux set -g status-right '#S'
```

Without `--tmux-conf`, the uninstaller still removes the generated conf and
the cache, and prints the block-removal command instead of guessing a path.

## Cache location

`${XDG_CACHE_HOME:-~/.cache}/leadv2/tmux-statusline/status.cache`. Override
for tests with `LEADV2_STATUSLINE_CACHE`; override the wrapped status command
with `LEADV2_STATUSLINE_CMD` (used by `tests/test-tmux-statusline.sh` to stay
hermetic — the test suite never calls the real quota runtime and never touches
a real tmux config).

## Tests

```sh
bash plugins/leadv2/codex-lead/tests/test-tmux-statusline.sh
```

Covers cache hit / stale refresh / error fallback, default install not
mutating tmux config, `--tmux-conf` idempotence and content preservation,
selective uninstall (incl. install→uninstall byte-identical round-trip), and
paths with spaces (fixture root and cache path both contain a space).
