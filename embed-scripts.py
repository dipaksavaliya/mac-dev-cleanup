#!/usr/bin/env python3
"""Regenerate the '## Scripts' section of SKILL.md from scripts/, so the single file stays shareable."""
import pathlib
root = pathlib.Path(__file__).parent
skill = root / "SKILL.md"
lang = {".sh": "zsh", ".py": "python"}
order = ["disk-batch.sh", "ios-clean.sh", "process-triage.sh", "worktree-audit.sh", "reap-codex-helpers.py"]
blocks = "".join(f"### scripts/{n}\n\n```{lang[pathlib.Path(n).suffix]}\n{(root / 'scripts' / n).read_text()}```\n\n" for n in order)
t = skill.read_text()
head, rest = t.split("## Scripts\n", 1)
start = rest.index("### scripts/")
end = rest.index("\n---\n", start) + 1  # the section ends at the next horizontal rule
skill.write_text(head + "## Scripts\n" + rest[:start] + blocks + rest[end:])
print("SKILL.md scripts section regenerated:", ", ".join(order))
