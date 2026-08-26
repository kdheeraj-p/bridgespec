#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Check that repository-relative Markdown links resolve to files."""

from __future__ import annotations

import re
import sys
from pathlib import Path
from urllib.parse import unquote


LINK = re.compile(r"(?<!!)\[[^\]]+\]\(([^)]+)\)")


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    failures: list[str] = []
    for markdown in root.rglob("*.md"):
        if ".git" in markdown.parts:
            continue
        text = markdown.read_text(encoding="utf-8")
        for match in LINK.finditer(text):
            raw = match.group(1).strip().split(maxsplit=1)[0].strip("<>")
            if raw.startswith(("http://", "https://", "mailto:", "#")):
                continue
            target = unquote(raw.split("#", 1)[0])
            if target and not (markdown.parent / target).resolve().exists():
                line = text.count("\n", 0, match.start()) + 1
                failures.append(f"{markdown.relative_to(root)}:{line}: {raw}")
    if failures:
        print("broken relative links:", file=sys.stderr)
        print("\n".join(failures), file=sys.stderr)
        return 2
    print("MARKDOWN LINKS VERIFIED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
