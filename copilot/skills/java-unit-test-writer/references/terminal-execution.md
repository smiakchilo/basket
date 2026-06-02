# Terminal Execution Rules

These rules apply to **every** Maven build launched during the java-unit-test-writer skill. Violations (yielding control, waiting passively, asking the user to continue) are **skill failures**.

## Primary Method — `execution_subagent`

Use `execution_subagent` for all Maven invocations. This tool runs the command, waits for it to finish internally, and returns the relevant output — all without yielding control.

If `execution_subagent` is not available, use `runSubagent` instead. It launches an autonomous subagent that manages its own terminal session and timeout. Include filtering instructions so the subagent returns only actionable output.

Example (no JDK override):

```
execution_subagent(
  query: "Run: cmd /c \"mvn test jacoco:report -pl core -Dtest=MyClassTest -DfailIfNoTests=false -B -ntp 2>&1\"\nReturn ONLY: (1) any compilation errors, (2) test failures with stack traces, (3) the BUILD SUCCESS or BUILD FAILURE line. Discard all other output.",
  description: "Running tests and generating JaCoCo report"
)
```

Example (with JDK override):

```
execution_subagent(
  query: "Run: cmd /c \"set JAVA_HOME=C:\Program Files\Java\jdk-11.0.20&& mvn test jacoco:report -pl core -Dtest=MyClassTest -DfailIfNoTests=false -B -ntp 2>&1\"\nReturn ONLY: (1) any compilation errors, (2) test failures with stack traces, (3) the BUILD SUCCESS or BUILD FAILURE line. Discard all other output.",
  description: "Running tests and generating JaCoCo report"
)
```

## Fallback — `run_in_terminal` (sync only)

If neither `execution_subagent` nor `runSubagent` is available, use `run_in_terminal` with **`mode=sync`** and **`timeout=600000`** (10 minutes). Do **not** use `mode=async`.

The Maven command **must** be wrapped in `cmd /c "..."` to run inside a `cmd.exe` subprocess. This avoids PowerShell argument-parsing issues with `-D` flags:

When no JDK override is needed:

```
cmd /c "mvn test jacoco:report -pl core -Dtest=MyClassTest -DfailIfNoTests=false -B -ntp 2>&1"
```

When `JAVA_SDK_PATH` is set and differs from the system default (see [JDK Override](#jdk-override)):

```
cmd /c "set JAVA_HOME=C:\Program Files\Java\jdk-11.0.20&& mvn test jacoco:report -pl core -Dtest=MyClassTest -DfailIfNoTests=false -B -ntp 2>&1"
```

If the sync command times out and the terminal is still running, **immediately** call `get_terminal_output` in a loop — on every single turn — until the output contains `BUILD SUCCESS` or `BUILD FAILURE`. Do not stop between polls. Do not emit any message to the user between polls. Do not wait for a "terminal completion notification".

## Maven Output Rules

All Maven commands **must** include `-B` (batch mode) and `-ntp` (no transfer progress) flags. These suppress download progress bars and interactive prompts without hiding errors or test output.

After receiving build output, **extract only**:
1. Compilation errors (lines starting with `[ERROR]`)
2. Test failures with stack traces
3. The `BUILD SUCCESS` or `BUILD FAILURE` status line

Discard everything else (dependency downloads, plugin banners, progress indicators) before further processing. This is critical for keeping context consumption low during iterative coverage loops.

## Banned Behaviors

The following are **unconditionally banned** during this skill. If you catch yourself about to do any of these, stop and re-read this section:

- Printing any variation of: "I'll wait for it to complete", "Still compiling", "I'll wait for the terminal completion notification", "The build is running", "Waiting for the build", or any similar passive-waiting message.
- Yielding control to the user while a build is in progress.
- Asking the user to type "Continue", "Proceed", or anything else to resume.
- Using `run_in_terminal` with `mode=async` for Maven commands.
- Deciding to "wait for a notification" instead of actively calling `get_terminal_output`.

If the build finishes, proceed to the next step immediately. If it failed, diagnose and fix — do not ask the user what to do.

## Windows Terminal Compatibility

Follow all rules in [windows-terminal.instructions.md](../../../instructions/windows-terminal.instructions.md). Every Maven command in this skill — whether via `execution_subagent`, `runSubagent`, or `run_in_terminal` — must comply with that file's Command Construction, Shell Discipline, and Output Retrieval sections.

## JDK Override

The JDK resolution blocking step computes and persists `JAVA_HOME_OVERRIDE_REQUIRED` (YES or NO) in session memory. Read this flag — do not re-derive it by comparing paths.

- **When `JAVA_HOME_OVERRIDE_REQUIRED` is `YES`** — prepend `set JAVA_HOME=<JAVA_SDK_PATH>&&` inside the `cmd /c "..."` block. This is the expected case whenever the project uses a different Java version than the system default (e.g., project requires Java 8 but system `JAVA_HOME` points to Java 21).

  ```
  cmd /c "set JAVA_HOME=C:\Program Files\Java\jdk1.8.0_391&& mvn test jacoco:report -pl core -Dtest=MyClassTest -DfailIfNoTests=false -B -ntp 2>&1"
  ```

  **Critical**: no space before `&&`. A trailing space would become part of the value and break path resolution.

- **When `JAVA_HOME_OVERRIDE_REQUIRED` is `NO`** — the system default JDK already matches the project's required version. Use Maven commands as-is.

This rule applies to **every** Maven command in this skill — whether via `execution_subagent`, `runSubagent`, or `run_in_terminal`.
