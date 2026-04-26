#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    cat <<EOF
Usage: $0 <log-file> [compiler-log-file]

Generates an HTML report from a run-benchmarks.sh log file.
The compiler log is auto-detected as <log-file-prefix>-compiler.log if not specified.

Examples:
  $0 logs/AsciiCheckerBenchmark-20260425-111233.log
  $0 logs/AsciiCheckerBenchmark-20260425-111233.log logs/AsciiCheckerBenchmark-20260425-111233-compiler.log
EOF
}

[ $# -lt 1 ] && { usage; exit 1; }

LOG_FILE="$1"
[ ! -f "$LOG_FILE" ] && { echo "Log file not found: $LOG_FILE" >&2; exit 1; }

COMPILER_LOG="${LOG_FILE%.log}-compiler.log"
[ $# -ge 2 ] && COMPILER_LOG="$2"

REPORT_FILE="${LOG_FILE%.log}.html"

# ---------------------------------------------------------------------------
# Parse log file
# ---------------------------------------------------------------------------

COMMAND_LINE="$(head -1 "$LOG_FILE")"
CPU_LINE="$(grep '^CPU:' "$LOG_FILE" || echo '')"
CACHE_LINE="$(grep '^Cache:' "$LOG_FILE" || echo '')"

# Extract JMH run metadata (VM version lines)
JMH_META="$(grep '^# ' "$LOG_FILE" | grep -v 'Run progress\|Fork:\|Warmup\|Measurement\|Benchmark:\|Parameters\|Benchmark mode\|Threads' | sort -u || true)"

# Extract results table from SUMMARY section (header + data lines)
RESULTS="$(awk '/^====+ SUMMARY ====+/{found=1; next} found && /^====+/{found=0} found{print}' "$LOG_FILE")"

# Extract xctrace profiler sections: lines between "Hottest code regions" and next blank separator
XCTRACE="$(awk '
    /Hottest code regions/ { in_section=1 }
    in_section { print }
    in_section && /^$/ { blank++; if (blank>=2) { in_section=0; blank=0 } }
' "$LOG_FILE" || true)"

HAS_COMPILER=0
[ -f "$COMPILER_LOG" ] && [ -s "$COMPILER_LOG" ] && HAS_COMPILER=1

HAS_XCTRACE=0
[ -n "$XCTRACE" ] && HAS_XCTRACE=1

# ---------------------------------------------------------------------------
# Helper: escape HTML
# ---------------------------------------------------------------------------
html_escape() {
    sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'
}

# ---------------------------------------------------------------------------
# Build results table rows
# ---------------------------------------------------------------------------
# Input lines look like:
#   === JDK 21 ===
#   Benchmark   (impl)  (stringType)  Mode  Cnt  Score  Error  Units
#   Foo.bar      swar    long ASCII   avgt    5   53.1 ± 8.5  ns/op
#   Total time: 00:01:23

build_results_html() {
    # JMH result lines use "avgt" (or thrpt/sample/ss) as a fixed mode column.
    # Split each line on that anchor: everything left is benchmark+params,
    # everything right is Mode Cnt Score Error Units.
    # The header line tells us how many param columns precede Mode.
    awk '
    BEGIN { jdk=""; header_printed=0; nparams=0 }

    /^=== JDK / {
        jdk=$0; gsub(/^=== |===$/,"",jdk); header_printed=0; next
    }

    /^Total time:/ {
        print "<tr class=\"total\"><td colspan=\"99\"><strong>" $0 "</strong></td></tr>"
        next
    }

    /^Benchmark/ {
        if (header_printed) { next }
        if (jdk != "") print "<tr class=\"jdk-header\"><th colspan=\"99\">" jdk "</th></tr>"
        # Count param columns: headers wrapped in parentheses between Benchmark and Mode
        nparams = 0
        for (i = 2; i <= NF; i++) {
            if ($i ~ /^\(/) nparams++
            else break
        }
        printf "<tr>"
        for (i = 1; i <= NF; i++) printf "<th>%s</th>", $i
        print "</tr>"
        header_printed = 1
        next
    }

    header_printed && / avgt | thrpt | sample | ss / {
        # Find the position of the mode word using index()
        for (mode in _m) delete _m[mode]
        _modes[1]=" avgt "; _modes[2]=" thrpt "; _modes[3]=" sample "; _modes[4]=" ss "
        mpos = 0
        for (mi = 1; mi <= 4; mi++) {
            p = index($0, _modes[mi])
            if (p > 0) { mpos = p; mword = _modes[mi]; break }
        }
        if (mpos == 0) { next }

        prefix = substr($0, 1, mpos - 1)
        suffix = substr($0, mpos + 1)   # "avgt    5  206.076 ± 89.137  ns/op"

        n = split(suffix, tail)

        gsub(/^[[:space:]]+|[[:space:]]+$/, "", prefix)
        np = split(prefix, pre, /  +/)

        printf "<tr>"
        printf "<td>%s</td>", pre[1]
        for (p = 2; p <= np; p++) {
            val = pre[p]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
            printf "<td>%s</td>", val
        }
        for (t = 1; t <= n; t++) {
            if (tail[t] == "±") continue
            printf "<td>%s</td>", tail[t]
        }
        print "</tr>"
    }
    ' <<EOF
$RESULTS
EOF
}

# ---------------------------------------------------------------------------
# Write HTML
# ---------------------------------------------------------------------------
cat > "$REPORT_FILE" <<HTMLEOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Benchmark Report — $(basename "$LOG_FILE" .log)</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: system-ui, sans-serif; background: #f5f5f5; color: #222; }
  h1 { padding: 20px 24px 8px; font-size: 1.3em; }
  .subtitle { padding: 0 24px 16px; color: #666; font-size: 0.85em; font-family: monospace; }

  /* Tabs */
  .tabs { display: flex; gap: 4px; padding: 0 24px; border-bottom: 2px solid #ddd; }
  .tab-btn {
    padding: 8px 18px; border: none; background: #e0e0e0; cursor: pointer;
    border-radius: 6px 6px 0 0; font-size: 0.9em; color: #444;
    border-bottom: 2px solid transparent; margin-bottom: -2px;
  }
  .tab-btn.active { background: #fff; border-color: #4a90d9; color: #1a1a1a; font-weight: 600; }
  .tab-btn:hover:not(.active) { background: #d0d8e8; }

  .tab-content { display: none; padding: 24px; }
  .tab-content.active { display: block; }

  /* Results table */
  table { border-collapse: collapse; width: 100%; background: #fff;
          border-radius: 6px; overflow: hidden; box-shadow: 0 1px 4px rgba(0,0,0,.1); }
  th, td { padding: 8px 14px; text-align: left; border-bottom: 1px solid #eee; font-size: 0.88em; }
  th { background: #4a90d9; color: #fff; font-weight: 600; }
  tr.jdk-header th { background: #2c5f8a; font-size: 0.95em; letter-spacing: .03em; }
  tr.total td { background: #f0f6ff; color: #555; font-size: 0.85em; }
  tr:hover td { background: #f7faff; }
  td:nth-child(n+4) { text-align: right; font-family: monospace; }

  /* CPU info */
  .info-block { background: #fff; border-radius: 6px; padding: 20px 24px;
                box-shadow: 0 1px 4px rgba(0,0,0,.1); max-width: 700px; }
  .info-block dl { display: grid; grid-template-columns: 140px 1fr; gap: 8px 16px; margin-top: 12px; }
  .info-block dt { font-weight: 600; color: #555; font-size: 0.88em; }
  .info-block dd { font-family: monospace; font-size: 0.88em; }

  /* Assembly / xctrace */
  pre { background: #1e1e1e; color: #d4d4d4; padding: 16px 20px; border-radius: 0 0 6px 6px;
        font-size: 0.78em; line-height: 1.55; overflow-x: auto;
        white-space: pre; box-shadow: 0 1px 4px rgba(0,0,0,.2); margin: 0; }
  details { margin-bottom: 8px; border-radius: 6px;
            box-shadow: 0 1px 4px rgba(0,0,0,.15); overflow: hidden; }
  summary {
    background: #2c3e50; color: #cdd9e5; padding: 10px 16px;
    cursor: pointer; font-family: monospace; font-size: 0.88em;
    list-style: none; display: flex; align-items: center; gap: 8px;
    user-select: none;
  }
  summary::before { content: "▶"; font-size: 0.75em; transition: transform .15s; }
  details[open] summary::before { transform: rotate(90deg); }
  summary:hover { background: #3a5068; }
  .section-header { font-weight: 700; color: #9cdcfe; }
</style>
</head>
<body>

<h1>Benchmark Report</h1>
<div class="subtitle">$(echo "$COMMAND_LINE" | html_escape)</div>

<div class="tabs">
  <button class="tab-btn active" onclick="showTab('results')">Results</button>
  <button class="tab-btn" onclick="showTab('cpu')">CPU Info</button>
$([ "$HAS_COMPILER" -eq 1 ] && echo '  <button class="tab-btn" onclick="showTab('"'"'assembly'"'"')">Assembly</button>')
$([ "$HAS_XCTRACE" -eq 1 ] && echo '  <button class="tab-btn" onclick="showTab('"'"'xctrace'"'"')">XCTrace Profile</button>')
</div>

<!-- Results tab -->
<div id="tab-results" class="tab-content active">
  <table>
    <tbody>
$(build_results_html)
    </tbody>
  </table>
</div>

<!-- CPU tab -->
<div id="tab-cpu" class="tab-content">
  <div class="info-block">
    <h2>Hardware</h2>
    <dl>
      <dt>CPU</dt><dd>$(echo "$CPU_LINE" | sed 's/^CPU: //' | html_escape)</dd>
      <dt>Cache</dt><dd>$(echo "$CACHE_LINE" | sed 's/^Cache: //' | html_escape)</dd>
    </dl>
    <h2 style="margin-top:20px">JVM</h2>
    <dl>
$(echo "$JMH_META" | html_escape | awk -F': ' 'NF>=2 { key=$1; val=$0; sub(/^[^:]+: /,"",val); gsub(/^# /,"",key); printf "      <dt>%s</dt><dd>%s</dd>\n", key, val }')
    </dl>
  </div>
</div>

HTMLEOF

# Assembly tab (optional)
if [ "$HAS_COMPILER" -eq 1 ]; then
    {
        echo '<!-- Assembly tab -->'
        echo '<div id="tab-assembly" class="tab-content">'
        # Split into collapsible <details> sections, one per compiled method.
        # Each section starts with "===...C2/C1-compiled nmethod...===" and
        # the method name is extracted from the following "Compiled method" line.
        awk '
        BEGIN { in_section=0; buf=""; method=""; tier=""; ndups=0 }

        /^=====.*compiled nmethod/ {
            if (in_section && buf != "") {
                key = tier SUBSEP method
                if (seen_key[key] != "" && seen_key[key] == buf) {
                    # identical content already emitted — skip
                } else {
                    seen_key[key] = buf
                    print "<details><summary>" tier " &mdash; " method "</summary>"
                    print "<pre>" buf "</pre></details>"
                }
            }
            in_section=1; buf=""; method="unknown"; tier="nmethod"
            if ($0 ~ /C2/) tier="C2"
            else if ($0 ~ /C1/) tier="C1"
            next
        }

        in_section && /^Compiled method/ {
            # detect OSR: presence of "%" flag and "@ N" offset
            osr = ($0 ~ / % / && $0 ~ / @ [0-9]/) ? " (OSR)" : ""
            line=$0
            sub(/ @ [0-9].*$/, "", line)
            sub(/\([0-9]* bytes\).*$/, "", line)
            gsub(/[[:space:]]+$/, "", line)   # strip trailing whitespace
            n=split(line, parts, /[[:space:]]+/)
            method=parts[n] osr
            buf = buf $0 "\n"
            next
        }

        in_section {
            buf = buf $0 "\n"
        }

        END {
            if (in_section && buf != "") {
                key = tier SUBSEP method
                if (seen_key[key] != "" && seen_key[key] == buf) {
                    # duplicate — skip
                } else {
                    print "<details><summary>" tier " &mdash; " method "</summary>"
                    print "<pre>" buf "</pre></details>"
                }
            }
        }
        ' "$COMPILER_LOG" | html_escape | \
            # un-escape the <details>/<summary>/<pre> tags we emitted above
            sed \
                -e 's/&lt;details&gt;/<details>/g' \
                -e 's/&lt;\/details&gt;/<\/details>/g' \
                -e 's/&lt;summary&gt;/<summary>/g' \
                -e 's/&lt;\/summary&gt;/<\/summary>/g' \
                -e 's/&lt;pre&gt;/<pre>/g' \
                -e 's/&lt;\/pre&gt;/<\/pre>/g' \
                -e 's/&lt;details open&gt;/<details open>/g' \
                -e 's/&amp;mdash;/\&mdash;/g'
        echo '</div>'
    } >> "$REPORT_FILE"
fi

# XCTrace tab (optional)
if [ "$HAS_XCTRACE" -eq 1 ]; then
    cat >> "$REPORT_FILE" <<HTMLEOF
<!-- XCTrace tab -->
<div id="tab-xctrace" class="tab-content">
  <pre>$(echo "$XCTRACE" | html_escape)</pre>
</div>

HTMLEOF
fi

cat >> "$REPORT_FILE" <<'HTMLEOF'
<script>
function showTab(name) {
    document.querySelectorAll('.tab-content').forEach(el => el.classList.remove('active'));
    document.querySelectorAll('.tab-btn').forEach(el => el.classList.remove('active'));
    document.getElementById('tab-' + name).classList.add('active');
    event.target.classList.add('active');
}
</script>
</body>
</html>
HTMLEOF

echo "Report saved to $REPORT_FILE"
