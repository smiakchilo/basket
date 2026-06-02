#!/usr/bin/env bash
# unpack.sh — Unpack a JAR file to .dependency-sources/ under the project root.
#
# Usage:
#   ./unpack.sh -j <jarPath> -d <projectDir> -g <groupId> -a <artifactId> -v <version>
#
# Outputs the absolute path to the unpacked directory.

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

# Skip if already unpacked
if [[ -d "$TARGET_DIR" ]] && [[ -n "$(find "$TARGET_DIR" -type f -print -quit 2>/dev/null)" ]]; then
    echo "Already unpacked at: $TARGET_DIR" >&2
    echo "$TARGET_DIR"
    exit 0
fi

mkdir -p "$TARGET_DIR"

# Unpack using jar (preferred) or unzip
if command -v jar &>/dev/null; then
    jar_abs=$(cd "$(dirname "$JAR_PATH")" && pwd)/$(basename "$JAR_PATH")
    (cd "$TARGET_DIR" && jar xf "$jar_abs")
elif command -v unzip &>/dev/null; then
    unzip -q -o "$JAR_PATH" -d "$TARGET_DIR"
else
    echo "Error: Neither 'jar' nor 'unzip' found in PATH." >&2
    exit 1
fi

# Remove META-INF
rm -rf "${TARGET_DIR}/META-INF"

file_count=$(find "$TARGET_DIR" -type f | wc -l)
echo "Unpacked ${file_count} files to: $TARGET_DIR" >&2
echo "$TARGET_DIR"
