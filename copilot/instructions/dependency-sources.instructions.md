---
description: "Use when: reading or analyzing files under .dependency-sources/. These are external dependency sources — either unpacked from a -sources.jar or decompiled from a compiled .jar using CFR. Decompiled code may contain artifacts such as synthetic bridge methods, missing comments, and slightly altered control flow."
applyTo: "**/.dependency-sources/**"
---

# Dependency Sources Context

Files in `.dependency-sources/` are **external library code**, not project source. They were retrieved by the `dependency-analyzer` skill.

## Rules

1. **Read-only.** Never edit these files. They are reference material, not project code.
2. **Do not suggest refactoring** or style fixes for dependency sources.
3. **Decompiled code caveats.** If the path was produced by CFR decompilation rather than a `-sources.jar`:
   - Comments and Javadoc are absent.
   - Local variable names may be synthetic (`var1`, `string2`).
   - `switch` on strings may appear as hash-based `if` chains.
   - Bridge methods and synthetic accessors may be present.
   - Lambda expressions may appear as anonymous inner classes.
4. **Version awareness.** The directory structure is `<groupId>/<artifactId>-<version>/`. Always note the version when reporting findings — the user's project may use a different version.
5. **Do not index or search broadly.** Target specific classes or packages rather than scanning the entire unpacked tree.
