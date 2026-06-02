---
name: log-analyzer
description: "Use when: analyzing log files, parsing logs, searching logs, tracing errors, diagnosing outages, collecting usage stats, filtering by log level, extracting stack traces, building event timelines, correlating threads across files, frequency analysis of errors or HTTP status codes. Handles AEM error logs, Apache HTTPD access logs, and Dispatcher logs. Designed for HUGE files (50MB+) that cannot be opened with read_file. All scripts use streaming (StreamReader / Select-String) and accept -MaxResults to stay within context budget. Uses two-tier model routing: worker model for data collection, expert model for deep analysis."
argument-hint: "Describe the analysis: what log file(s), what you're looking for, and any time window or filters."
---

# Log Analyzer

Analyze huge Logback / AEM / Apache log files using streaming PowerShell scripts. All scripts process files line-by-line without loading them into memory, and cap output via `-MaxResults` to stay within context budget.

## Supported Formats (auto-detected)

| Format ID      | Source                | Entry pattern                                           | Multiline |
|----------------|-----------------------|---------------------------------------------------------|-----------|
| `aem-error`    | AEM `aemerror.log`    | `DD.MM.YYYY HH:mm:ss.SSS [pod] *LEVEL* [thread] logger msg` | Yes (stack traces) |
| `httpd-access` | Apache HTTPD access   | `pod IP - DD/Mon/YYYY:HH:mm:ss +0000 "REQ" status size "ref" "ua"` | No |
| `dispatcher`   | AEM Dispatcher        | `[DD/Mon/YYYY:HH:mm:ss +0000] [S] [pod] "REQ" status Nms [farm] [action] host` | No |

Format reference: [formats.md](./references/formats.md)

## Quick Start

Every script lives in `./scripts/` and accepts `-Path` (mandatory) and `-MaxResults` (default varies by script). Format is auto-detected unless overridden with `-Format`.

```powershell
# Resolve the skill scripts directory
$logSkill = "$HOME\.copilot\skills\log-analyzer\scripts"
$logFile  = "path\to\aemerror.log"
```

## Configuration

**BLOCKING — do this before any script execution.**

Read the shared model config to get model names for the two-tier workflow:

```
read_file: ../../model-config.md
```

Extract the `worker` and `expert` model names from the **Roles** table. These are used in the [Two-Phase Workflow](#two-phase-workflow) below.

## Capabilities

### 1. Format Detection

Detect the format of a log file by sampling the first 20 lines.

```powershell
& "$logSkill\detect-format.ps1" -Path $logFile
```

**Output:** `PSCustomObject` with `Format`, `EntryStartPattern`, `FullPattern`, `Multiline`, `Confidence`, `SampleParsed`.

**Always run this first** when you're unsure of the format.

---

### 2. Context Search

Search for a pattern with surrounding context. For AEM logs, automatically merges multiline stack traces into the matching entry.

```powershell
& "$logSkill\search-context.ps1" -Path $logFile -Pattern "NullPointerException" -ContextBefore 3 -ContextAfter 10 -MaxResults 20
```

| Parameter       | Default | Description |
|-----------------|---------|-------------|
| `-Pattern`      | —       | Regex to search for |
| `-ContextBefore`| 3       | Context entries before match |
| `-ContextAfter` | 5       | Context lines after match |
| `-MaxResults`   | 50      | Cap on output entries |
| `-CaseSensitive`| off     | Enable case-sensitive matching |
| `-MergeMultiline`| auto   | Force multiline merging on/off |

**Use when:** searching for a specific error, class name, exception, or keyword.

---

### 3. Log Level Filtering

Filter AEM error log entries by level. Outputs complete entries including stack traces.

```powershell
& "$logSkill\filter-level.ps1" -Path $logFile -Level ERROR,WARN -MaxResults 30
```

| Parameter       | Default | Description |
|-----------------|---------|-------------|
| `-Level`        | —       | One or more: ERROR, WARN, INFO, DEBUG, TRACE |
| `-ExcludeLevel` | none    | Levels to exclude |
| `-MaxResults`   | 50      | Cap on output |
| `-NoStackTrace` | off     | Show only entry header line, skip continuation |

**Use when:** filtering noise — e.g., show only ERRORs and WARNs.

---

### 4. Error Extraction

Extract ERROR-level entries with full stack traces. Specialized version of filter-level with extra capabilities: exception class detection, summary mode, tail mode.

```powershell
# First 10 errors
& "$logSkill\extract-errors.ps1" -Path $logFile -MaxResults 10

# Last 5 errors (tail mode — reads whole file, keeps last N)
& "$logSkill\extract-errors.ps1" -Path $logFile -MaxResults 5 -Tail

# Summary: count errors by exception class
& "$logSkill\extract-errors.ps1" -Path $logFile -Summary -MaxResults 20

# Filter by logger
& "$logSkill\extract-errors.ps1" -Path $logFile -LoggerPattern "com\.adobe\.granite" -MaxResults 10
```

| Parameter         | Default | Description |
|-------------------|---------|-------------|
| `-MessagePattern` | none    | Regex filter on message text (checked against all lines) |
| `-LoggerPattern`  | none    | Regex filter on logger class name |
| `-MaxResults`     | 30      | Max entries / summary rows |
| `-Tail`           | off     | Return last N errors instead of first N |
| `-Summary`        | off     | Output frequency table of exception classes |
| `-IncludeSuppressed` | off  | Include `Suppressed:` sections in stack traces |

**Use when:** investigating errors, building root-cause analysis, triaging outage.

---

### 5. Timeline

Extract entries within a time window. Supports all three formats.

```powershell
# AEM error log — use DD.MM.YYYY format
& "$logSkill\timeline.ps1" -Path $logFile -Start "23.04.2026 13:00:00" -End "23.04.2026 14:00:00" -MaxResults 50

# HTTPD access log
& "$logSkill\timeline.ps1" -Path $accessLog -Start "26/Nov/2025:23:00:00 +0000" -End "26/Nov/2025:23:59:59 +0000"

# With level filter (AEM only)
& "$logSkill\timeline.ps1" -Path $logFile -Start "23.04.2026 13:00:00" -End "23.04.2026 14:00:00" -LevelFilter ERROR,WARN
```

| Parameter      | Default | Description |
|----------------|---------|-------------|
| `-Start`       | —       | Window start (inclusive). Use the log's native timestamp format |
| `-End`         | —       | Window end (inclusive) |
| `-MaxResults`  | 100     | Max entries |
| `-LevelFilter` | none    | AEM only: filter by level within the window |

**Use when:** reconstructing the sequence of events during an outage window.

---

### 6. Frequency Analysis

Count and rank occurrences by field. Outputs a sorted frequency table.

```powershell
# Top error types in AEM log
& "$logSkill\frequency.ps1" -Path $logFile -GroupBy ExceptionClass -LevelFilter ERROR

# HTTP status code distribution
& "$logSkill\frequency.ps1" -Path $accessLog -GroupBy Status

# Top 404 URLs in dispatcher
& "$logSkill\frequency.ps1" -Path $dispatcherLog -GroupBy Path

# Busiest loggers
& "$logSkill\frequency.ps1" -Path $logFile -GroupBy Logger -MaxResults 20

# Custom regex grouping
& "$logSkill\frequency.ps1" -Path $logFile -CustomPattern '(?<Key>com\.\w+\.\w+\.\w+)'
```

| GroupBy field     | Formats                    |
|-------------------|----------------------------|
| `Level`           | aem-error                  |
| `Logger`          | aem-error                  |
| `Thread`          | aem-error                  |
| `Pod`             | aem-error, httpd-access    |
| `ExceptionClass`  | aem-error                  |
| `Status`          | httpd-access, dispatcher   |
| `Method`          | httpd-access, dispatcher   |
| `Path`            | httpd-access, dispatcher   |
| `ClientIP`        | httpd-access               |
| `Host`            | dispatcher                 |
| `Farm`            | dispatcher                 |
| `Action`          | dispatcher                 |
| `Severity`        | dispatcher                 |
| `Duration`        | dispatcher                 |
| `UserAgent`       | httpd-access               |

**Use when:** finding top offenders, building dashboards, identifying patterns.

---

### 7. Correlation / Thread Tracing

Follow a thread, request ID, pod name, or any token across one or more log files. Results are merged and sorted by timestamp.

```powershell
# Follow a thread across one file
& "$logSkill\correlate.ps1" -Path $logFile -ThreadName "sling-default-4-Registered Service.5615" -MaxResults 50

# Follow a request ID across author + publish logs
& "$logSkill\correlate.ps1" -Path $authorLog,$publishLog -RequestId "f92c2931-e51b-49a0-ae46-374397357024"

# Follow a pod across all log files in a directory
& "$logSkill\correlate.ps1" -Path (Get-ChildItem "logs\*.log").FullName -PodName "cm-p149356-e1522219-aem-author-d77d46ffc-zngs2"

# Generic pattern
& "$logSkill\correlate.ps1" -Path $logFile -Pattern "TaskArchiveService" -MaxResults 20
```

| Parameter     | Default | Description |
|---------------|---------|-------------|
| `-ThreadName` | none    | Exact thread name |
| `-RequestId`  | none    | Request/correlation ID (searched anywhere in entry) |
| `-PodName`    | none    | Pod name filter |
| `-Pattern`    | none    | Generic regex |
| `-MaxResults` | 100     | Max entries across all files |

Multiple correlation keys are combined with AND logic.

**Use when:** tracing a request end-to-end, following a thread through a failure, correlating events across author/publish/dispatcher.

---

## Usage Guidelines for Agents

### Context Budget

1. **Always use `-MaxResults`** — default values are conservative (30–100) but adjust down for exploratory queries.
2. **Scouting phase**: use `-MaxResults 5–15` for broad initial sweeps.
3. **Follow-up scouting**: increase `-MaxResults 20–50` for targeted deep dives requested by the analysis phase.
4. **Use `-Summary` mode first** — `extract-errors.ps1 -Summary` gives a frequency table in ~30 lines instead of potentially thousands of lines of stack traces.
5. **Use `-NoStackTrace`** — `filter-level.ps1 -NoStackTrace` gives one-line-per-entry for quick scanning.
6. **Use `-Tail`** — for recent errors, `-Tail -MaxResults 5` is faster than scanning from the top.
7. **Narrow with filters** — combine `-LoggerPattern`, `-MessagePattern`, `-LevelFilter` to reduce output.

### Two-Phase Workflow

This skill uses two-tier model routing. The **worker** model handles all script execution and data collection. The **expert** model handles analysis, pattern detection, and recommendations.

#### Phase 1 — Scouting (worker model)

Delegate all data collection to a `runSubagent` call with the **worker** model from [model-config.md](#configuration).

The scouting subagent:
- Runs PowerShell scripts to collect raw data
- Uses aggressive `-MaxResults` (5–15) for the initial pass
- Returns structured output — **no interpretation, no recommendations**
- May be called multiple times if the analysis phase requests follow-up data

Use the [Scouting Prompt Template](#scouting-prompt-template) below to construct the subagent prompt.

**Typical scouting sequence:**

```
1. detect-format.ps1           → confirm format
2. extract-errors.ps1 -Summary → error landscape overview
3. frequency.ps1               → top offenders by field
4. timeline.ps1                → entries in the outage window
5. filter-level.ps1            → filtered entries by level
6. search-context.ps1          → keyword matches with context
7. correlate.ps1               → thread/request tracing
```

Not every script is needed for every request — select based on what the user is asking.

**Multi-file scouting:** When multiple log files are present, the scouting subagent should:
1. Run `detect-format.ps1` on each to confirm formats
2. Run `extract-errors.ps1 -Summary` on each to compare error landscapes
3. Use `correlate.ps1` with multiple `-Path` values to trace cross-tier events
4. Use `timeline.ps1` on each with the same time window

#### Phase 2 — Analysis (expert model)

After scouting returns, the invoking agent (or a `runSubagent` with the **expert** model) performs deep analysis on the collected data.

The analysis phase:
- **Does NOT run scripts** — it works only with the scouting output
- Performs pattern detection, anomaly identification, and root-cause reasoning
- May request **follow-up scouting** by describing what additional data is needed (the agent then launches another worker subagent)

See [Analysis Guidelines](#analysis-guidelines) for what to cover.

---

### Scouting Prompt Template

Fill in the placeholders and pass this as the `prompt` to `runSubagent`. Set `model` to the **worker** model from `model-config.md`.

```
You are a log data collector. Read the skill documentation first:
  read_file: $HOME/.copilot/skills/log-analyzer/SKILL.md

Script directory: $HOME/.copilot/skills/log-analyzer/scripts

Log file(s):
  {{LOG_FILE_PATHS}}

Investigation goal:
  {{WHAT_TO_INVESTIGATE}}

Time window (if applicable):
  {{START}} to {{END}}

Instructions:
1. Run detect-format.ps1 on each file to confirm format.
2. Run the scripts listed below. Use -MaxResults {{MAX_RESULTS}} unless noted.
3. Return ALL script output in structured sections with headers.
4. Do NOT interpret results, suggest causes, or make recommendations.
5. If a script produces no output, report that explicitly.

Scripts to run:
  {{SCRIPT_LIST_WITH_PARAMETERS}}

Output format:
  ## Format Detection
  <output>

  ## Error Summary
  <output>

  ## Frequency Analysis
  <output>

  ## Timeline
  <output>

  ## Search Results
  <output>

  ## Correlation
  <output>
```

**Example invocation:**

```
runSubagent(
  model: "<worker model from model-config.md>",
  description: "Scout log data",
  prompt: "<filled template above>"
)
```

---

### Analysis Guidelines

After receiving scouting results, the analysis phase must cover:

1. **Error pattern clustering** — group related errors by exception class, logger, or message similarity. Identify which clusters are symptoms vs. root causes.
2. **Temporal correlation** — map error spikes to the timeline. Identify cascade patterns (error A precedes error B by N seconds).
3. **Cross-file event chains** — if multiple log files were scouted, trace request flow across tiers (author → publish → dispatcher).
4. **Severity assessment** — rank findings by impact: service-affecting vs. noise. Flag errors that indicate data loss, security issues, or service degradation.
5. **Root-cause hypothesis** — propose the most likely root cause(s) with supporting evidence from the scouted data.
6. **Recommended actions** — actionable next steps: config changes, code fixes, further investigation areas.
7. **Follow-up scouting** — if the scouted data is insufficient, describe exactly what additional data is needed (which script, which parameters, which file) so the agent can launch another worker subagent.

---

### Encoding

All scripts default to UTF-8 with BOM detection. If a file uses a different encoding, the StreamReader constructor will auto-detect most common encodings.

### Performance

- Scripts stream line-by-line — memory usage is constant regardless of file size
- `Select-String` is used where possible (fastest for simple searches)
- `StreamReader` is used for multiline-aware processing
- For files over 1GB, expect processing time of 30–120 seconds per script invocation
- The `-Tail` flag on `extract-errors.ps1` still reads the entire file (it uses a ring buffer) — it's O(n) not O(1)

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| "Files above 50MB cannot be synchronized" | Trying to use `read_file` on a huge log | Use this skill's scripts instead |
| `detect-format.ps1` returns `unknown` | File uses an unrecognized format | Check first 20 lines manually with `Get-Content -TotalCount 20` |
| Truncated stack traces | `-MaxResults` hit mid-entry | Increase `-MaxResults` or use `-LoggerPattern` to narrow |
| Empty output from `filter-level.ps1` | Wrong format (not AEM error log) | Check with `detect-format.ps1` first |
| Slow performance on huge files | Expected for GB-scale files | Use `-MaxResults` aggressively, filter early |
| Timestamp parse errors | Start/End format doesn't match log format | Use the log's native timestamp format (see formats.md) |
