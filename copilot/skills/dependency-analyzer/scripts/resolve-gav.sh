#!/usr/bin/env bash
# resolve-gav.sh — Resolve GAV of a Maven dependency from POM hierarchy.
#
# Usage:
#   ./resolve-gav.sh -d <project-dir> [-a <artifactId>] [-g <groupId>] [-c <className>]
#
# Outputs tab-separated: groupId  artifactId  version  scope  source

set -euo pipefail

PROJECT_DIR=""
ARTIFACT_ID=""
GROUP_ID=""
CLASS_NAME=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--project-dir) PROJECT_DIR="$2"; shift 2 ;;
        -a|--artifact-id) ARTIFACT_ID="$2"; shift 2 ;;
        -g|--group-id)    GROUP_ID="$2";    shift 2 ;;
        -c|--class-name)  CLASS_NAME="$2";  shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [[ -z "$PROJECT_DIR" ]]; then
    echo "Error: -d <project-dir> is required." >&2
    exit 1
fi

if [[ -z "$ARTIFACT_ID" && -z "$GROUP_ID" && -z "$CLASS_NAME" ]]; then
    echo "Error: At least one of -a, -g, or -c must be specified." >&2
    exit 1
fi

if [[ ! -f "$PROJECT_DIR/pom.xml" ]]; then
    echo "Error: No pom.xml found in $PROJECT_DIR" >&2
    exit 1
fi

# Phase 1: grep POM files for the artifact (fast path)
find_in_poms() {
    local search_term="$1"
    local pom_files
    pom_files=$(find "$PROJECT_DIR" -maxdepth 3 -name "pom.xml" -not -path "*/target/*" -not -path "*/node_modules/*")

    for pom in $pom_files; do
        if grep -q "$search_term" "$pom" 2>/dev/null; then
            # Extract the dependency block containing the search term
            # Use awk to find dependency blocks
            awk -v search="$search_term" '
                /<dependency>/ { block=""; in_dep=1 }
                in_dep { block = block $0 "\n" }
                /<\/dependency>/ {
                    if (in_dep && index(block, search) > 0) {
                        # Extract groupId, artifactId, version
                        g=""; a=""; v=""; s="compile"
                        n = split(block, lines, "\n")
                        for (i=1; i<=n; i++) {
                            if (match(lines[i], /<groupId>([^<]+)<\/groupId>/, m)) g=m[1]
                            if (match(lines[i], /<artifactId>([^<]+)<\/artifactId>/, m)) a=m[1]
                            if (match(lines[i], /<version>([^<]+)<\/version>/, m)) v=m[1]
                            if (match(lines[i], /<scope>([^<]+)<\/scope>/, m)) s=m[1]
                        }
                        if (g != "" && a != "") {
                            printf "%s\t%s\t%s\t%s\tPOM: %s\n", g, a, v, s, FILENAME
                        }
                    }
                    in_dep=0
                }
            ' "$pom"
        fi
    done
}

search_term=""
if [[ -n "$ARTIFACT_ID" ]]; then
    search_term="$ARTIFACT_ID"
elif [[ -n "$GROUP_ID" ]]; then
    search_term="$GROUP_ID"
fi

if [[ -n "$search_term" ]]; then
    results=$(find_in_poms "$search_term")
    if [[ -n "$results" ]]; then
        echo "$results"
        exit 0
    fi
fi

# Phase 2: Full dependency tree (handles transitive deps)
echo "Direct POM search found nothing. Running mvn dependency:tree..." >&2

if [[ -n "$ARTIFACT_ID" ]]; then
    pattern="$ARTIFACT_ID"
elif [[ -n "$GROUP_ID" ]]; then
    pattern="$GROUP_ID"
elif [[ -n "$CLASS_NAME" ]]; then
    # Convert class name to package prefix guess
    IFS='.' read -ra parts <<< "$CLASS_NAME"
    if [[ ${#parts[@]} -ge 3 ]]; then
        pattern="${parts[0]}.${parts[1]}.${parts[2]}"
    else
        pattern="$CLASS_NAME"
    fi
else
    pattern=""
fi

tree_output=$(cd "$PROJECT_DIR" && mvn dependency:tree -B -ntp -Dincludes="*${pattern}*" 2>&1) || true

# Parse dependency:tree output
echo "$tree_output" | grep -oP '[\+\|\\\- ]+\K[\w.\-]+:[\w.\-]+:\w+:[\w.\-]+:\w+' | while IFS=: read -r g a packaging v scope; do
    printf "%s\t%s\t%s\t%s\tdependency:tree\n" "$g" "$a" "$v" "$scope"
done

