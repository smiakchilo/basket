---
description: "Use when executing any skill workflow from the skills/ folder. Governs how to read, write, and consolidate persistent skill memos stored under /memories/skill-memos/."
applyTo: "**/skills/**/SKILL.md"
---

# Skill Learning — Persistent Memos

> **Applies to**: every skill execution from the `skills/` folder.

## Before Execution

Before starting any skill workflow, read the skill's memo file via the memory tool:

```
/memories/skill-memos/<skill-name>.md
```

If the file exists, internalize its contents — they capture previously encountered problems and verified solutions. Apply any relevant advice during the current execution.

If the file does not exist, proceed normally. It will be created when the first issue arises.

## After Resolving an Issue

Whenever an unexpected problem is encountered during skill execution **and successfully resolved** (e.g., a build failure, a wrong assumption about the codebase, a flaky tool invocation, an API misuse), append a concise memo entry to the skill's memo file:

```
### <Short title> — <YYYY-MM-DD>
**Problem**: <one sentence>
**Fix**: <one sentence>
```

Use the memory tool's `create` command if the file does not yet exist, or `insert` / `str_replace` to append to an existing file.

## Consolidation

After appending a new entry, check the file's total length. If it exceeds approximately 30 lines:

1. Remove entries that are obsolete (superseded by newer entries or no longer applicable).
2. Merge entries that describe the same root cause.
3. Keep every remaining entry to three lines or fewer.

The goal is a brief, scannable reference — not a journal.

## Constraints

- **No sensitive data.** Never store credentials, tokens, or full filesystem paths containing usernames.
- **Scope.** Only record issues encountered *during skill execution*, not general coding preferences (those belong in instruction files).
- **One file per skill.** Do not split a skill's memos across multiple files.
