#!/usr/bin/env bash
# Lint Swift (SwiftLint), TypeScript (Oxlint with complexity limits and the
# local cognitive complexity rule) and the C CLI (clang-tidy, config in
# cli/.clang-tidy), then typecheck. Any finding fails.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

# Without Xcode, SwiftLint needs to be told where sourcekitd lives.
export TOOLCHAIN_DIR="${TOOLCHAIN_DIR:-$(xcode-select -p)}"

# Apple's Command Line Tools don't ship clang-tidy; Homebrew's llvm does.
clang_tidy=/opt/homebrew/opt/llvm/bin/clang-tidy
if [[ ! -x $clang_tidy ]]; then
  echo "lint: installing llvm for clang-tidy" >&2
  brew install llvm >&2
fi

status=0
swiftlint lint --quiet || status=1
web/node_modules/.bin/oxlint -c web/.oxlintrc.json --deny-warnings web examples || status=1
"$clang_tidy" --quiet cli/*.c -- -std=c17 -Icli -isysroot "$(xcrun --show-sdk-path)" 2>/dev/null || status=1
(cd web && bun run typecheck) || status=1
exit $status
