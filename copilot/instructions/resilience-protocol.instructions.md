---
description: "Use when executing any multi-step skill or agent workflow. Provides progress checkpointing, resume-on-continue, periodic status emission, and context budget management to prevent mid-execution terminations."
applyTo: "**/skills/**/SKILL.md"
---

# Resilience Protocol

> **Applies to**: every skill and agent execution that spans more than a handful of steps.

## Progress Checkpointing

After completing each **major step** of a skill (e.g. Step 1, Step 2, …), save a progress checkpoint to session memory:

```
/memories/session/skill-progress.md
```

The checkpoint must contain:

- **Skill name** and the user's original request (one line).
- **Last completed step** number and name.
- **Key findings so far** — a bullet list of facts needed to continue (e.g. class structure, branch count, coverage numbers, files created/modified).
- **Next step** to execute.

Use the memory tool's `create` (first checkpoint) or `str_replace` (subsequent updates) command. Keep the file under 40 lines — replace previous content rather than appending.

### When to Checkpoint

Checkpoint after every step that produces durable output: reading/analyzing a file, writing or editing code, running a build, measuring coverage, completing a review pass. Do **not** checkpoint after trivial actions like reading instructions.

## Resume-on-Continue

At the **very beginning** of every skill execution (Step 0 or equivalent):

1. Read `/memories/session/skill-progress.md` via the memory tool.
2. If the file exists **and** its skill name + request match the current invocation:
   - Present a one-line summary of the saved progress to the user.
   - Ask via `vscode_askQuestions`: **Resume from Step N** (recommended) or **Restart from scratch**.
   - If the user chooses to resume, skip to the saved next step — do not re-read files, re-run builds, or re-analyze code that was already processed.
3. If the file does not exist or does not match, proceed normally.

### Cleanup

When a skill completes successfully (final checklist / report delivered), **delete** `/memories/session/skill-progress.md` so the next invocation starts fresh.

## Periodic Status Emission

After each major step, emit a **brief status message** to the user — one or two sentences summarizing what was accomplished and what comes next. Examples:

- _"Step 3 complete — 14 branches identified, 6 already covered by existing tests. Moving to Step 4: writing new test methods."_
- _"Coverage iteration 2 — LINE 82%, BRANCH 75%. Adding tests for the null-input branches."_
- _"Code review gate passed — no critical issues found. Proceeding to test writing."_

This serves two purposes:
1. **Keeps the session alive** — idle-detection timers reset on every message.
2. **Gives the user visibility** into progress so they know the agent is working, not stuck.

## Context Budget Awareness

Long-running skills risk exhausting the context window. Follow these rules to minimize context consumption:

### Summarize, Don't Hoard

After reading a file for analysis (not for editing), capture the key findings in your reasoning and in the checkpoint — do **not** hold the raw file content in working memory. If you need to edit the file later, re-read only the relevant section at that point.

### Minimize Build Output

When processing Maven, Gradle, or other build tool output:

1. Extract **only** the actionable information: compilation errors, test failures with stack traces, BUILD SUCCESS/FAILURE status, and coverage counters.
2. Discard download progress, dependency resolution logs, plugin execution banners, and informational messages.
3. When using `execution_subagent` or `runSubagent`, include filtering instructions in the query so the subagent returns only the relevant excerpt.

### Sequential, Not Parallel

When processing multiple files or classes, complete one fully (including its checkpoint) before starting the next. Do not hold intermediate state for multiple items simultaneously.

### Avoid Re-Reading Instructions

Instruction files and skill definitions are loaded once at the beginning. Do not re-read them during iteration loops. If you need to verify a specific rule, recall it from your initial reading or re-read only the specific section (by line range), not the entire file.
