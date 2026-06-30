#!/usr/bin/env python3
"""
cbflow migrate — carry user values from an old config file to a new one.

One file at a time. For every TCL assignment in the OLD file whose key
also appears in the NEW file, the old value replaces the new value. The
new file is updated in place with a <new>.bak backup. Keys only in the
new file are listed as "NEW — needs manual review"; keys only in the old
file are listed as "DROPPED — removed/renamed in new version".

Recognized assignment forms (the only TCL constructs CBflow configs use):

    set varname              "value"
    set varname(sub,key)     "value"
    set varname(sub,key)     {value with spaces}
    array set arrname {
        sub,key1    "value1"
        sub,key2    {value2}
    }

Multi-line continuations (\\ at EOL) and procedural code are not touched
— those lines pass through unchanged.

Usage:
    cbflow migrate --old <old.tcl> --new <new.tcl> [--dry-run]
"""

from __future__ import annotations

import argparse
import re
import shutil
import sys
from pathlib import Path


# ───────────────────────────────────────────────────────────────────────────
# Regexes — kept narrow on purpose; anything that doesn't match is skipped.
# ───────────────────────────────────────────────────────────────────────────

# `set <name>[(<key>)]  <value>  [trailing]`
#   1: prefix incl. leading ws and `set`
#   2: full name (with optional parenthesized key)
#   3: whitespace between name and value
#   4: raw value text  (the substituted span)
#   5: trailing whitespace + optional ; or # comment
SET_RE = re.compile(
    r'^(\s*set\s+)'
    r'([A-Za-z_][\w]*(?:\([^)]+\))?)'
    r'([ \t]+)'
    r'(.+?)'
    r'([ \t]*(?:;\s*)?(?:#.*)?)$'
)

# `array set <name> {` — opens a multi-line block of key/value pairs.
ARRAY_OPEN_RE = re.compile(
    r'^(\s*array\s+set\s+)([A-Za-z_][\w]*)(\s*)\{(.*)$'
)

# Inside an array-set block: `<key>  <value>  [trailing]`.
# Keys may be barewords (incl. comma-joined sub-keys) or "quoted".
ARRAY_KV_RE = re.compile(
    r'^([ \t]+)'
    r'([^\s\{\}#"]+|"[^"]*")'
    r'([ \t]+)'
    r'(.+?)'
    r'([ \t]*(?:;\s*)?(?:#.*)?)$'
)


def _normkey(k: str) -> str:
    """Strip surrounding double quotes from an array-block key."""
    if len(k) >= 2 and k[0] == '"' and k[-1] == '"':
        return k[1:-1]
    return k


# ───────────────────────────────────────────────────────────────────────────
# Parser — produces {full_key: raw_value_text}
# ───────────────────────────────────────────────────────────────────────────

def parse(text: str) -> dict[str, str]:
    """Parse a TCL config text into a flat {full_key: raw_value} map.

    Keys are normalized to the access form a user types (e.g. `tech(rcx,ss)`)
    so a `set tech(rcx,ss) ...` line and a key inside `array set tech { ... }`
    both round-trip to the same dict key.

    Values keep their original literal form (quotes/braces preserved) so
    substitution can paste them back verbatim.
    """
    out: dict[str, str] = {}
    current_array: str | None = None

    for line in text.splitlines():
        if current_array is not None:
            stripped = line.strip()
            if stripped.startswith('}'):
                current_array = None
                continue
            m = ARRAY_KV_RE.match(line)
            if m:
                _, k_raw, _, v_raw, _ = m.groups()
                out[f'{current_array}({_normkey(k_raw)})'] = v_raw
            continue

        m = SET_RE.match(line)
        if m:
            _, name, _, v_raw, _ = m.groups()
            out[name] = v_raw
            continue

        m = ARRAY_OPEN_RE.match(line)
        if m:
            _, name, _, _ = m.groups()
            current_array = name

    return out


# ───────────────────────────────────────────────────────────────────────────
# Migrator — walks the NEW file line-by-line, substituting in old values
# ───────────────────────────────────────────────────────────────────────────

def migrate_text(old_text: str, new_text: str
                 ) -> tuple[str, list[str], list[str], list[str]]:
    """Produce the migrated NEW text plus three audit lists.

    Returns (migrated_text, migrated_keys, new_only_keys, dropped_keys).
    """
    old_map = parse(old_text)
    seen_in_new: set[str] = set()
    migrated: list[str] = []
    new_only: list[str] = []
    out_lines: list[str] = []
    current_array: str | None = None

    for line in new_text.splitlines():
        if current_array is not None:
            stripped = line.strip()
            if stripped.startswith('}'):
                current_array = None
                out_lines.append(line)
                continue
            m = ARRAY_KV_RE.match(line)
            if m:
                pre, k_raw, gap, v_raw, trail = m.groups()
                full_key = f'{current_array}({_normkey(k_raw)})'
                seen_in_new.add(full_key)
                if full_key in old_map and old_map[full_key] != v_raw:
                    out_lines.append(pre + k_raw + gap + old_map[full_key] + trail)
                    migrated.append(full_key)
                elif full_key in old_map:
                    out_lines.append(line)  # values already identical
                else:
                    out_lines.append(line)
                    new_only.append(full_key)
            else:
                out_lines.append(line)
            continue

        m = SET_RE.match(line)
        if m:
            pre, name, gap, v_raw, trail = m.groups()
            seen_in_new.add(name)
            if name in old_map and old_map[name] != v_raw:
                out_lines.append(pre + name + gap + old_map[name] + trail)
                migrated.append(name)
            elif name in old_map:
                out_lines.append(line)
            else:
                out_lines.append(line)
                new_only.append(name)
            continue

        m = ARRAY_OPEN_RE.match(line)
        if m:
            _, name, _, _ = m.groups()
            current_array = name
            out_lines.append(line)
            continue

        out_lines.append(line)

    # Preserve trailing newline behavior of the original new file.
    trailing_nl = '\n' if new_text.endswith('\n') else ''
    merged = '\n'.join(out_lines) + trailing_nl

    dropped = sorted(set(old_map.keys()) - seen_in_new)
    return merged, sorted(migrated), sorted(new_only), dropped


# ───────────────────────────────────────────────────────────────────────────
# CLI
# ───────────────────────────────────────────────────────────────────────────

def _print_report(old_path: Path, new_path: Path,
                  migrated: list[str], new_only: list[str], dropped: list[str],
                  wrote: bool) -> None:
    bar = '─' * 72
    print()
    print(bar)
    print(f"  cbflow migrate — report")
    print(bar)
    print(f"  Old:  {old_path}")
    print(f"  New:  {new_path}")
    print(bar)

    print(f"  Migrated  : {len(migrated):4d}  (old values carried into new)")
    print(f"  New-only  : {len(new_only):4d}  (NOT in old — review manually)")
    print(f"  Dropped   : {len(dropped):4d}  (in old, gone from new)")
    print(bar)

    if migrated:
        print("\n  Migrated keys:")
        for k in migrated:
            print(f"    • {k}")

    if new_only:
        print("\n  NEW keys — please review and set manually:")
        for k in new_only:
            print(f"    ! {k}")

    if dropped:
        print("\n  Dropped keys — value lost (removed or renamed in new):")
        for k in dropped:
            print(f"    × {k}")

    print()
    if wrote:
        print(f"  Wrote: {new_path}")
        print(f"  Backup: {new_path}.bak")
    else:
        print(f"  --dry-run: no files modified.")
    print()


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(
        prog='cbflow migrate',
        description='Carry user values from an OLD config file into a NEW one.',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""\
Example:
  cbflow migrate \\
    --old /opt/cbflow_v1/PD/config/tech/gf_22nm/v1.0.0/tech_config.tcl \\
    --new /opt/cbflow_v2/PD/config/tech/gf_22nm/v1.0.0/tech_config.tcl

The NEW file is updated in place with a <new>.bak backup. Use --dry-run
to preview the report without touching disk.
""")
    p.add_argument('--old', required=True, type=Path,
                   help='User\'s existing config file (source of values).')
    p.add_argument('--new', required=True, type=Path,
                   help='New flow\'s corresponding config file (target).')
    p.add_argument('--dry-run', action='store_true',
                   help='Show the report; do not modify any file.')
    args = p.parse_args(argv)

    if not args.old.is_file():
        print(f"ERROR: --old not found or not a file: {args.old}", file=sys.stderr)
        return 2
    if not args.new.is_file():
        print(f"ERROR: --new not found or not a file: {args.new}", file=sys.stderr)
        return 2

    old_text = args.old.read_text()
    new_text = args.new.read_text()
    merged, migrated, new_only, dropped = migrate_text(old_text, new_text)

    wrote = False
    if not args.dry_run:
        backup = args.new.with_suffix(args.new.suffix + '.bak')
        shutil.copy2(args.new, backup)
        args.new.write_text(merged)
        wrote = True

    _print_report(args.old, args.new, migrated, new_only, dropped, wrote)
    return 0


if __name__ == '__main__':
    sys.exit(main())
