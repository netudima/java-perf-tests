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

BUILD_JAVA_HOME="$JDK_HOME_21"

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
    echo "Building benchmarks with JDK 21..."
    mvn -f "$SCRIPT_DIR/pom.xml" clean package -q
fi

BENCHMARK_NAME="${1:-all}"
LOG_FILE="$SCRIPT_DIR/logs/${BENCHMARK_NAME}-$(date '+%Y%m%d-%H%M%S').log"
mkdir -p "$SCRIPT_DIR/logs"
echo "run-benchmarks.sh $ORIGINAL_ARGS" | tee "$LOG_FILE"

CPU_MODEL="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo 'unknown')"
CPU_CORES="$(sysctl -n hw.logicalcpu 2>/dev/null || nproc 2>/dev/null || echo 'unknown')"

fmt_bytes() {
    val="$1"
    if [ "$val" -ge 1048576 ] 2>/dev/null; then
        printf '%dMB' $((val / 1048576))
    elif [ "$val" -ge 1024 ] 2>/dev/null; then
        printf '%dKB' $((val / 1024))
    else
        printf '%dB' "$val"
    fi
}

L1I="$(sysctl -n hw.l1icachesize 2>/dev/null || grep -m1 'cache size' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo '')"
L1D="$(sysctl -n hw.l1dcachesize 2>/dev/null || echo '')"
L2="$(sysctl -n hw.l2cachesize 2>/dev/null || echo '')"
L3="$(sysctl -n hw.l3cachesize 2>/dev/null || echo '')"
CACHE_LINE="$(sysctl -n hw.cachelinesize 2>/dev/null || getconf LEVEL1_DCACHE_LINESIZE 2>/dev/null || echo '')"

CACHE_INFO=""
[ -n "$L1I" ] && CACHE_INFO="${CACHE_INFO} L1i=$(fmt_bytes "$L1I")"
[ -n "$L1D" ] && CACHE_INFO="${CACHE_INFO} L1d=$(fmt_bytes "$L1D")"
[ -n "$L2"  ] && CACHE_INFO="${CACHE_INFO} L2=$(fmt_bytes "$L2")"
[ -n "$L3"  ] && CACHE_INFO="${CACHE_INFO} L3=$(fmt_bytes "$L3")"
[ -n "$CACHE_LINE" ] && CACHE_INFO="${CACHE_INFO} line=${CACHE_LINE}B"

echo "CPU: ${CPU_MODEL} (${CPU_CORES} logical cores)" | tee -a "$LOG_FILE"
echo "Cache:${CACHE_INFO}" | tee -a "$LOG_FILE"

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

    # jdk.incubator.vector is an incubator module on JDK 17/21; pass it to forked JVMs.
    # On JDK 25 it is already part of the default module graph, the flag is still accepted.
    VECTOR_ARG="-jvmArgsAppend --add-modules=jdk.incubator.vector"

    tmpfile="$(mktemp)"
    if [ -n "$PROFILER" ]; then
        "$java_bin" -jar "$JAR" -prof "$PROFILER" $VECTOR_ARG "$@" | tee -a "$LOG_FILE" | tee "$tmpfile"
    else
        "$java_bin" -jar "$JAR" $VECTOR_ARG "$@" | tee -a "$LOG_FILE" | tee "$tmpfile"
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
