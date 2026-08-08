#!/usr/bin/env python3
"""Generate platform-specific skill packages from the canonical SKILL.md."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


SKILL_DIR = Path(__file__).resolve().parents[1]
SOURCE = SKILL_DIR / "SKILL.md"
OPENAI_METADATA = SKILL_DIR / "agents" / "openai.yaml"
DIST = SKILL_DIR / "dist"
VERSION = "1.1.0"
PLATFORMS = ("claude-code", "codex", "omp", "opencode", "kimi-code")


def parse_source(text: str) -> tuple[str, str, str]:
    if not text.startswith("---\n"):
        raise ValueError("SKILL.md must start with YAML frontmatter")
    try:
        frontmatter, body = text[4:].split("\n---\n", 1)
    except ValueError as exc:
        raise ValueError("SKILL.md frontmatter is not closed") from exc

    lines = frontmatter.splitlines()
    if not lines or lines[0] != "name: webbridge-form-filling":
        raise ValueError("canonical skill name must be webbridge-form-filling")
    if len(lines) < 3 or lines[1] != "description: |":
        raise ValueError("canonical description must use a YAML block")
    if any(line and not line.startswith("  ") for line in lines[2:]):
        raise ValueError("canonical frontmatter may only contain name and description")

    description = " ".join(line.strip() for line in lines[2:]).strip()
    if not description:
        raise ValueError("canonical description must not be empty")
    return "webbridge-form-filling", description, body


def block_description(description: str) -> str:
    return f"description: |\n  {description}"


def render(platform: str, name: str, description: str, body: str) -> str:
    quoted = json.dumps(description, ensure_ascii=False)
    headers = {
        "claude-code": f"name: {name}\ndescription: {quoted}\nversion: {VERSION}",
        "codex": f"name: {name}\n{block_description(description)}",
        "omp": f"name: {name}\n{block_description(description)}",
        "opencode": f"name: {name}\ndescription: {quoted}",
        "kimi-code": (
            f"name: {name}\n{block_description(description)}\n"
            f'metadata:\n  version: "{VERSION}"'
        ),
    }
    return f"---\n{headers[platform]}\n---\n{body}"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--check",
        action="store_true",
        help="fail if committed distributions differ from generated output",
    )
    args = parser.parse_args()

    try:
        name, description, body = parse_source(SOURCE.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    stale: list[str] = []
    for platform in PLATFORMS:
        target = DIST / platform / "SKILL.md"
        expected = render(platform, name, description, body)
        if args.check:
            if not target.exists() or target.read_text(encoding="utf-8") != expected:
                stale.append(str(target.relative_to(SKILL_DIR.parent)))
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(expected, encoding="utf-8")
        print(f"generated {target.relative_to(SKILL_DIR.parent)}")

    codex_metadata = DIST / "codex" / "agents" / "openai.yaml"
    try:
        expected_metadata = OPENAI_METADATA.read_text(encoding="utf-8")
    except OSError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    if args.check:
        if (
            not codex_metadata.exists()
            or codex_metadata.read_text(encoding="utf-8") != expected_metadata
        ):
            stale.append(str(codex_metadata.relative_to(SKILL_DIR.parent)))
    else:
        codex_metadata.parent.mkdir(parents=True, exist_ok=True)
        codex_metadata.write_text(expected_metadata, encoding="utf-8")
        print(f"generated {codex_metadata.relative_to(SKILL_DIR.parent)}")

    if stale:
        print("out-of-date generated files:", file=sys.stderr)
        for path in stale:
            print(f"  {path}", file=sys.stderr)
        print("run: python3 webbridge-form-filling/scripts/sync_dist.py", file=sys.stderr)
        return 1
    if args.check:
        print(
            f"ok: canonical skill, Codex UI metadata, and "
            f"{len(PLATFORMS)} distributions are in sync"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
