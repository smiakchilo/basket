---
description: Best practices for invoking Maven/Gradle builds in Windows Terminal to avoid quoting issues, output flooding, and timeouts.
applyTo: **
---

# Windows Terminal Compatibility

Agents on Windows use PowerShell by default. PowerShell parses arguments with `-D` flags (Maven, Gradle, Java CLI) differently from `cmd.exe`, causing quoting failures, garbled properties, and silent misconfigurations. The rules below prevent those issues and apply to **every** terminal command that invokes Maven, Gradle, or any JVM-based tool with `-D` system properties.

## Command Construction

1. **Always wrap Maven/Gradle in `cmd /c "..."`** — both for `execution_subagent`, `runSubagent`, and `run_in_terminal`. This spawns a `cmd.exe` subprocess that handles `-D` flags natively.
2. **Never quote `-D` values** unless the value contains spaces or shell metacharacters. Write `-Dtest=MyClassTest`, not `-Dtest="MyClassTest"` or `-Dtest='MyClassTest'`.
3. **Never use PowerShell backtick escapes** (`` ` ``) in Maven/Gradle commands — they are PowerShell-specific and break inside `cmd /c`.
4. **Use `&&` to chain commands** inside a `cmd /c "..."` block. Use `;` only in bare PowerShell context.
5. **Append `2>&1`** inside the `cmd /c` block to merge stderr into stdout. This ensures error messages and build warnings appear in the captured output.
6. **Always include `-B -ntp`** in Maven commands. `-B` (batch mode) suppresses interactive prompts. `-ntp` (no transfer progress) eliminates download percentage spam. These flags dramatically reduce output volume without hiding errors or test results.

## Maven Output Optimization

Build output floods the context window and is the primary driver of mid-execution terminations in long-running skills. Follow these rules:

1. **Extract only actionable output** from Maven builds: compilation errors (`[ERROR]` lines), test failures with stack traces, and the `BUILD SUCCESS` / `BUILD FAILURE` status line.
2. **Discard** dependency download logs, plugin execution banners, progress indicators, and informational `[INFO]` lines that do not indicate errors.
3. When using `execution_subagent` or `runSubagent`, include output-filtering instructions in the query so the subagent returns only the relevant excerpt.
4. When using `run_in_terminal` directly, mentally filter the output before incorporating it into your reasoning — do not quote entire build logs in your responses or reasoning.

## Timeout Guidance

- **Default**: `timeout=300000` (5 minutes) for most Maven/Gradle commands.
- **AEM projects with JaCoCo**: `timeout=600000` (10 minutes). AEM `core` module builds with JaCoCo instrumentation, test execution, and report generation routinely take 5–8 minutes.
- If a sync command times out and the terminal is still running, call `get_terminal_output` immediately and repeatedly until `BUILD SUCCESS` or `BUILD FAILURE` appears. Do not yield control.

## Shell Discipline

1. **Never open a second terminal** to re-run a build. Reuse the existing terminal session.
2. **Never switch shells mid-build.** If a command started in PowerShell (via `run_in_terminal`), continue using the same session for `get_terminal_output`.
3. If `get_terminal_output` returns empty or truncated output, call it again — do not switch shells, do not re-launch the build.

## Output Retrieval

1. After every `run_in_terminal` build invocation, call `get_terminal_output` **at least once** even if `run_in_terminal` already returned output. Terminal output may arrive in chunks.
2. When scanning output for `BUILD SUCCESS` or `BUILD FAILURE`, search the **entire** returned string, not just the last few lines — Windows terminal output can interleave progress lines with the final status.
3. If the output exceeds the tool's size limit, look for the build status token near the end. Do not re-run the build just because output was truncated.
