#!/usr/bin/env bash
# decompile.sh — Decompile a compiled JAR using CFR (version auto-detected from tools/ folder).
#
# Usage:
#   ./decompile.sh -j <jarPath> -d <projectDir> -g <groupId> -a <artifactId> -v <version>
#
# Outputs the absolute path to the decompiled sources directory.

set -euo pipefail

JAR_PATH=""
PROJECT_DIR=""
GROUP_ID=""
ARTIFACT_ID=""
VERSION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -j|--jar-path)    JAR_PATH="$2";    shift 2 ;;
        -d|--project-dir) PROJECT_DIR="$2"; shift 2 ;;
        -g|--group-id)    GROUP_ID="$2";    shift 2 ;;
        -a|--artifact-id) ARTIFACT_ID="$2"; shift 2 ;;
        -v|--version)     VERSION="$2";     shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [[ -z "$JAR_PATH" || -z "$PROJECT_DIR" || -z "$GROUP_ID" || -z "$ARTIFACT_ID" || -z "$VERSION" ]]; then
    echo "Error: All parameters (-j, -d, -g, -a, -v) are required." >&2
    exit 1
fi

TARGET_DIR="${PROJECT_DIR}/.dependency-sources/${GROUP_ID}/${ARTIFACT_ID}-${VERSION}"

# Skip if already decompiled
if [[ -d "$TARGET_DIR" ]] && [[ -n "$(find "$TARGET_DIR" -name '*.java' -print -quit 2>/dev/null)" ]]; then
    echo "Already decompiled at: $TARGET_DIR" >&2
    echo "$TARGET_DIR"
    exit 0
fi

# Locate CFR JAR — discover whichever version is in the tools/ folder
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
CFR_JAR=$(find "${SKILL_DIR}/tools" -maxdepth 1 -name 'cfr-*.jar' -print -quit 2>/dev/null)

if [[ -z "$CFR_JAR" || ! -f "$CFR_JAR" ]]; then
    echo "Error: No CFR JAR (cfr-*.jar) found in: ${SKILL_DIR}/tools/" >&2
    exit 1
fi

CFR_VERSION=$(basename "$CFR_JAR" .jar | sed 's/^cfr-//')

if ! command -v java &>/dev/null; then
    echo "Error: Java not found in PATH. A JRE/JDK is required for decompilation." >&2
    exit 1
fi

mkdir -p "$TARGET_DIR"

echo "Decompiling $JAR_PATH with CFR $CFR_VERSION..." >&2
java -jar "$CFR_JAR" "$JAR_PATH" --outputdir "$TARGET_DIR" --silent true 2>/dev/null

# Remove summary file if generated
rm -f "${TARGET_DIR}/summary.txt"

java_count=$(find "$TARGET_DIR" -name '*.java' | wc -l)
echo "Decompiled ${java_count} Java files to: $TARGET_DIR" >&2
echo "$TARGET_DIR"
