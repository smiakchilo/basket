# JDK Detector — Worker Subagent Protocol

> **Purpose**: This document is read by a **worker-model subagent** invoked during the Java Version & Runner Resolution blocking step of the java-unit-test-writer skill. The subagent detects the Java version required by the project and locates a matching JDK installation.

## Steps

1. Read the nearest pom.xml. Extract the required Java major version by checking in order:
   a. `maven.compiler.release` property
   b. `maven.compiler.source` property
   c. `maven.compiler.target` property
   d. `<release>`, `<source>`, or `<target>` inside `maven-compiler-plugin` configuration
   Normalize: `1.8` → 8, `11` → 11, `17` → 17, etc.
   If the version cannot be determined, return: `{ "status": "version-unknown" }`

2. Check `/memories/repo/jdk-paths.md` for a row whose Version column matches the required version.
   If found, verify the directory still exists (`Test-Path`).
   If the directory exists, remember the cached path and skip step 4 — but always run step 3.
   If the directory is gone, note the stale entry and continue.

3. Run: `cmd /c "java -version 2>&1"`
   Parse the major version from the output. Java 8 reports `1.8.x`; Java 9+ reports `N.x`.
   If the version matches the required version: set `system_default = true`. If no cached path was found in step 2, use the system JDK path as `java_sdk_path`.
   If the version does not match: set `system_default = false`.

4. If `system_default` is `false` AND no valid cached path was found in step 2, scan these directories for a matching JDK installation:
   - `C:\Program Files\Java\*`
   - `C:\Program Files (x86)\Java\*`
   - `C:\Java\*`
   - `D:\Java\*`, `E:\Java\*`
   Match directory names containing `jdk-<major>`, `jdk<major>`, or `jdk1.<major>` (Java 8).
   Prefer the same vendor as the current system JDK; otherwise pick any stable JDK over a JRE.

5. Return exactly this JSON:
   ```json
   {
     "status": "found" | "not-found" | "version-unknown",
     "required_version": <N>,
     "java_sdk_path": "<absolute path or empty>",
     "java_runner_path": "<absolute path>\\bin\\java.exe or empty",
     "stale_entry_version": <N or null>,
     "system_default": true | false
   }
   ```
