#!/usr/bin/env bash
# Run the test suites. Any failure fails the script.
#
#   scripts/test.sh               Swift (unit, windowless page bridge, CLI
#                                 against a recording server) and bun tests.
#                                 Nothing appears on screen.
#   scripts/test.sh --ui          only the on-screen suites: `painted`, the
#                                 golden snapshots in Tests/golden
#                                 (UPDATE_GOLDENS=1 rewrites them) and the CLI
#                                 contract against a dev server.
#   scripts/test.sh --mutations   the default run, then every mutant in
#                                 Tests/mutations (Tests/mutations/run.sh).
#   scripts/test.sh --build-only  build what the suites need, run nothing.
#   scripts/test.sh -- ARGS       extra arguments for `swift test`
#
# CANVAS_TEST_TIMEOUT (seconds, default 90) caps each suite's run, not the
# build. A suite that runs over is killed with its whole process group.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

mutations=0
ui=0
build_only=0
swift_args=()
while (($#)); do
  case "$1" in
    --mutations) mutations=1 ;;
    --ui) ui=1 ;;
    --build-only) build_only=1 ;;
    --) shift; swift_args+=("$@"); break ;;
    *) echo "test.sh: unknown argument: $1" >&2; exit 64 ;;
  esac
  shift
done

limit="${CANVAS_TEST_TIMEOUT:-90}"
ui_suites='BridgeTests\.UI'

# The Command Line Tools ship swift-testing outside SwiftPM's default search
# paths, so point the compiler, linker and runtime at it.
clt="$(xcode-select -p)"
frameworks="$clt/Library/Developer/Frameworks"
testing_libs="$clt/Library/Developer/usr/lib"
testing_flags=()
if [[ -d "$frameworks/Testing.framework" ]]; then
  testing_flags=(
    -Xswiftc -F -Xswiftc "$frameworks"
    -Xlinker -F -Xlinker "$frameworks"
    -Xlinker -rpath -Xlinker "$frameworks"
    -Xlinker -rpath -Xlinker "$testing_libs"
  )
fi

# Runs a command in its own process group and kills the group if it is
# still running after $limit seconds (exit 124).
with_timeout() {
  perl -e '
    my $limit = shift;
    my $pid = fork() // die "fork: $!";
    if ($pid == 0) { setpgrp(0, 0); exec(@ARGV) or die "exec $ARGV[0]: $!"; }
    $SIG{ALRM} = sub {
      print STDERR "test.sh: $ARGV[0] still running after ${limit}s; killed\n";
      kill("TERM", -$pid); sleep(2); kill("KILL", -$pid); exit(124);
    };
    alarm($limit);
    waitpid($pid, 0);
    exit($? & 127 ? 128 + ($? & 127) : $? >> 8);
  ' "$limit" "$@"
}

# The bridge and native tests load web/dist and the CLI tests run
# .build/cli/canvas.
web_dist_stale() {
  local out
  for out in web/dist/index.html web/dist/native.js; do
    [[ -f $out ]] || return 0
    [[ -n "$(find web/src web/native web/build.ts web/package.json -newer "$out" -print -quit)" ]] && return 0
  done
  return 1
}

build_deps() {
  if web_dist_stale; then
    (cd web && bun run build) || return 1
  fi
  cli/build.sh >/dev/null || return 1
  swift build --build-tests "${testing_flags[@]}"
}

run_swift() {
  with_timeout swift test --skip-build --no-parallel "${testing_flags[@]}" --skip "$ui_suites" \
    ${swift_args[@]+"${swift_args[@]}"}
}

run_web() {
  if [[ -n "$(find web -name '*.test.ts*' -not -path '*/node_modules/*' -print -quit 2>/dev/null)" ]]; then
    (cd web && with_timeout bun test)
  fi
}

run_ui() {
  with_timeout env CANVAS_UI_TESTS=1 swift test --skip-build --no-parallel "${testing_flags[@]}" \
    --filter "$ui_suites" ${swift_args[@]+"${swift_args[@]}"}
}

build_deps || exit 1
if ((build_only)); then exit 0; fi
if ((ui)); then
  run_ui
  exit
fi

status=0
run_swift || status=1
run_web || status=1
if ((mutations)); then Tests/mutations/run.sh || status=1; fi
exit $status
