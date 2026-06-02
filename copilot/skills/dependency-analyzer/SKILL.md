---
name: dependency-analyzer
description: "Use when: analyzing external dependency source code, looking up a class or method from a third-party library, inspecting dependency internals, reading source of a Maven dependency, decompiling a JAR, finding where a transitive dependency comes from, resolving GAV coordinates. Retrieves sources or decompiles compiled JARs using bundled CFR 0.152, unpacks them under .dependency-sources/ for fast access."
argument-hint: "Class name, package, or GAV coordinates of the dependency to analyze (e.g. 'org.apache.commons:commons-lang3:3.12.0' or 'StringUtils')"
---

# Dependency Analyzer

Retrieve and unpack source code for external Maven dependencies so the agent can read and analyze them. If sources are unavailable, decompiles the compiled JAR using the bundled CFR 0.152 decompiler.

## When to Use

- User asks about a class or method that belongs to an external dependency (not project source)
- User wants to inspect the internals of a third-party library
- User needs to understand how a dependency implements something
- User asks where a transitive dependency comes from
- Agent needs to read dependency source code to answer a question accurately

## Model Routing

**BLOCKING — do this before any other step.**

Read the shared model config to get model names:

```
read_file: $HOME/.copilot/model-config.md
```

Extract the **worker** model name from the **Roles** table.

**This skill runs entirely on the worker model.** All steps — GAV resolution, fetching, unpacking, decompilation, and path reporting — are mechanical data-retrieval operations with no deep reasoning required. When this skill is invoked by another skill or agent, delegate the entire workflow to a subagent using the worker model:

```
runSubagent(model: "<worker model from config>", prompt: "Run the dependency-analyzer skill for <GAV or class>...")
```

When invoked directly via `/dependency-analyzer`, the current model executes the steps below. If the current model is the expert, consider switching to the worker model via subagent delegation to conserve budget.

## Step 0 — Read Skill Memos

Use the memory tool to read `/memories/skill-memos/dependency-analyzer.md`. If it exists, apply any relevant advice. If not, proceed normally.

**Write-back rule** — whenever an unexpected problem arises during execution and you resolve it, append a memo entry (`### Title — YYYY-MM-DD` / `**Problem**: …` / `**Fix**: …`) to the same file (create if absent). Consolidate if the file exceeds ~30 lines.

## Step 1 — Resolve Script Paths

Determine the OS and set the script directory and extension:

```powershell
# PowerShell (Windows)
$depSkill = "$HOME\.copilot\skills\dependency-analyzer\scripts"
```

```bash
# Bash (macOS/Linux)
depSkill="$HOME/.copilot/skills/dependency-analyzer/scripts"
```

**Cross-platform detection**: Use `$IsWindows`, `$IsMacOS`, `$IsLinux` in PowerShell 7+, or `$env:OS -match 'Windows'` in Windows PowerShell 5.1. On Windows, use `.ps1` scripts. On macOS/Linux, use `.sh` scripts.

## Step 2 — Identify the Dependency

Determine the GAV (groupId, artifactId, version) coordinates. There are three paths:

### Path A: GAV Provided by User

If the user specifies the full GAV (e.g., `org.apache.commons:commons-lang3:3.12.0`), parse it directly and skip to Step 3.

### Path B: Partial Info Provided

If the user provides a class name, package, or partial artifact name, use the resolve-gav script:

```powershell
# PowerShell
& "$depSkill\resolve-gav.ps1" -ProjectDir "<project-root>" -ArtifactId "<known-artifact>" -GroupId "<known-group>"
```

```bash
# Bash
"$depSkill/resolve-gav.sh" -d "<project-root>" -a "<known-artifact>" -g "<known-group>"
```

| Parameter | PS Flag | Bash Flag | Required | Description |
|-----------|---------|-----------|----------|-------------|
| Project dir | `-ProjectDir` | `-d` | Yes | Maven project root (where root `pom.xml` lives) |
| Artifact ID | `-ArtifactId` | `-a` | No* | Full or partial artifact name |
| Group ID | `-GroupId` | `-g` | No* | Full or partial group name |
| Class name | `-ClassName` | `-c` | No* | Fully-qualified class name |

*At least one of ArtifactId, GroupId, or ClassName must be provided.

The script performs a two-phase search:
1. **Fast path**: Parses all `pom.xml` files in the project hierarchy (root + modules) for direct dependency matches.
2. **Full tree**: If the fast path finds nothing, runs `mvn dependency:tree -B -ntp` to find transitive dependencies.

If multiple matches are returned, present them to the user and ask which one to use.

### Path C: Insufficient Info

If you cannot determine the dependency, ask the user for at least the artifactId.

## Step 3 — Check Cache

Before fetching, check if sources are already unpacked:

```powershell
$cacheDir = Join-Path "<project-root>" ".dependency-sources" "<groupId>" "<artifactId>-<version>"
if (Test-Path $cacheDir) { /* already available — report path and stop */ }
```

```bash
cacheDir="<project-root>/.dependency-sources/<groupId>/<artifactId>-<version>"
if [[ -d "$cacheDir" ]]; then # already available — report path and stop
```

If the cache directory exists and contains files, skip to Step 6.

## Step 4 — Fetch the JAR

Use the fetch-dependency script to retrieve the JAR:

```powershell
# PowerShell
$result = & "$depSkill\fetch-dependency.ps1" -GroupId "<g>" -ArtifactId "<a>" -Version "<v>" -ProjectDir "<project-root>"
```

```bash
# Bash — output is tab-separated: jarPath  isSources  fetchMethod
result=$("$depSkill/fetch-dependency.sh" -g "<g>" -a "<a>" -v "<v>" -d "<project-root>")
```

| Parameter | PS Flag | Bash Flag | Required | Description |
|-----------|---------|-----------|----------|-------------|
| Group ID | `-GroupId` | `-g` | Yes | Maven groupId |
| Artifact ID | `-ArtifactId` | `-a` | Yes | Maven artifactId |
| Version | `-Version` | `-v` | Yes | Maven version |
| Project dir | `-ProjectDir` | `-d` | No | Project root (for `mvn` commands). Default: `.` |
| M2 repo | `-M2Repo` | `-m` | No | Local repo path. Default: `~/.m2/repository` |

The script uses a cascading strategy:
1. Check local `.m2/repository` for `-sources.jar`
2. Run `mvn dependency:copy` for the sources classifier
3. Fall back to direct HTTPS download from Maven Central
4. If no sources JAR found anywhere, repeat 1-3 for the main (compiled) `.jar`

**Output** (PowerShell): `PSCustomObject` with `JarPath`, `IsSources` (bool), `FetchMethod`.
**Output** (Bash): tab-separated `jarPath  isSources  fetchMethod`.

**Note on enterprise/private repos**: The Maven CLI path (`dependency:copy`) respects `settings.xml` credentials and mirrors. The HTTP fallback only targets Maven Central and will not work for private artifacts.

## Step 5 — Unpack or Decompile

Based on whether the fetched JAR contains sources or compiled classes:

### If Sources JAR (`IsSources = true`)

Unpack directly:

```powershell
# PowerShell
$outputDir = & "$depSkill\unpack.ps1" -JarPath "<jar>" -ProjectDir "<project-root>" -GroupId "<g>" -ArtifactId "<a>" -Version "<v>"
```

```bash
# Bash
outputDir=$("$depSkill/unpack.sh" -j "<jar>" -d "<project-root>" -g "<g>" -a "<a>" -v "<v>")
```

### If Compiled JAR (`IsSources = false`)

Decompile using CFR 0.152:

```powershell
# PowerShell
$outputDir = & "$depSkill\decompile.ps1" -JarPath "<jar>" -ProjectDir "<project-root>" -GroupId "<g>" -ArtifactId "<a>" -Version "<v>"
```

```bash
# Bash
outputDir=$("$depSkill/decompile.sh" -j "<jar>" -d "<project-root>" -g "<g>" -a "<a>" -v "<v>")
```

Both scripts output the absolute path to the unpacked/decompiled directory.

| Parameter | PS Flag | Bash Flag | Required | Description |
|-----------|---------|-----------|----------|-------------|
| JAR path | `-JarPath` | `-j` | Yes | Path to the fetched JAR file |
| Project dir | `-ProjectDir` | `-d` | Yes | Project root |
| Group ID | `-GroupId` | `-g` | Yes | For organizing output path |
| Artifact ID | `-ArtifactId` | `-a` | Yes | For organizing output path |
| Version | `-Version` | `-v` | Yes | For organizing output path |

**Output layout**: `.dependency-sources/<groupId>/<artifactId>-<version>/` under the project root.

The decompile script:
- Uses the CFR JAR bundled at [tools/cfr-0.152.jar](./tools/cfr-0.152.jar)
- Requires `java` in PATH
- Removes `META-INF/` and `summary.txt` from output
- Skips decompilation if `.java` files already exist in the target directory

## Step 6 — Report Path and Memo

Report the precise path to the caller:

```
Dependency sources available at: <project-root>/.dependency-sources/<groupId>/<artifactId>-<version>/
```

Then record the successful path in the skill memo for future reference. Note which fetch method worked (local-m2, maven-copy, or maven-central-http) and whether sources or decompilation was used. This helps optimize future invocations.

The caller can now use `read_file`, `grep_search`, or `semantic_search` against the unpacked sources to answer the user's original question.

## Error Handling

| Scenario | Action |
|----------|--------|
| No `pom.xml` in project dir | Ask user for the correct project root |
| Dependency not found in POM or tree | Ask user for exact GAV coordinates |
| Multiple matches from resolve-gav | Present options and ask user to choose |
| All fetch methods fail | Report failure, suggest checking artifact coordinates and network access |
| No `java` in PATH (decompilation) | Report that JDK/JRE is needed, suggest installing or configuring JAVA_HOME |
| CFR decompilation produces errors | Still usable — CFR outputs partial results. Note which classes failed |

## File Organization

```
~/.copilot/skills/dependency-analyzer/
├── SKILL.md                     # This file
├── scripts/
│   ├── resolve-gav.ps1          # GAV resolution (PowerShell)
│   ├── resolve-gav.sh           # GAV resolution (Bash)
│   ├── fetch-dependency.ps1     # JAR fetching (PowerShell)
│   ├── fetch-dependency.sh      # JAR fetching (Bash)
│   ├── unpack.ps1               # JAR unpacking (PowerShell)
│   ├── unpack.sh                # JAR unpacking (Bash)
│   ├── decompile.ps1            # CFR decompilation (PowerShell)
│   └── decompile.sh             # CFR decompilation (Bash)
├── tools/
│   └── cfr-0.152.jar            # Bundled CFR decompiler
└── references/
    └── maven-repo-layout.md     # .m2 path conventions
```
