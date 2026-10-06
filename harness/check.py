#!/usr/bin/env python3
"""Validate harness wiring, not Swift syntax or application behavior."""

import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ALWAYS_LOADED_CAP = 200
RULES = ("swift", "swiftui", "swiftdata", "testing")
SKILLS = ("implementation-flow", "harness-record", "harness-growth")
REVIEWERS = ("plan-reviewer", "swift-reviewer", "test-reviewer")


def markdown_files(root):
    files = [root / "AGENTS.md", root / "CLAUDE.md"]
    for directory in ("rules", "harness", ".claude"):
        files.extend((root / directory).rglob("*.md"))
    return files


def check(root):
    errors = []
    required = [root / "AGENTS.md", root / "CLAUDE.md"]
    required.extend(root / "rules" / f"{name}.md" for name in RULES)
    required.extend(root / ".claude/skills" / name / "SKILL.md" for name in SKILLS)
    required.extend(root / ".claude/agents" / f"{name}.md" for name in REVIEWERS)
    for path in required:
        if not path.is_file():
            errors.append(f"Missing: {path.relative_to(root)}")

    for path in markdown_files(root):
        if not path.is_file():
            continue

        source = path.read_text(encoding="utf-8")
        targets = re.findall(r"\[[^\]]*\]\(([^)]+)\)", source)
        targets.extend(re.findall(r"(?m)^@([^\s]+)$", source))
        for target in targets:
            if re.match(r"[a-zA-Z][a-zA-Z0-9+.-]*:", target):
                continue

            local_path = target.split("#", 1)[0]
            if local_path and not (path.parent / local_path).exists():
                errors.append(f"Broken reference in {path.relative_to(root)}: {target}")

        is_skill = path.name == "SKILL.md"
        is_reviewer = path.parent == root / ".claude/agents"
        if not is_skill and not is_reviewer:
            continue

        frontmatter = re.match(r"\A---\n(.*?)\n---\n", source, re.DOTALL)
        if frontmatter is None:
            errors.append(f"Missing frontmatter: {path.relative_to(root)}")
            continue

        expected_name = path.parent.name
        if is_reviewer:
            expected_name = path.stem

        metadata = frontmatter.group(1)
        if not re.search(rf"(?m)^name: {re.escape(expected_name)}$", metadata):
            errors.append(f"Invalid name: {path.relative_to(root)}")
        if not re.search(r"(?m)^description: \S.+$", metadata):
            errors.append(f"Missing description: {path.relative_to(root)}")

    loaded = [root / "AGENTS.md", *(root / "rules").glob("*.md")]
    line_count = sum(len(p.read_text(encoding="utf-8").splitlines()) for p in loaded if p.is_file())
    if line_count > ALWAYS_LOADED_CAP:
        errors.append(f"Always-loaded rules: {line_count} lines exceeds {ALWAYS_LOADED_CAP}")

    settings_path = root / ".claude/settings.json"
    try:
        settings = json.loads(settings_path.read_text(encoding="utf-8"))
        hooks = settings["hooks"]["PostToolUse"]
        if not hooks:
            errors.append("PostToolUse hook is empty")
        for group in hooks:
            if group["matcher"] != "Edit|Write":
                errors.append("Unexpected PostToolUse matcher")
            if not group["hooks"]:
                errors.append("PostToolUse commands are empty")
            for hook in group["hooks"]:
                command = hook["command"]
                match = re.fullmatch(r'bash "\$\{CLAUDE_PROJECT_DIR:-\.\}/([^"]+)"', command)
                if hook["type"] != "command" or match is None:
                    errors.append("Unsupported harness hook command")
                    continue

                if not (root / match.group(1)).is_file():
                    errors.append(f"Missing hook script: {match.group(1)}")
    except (OSError, ValueError, KeyError, TypeError) as error:
        errors.append(f"Invalid Claude settings: {error}")

    return errors


if __name__ == "__main__":
    failures = check(ROOT)
    for failure in failures:
        print(failure, file=sys.stderr)
    if failures:
        sys.exit(1)

    print("Agent harness: passed (configuration and references only)")
