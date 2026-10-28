#!/usr/bin/env python3
"""Careful, comment-preserving edits of ~/.grok/config.toml for install.sh.

Only two keys are ever touched: `[ui] theme` and `[features] terminal_theme`.
Every other line is kept byte for byte. After editing, the result is parsed
and compared with the original parse; if anything other than those two keys
changed (or the file no longer parses), nothing is written.

    grok_config.py get CONFIG
    grok_config.py set CONFIG [--theme NAME | --unset-theme]
                              [--feature true|false | --unset-feature] [--dry-run]

Exit codes: 0 ok, 2 usage, 3 layout we will not edit automatically,
4 no TOML parser available (Python < 3.11 without `tomli`).
"""
from __future__ import annotations

import argparse
import copy
import json
import os
import re
import sys
import tempfile

try:
    import tomllib  # Python 3.11+
except ModuleNotFoundError:  # pragma: no cover
    try:
        import tomli as tomllib  # type: ignore
    except ModuleNotFoundError:
        print("error: need Python 3.11+ (tomllib) or the 'tomli' package", file=sys.stderr)
        sys.exit(4)

HEADER = re.compile(r"^\s*\[\s*([A-Za-z0-9_.\"' -]+?)\s*\]\s*(#.*)?$")
ANY_HEADER = re.compile(r"^\s*\[")


class LayoutError(Exception):
    pass


def parse(text: str) -> dict:
    return tomllib.loads(text)


def find_table(lines: list[str], name: str) -> int | None:
    for i, line in enumerate(lines):
        m = HEADER.match(line.rstrip("\r\n"))
        if m and not line.lstrip().startswith("[[") and m.group(1).replace('"', "").replace("'", "") == name:
            return i
    return None


def table_end(lines: list[str], start: int) -> int:
    for j in range(start + 1, len(lines)):
        if ANY_HEADER.match(lines[j]):
            return j
    return len(lines)


def key_line(lines: list[str], start: int, end: int, key: str) -> int | None:
    pat = re.compile(r"^\s*(" + re.escape(key) + r"|\"" + re.escape(key) + r"\"|'" + re.escape(key) + r"')\s*=")
    for j in range(start + 1, end):
        if pat.match(lines[j]):
            return j
    return None


def set_key(lines: list[str], data: dict, table: str, key: str, value: str | None) -> list[str]:
    """value is a TOML literal (e.g. '"terminal"' or 'true'), or None to delete."""
    lines = list(lines)
    idx = find_table(lines, table)
    if idx is None:
        if table in data:
            # defined via dotted keys or an inline table: do not guess
            raise LayoutError(f"'{table}' is defined without a [{table}] header")
        if value is None:
            return lines
        if lines and not lines[-1].endswith("\n"):
            lines[-1] += "\n"
        if lines and lines[-1].strip():
            lines.append("\n")
        lines += [f"[{table}]\n", f"{key} = {value}\n"]
        return lines
    end = table_end(lines, idx)
    k = key_line(lines, idx, end, key)
    if k is None:
        if value is not None:
            lines.insert(idx + 1, f"{key} = {value}\n")
        return lines
    if value is None:
        del lines[k]
        end -= 1
        # drop the table header too if nothing but blank lines is left in it
        if all(not l.strip() for l in lines[idx + 1:end]):
            del lines[idx:end]
            while lines and not lines[-1].strip():
                lines.pop()
    else:
        nl = "\r\n" if lines[k].endswith("\r\n") else "\n"
        indent = re.match(r"^\s*", lines[k]).group(0)
        lines[k] = f"{indent}{key} = {value}{nl}"
    return lines


def strip(d: dict) -> dict:
    d = copy.deepcopy(d)
    for t, k in (("ui", "theme"), ("features", "terminal_theme")):
        if isinstance(d.get(t), dict):
            d[t].pop(k, None)
            if not d[t]:
                del d[t]
    return d


def cmd_get(path: str) -> int:
    data = {}
    if os.path.exists(path):
        with open(path, "rb") as fh:
            data = tomllib.load(fh)
    ui, feat = data.get("ui", {}), data.get("features", {})
    print(json.dumps({
        "exists": os.path.exists(path),
        "theme": ui.get("theme"),
        "ui_theme_legacy": ui.get("ui_theme"),
        "terminal_theme": feat.get("terminal_theme"),
    }))
    return 0


def cmd_set(args) -> int:
    text = ""
    if os.path.exists(args.config):
        with open(args.config, encoding="utf-8", newline="") as fh:
            text = fh.read()
    before = parse(text)
    lines = text.splitlines(keepends=True)
    if args.theme is not None or args.unset_theme:
        lines = set_key(lines, before, "ui", "theme", None if args.unset_theme else json.dumps(args.theme))
    if args.feature is not None or args.unset_feature:
        lines = set_key(lines, before, "features", "terminal_theme", None if args.unset_feature else args.feature)
    new = "".join(lines)
    try:
        after = parse(new)
    except tomllib.TOMLDecodeError as e:
        raise LayoutError(f"edit would produce invalid TOML ({e})")
    if strip(after) != strip(before):
        raise LayoutError("edit would change keys other than ui.theme / features.terminal_theme")
    want_theme = None if args.unset_theme else args.theme
    if (args.theme is not None or args.unset_theme) and after.get("ui", {}).get("theme") != want_theme:
        raise LayoutError("ui.theme did not end up with the expected value")
    if args.feature is not None or args.unset_feature:
        want = None if args.unset_feature else (args.feature == "true")
        if after.get("features", {}).get("terminal_theme") != want:
            raise LayoutError("features.terminal_theme did not end up with the expected value")
    if new == text:
        print("unchanged")
        return 0
    if args.dry_run:
        print("would-change")
        return 0
    d = os.path.dirname(os.path.abspath(args.config))
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".config.toml.")
    with os.fdopen(fd, "w", encoding="utf-8", newline="") as fh:
        fh.write(new)
    if os.path.exists(args.config):
        os.chmod(tmp, os.stat(args.config).st_mode & 0o7777)
    os.replace(tmp, args.config)
    print("changed")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    g = sub.add_parser("get")
    g.add_argument("config")
    s = sub.add_parser("set")
    s.add_argument("config")
    t = s.add_mutually_exclusive_group()
    t.add_argument("--theme")
    t.add_argument("--unset-theme", action="store_true")
    f = s.add_mutually_exclusive_group()
    f.add_argument("--feature", choices=["true", "false"])
    f.add_argument("--unset-feature", action="store_true")
    s.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    try:
        return cmd_get(args.config) if args.cmd == "get" else cmd_set(args)
    except LayoutError as e:
        print(f"error: {e}", file=sys.stderr)
        return 3
    except tomllib.TOMLDecodeError as e:
        print(f"error: {args.config} is not valid TOML ({e})", file=sys.stderr)
        return 3


if __name__ == "__main__":
    sys.exit(main())
