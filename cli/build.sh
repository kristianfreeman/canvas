#!/usr/bin/env bash
# Build the canvas CLI.
#   cli/build.sh [OUT]          release build, default .build/cli/canvas
#   cli/build.sh --debug [OUT]  -O0 with ASan and UBSan, default .build/cli/canvas-debug
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

debug=0
if [[ "${1:-}" == "--debug" ]]; then
  debug=1
  shift
fi

flags=(-std=c17 -Wall -Wextra -Wpedantic -Werror -Wshadow -Wconversion)
if [[ $debug == 1 ]]; then
  out="${1:-.build/cli/canvas-debug}"
  flags+=(-O0 -g -fsanitize=address,undefined -fno-omit-frame-pointer)
else
  out="${1:-.build/cli/canvas}"
  flags+=(-O2 -Wl,-dead_strip)
fi

mkdir -p "$(dirname "$out")"
clang "${flags[@]}" -Icli cli/*.c -o "$out"
codesign -s - -f "$out" 2>/dev/null
echo "$out"
