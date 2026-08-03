#!/usr/bin/env python3
"""Batched spentness GC for a Claude project-memory index."""

import argparse
import collections
import datetime
import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

import yaml


ENTRY = re.compile(r"^- \[([^]]+)\]\(([^)]+)\) — (.*)$")
CLI_LIMITS = re.compile(
    rb'var PS="MEMORY\.md",[A-Za-z_$][A-Za-z0-9_$]*=([0-9]+),'
    rb'[A-Za-z_$][A-Za-z0-9_$]*=([0-9]+)'
)
STATE_NAME = ".memory-gc-state.json"
UNRESOLVED = re.compile(
    r"(?i)\b(?:open|unresolved|awaiting|pending|blocked|queued|owed|"
    r"not\s+yet|never[- ]fixed|in\s+progress|fix\s+queued|follow-?up|"
    r"still\s+(?:dead|broken|open|blocked)|needs?\s+(?:founder|root))\b"
)


class VerdictError(RuntimeError):
    pass


class MeasurementError(RuntimeError):
    pass


def file_sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def bytes_sha(data):
    return hashlib.sha256(data).hexdigest()


def one_line(value):
    return re.sub(r"\s+", " ", str(value or "")).strip()


def python_pattern(value):
    """Translate the POSIX character classes used by the YAML trigger store."""
    replacements = {
        "[[:space:]]": r"\s",
        "[[:digit:]]": r"\d",
        "[[:alnum:]]": r"[A-Za-z0-9]",
        "[[:alpha:]]": r"[A-Za-z]",
    }
    for source, replacement in replacements.items():
        value = value.replace(source, replacement)
    return value


def yaml_value(text, key):
    match = re.search(
        r"(?m)^\s*" + re.escape(key) + r"\s*:\s*['\"]?([^\n'\"]+)", text
    )
    return match.group(1).strip() if match else ""


def active_markers(project_root):
    """Return exact identifiers and regexes from explicitly ACTIVE YAML entries."""
    exact = set()
    patterns = []
    for relative in (
        "docs/leadv2/immune-patterns.yaml",
        "docs/leadv2-negative-memory.yaml",
    ):
        path = project_root / relative
        if not path.is_file():
            continue
        try:
            data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
        except (OSError, yaml.YAMLError) as exc:
            raise MeasurementError(f"cannot read ACTIVE patterns from {path}: {exc}")

        def walk(value):
            if isinstance(value, dict):
                if str(value.get("status", "")).strip().upper() == "ACTIVE":
                    for key in ("id", "slug", "name"):
                        marker = one_line(value.get(key))
                        if marker:
                            exact.add(marker.casefold())
                    for key in ("pattern", "regex", "trigger_pattern"):
                        marker = one_line(value.get(key))
                        if marker:
                            patterns.append(marker)
                for child in value.values():
                    walk(child)
            elif isinstance(value, list):
                for child in value:
                    walk(child)

        walk(data)
    return {"exact": sorted(exact), "patterns": patterns}


def entry_immunity(entry, raw, markers):
    immune = []
    if "STANDING:" in entry["raw_line"] or "STANDING:" in raw:
        immune.append("standing")
    if yaml_value(raw, "type").casefold() == "user":
        immune.append("user_type")
    if yaml_value(raw, "memory_gc").casefold() == "keep":
        immune.append("opt_out")
    if not entry["exists"]:
        immune.append("orphan_index_line")
    if ". Also:" in entry["raw_line"]:
        # Removing this line would also remove pointers whose files are not moved.
        immune.append("multi_pointer_index_line")
    if UNRESOLVED.search(entry["raw_line"] + "\n" + raw):
        # A model may not invent resolution that contradicts the indexed source.
        immune.append("unresolved_work")

    identities = {
        one_line(entry.get("slug")).casefold(),
        one_line(entry.get("title")).casefold(),
        one_line(yaml_value(raw, "name")).casefold(),
    }
    if identities.intersection(markers["exact"]):
        immune.append("active")
    else:
        corpus = "\n".join(
            (
                entry.get("slug", ""),
                entry.get("title", ""),
                entry.get("hook", ""),
                entry.get("description", ""),
                raw,
            )
        )
        for pattern in markers["patterns"]:
            try:
                if re.search(python_pattern(pattern), corpus, re.IGNORECASE):
                    immune.append("active")
                    break
            except re.error:
                if pattern.casefold() in corpus.casefold():
                    immune.append("active")
                    break
    return immune


def safe_entry_path(base, slug):
    candidate = (base / (slug + ".md")).resolve()
    try:
        candidate.relative_to(base.resolve())
    except ValueError as exc:
        raise VerdictError(f"entry target escapes memory directory: {slug}") from exc
    return candidate


def parse_index(index, project_root):
    raw_bytes = index.read_bytes()
    text = raw_bytes.decode("utf-8")
    lines = text.splitlines(keepends=True)
    markers = active_markers(project_root)
    entries = []
    section = ""
    for line_number, line in enumerate(lines, 1):
        if line.startswith("## "):
            section = line[3:].strip()
        match = ENTRY.match(line.rstrip("\r\n"))
        if not match:
            continue
        title, target, hook = match.groups()
        slug = target[:-3] if target.endswith(".md") else target
        path = safe_entry_path(index.parent, slug)
        exists = path.is_file()
        raw = path.read_text(encoding="utf-8") if exists else ""
        entry = {
            "entry_id": f"e{len(entries) + 1:04d}",
            "line_no": line_number,
            "section": section,
            "title": title,
            "slug": slug,
            "hook": hook,
            "raw_line": line,
            "description": one_line(yaml_value(raw, "description"))[:400],
            "type": one_line(yaml_value(raw, "type") or "unknown"),
            "exists": exists,
        }
        entry["immune"] = entry_immunity(entry, raw, markers)
        entry["content_excerpt"] = one_line(raw)[:2400]
        entries.append(entry)
    return raw_bytes, lines, entries


def discover_cli_limits(binary):
    resolved = shutil.which(binary)
    if not resolved:
        raise MeasurementError(
            f"cannot measure MEMORY.md limits: model CLI not found: {binary}; "
            "configure --byte-cap and --line-limit from the session loader"
        )
    path = Path(resolved).resolve()
    overlap = b""
    try:
        with path.open("rb") as handle:
            while True:
                chunk = handle.read(1024 * 1024)
                if not chunk:
                    break
                haystack = overlap + chunk
                match = CLI_LIMITS.search(haystack)
                if match:
                    line_limit, byte_cap = (int(value) for value in match.groups())
                    if line_limit <= 0 or byte_cap <= 0:
                        break
                    return line_limit, byte_cap, f"embedded MEMORY.md loader config in {path}"
                overlap = haystack[-256:]
    except OSError as exc:
        raise MeasurementError(f"cannot inspect model CLI {path}: {exc}") from exc
    raise MeasurementError(
        f"cannot locate MEMORY.md byte/line limits in {path}; configure --byte-cap "
        "and --line-limit from a measured session loader instead of inventing a cap"
    )


def measured_cap(args, byte_count, line_count):
    if (args.byte_cap is None) != (args.line_limit is None):
        raise MeasurementError("--byte-cap and --line-limit must be configured together")
    if args.byte_cap is not None:
        byte_cap, line_limit = args.byte_cap, args.line_limit
        source = "explicit CLI configuration"
    else:
        line_limit, byte_cap, source = discover_cli_limits(
            os.environ.get("CLAUDE_BIN", "claude")
        )
    if byte_cap <= 0 or line_limit <= 0:
        raise MeasurementError("configured MEMORY.md limits must be positive")
    mean = byte_count / line_count if line_count else 0.0
    byte_derived_lines = math.floor(byte_cap / mean) if mean else line_limit
    derived_lines = min(line_limit, byte_derived_lines)
    return {
        "byte_cap": byte_cap,
        "engine_line_limit": line_limit,
        "mean_line_bytes": mean,
        "byte_derived_lines": byte_derived_lines,
        "derived_line_cap": derived_lines,
        "source": source,
    }


def request_for(entries, cap, byte_count, line_count):
    requested = []
    for entry in entries:
        requested.append(
            {
                "entry_id": entry["entry_id"],
                "slug": entry["slug"],
                "section": entry["section"],
                "title": entry["title"],
                "hook": entry["hook"],
                "description": entry["description"],
                "type": entry["type"],
                "content_excerpt": entry["content_excerpt"],
                "protected_by_code": entry["immune"],
            }
        )
    return {
        "measured_index_bytes": byte_count,
        "measured_index_lines": line_count,
        "configured_byte_cap": cap["byte_cap"],
        "entries": requested,
    }


def verdict_map(data):
    if not isinstance(data, dict) or not isinstance(data.get("verdicts"), list):
        raise VerdictError("response does not contain a verdicts list")
    result = {}
    for item in data["verdicts"]:
        if not isinstance(item, dict) or not isinstance(item.get("entry_id"), str):
            raise VerdictError("verdict is missing entry_id")
        if item["entry_id"] in result:
            raise VerdictError("response contains duplicate entry_id")
        result[item["entry_id"]] = item
    return result


def json_object(text):
    decoder = json.JSONDecoder()
    for match in re.finditer(r"\{", text):
        try:
            value, _ = decoder.raw_decode(text[match.start() :])
        except json.JSONDecodeError:
            continue
        if isinstance(value, dict) and "verdicts" in value:
            return value
    raise VerdictError("model result did not contain a JSON verdict object")


def call_model(plan, model):
    binary = os.environ.get("CLAUDE_BIN", "claude")
    resolved = shutil.which(binary)
    if not resolved:
        raise VerdictError(f"model CLI not found: {binary}")
    template = Path(__file__).resolve().parent.parent / "prompts" / "memory-gc-verdict.md"
    if not template.is_file():
        raise VerdictError(f"prompt template not found: {template}")
    prompt = template.read_text(encoding="utf-8").replace(
        "<<<ENTRIES_JSON>>>", json.dumps(plan["request"], separators=(",", ":"))
    )
    try:
        timeout = int(os.environ.get("LEADV2_MEMGC_TIMEOUT", "120"))
    except ValueError as exc:
        raise VerdictError("LEADV2_MEMGC_TIMEOUT must be an integer") from exc
    if timeout <= 0:
        raise VerdictError("LEADV2_MEMGC_TIMEOUT must be positive")
    command = [
        resolved,
        "-p",
        prompt,
        "--model",
        model,
        "--max-turns",
        "1",
        "--tools",
        "",
        "--safe-mode",
        "--no-session-persistence",
        "--output-format",
        "json",
    ]
    try:
        result = subprocess.run(
            command, capture_output=True, text=True, timeout=timeout, check=False
        )
    except subprocess.TimeoutExpired as exc:
        raise VerdictError(f"model call timed out after {timeout}s") from exc
    except OSError as exc:
        raise VerdictError(f"model call could not start: {exc}") from exc
    if result.returncode:
        detail = (result.stderr or result.stdout).strip().replace("\n", " ")[-500:]
        raise VerdictError(
            f"model call exited {result.returncode}: {detail or 'no error output'}"
        )
    try:
        envelope = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise VerdictError(f"model CLI returned invalid JSON: {exc}") from exc
    payload = envelope.get("structured_output") if isinstance(envelope, dict) else None
    if not isinstance(payload, dict):
        raw = envelope.get("result", "") if isinstance(envelope, dict) else ""
        payload = json_object(raw if isinstance(raw, str) else json.dumps(raw))
    return verdict_map(payload)


def get_verdicts(plan, verdicts_file, model):
    if verdicts_file:
        try:
            data = json.loads(Path(verdicts_file).read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            raise VerdictError(f"cannot load verdicts file: {exc}") from exc
        result, status = verdict_map(data), "verdicts-file override"
    else:
        result, status = call_model(plan, model), f"available (model={model})"
    expected = {entry["entry_id"] for entry in plan["entries"]}
    if set(result) != expected:
        raise VerdictError(
            "verdict IDs do not match request "
            f"(missing={sorted(expected - set(result))}, "
            f"unknown={sorted(set(result) - expected)})"
        )
    return result, status


def validate(plan, got):
    rows = []
    rejected = []
    for entry in plan["entries"]:
        supplied = got[entry["entry_id"]]
        model_verdict = supplied.get("verdict")
        reason = one_line(supplied.get("reason"))
        bad = ""
        if model_verdict not in ("live", "spent"):
            bad = "bad_verdict"
        elif not reason:
            bad = "empty_reason"
        elif len(reason) > 240:
            bad = "reason_too_long"
        elif model_verdict == "spent" and entry["immune"]:
            bad = "immune_violation"
        if bad:
            rejected.append(
                {"entry_id": entry["entry_id"], "slug": entry["slug"], "reason": bad}
            )
            verdict = "live"
            if bad == "immune_violation":
                reason = "protected by code immunity: " + ",".join(entry["immune"])
            else:
                reason = "rejected model verdict: " + bad
        else:
            verdict = model_verdict
        rows.append(
            (
                entry,
                {
                    "verdict": verdict,
                    "model_verdict": model_verdict,
                    "reason": reason,
                },
            )
        )
    return rows, rejected


def projection(plan, rows):
    spent = [entry for entry, verdict in rows if verdict["verdict"] == "spent"]
    removed_bytes = sum(len(entry["raw_line"].encode("utf-8")) for entry in spent)
    return {
        "spent": spent,
        "lines": plan["total_lines"] - len(spent),
        "bytes": plan["byte_count"] - removed_bytes,
    }


def report(plan, rows, rejected, llm):
    projected = projection(plan, rows)
    cap = plan["read_cap"]
    within = (
        projected["bytes"] <= cap["byte_cap"]
        and projected["lines"] <= cap["engine_line_limit"]
    )
    lines = [
        "# Memory index GC plan",
        "",
        f"llm: {llm}",
        f"read-cost cap source: {cap['source']}",
        f"configured maximum index read cost: {cap['byte_cap']} bytes; "
        f"loader line limit: {cap['engine_line_limit']}",
        f"measured current index read cost: {plan['byte_count']} bytes / "
        f"{plan['total_lines']} lines = {cap['mean_line_bytes']:.3f} bytes/line",
        "derived line cap: min(" + str(cap["engine_line_limit"]) + ", floor("
        + str(cap["byte_cap"]) + f" / {cap['mean_line_bytes']:.3f})) = "
        + str(cap["derived_line_cap"]),
        f"projected post-GC index: {projected['bytes']} bytes / "
        f"{projected['lines']} lines (at or under configured read cap: "
        f"{'yes' if within else 'no'})",
        f"spent entries: {len(projected['spent'])}",
        "spent set: " + (", ".join(entry["slug"] for entry in projected["spent"]) or "(empty)"),
        "",
        "## Per-entry verdicts",
    ]
    for entry, verdict in rows:
        immunity = f" [immune={','.join(entry['immune'])}]" if entry["immune"] else ""
        override = (
            f" [model={verdict['model_verdict']} overridden]"
            if verdict["model_verdict"] != verdict["verdict"]
            else ""
        )
        lines.append(
            f"- {entry['entry_id']} {entry['slug']}: {verdict['verdict']}"
            f"{immunity}{override} — {verdict['reason']}"
        )
    for item in rejected:
        lines.append(
            f"- rejected_verdict: {item['entry_id']} {item['slug']} {item['reason']}"
        )
    return "\n".join(lines) + "\n", projected


def state_path(memory_dir):
    return memory_dir / STATE_NAME


def load_state(memory_dir):
    path = state_path(memory_dir)
    if not path.is_file():
        return {}
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return value if isinstance(value, dict) else {}


def prepare(args):
    memory_dir = Path(args.memory_dir).resolve()
    project_root = Path(args.project_root).resolve()
    index = memory_dir / "MEMORY.md"
    raw_bytes, lines, entries = parse_index(index, project_root)
    cap = measured_cap(args, len(raw_bytes), len(lines))
    current_sha = bytes_sha(raw_bytes)
    plan = {
        "memory_dir": str(memory_dir),
        "project_root": str(project_root),
        "index_sha256_pre": current_sha,
        "byte_count": len(raw_bytes),
        "total_lines": len(lines),
        "lines": lines,
        "entries": entries,
        "read_cap": cap,
    }
    previous = load_state(memory_dir)
    if previous.get("index_sha256") == current_sha:
        plan["early_exit"] = True
        plan["early_reason"] = "index already classified at current sha256"
        plan["request"] = {"entries": []}
    elif not entries:
        plan["early_exit"] = True
        plan["early_reason"] = "index has no memory entries"
        plan["request"] = {"entries": []}
    else:
        plan["request"] = request_for(entries, cap, len(raw_bytes), len(lines))
    Path(args.plan).write_text(json.dumps(plan), encoding="utf-8")


def unique_run_dir(memory_dir):
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("gc-%Y%m%dT%H%M%S%fZ")
    run = memory_dir / "archive" / stamp
    run.mkdir(parents=True)
    return stamp, run


def write_atomic(path, data):
    temporary = path.with_name(path.name + ".memory-gc-tmp")
    temporary.write_bytes(data)
    if path.exists():
        shutil.copymode(path, temporary)
    os.replace(temporary, path)


def apply_rows(plan, rows, rejected, model):
    memory_dir = Path(plan["memory_dir"])
    index = memory_dir / "MEMORY.md"
    if file_sha(index) != plan["index_sha256_pre"]:
        raise VerdictError("index changed during GC")
    projected = projection(plan, rows)
    moves = []
    for entry, verdict in rows:
        if verdict["verdict"] != "spent":
            continue
        if entry["immune"]:
            raise VerdictError(f"internal immunity violation for {entry['slug']}")
        source = safe_entry_path(memory_dir, entry["slug"])
        if not source.is_file():
            raise VerdictError(f"spent entry file disappeared: {entry['slug']}")
        reason_line = f"- {entry['slug']} — {verdict['reason']}"
        moves.append(
            {
                "entry_id": entry["entry_id"],
                "slug": entry["slug"],
                "title": entry["title"],
                "action": "spent",
                "reason": verdict["reason"],
                "reason_line": reason_line,
                "index_line": entry["raw_line"].rstrip("\r\n"),
                "from_line": entry["line_no"],
            }
        )

    remove_lines = {item["from_line"] for item in moves}
    output_text = "".join(
        line for number, line in enumerate(plan["lines"], 1) if number not in remove_lines
    )
    output_bytes = output_text.encode("utf-8")
    now = datetime.datetime.now(datetime.timezone.utc).isoformat()
    previous_state = state_path(memory_dir)
    catalog = memory_dir / "archive" / "ARCHIVE.md"

    if not moves:
        state = {
            "classified_at": now,
            "index_sha256": plan["index_sha256_pre"],
            "model": model,
            "run_id": None,
        }
        write_atomic(state_path(memory_dir), (json.dumps(state, indent=2) + "\n").encode())
        return None, projected

    stamp, run = unique_run_dir(memory_dir)
    shutil.copyfile(index, run / "MEMORY.md.pre")
    if previous_state.is_file():
        shutil.copyfile(previous_state, run / (STATE_NAME + ".pre"))
    catalog_size = catalog.stat().st_size if catalog.is_file() else 0
    (run / "MEMORY.md.archived").write_text(
        "".join(
            entry["raw_line"]
            for entry, verdict in rows
            if verdict["verdict"] == "spent"
        ),
        encoding="utf-8",
    )
    (run / "REASONS.md").write_text(
        "\n".join(item["reason_line"] for item in moves) + "\n", encoding="utf-8"
    )

    moved = []
    try:
        for item in moves:
            source = safe_entry_path(memory_dir, item["slug"])
            destination = safe_entry_path(run, item["slug"])
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(source), str(destination))
            moved.append((source, destination))
        write_atomic(index, output_bytes)
        manifest = {
            "run_id": stamp,
            "run_at": now,
            "memory_dir": str(memory_dir),
            "project_root": plan["project_root"],
            "read_cap": plan["read_cap"],
            "model": model,
            "index_sha256_pre": plan["index_sha256_pre"],
            "index_sha256_post": bytes_sha(output_bytes),
            "index_bytes_pre": plan["byte_count"],
            "index_bytes_post": len(output_bytes),
            "index_lines_pre": plan["total_lines"],
            "index_lines_post": projected["lines"],
            "state_pre_exists": previous_state.is_file(),
            "archive_catalog_bytes_pre": catalog_size,
            "entries": moves,
            "rejected": rejected,
        }
        (run / "manifest.yaml").write_text(
            json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
        )
        with catalog.open("a", encoding="utf-8") as handle:
            handle.write("\n### GC run " + stamp + "\n")
            handle.write("\n".join(item["reason_line"] for item in moves) + "\n")
        state = {
            "classified_at": now,
            "index_sha256": bytes_sha(output_bytes),
            "model": model,
            "run_id": stamp,
        }
        write_atomic(state_path(memory_dir), (json.dumps(state, indent=2) + "\n").encode())
    except Exception:
        shutil.copyfile(run / "MEMORY.md.pre", index)
        for source, destination in reversed(moved):
            if destination.exists() and not source.exists():
                source.parent.mkdir(parents=True, exist_ok=True)
                shutil.move(str(destination), str(source))
        shutil.rmtree(run)
        raise
    return run, projected


def finalize(args):
    memory_dir = Path(args.memory_dir).resolve()
    plan = json.loads(Path(args.plan).read_text(encoding="utf-8"))
    if Path(plan["memory_dir"]) != memory_dir:
        raise VerdictError("plan memory directory does not match --memory-dir")
    if plan.get("early_exit"):
        print(
            "memory-index-gc: no-op ("
            + plan["early_reason"]
            + f"; {plan['byte_count']} bytes, derived line cap "
            + str(plan["read_cap"]["derived_line_cap"])
            + ")"
        )
        return 0
    try:
        got, llm = get_verdicts(plan, args.verdicts_file, args.model)
    except VerdictError as exc:
        (memory_dir / "memory-gc-report.md").write_text(
            "# Memory index GC plan\n\nllm: error: " + str(exc) + "\n",
            encoding="utf-8",
        )
        print(f"memory-index-gc: model verdict call failed: {exc}", file=sys.stderr)
        return 7
    rows, rejected = validate(plan, got)
    text, projected = report(plan, rows, rejected, llm)
    (memory_dir / "memory-gc-report.md").write_text(text, encoding="utf-8")
    if not args.apply:
        print(f"memory-index-gc: dry-run report {memory_dir / 'memory-gc-report.md'}")
        return 0
    try:
        run, projected = apply_rows(plan, rows, rejected, args.model)
    except VerdictError as exc:
        print(f"memory-index-gc: apply refused: {exc}", file=sys.stderr)
        return 5
    suffix = f"; archive {run}" if run else "; no archive created"
    print(
        f"memory-index-gc: applied {len(projected['spent'])} spent entries; "
        f"index {projected['bytes']} bytes / {projected['lines']} lines{suffix}"
    )
    return 0


def restore(args):
    memory_dir = Path(args.memory_dir).resolve()
    index = memory_dir / "MEMORY.md"
    run = Path(args.run_dir).resolve()
    manifest = json.loads((run / "manifest.yaml").read_text(encoding="utf-8"))
    if file_sha(index) != manifest["index_sha256_post"]:
        print("restore refused: live index changed", file=sys.stderr)
        return 6
    for entry in manifest["entries"]:
        destination = safe_entry_path(memory_dir, entry["slug"])
        if destination.exists():
            print(f"restore refused: destination exists: {destination}", file=sys.stderr)
            return 6
    shutil.copyfile(run / "MEMORY.md.pre", index)
    for entry in manifest["entries"]:
        source = safe_entry_path(run, entry["slug"])
        destination = safe_entry_path(memory_dir, entry["slug"])
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(source), str(destination))
    previous = run / (STATE_NAME + ".pre")
    current = state_path(memory_dir)
    if manifest.get("state_pre_exists"):
        shutil.copyfile(previous, current)
    elif current.exists():
        current.unlink()
    catalog = memory_dir / "archive" / "ARCHIVE.md"
    if catalog.exists():
        with catalog.open("r+b") as handle:
            handle.truncate(manifest.get("archive_catalog_bytes_pre", 0))
    print(f"restored {manifest['run_id']}")
    return 0


def audit(args):
    run = Path(args.run_dir).resolve()
    project_root = Path(args.project_root).resolve()
    manifest = json.loads((run / "manifest.yaml").read_text(encoding="utf-8"))
    markers = active_markers(project_root)
    archived_lines = collections.Counter(
        (run / "MEMORY.md.archived").read_text(encoding="utf-8").splitlines()
    )
    reason_lines = collections.Counter(
        (run / "REASONS.md").read_text(encoding="utf-8").splitlines()
    )
    immunity_counts = collections.Counter()
    empty_reasons = 0
    missing_index_lines = 0
    missing_reason_lines = 0
    for item in manifest["entries"]:
        path = safe_entry_path(run, item["slug"])
        raw = path.read_text(encoding="utf-8") if path.is_file() else ""
        entry = {
            "slug": item["slug"],
            "title": item["title"],
            "hook": item["index_line"],
            "description": one_line(yaml_value(raw, "description")),
            "raw_line": item["index_line"],
            "exists": path.is_file(),
        }
        immunity_counts.update(entry_immunity(entry, raw, markers))
        if not one_line(item.get("reason")):
            empty_reasons += 1
        if archived_lines[item["index_line"]] <= 0:
            missing_index_lines += 1
        else:
            archived_lines[item["index_line"]] -= 1
        if reason_lines[item.get("reason_line", "")] <= 0:
            missing_reason_lines += 1
        else:
            reason_lines[item["reason_line"]] -= 1
    result = {
        "archived_entries": len(manifest["entries"]),
        "entries_with_reason": len(manifest["entries"]) - empty_reasons,
        "empty_reasons": empty_reasons,
        "missing_archived_index_lines": missing_index_lines,
        "missing_reason_lines": missing_reason_lines,
        "immunity_query": {
            "standing": immunity_counts["standing"],
            "user_type": immunity_counts["user_type"],
            "opt_out": immunity_counts["opt_out"],
            "active": immunity_counts["active"],
            "orphan_index_line": immunity_counts["orphan_index_line"],
            "multi_pointer_index_line": immunity_counts["multi_pointer_index_line"],
            "unresolved_work": immunity_counts["unresolved_work"],
            "total_violations": sum(immunity_counts.values()),
        },
    }
    print(json.dumps(result, indent=2))
    return 0 if not (
        empty_reasons
        or missing_index_lines
        or missing_reason_lines
        or sum(immunity_counts.values())
    ) else 8


def main():
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    prepare_parser = subparsers.add_parser("prepare")
    prepare_parser.add_argument("--memory-dir", required=True)
    prepare_parser.add_argument("--project-root", required=True)
    prepare_parser.add_argument("--plan", required=True)
    prepare_parser.add_argument("--byte-cap", type=int)
    prepare_parser.add_argument("--line-limit", type=int)

    finalize_parser = subparsers.add_parser("finalize")
    finalize_parser.add_argument("--memory-dir", required=True)
    finalize_parser.add_argument("--plan", required=True)
    finalize_parser.add_argument("--model", default="haiku")
    finalize_parser.add_argument("--verdicts-file")
    finalize_parser.add_argument("--apply", action="store_true")

    restore_parser = subparsers.add_parser("restore")
    restore_parser.add_argument("--memory-dir", required=True)
    restore_parser.add_argument("--run-dir", required=True)

    audit_parser = subparsers.add_parser("audit")
    audit_parser.add_argument("--run-dir", required=True)
    audit_parser.add_argument("--project-root", required=True)

    args = parser.parse_args()
    try:
        if args.command == "prepare":
            prepare(args)
            return 0
        if args.command == "finalize":
            return finalize(args)
        if args.command == "restore":
            return restore(args)
        return audit(args)
    except MeasurementError as exc:
        print(f"memory-index-gc: measurement blocked: {exc}", file=sys.stderr)
        return 8
    except (OSError, UnicodeError, json.JSONDecodeError, yaml.YAMLError) as exc:
        print(f"memory-index-gc: fatal: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
