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
                    Example: -p stringType="long ASCII" -p impl=swar
  -j <version>      JDK version to run with: 17, 21, 25 (default: 21)
                    Use "all" to run sequentially on all three versions.
  -prof <profiler>  JMH profiler to use (e.g. xctraceasm, async, gc).
  -h                Show this help

Any remaining arguments are passed through to JMH (e.g. a benchmark name filter).

Examples:
  $0
  $0 -j 17
  $0 -j all
  $0 -p stringType="long ASCII" -j 25
  $0 -p stringType="short non-ASCII" -p impl=swar AsciiCheckerBenchmark
  $0 -prof xctraceasm -p impl=swar AsciiCheckerBenchmark
EOF
}

JDK_VERSION="21"
PROFILER=""
# Newline-separated "name=value" strings to safely preserve spaces in values.
PARAMS=""

# Capture original args before parsing consumes them.
ORIGINAL_ARGS="$*"

while [ $# -gt 0 ]; do
    case "$1" in
        -p)
            [ $# -lt 2 ] && { echo "Option -p requires an argument." >&2; usage; exit 1; }
            PARAMS="${PARAMS}${2}
"
            shift 2 ;;
        -j)
            [ $# -lt 2 ] && { echo "Option -j requires an argument." >&2; usage; exit 1; }
            JDK_VERSION="$2"
            shift 2 ;;
        -prof)
            [ $# -lt 2 ] && { echo "Option -prof requires an argument." >&2; usage; exit 1; }
            PROFILER="$2"
            shift 2 ;;
        -h) usage; exit 0 ;;
        -*) echo "Unknown option: $1" >&2; usage; exit 1 ;;
        *)  break ;;
    esac
done

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

BENCHMARK_NAME="${1:-all}"
LOG_FILE="$SCRIPT_DIR/logs/${BENCHMARK_NAME}-$(date '+%Y%m%d-%H%M%S').log"
mkdir -p "$SCRIPT_DIR/logs"
echo "run-benchmarks.sh $ORIGINAL_ARGS" | tee "$LOG_FILE"

START_TIME=$(date +%s)
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
    if [ -n "$PROFILER" ]; then
        "$java_bin" -jar "$JAR" -prof "$PROFILER" "$@" | tee -a "$LOG_FILE" | tee "$tmpfile"
    else
        "$java_bin" -jar "$JAR" "$@" | tee -a "$LOG_FILE" | tee "$tmpfile"
    fi
    summary="$(grep -E '^(Benchmark|[A-Za-z].+avgt)' "$tmpfile")"
    rm -f "$tmpfile"
    if [ -n "$summary" ]; then
        SUMMARIES="${SUMMARIES}=== JDK ${version} ===
${summary}
"
    fi
done

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
ELAPSED_FMT="$(printf '%02d:%02d:%02d' $((ELAPSED/3600)) $((ELAPSED%3600/60)) $((ELAPSED%60)))"

if [ -n "$SUMMARIES" ]; then
    echo ""
    echo "============================== SUMMARY =============================="
    printf '%s' "$SUMMARIES"
    echo "Total time: ${ELAPSED_FMT}"
    echo "======================================================================"
fi | tee -a "$LOG_FILE"

# Extract compiler output sections into a separate file.
COMPILER_LOG="${LOG_FILE%.log}-compiler.log"
awk '
    /============================= C2-compiled nmethod/ { in_section=1 }
    in_section { print }
    /\[\/Disassembly\]/ { in_section=0 }
' "$LOG_FILE" > "$COMPILER_LOG"

if [ -s "$COMPILER_LOG" ]; then
    echo "Compiler log saved to $COMPILER_LOG"
else
    rm -f "$COMPILER_LOG"
fi
echo "Log saved to $LOG_FILE"
