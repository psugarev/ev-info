#!/usr/bin/env python3
"""Localisation integrity check.

Fails when the app could show English (or a missing label) in Bulgarian:

1. every catalog entry has an English and a Bulgarian value;
2. no entry is still marked `extractionState: stale`;
3. every key passed to `AppLocalization.string/format` exists in the catalog;
4. every literal key used by common SwiftUI text initialisers
   (`Text("…")`, `Button("…")`, `Section("…")`, …) exists in the catalog,
   including keys built with Swift string interpolation (`Text("\\(count) trips")`
   is checked as `%lld trips`).

Run locally before a PR:  python3 scripts/check-localization.py
The same script runs in CI (`.github/workflows/ci.yml`).
"""

from __future__ import annotations

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CATALOG = ROOT / "Resources" / "Localizable.xcstrings"
SOURCES = ROOT / "Sources"

CALL_STARTS = re.compile(
    r"(?:AppLocalization\.(?:string|format)|LocalizedStringKey|\b(?:Text|Button|Section|Picker|"
    r"Toggle|Label|LabeledContent|navigationTitle|confirmationDialog|ContentUnavailableView|"
    r"CardLabel\(text:))\s*\(\s*"
)

# Keys that are intentionally identical in both languages (units, symbols).
ALLOWED_UNTRANSLATED = {
    "", "%", "%lld", "%lld/%lld", "%lld percent", "0", "Δ", "kW", "—", "235/55 R19",
    "255/45 R20", "10–30 mV", "> 30 mV", "≤ 10 mV", "Български", "V", "A",
}


def literal_at(text: str, quote: int) -> tuple[str, int] | None:
    """Read a Swift string literal starting at `quote` (a `"`).

    Handles escapes and `\\(…)` interpolation, including string literals
    nested inside the interpolation. Returns (raw content, index after quote).
    """
    if text[quote] != '"':
        return None
    i = quote + 1
    content: list[str] = []
    while i < len(text):
        ch = text[i]
        if ch == "\\":
            nxt = text[i + 1] if i + 1 < len(text) else ""
            if nxt == "(":
                # Skip the balanced interpolation, keeping the source text.
                depth = 1
                content.append("\\(")
                i += 2
                while i < len(text) and depth > 0:
                    c = text[i]
                    if c == "(":
                        depth += 1
                    elif c == ")":
                        depth -= 1
                    content.append(c)
                    i += 1
                continue
            content.append(ch)
            content.append(nxt)
            i += 2
            continue
        if ch == '"':
            return "".join(content), i + 1
        content.append(ch)
        i += 1
    return None


def interpolation_pattern(raw: str) -> re.Pattern[str] | None:
    """Catalog-key regex for a Swift literal, or None when it has no interpolation."""
    if "\\(" not in raw:
        return None
    pieces: list[str] = []
    literal: list[str] = []
    i = 0
    while i < len(raw):
        if raw[i] == "\\" and i + 1 < len(raw) and raw[i + 1] == "(":
            if literal:
                pieces.append(re.escape("".join(literal)))
                literal = []
            depth = 1
            i += 2
            while i < len(raw) and depth > 0:
                if raw[i] == "(":
                    depth += 1
                elif raw[i] == ")":
                    depth -= 1
                i += 1
            pieces.append(r"%(?:@|lld|d|u|lf|\.\d+f)")
            continue
        literal.append(raw[i])
        i += 1
    if literal:
        pieces.append(re.escape("".join(literal)))
    return re.compile("".join(pieces) + r"\Z")


def unescape(raw: str) -> str:
    try:
        return json.loads(f'"{raw}"')
    except json.JSONDecodeError:
        return raw.replace('\\"', '"').replace("\\\\", "\\")


def catalog_has_translation(entry: dict | None) -> bool:
    if not entry:
        return False
    return bool(entry.get("localizations", {}).get("bg", {}).get("stringUnit", {}).get("value"))


def main() -> None:
    if not CATALOG.exists():
        print(f"catalog not found: {CATALOG}")
        sys.exit(1)

    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))["strings"]
    problems: list[str] = []

    for key, entry in catalog.items():
        if key in ALLOWED_UNTRANSLATED:
            continue
        if entry.get("extractionState") == "stale":
            problems.append(f"stale key: {key!r}")
            continue
        if not entry.get("localizations"):
            problems.append(f"no translations: {key!r}")
            continue
        for lang in ("en", "bg"):
            value = entry["localizations"].get(lang, {}).get("stringUnit", {}).get("value")
            if not value:
                problems.append(f"missing {lang}: {key!r}")

    used: set[str] = set()
    for path in SOURCES.rglob("*.swift"):
        text = path.read_text(encoding="utf-8")
        for m in CALL_STARTS.finditer(text):
            start = m.end()
            if start >= len(text) or text[start] != '"':
                continue
            literal = literal_at(text, start)
            if literal is None:
                continue
            raw, _ = literal
            key = unescape(raw) if "\\(" not in raw else raw
            if not re.search(r"[A-Za-zА-Яа-я0-9]{2,}", key):
                continue
            used.add(key)

    for key in sorted(used):
        if key in ALLOWED_UNTRANSLATED:
            continue
        pattern = interpolation_pattern(key)
        if pattern is not None:
            matches = [k for k in catalog if pattern.match(k)]
            if not matches:
                problems.append(f"interpolated key not in catalog: {key!r}")
            elif not any(catalog_has_translation(catalog[k]) for k in matches):
                problems.append(f"interpolated key not translated: {key!r}")
            continue
        entry = catalog.get(key)
        if entry is None:
            problems.append(f"used but missing from catalog: {key!r}")
        elif not catalog_has_translation(entry):
            problems.append(f"used but not translated: {key!r}")

    if problems:
        print("Localisation check failed:")
        for problem in problems:
            print(f"  ✗ {problem}")
        print(f"\n{len(problems)} problem(s)")
        sys.exit(1)

    print(f"Localisation OK: {len(catalog)} catalog keys, {len(used)} referenced, "
          f"no stale entries, every referenced key translated.")


if __name__ == "__main__":
    main()
