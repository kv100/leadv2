#!/usr/bin/env python3
"""leadv2-routing-merge.py — materialize canonical+tenant into ONE routing config.

PLUGIN-REPO-CARRIES-A-SHADOW-ROUTING-CONFIG-01 (row 85e7878c), 2026-09-10.

Until 2026-09-10 a file at <root>/.claude/ref/leadv2-routing.yaml SUBSTITUTED
plugins/leadv2/config/leadv2-routing.yaml for every router-registry reader.
In the plugin repo that file was a 558-line hand-made copy, drifted 229 lines
behind canonical and missing the `capability:` field in capability_matrix --
so routing orders written into canonical did not act. A copy that must be
kept in sync is the defect; this merge replaces the copy with a delta.

Usage:
  leadv2-routing-merge.py <canonical.yaml> <tenant.yaml> <out.yaml>

Merge rules (one rule, no per-key surprises):
  - mappings merge recursively: a key the tenant lacks is INHERITED from
    canonical, a key it carries WINS;
  - everything else (scalars, lists) is REPLACED ENTIRELY by the tenant value
    when the tenant carries the key. Union is deliberately NOT offered: on
    capability_matrix and dispatch_ladder a tenant must be able to REMOVE a
    row, not only to add one.

The output is a CACHE artifact, never a source of truth: comments are not
preserved. Reader requirements it must keep satisfying: (a) valid YAML for
every yaml.safe_load reader; (b) a block-form `protected_path_patterns:`
list that lib/leadv2-review-signals.sh's regex extractor can find (it
matches `^[ \t]+-[ \t]` items under the key; safe_dump's block style
emits them indented). The suite pins both.

rc=3 -- refusal naming the file -- when either side does not parse or is not
a top-level mapping. A broken tenant file must NEVER be silently fallen back
to canonical: a silent fallback is the substitution defect seen from the
other side.

Journal line, stderr, exactly once per build (cache miss):
  [leadv2-routing-config] merged canonical=<p> tenant=<p> overridden=<n> out=<p>
"""
import os
import sys
import tempfile

import yaml


def _load(path):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            doc = yaml.safe_load(fh)
    except Exception as exc:  # noqa: BLE001 - any parse failure is a refusal
        sys.stderr.write(
            "[leadv2-routing-config] REFUSE: routing yaml does not parse: "
            "%s: %s\n" % (path, exc)
        )
        sys.exit(3)
    if doc is None:
        doc = {}
    if not isinstance(doc, dict):
        sys.stderr.write(
            "[leadv2-routing-config] REFUSE: routing yaml top level is not a "
            "mapping: %s\n" % path
        )
        sys.exit(3)
    return doc


def _leaves(node):
    if isinstance(node, dict):
        return sum(_leaves(v) for v in node.values())
    return 1


def deep_merge(base, delta):
    """(merged, overridden_leaf_count). Tenant wins; lists replace entirely."""
    if isinstance(base, dict) and isinstance(delta, dict):
        out = dict(base)
        count = 0
        for key, val in delta.items():
            if key in out:
                out[key], sub = deep_merge(out[key], val)
                count += sub
            else:
                out[key] = val
                count += _leaves(val)
        return out, count
    return delta, _leaves(delta)


def main(argv):
    if len(argv) != 4:
        sys.stderr.write("usage: leadv2-routing-merge.py <canonical> <tenant> <out>\n")
        return 3
    canonical_p, tenant_p, out_p = argv[1], argv[2], argv[3]
    base = _load(canonical_p)
    delta = _load(tenant_p)
    merged, overridden = deep_merge(base, delta)
    out_dir = os.path.dirname(out_p) or "."
    os.makedirs(out_dir, exist_ok=True)
    # Atomic publish: temp file in the SAME directory + rename, so a
    # concurrent reader (another dispatch resolving the same pair) sees
    # either the old complete file or the new complete file, never a mix.
    fd, tmp = tempfile.mkstemp(dir=out_dir, prefix=".merge-", suffix=".yaml")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            yaml.safe_dump(
                merged,
                fh,
                default_flow_style=False,
                sort_keys=False,
                allow_unicode=True,
                width=1000,
            )
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, out_p)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)
    sys.stderr.write(
        "[leadv2-routing-config] merged canonical=%s tenant=%s overridden=%d out=%s\n"
        % (canonical_p, tenant_p, overridden, out_p)
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
