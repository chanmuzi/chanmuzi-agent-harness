#!/usr/bin/env python3
"""Render synchronized root CLAUDE.md and AGENTS.md from shared project-doc content."""

from pathlib import Path
import sys


REPO_DIR = Path(__file__).resolve().parents[1]
SOURCE = REPO_DIR / "shared" / "project-doc.md"

HEADER = {
    "CLAUDE.md": "# CLAUDE.md (project-level)\n\n",
    "AGENTS.md": "# AGENTS.md\n\n",
}

NOTICE = (
    "<!-- Generated from shared/project-doc.md via shared/render_project_docs.py. -->\n\n"
)


def render(target_name: str, body: str) -> str:
    return HEADER[target_name] + NOTICE + body


def main() -> int:
    check_only = "--check" in sys.argv[1:]
    body = SOURCE.read_text()
    failed = False

    for target_name in ("CLAUDE.md", "AGENTS.md"):
      target = REPO_DIR / target_name
      rendered = render(target_name, body)
      if check_only:
          if not target.exists() or target.read_text() != rendered:
              print(f"out_of_sync:{target_name}")
              failed = True
      else:
          target.write_text(rendered)
          print(f"rendered:{target_name}")

    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
