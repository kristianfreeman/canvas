#!/usr/bin/env bash
# Benchmark the canvas CLI and server with hyperfine.
#
#   scripts/bench.sh [--check] [--only a,b,...]
#
# Environment:
#   CANVAS_BIN         the C CLI to measure (default: canvas on PATH, which
#                      install.sh links to Canvas.app/Contents/MacOS/canvas)
#   CANVAS_HOME        the server's home; must match the server CANVAS_BIN
#                      reaches. Leave unset for the installed app, which
#                      launchd starts without your environment.
#   BENCH_RUNS         timed runs per scenario (default 30)
#   BENCH_COLD_RUNS    runs for cold_show (default 10)
#   BENCH_TRACE_RUNS   --trace runs for the stage breakdown (default 20)
#   BENCH_OUT          results file (default bench/results/latest.json)
#
# Scenarios (each a metric in the results):
#   exec_floor     an empty ad hoc signed binary: the launch tax every
#                  non-Apple process pays here, so no CLI can beat it
#   cli_help       process startup, no server contact
#   ping           round trip to a warm server
#   show_new       new panel (plain Markdown) on a warm server
#   show_new_code  new panel with two highlighted code blocks
#   show_new_tsx   new panel rendering a small TSX component
#   show_replace   same id, already visible
#   hide           hide one visible panel
#   toggle_pair    toggle on, then off (includes one /bin/sh startup)
#   cold_show      server stopped first, so it includes the server launch
#                  (by launchd on the first connection when the agent is
#                  loaded)
#   mem_warm       server + its WebKit processes, warm page, no panels
#   mem_one_panel  the same with one panel open
#   mem_trimmed    a separate server (same binary, temp home) after its
#                  warm page was dropped for idleness (idle_minutes = 1)
# Server-side metrics, accept to reply (or another stage) in the server's
# trace records for the runs above:
#   server_show_new, server_show_new_visible, server_show_new_painted,
#   server_show_new_code, server_show_replace, server_hide
# plus a stage breakdown of show_new from --trace (median per stage).
#
# Memory: WebKit's helper processes (com.apple.WebKit.WebContent,
# .Networking, .GPU) are XPC services parented to launchd, so they're found
# by their responsible pid instead (see bench/bench.py). The figure is the
# sum of footprint's phys_footprint over the server and those processes.
#
# --check compares the results with bench/budgets.json and exits 1 listing
# regressions.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

bin="${CANVAS_BIN:-canvas}"
runs="${BENCH_RUNS:-30}"
cold_runs="${BENCH_COLD_RUNS:-10}"
trace_runs="${BENCH_TRACE_RUNS:-20}"
out="${BENCH_OUT:-bench/results/latest.json}"
home="${CANVAS_HOME:-$HOME/Library/Application Support/Canvas}"
fixtures="$root/bench/fixtures"
raw="$root/bench/results/raw"
self="$root/scripts/bench.sh"

# Each scenario is killed (with its process group) if it runs this long.
scenario_limit=300

server_pid() { lsof -t "$home/server.lock" 2>/dev/null | head -1 || true; }

# Waits for the process itself to exit: under launchd a ping would just
# start a new server.
stop_server() {
  local pid
  pid="$(server_pid)"
  [[ -z "$pid" ]] && return 0
  kill "$pid" 2>/dev/null
  for _ in $(seq 50); do
    kill -0 "$pid" 2>/dev/null || return 0
    sleep 0.1
  done
  echo "bench: server did not stop" >&2
  return 1
}

# Close every panel and give WebKit a moment to tear the pages down.
reset_panels() {
  "$bin" hide --all
  sleep "${1:-0.3}"
}

warm_server() {
  "$bin" show "$fixtures/note.md" --id bench-warm >/dev/null
  reset_panels
}

# Hidden entry points for hyperfine --prepare.
case "${1:-}" in
  __stop) stop_server; exit ;;
  __reset) reset_panels; exit ;;
esac

check=0
only=""
while (($#)); do
  case "$1" in
    --check) check=1 ;;
    --only) only="$2"; shift ;;
    *) echo "bench: unknown argument: $1" >&2; exit 64 ;;
  esac
  shift
done

wanted() { [[ -z "$only" || ",$only," == *",$1,"* ]]; }

with_timeout() {
  perl -e '
    my $limit = shift;
    my $pid = fork() // die "fork: $!";
    if ($pid == 0) { setpgrp(0, 0); exec(@ARGV) or die "exec $ARGV[0]: $!"; }
    $SIG{ALRM} = sub {
      print STDERR "bench: $ARGV[0] still running after ${limit}s; killed\n";
      kill("TERM", -$pid); sleep(2); kill("KILL", -$pid); exit(124);
    };
    alarm($limit);
    waitpid($pid, 0);
    exit($? & 127 ? 128 + ($? & 127) : $? >> 8);
  ' "$scenario_limit" "$@"
}

q() { printf '%q' "$1"; }

# measure NAME RUNS WARMUP [hyperfine options...] COMMAND
measure() {
  local name="$1" count="$2" warmup="$3"
  shift 3
  wanted "$name" || return 0
  echo "bench: $name" >&2
  with_timeout hyperfine -N --style none --warmup "$warmup" --runs "$count" \
    --export-json "$raw/time_$name.json" "$@"
}

# The server's trace log holds the last 256 requests, so it's read after
# each scenario it covers.
server_records() {
  wanted "$1" || return 0
  python3 bench/bench.py trace-records "$home/canvas.sock" "$raw/server_$1.json"
}

exec_floor_binary() {
  local floor=/tmp/canvas-exec-floor
  printf 'int main(void) { return 0; }\n' | clang -O2 -x c - -o "$floor"
  codesign -s - -f "$floor" 2>/dev/null
  echo "$floor"
}

trace_breakdown() {
  wanted trace || return 0
  echo "bench: trace ($trace_runs runs)" >&2
  if ! "$bin" show "$fixtures/note.md" --id bench-trace-probe --trace 2>/dev/null; then
    echo "bench: $bin has no --trace; skipping the stage breakdown" >&2
    return 0
  fi
  reset_panels
  for i in $(seq "$trace_runs"); do
    "$bin" show "$fixtures/note.md" --id "bench-trace-$i" --trace 2>>"$raw/trace_lines.ndjson"
    reset_panels
  done
  python3 bench/bench.py trace-records "$home/canvas.sock" "$raw/trace_records.json"
}

memory() {
  wanted memory || return 0
  echo "bench: memory" >&2
  reset_panels 3
  python3 bench/bench.py memory "$(server_pid)" "$raw/mem_warm.json"
  "$bin" show "$fixtures/note.md" --id bench-memory
  sleep 2
  python3 bench/bench.py memory "$(server_pid)" "$raw/mem_one_panel.json"
  reset_panels
}

# A second server from the same install, in a temp home with a one-minute
# idle trim, measured once its warm page is gone.
memory_trimmed() {
  wanted memory || return 0
  local server tmp pid
  server="$(dirname "$resolved")/canvas-server"
  if [[ ! -x "$server" ]]; then
    echo "bench: no canvas-server next to $resolved; skipping mem_trimmed" >&2
    return 0
  fi
  echo "bench: memory after the idle trim (about 70 s)" >&2
  tmp="$(mktemp -d /tmp/canvas-trim.XXXX)"
  printf 'idle_minutes = 1\n' > "$tmp/config.toml"
  CANVAS_HOME="$tmp" CANVAS_CONFIG="$tmp/config.toml" CANVAS_SERVER="$server" \
    "$bin" show "$fixtures/note.md" --id bench-trim
  CANVAS_HOME="$tmp" "$bin" hide --all
  sleep 70
  pid="$(lsof -t "$tmp/server.lock" 2>/dev/null | head -1 || true)"
  if [[ -n "$pid" ]]; then
    python3 bench/bench.py memory "$pid" "$raw/mem_trimmed.json"
    kill "$pid" 2>/dev/null || true
  fi
  sleep 0.5
  rm -rf "$tmp"
}

rm -rf "$raw"
mkdir -p "$raw" "$(dirname "$out")"

b="$(q "$bin")"
note="$(q "$fixtures/note.md")"
reset="$(q "$self") __reset"
resolved="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$(command -v "$bin" || echo "$bin")")"

if wanted exec_floor; then
  measure exec_floor "$runs" 3 "$(q "$(exec_floor_binary)")"
fi
measure cli_help "$runs" 3 "$b help"
warm_server
measure ping "$runs" 3 "$b ping"
measure show_new "$runs" 2 --prepare "$reset" "$b show $note --id bench-new"
server_records show_new
measure show_new_code "$runs" 2 --prepare "$reset" "$b show $(q "$fixtures/code.md") --id bench-code"
server_records show_new_code
measure show_new_tsx "$runs" 2 --prepare "$reset" "$b show $(q "$fixtures/hello.tsx") --id bench-tsx"
"$bin" show "$fixtures/note.md" --id bench-replace
measure show_replace "$runs" 2 "$b show $note --id bench-replace"
server_records show_replace
reset_panels
measure hide "$runs" 2 --prepare "$b show $note --id bench-hide" "$b hide --id bench-hide"
server_records hide
reset_panels
measure toggle_pair "$runs" 2 --prepare "$reset" \
  "/bin/sh -c '$b toggle $note --id bench-toggle --no-focus && $b toggle $note --id bench-toggle --no-focus'"
trace_breakdown
memory
measure cold_show "$cold_runs" 1 --prepare "$(q "$self") __stop" "$b show $note --id bench-cold"
reset_panels
memory_trimmed

tilde='~'
python3 bench/bench.py summarize "$raw" "$out" \
  "bin=${bin/#"$HOME"/$tilde}" "resolved=${resolved/#"$HOME"/$tilde}" \
  "home=$home" "date=$(date -u +%Y-%m-%dT%H:%M:%SZ)" "git=$(git rev-parse --short HEAD 2>/dev/null || echo none)" \
  "macos=$(sw_vers -productVersion)" "runs=$runs"

if ((check)); then
  python3 bench/bench.py check "$out" bench/budgets.json
fi
