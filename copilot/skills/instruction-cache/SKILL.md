---
name: instruction-cache
description: "Use when: loading instruction files for a code review, computing SHA-256 hashes for instruction files, checking cached summaries of instruction files, updating the instruction cache after a review. Discovers project-level and user-level instruction files, compares them against a persistent SHA-256 cache, and returns either cached summaries (on hits) or full content (on misses) for efficient reuse across reviews."
---

# Instruction Cache

Discovers and hashes project-level and user-level instruction files, serves cached summaries for unchanged files, and persists new summaries after analysis — avoiding redundant re-reads across reviews.

## Load Protocol

Execute every step in this protocol directly (inline, not via a subagent). Place results in `## Instruction Summaries` (cache hits) and `## Instruction Files (Full)` (cache misses).

### Step 1 — Find project-level instructions

Search for and read every file matching these patterns in the workspace:
- `.github/copilot-instructions.md`
- `.github/instructions/**`
- `CLAUDE.md` in the workspace root
- `.claude/rules/**`
- `AGENTS.md` in the workspace root and in any subdirectory (e.g. `core/AGENTS.md`, `core/src/test/AGENTS.md`, etc.)

### Step 2 — Cache check

For each instruction file located in Step 1, check whether a cached summary exists and is up to date:

1. Read `.github/memories/repo/instruction-cache.md`. If the file does not exist, treat all instruction files as cache misses.
2. Compute the SHA-256 hash of each instruction file:
   - PowerShell: `Get-FileHash -Path "<path>" -Algorithm SHA256 | Select-Object -ExpandProperty Hash`
   - Unix: `sha256sum "<path>" | cut -d' ' -f1`
3. Compare the hash against the `**Hash**:` entry in the cache for that path:
   - **Cache hit** (hash matches): place the file's cached `**Summary**:` bullet list in the `## Instruction Summaries` output section.
   - **Cache miss** (hash differs, or file not in cache): place the full file content **and** the computed hash in the `## Instruction Files (Full)` output section.

## Update Protocol

Execute every step in this protocol directly (inline, not via a subagent).

1. Read the existing `.github/memories/repo/instruction-cache.md` (create the file if it does not exist).
2. For each entry in `## New Instruction Summaries`:
   - Parse the `### <file-path> | SHA256: <hash>` header to extract the path and hash.
   - Find the matching `## <file-path>` block in the cache and replace it entirely; or append a new block if the path is not yet cached.
   - Block format:
     ```
     ## <absolute-file-path>
     **Hash**: <sha256>
     **Summary**:
     - <rule 1>
     - <rule 2>
     ```
3. Write the updated content back to `.github/memories/repo/instruction-cache.md`.
