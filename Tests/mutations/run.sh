#!/usr/bin/env bash
# Mutation testing. Each Tests/mutations/*.patch plants one realistic bug;
# its first line says which. For each patch this applies it to a copy of the
# working tree, runs the default suites there (scripts/test.sh: no UI, no
# windows) and expects them to fail. Exits 1 if a mutant survives, a patch
# no longer applies or builds, or the unmutated copy fails its own tests.
#
#   Tests/mutations/run.sh [PATCH...]   default: every patch
#
# The copy is .build/mutations/tree, synced from the working tree on every
# run. It keeps its own .build, so a mutant only rebuilds what it touches.
# The working tree itself is never modified. Logs: .build/mutations/logs.
set -uo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
tree="$root/.build/mutations/tree"
logs="$root/.build/mutations/logs"
# The copy sits inside this repository, where `git apply` would take patch
# paths as relative to the repository root and skip them all.
export GIT_CEILING_DIRECTORIES="$root/.build/mutations"

patches=("$@")
if ((${#patches[@]} == 0)); then patches=("$root"/Tests/mutations/*.patch); fi

sync_tree() {
  mkdir -p "$tree" "$logs"
  rsync -a --delete \
    --exclude /.build --exclude /.git --exclude /.swiftpm --exclude /web/node_modules --exclude /tmp \
    "$root/" "$tree/"
  ln -sfn "$root/web/node_modules" "$tree/web/node_modules"
}

# web/dist is build output, so the copy builds its own from its sources.
build_web() {
  (cd "$tree/web" && bun run build)
}

touches_web() {
  grep -q '^+++ b/web/' "$1"
}

# 0: the suites pass, 1: they fail, 2: the tree doesn't build.
run_suites() {
  (cd "$tree" && scripts/test.sh --build-only) || return 2
  (cd "$tree" && CANVAS_TEST_TIMEOUT=60 scripts/test.sh) && return 0
  return 1
}

# Prints killed, survived or an error, and leaves the tree unmutated.
try_mutant() {
  local patch="$1" log="$2"
  (cd "$tree" && git apply "$patch") >"$log" 2>&1 || { echo "does not apply"; return; }
  local outcome
  if touches_web "$patch" && ! build_web >>"$log" 2>&1; then
    outcome="does not build"
  else
    run_suites >>"$log" 2>&1
    case $? in
      0) outcome="survived" ;;
      1) outcome="killed" ;;
      *) outcome="does not build" ;;
    esac
  fi
  (cd "$tree" && git apply -R "$patch") >>"$log" 2>&1 || outcome="$outcome; revert failed"
  if touches_web "$patch"; then build_web >>"$log" 2>&1 || outcome="$outcome; web rebuild failed"; fi
  echo "$outcome"
}

echo "mutations: syncing $tree"
sync_tree
if ! build_web >"$logs/baseline.log" 2>&1 || ! run_suites >>"$logs/baseline.log" 2>&1; then
  echo "mutations: the unmutated copy fails its tests; see $logs/baseline.log" >&2
  exit 1
fi

failed=0
for patch in "${patches[@]}"; do
  name="$(basename "$patch" .patch)"
  log="$logs/$name.log"
  started=$SECONDS
  outcome="$(try_mutant "$patch" "$log")"
  printf '%-28s %-16s %3ss  %s\n' "$name" "$outcome" $((SECONDS - started)) "$(head -n 1 "$patch")"
  [[ "$outcome" == killed ]] || { failed=1; echo "  log: $log"; }
done

if ((failed)); then
  echo "mutations: not every mutant was killed" >&2
  exit 1
fi
echo "mutations: all ${#patches[@]} killed"
