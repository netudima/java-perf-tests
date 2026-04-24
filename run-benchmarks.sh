#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/set-env.sh" ]; then
    # shellcheck source=set-env.sh
    . "$SCRIPT_DIR/set-env.sh"
else
    echo "set-env.sh not found. Copy set-env.sh.template to set-env.sh and set your JDK paths." >&2
    exit 1
fi

BUILD_JAVA_HOME="$JDK_HOME_17"

JAR="$SCRIPT_DIR/target/benchmarks.jar"

jdk_home_for_version() {
    case "$1" in
        17) echo "$JDK_HOME_17" ;;
        21) echo "$JDK_HOME_21" ;;
        25) echo "$JDK_HOME_25" ;;
        *)  echo "" ;;
    esac
}

usage() {
    cat <<EOF
Usage: $0 [options] [JMH args...]

Options:
  -p <name=value>   Pass a JMH @Param value (repeatable).
                    Example: -p stringType="long ASCII" -p checkerName=swar
  -j <version>      JDK version to run with: 17, 21, 25 (default: 21)
                    Use "all" to run sequentially on all three versions.
  -h                Show this help

Any remaining arguments are passed through to JMH (e.g. a benchmark name filter).

Examples:
  $0
  $0 -j 17
  $0 -j all
  $0 -p stringType="long ASCII" -j 25
  $0 -p stringType="short non-ASCII" -p checkerName=swar AsciiCheckerBenchmark
EOF
}

JDK_VERSION="21"
# Newline-separated "name=value" strings to safely preserve spaces in values.
PARAMS=""

while getopts ":p:j:h" opt; do
    case $opt in
        p) PARAMS="${PARAMS}${OPTARG}
" ;;
        j) JDK_VERSION="$OPTARG" ;;
        h) usage; exit 0 ;;
        :) echo "Option -$OPTARG requires an argument." >&2; usage; exit 1 ;;
        \?) echo "Unknown option: -$OPTARG" >&2; usage; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

# Save remaining positional args (benchmark filter etc.) as newline-separated
# so we can rebuild them safely inside the for loop without an array.
EXTRA_ARGS=""
for arg in "$@"; do
    EXTRA_ARGS="${EXTRA_ARGS}${arg}
"
done

if [ "$JDK_VERSION" = "all" ]; then
    RUN_VERSIONS="17 21 25"
else
    if [ -z "$(jdk_home_for_version "$JDK_VERSION")" ]; then
        echo "Unknown JDK version: $JDK_VERSION. Allowed: 17, 21, 25, all." >&2
        exit 1
    fi
    RUN_VERSIONS="$JDK_VERSION"
fi

JAVA_HOME="$BUILD_JAVA_HOME"
export JAVA_HOME
export PATH="$JAVA_HOME/bin:$PATH"

if [ ! -f "$JAR" ]; then
    echo "Building benchmarks with JDK 17..."
    mvn -f "$SCRIPT_DIR/pom.xml" clean package -q
fi

SUMMARIES=""

for version in $RUN_VERSIONS; do
    java_bin="$(jdk_home_for_version "$version")/bin/java"
    if [ ! -x "$java_bin" ]; then
        echo "JDK $version not found at $(jdk_home_for_version "$version"), skipping." >&2
        continue
    fi
    echo "Running benchmarks with JDK $version ($(jdk_home_for_version "$version"))..."

    # Rebuild positional params: -p name=value ... [extra args]
    set --
    if [ -n "$PARAMS" ]; then
        while IFS= read -r pair; do
            [ -n "$pair" ] && set -- "$@" -p "$pair"
        done <<EOF
$PARAMS
EOF
    fi
    if [ -n "$EXTRA_ARGS" ]; then
        while IFS= read -r arg; do
            [ -n "$arg" ] && set -- "$@" "$arg"
        done <<EOF
$EXTRA_ARGS
EOF
    fi

    tmpfile="$(mktemp)"
    "$java_bin" -jar "$JAR" "$@" | tee "$tmpfile"
    summary="$(grep -E '^(Benchmark|[A-Za-z].+avgt)' "$tmpfile")"
    rm -f "$tmpfile"
    if [ -n "$summary" ]; then
        SUMMARIES="${SUMMARIES}=== JDK ${version} ===
${summary}
"
    fi
done

if [ -n "$SUMMARIES" ]; then
    echo ""
    echo "============================== SUMMARY =============================="
    printf '%s' "$SUMMARIES"
    echo "======================================================================"
fi
