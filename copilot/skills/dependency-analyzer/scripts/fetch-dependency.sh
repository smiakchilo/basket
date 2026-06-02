#!/usr/bin/env bash
# fetch-dependency.sh — Fetch a Maven dependency JAR (sources or compiled).
#
# Cascading strategy: local .m2 → mvn dependency:copy → Maven Central HTTP.
# Tries -sources.jar first, falls back to main .jar.
#
# Usage:
#   ./fetch-dependency.sh -g <groupId> -a <artifactId> -v <version> [-d <projectDir>] [-m <m2Repo>]
#
# Outputs tab-separated: jarPath  isSources(true|false)  fetchMethod

set -euo pipefail

GROUP_ID=""
ARTIFACT_ID=""
VERSION=""
PROJECT_DIR="."
M2_REPO="${HOME}/.m2/repository"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -g|--group-id)    GROUP_ID="$2";    shift 2 ;;
        -a|--artifact-id) ARTIFACT_ID="$2"; shift 2 ;;
        -v|--version)     VERSION="$2";     shift 2 ;;
        -d|--project-dir) PROJECT_DIR="$2"; shift 2 ;;
        -m|--m2-repo)     M2_REPO="$2";     shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [[ -z "$GROUP_ID" || -z "$ARTIFACT_ID" || -z "$VERSION" ]]; then
    echo "Error: -g, -a, and -v are all required." >&2
    exit 1
fi

GROUP_PATH="${GROUP_ID//./\/}"
ARTIFACT_BASE="${M2_REPO}/${GROUP_PATH}/${ARTIFACT_ID}/${VERSION}"

maven_central_url() {
    local classifier="$1"
    local filename
    if [[ -n "$classifier" ]]; then
        filename="${ARTIFACT_ID}-${VERSION}-${classifier}.jar"
    else
        filename="${ARTIFACT_ID}-${VERSION}.jar"
    fi
    echo "https://repo1.maven.org/maven2/${GROUP_PATH}/${ARTIFACT_ID}/${VERSION}/${filename}"
}

try_local_m2() {
    local classifier="$1"
    local filename
    if [[ -n "$classifier" ]]; then
        filename="${ARTIFACT_ID}-${VERSION}-${classifier}.jar"
    else
        filename="${ARTIFACT_ID}-${VERSION}.jar"
    fi
    local path="${ARTIFACT_BASE}/${filename}"
    if [[ -f "$path" ]]; then
        echo "$path"
        return 0
    fi
    return 1
}

try_maven_copy() {
    local classifier="$1"
    local artifact="${GROUP_ID}:${ARTIFACT_ID}:${VERSION}"
    if [[ -n "$classifier" ]]; then
        artifact="${artifact}:jar:${classifier}"
    fi
    local tmp_dir
    tmp_dir=$(mktemp -d)

    if cd "$PROJECT_DIR" && mvn dependency:copy "-Dartifact=${artifact}" "-DoutputDirectory=${tmp_dir}" -B -ntp >/dev/null 2>&1; then
        local jar
        jar=$(find "$tmp_dir" -name '*.jar' -print -quit 2>/dev/null)
        if [[ -n "$jar" ]]; then
            mkdir -p "$ARTIFACT_BASE"
            local dest="${ARTIFACT_BASE}/$(basename "$jar")"
            cp "$jar" "$dest"
            rm -rf "$tmp_dir"
            echo "$dest"
            return 0
        fi
    fi
    rm -rf "$tmp_dir"
    return 1
}

try_http_download() {
    local classifier="$1"
    local url
    url=$(maven_central_url "$classifier")
    local filename
    if [[ -n "$classifier" ]]; then
        filename="${ARTIFACT_ID}-${VERSION}-${classifier}.jar"
    else
        filename="${ARTIFACT_ID}-${VERSION}.jar"
    fi
    mkdir -p "$ARTIFACT_BASE"
    local dest="${ARTIFACT_BASE}/${filename}"

    if command -v curl &>/dev/null; then
        if curl -fsSL -o "$dest" "$url" 2>/dev/null && [[ -s "$dest" ]]; then
            echo "$dest"
            return 0
        fi
    elif command -v wget &>/dev/null; then
        if wget -q -O "$dest" "$url" 2>/dev/null && [[ -s "$dest" ]]; then
            echo "$dest"
            return 0
        fi
    fi
    rm -f "$dest"
    return 1
}

fetch_jar() {
    local classifier="$1"
    local is_sources="$2"

    # Step A: Local .m2
    local path
    if path=$(try_local_m2 "$classifier"); then
        printf "%s\t%s\tlocal-m2\n" "$path" "$is_sources"
        return 0
    fi

    # Step B: Maven dependency:copy
    echo "Not in local .m2. Trying mvn dependency:copy..." >&2
    if path=$(try_maven_copy "$classifier"); then
        printf "%s\t%s\tmaven-copy\n" "$path" "$is_sources"
        return 0
    fi

    # Step C: HTTP download from Maven Central
    echo "Maven copy failed. Trying direct download from Maven Central..." >&2
    if path=$(try_http_download "$classifier"); then
        printf "%s\t%s\tmaven-central-http\n" "$path" "$is_sources"
        return 0
    fi

    return 1
}

# --- Main ---

# Try sources JAR first
echo "Fetching sources JAR for ${GROUP_ID}:${ARTIFACT_ID}:${VERSION}..." >&2
if fetch_jar "sources" "true"; then
    exit 0
fi

# Fall back to main (compiled) JAR
echo "Sources JAR not available. Fetching compiled JAR..." >&2
if fetch_jar "" "false"; then
    exit 0
fi

echo "Error: Failed to fetch ${GROUP_ID}:${ARTIFACT_ID}:${VERSION} from any source." >&2
exit 1
