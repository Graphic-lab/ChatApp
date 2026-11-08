#!/usr/bin/env bash
# Verification gates: database rules → iOS build + unit tests (when a simulator exists).
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)

echo "== 1/2 Databaseregels (PGlite)"
(cd "$root/supabase/tests" && npm test 2>&1 | grep -E "^# (tests|pass|fail)")

echo "== 2/2 iOS build en unit tests"
(cd "$root/ios" && xcodegen generate --quiet)
sim=$(xcrun simctl list devices available 2>/dev/null | grep -Eo "iPhone [^(]+\(([0-9A-F-]{36})\)" | head -1 | grep -Eo "[0-9A-F-]{36}" || true)
if [ -z "$sim" ]; then
  echo "Geen iOS-simulator beschikbaar. Installeer: xcodebuild -downloadPlatform iOS"
  exit 1
fi
xcodebuild test \
  -project "$root/ios/HeartToHeart.xcodeproj" \
  -scheme HeartToHeart \
  -destination "id=$sim" \
  CODE_SIGNING_ALLOWED=NO \
  | grep -E "Test Suite '.*(passed|failed)|error:|\*\* (TEST|BUILD) (SUCCEEDED|FAILED)" || true
