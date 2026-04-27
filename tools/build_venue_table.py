#!/usr/bin/env python3
"""
Venue abbreviation table management script.

Maintains Sources/PapyrusCore/Resources/venue_abbreviations.json
by merging data from external sources (CCF, CORE, DBLP) and manual entries.

Usage:
  python3 tools/build_venue_table.py status
  python3 tools/build_venue_table.py import-ccf [--dry-run]
  python3 tools/build_venue_table.py add "pattern" "ABBR" [--force]
"""

import argparse
import json
import re
import urllib.request
from pathlib import Path

CCF_URL = (
    "https://gist.githubusercontent.com/CrackedPoly/"
    "23650f5d0ab74be9dce83e7e4c0d36c4/raw"
)


def get_json_path() -> Path:
    return (
        Path(__file__).parent.parent
        / "Sources"
        / "PapyrusCore"
        / "Resources"
        / "venue_abbreviations.json"
    )


def load_table() -> list:
    with open(get_json_path(), "r", encoding="utf-8") as f:
        return json.load(f)


def save_table(table: list):
    """Sort by pattern length (longest first) then alphabetically, then save."""
    table = sorted(table, key=lambda x: (-len(x[0]), x[0]))
    with open(get_json_path(), "w", encoding="utf-8") as f:
        json.dump(table, f, ensure_ascii=False, indent=2)
    print(f"Saved {len(table)} entries to {get_json_path()}")


def normalize(name: str) -> str:
    """
    Mirror VenueFormatter.normalize() logic in Swift.
    - lowercase
    - strip prefixes: 'proceedings of the', 'proceedings of', 'in '
    - remove ordinals (1st, 2nd, 3rd, ...)
    - remove trailing year numbers (e.g. ' 2023')
    - remove common prepositions/articles: 'the ', ' of', ' on', ' and'
    - collapse multiple spaces
    """
    name = name.lower()

    for prefix in ["proceedings of the", "proceedings of", "in "]:
        if name.startswith(prefix):
            name = name[len(prefix) :]
            break

    name = name.strip()
    name = re.sub(r"\b\d+(st|nd|rd|th)\b", "", name)
    name = re.sub(r"\s+\d{4}\s*$", "", name)

    for word in ["the ", " of", " on", " and"]:
        name = name.replace(word, "")

    return re.sub(r"\s+", " ", name).strip()


def fetch_ccf_conferences() -> list:
    """Fetch CCF 2022 recommended list and extract conference (pattern, abbr) pairs."""
    print(f"Fetching CCF data from {CCF_URL} ...")
    req = urllib.request.Request(
        CCF_URL,
        headers={"User-Agent": "Mozilla/5.0 (Papyrus venue table builder)"},
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        data = json.loads(resp.read().decode("utf-8"))

    entries = []
    for item in data.get("list", []):
        if item.get("type") != "Conference":
            continue

        abbr = item.get("abbr", "").strip()
        name = item.get("name", "").strip()
        if not abbr or not name:
            continue

        # Remove parenthetical abbreviation from end of name, e.g.
        # "ACM SIGPLAN Symposium on Principles & Practice of Parallel Programming (PPoPP)"
        name = re.sub(r"\s*\([^)]+\)\s*$", "", name).strip()
        pattern = normalize(name)

        # Clean abbreviation: collapse whitespace, uppercase
        abbr = re.sub(r"\s+", "", abbr).upper()

        if pattern and abbr and len(pattern) > 2:
            entries.append([pattern, abbr])

    print(f"Extracted {len(entries)} conference entries from CCF")
    return entries


def cmd_status(_args):
    table = load_table()
    print(f"Total entries: {len(table)}")

    by_abbr_len = {}
    for pattern, abbr in table:
        by_abbr_len.setdefault(len(abbr), 0)
        by_abbr_len[len(abbr)] += 1

    print("Abbreviation length distribution:")
    for length in sorted(by_abbr_len):
        print(f"  {length:2d} chars: {by_abbr_len[length]:4d} entries")

    longest_pattern = max(table, key=lambda x: len(x[0]))
    print(f"\nLongest pattern ({len(longest_pattern[0])} chars):")
    print(f"  {longest_pattern[0]}")


def cmd_import_ccf(args):
    existing = load_table()
    existing_map = {p: a for p, a in existing}

    ccf = fetch_ccf_conferences()

    added = []
    for pattern, abbr in ccf:
        if pattern not in existing_map:
            added.append([pattern, abbr])
            existing_map[pattern] = abbr
        elif existing_map[pattern] != abbr:
            # Conflict: same pattern, different abbr
            print(
                f"  CONFLICT: '{pattern}' -> existing '{existing_map[pattern]}' vs CCF '{abbr}'"
            )

    if not added:
        print("No new entries to add from CCF.")
        return

    print(f"\nWill add {len(added)} new entries (first 20 shown):")
    for pattern, abbr in added[:20]:
        print(f"  {pattern} -> {abbr}")
    if len(added) > 20:
        print(f"  ... and {len(added) - 20} more")

    if args.dry_run:
        print("\nDry run — no changes written.")
        return

    existing.extend(added)
    save_table(existing)
    print(f"\nAdded {len(added)} entries. Total now: {len(existing)}")


def cmd_add(args):
    table = load_table()
    pattern = normalize(args.pattern)
    abbr = args.abbr.upper()

    for i, (p, a) in enumerate(table):
        if p == pattern:
            print(f"Pattern already exists: '{p}' -> '{a}'")
            if args.force:
                table[i] = [pattern, abbr]
                save_table(table)
                print(f"Overwritten with: '{pattern}' -> '{abbr}'")
            return

    table.append([pattern, abbr])
    save_table(table)
    print(f"Added: '{pattern}' -> '{abbr}'")


def main():
    parser = argparse.ArgumentParser(
        description="Manage venue abbreviation table for Papyrus"
    )
    sub = parser.add_subparsers(dest="cmd", required=True)

    sub.add_parser("status", help="Show table statistics")

    p_import = sub.add_parser("import-ccf", help="Import from CCF 2022 conference list")
    p_import.add_argument("--dry-run", action="store_true", help="Preview changes without writing")

    p_add = sub.add_parser("add", help="Add a single (pattern, abbr) entry")
    p_add.add_argument("pattern", help="Full venue name (will be normalized)")
    p_add.add_argument("abbr", help="Abbreviation")
    p_add.add_argument("--force", action="store_true", help="Overwrite if pattern exists")

    args = parser.parse_args()

    if args.cmd == "status":
        cmd_status(args)
    elif args.cmd == "import-ccf":
        cmd_import_ccf(args)
    elif args.cmd == "add":
        cmd_add(args)


if __name__ == "__main__":
    main()
