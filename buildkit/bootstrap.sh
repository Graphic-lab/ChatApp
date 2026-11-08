#!/usr/bin/env bash
# One-time setup on a new dev machine. Safe to re-run.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)

"$root/buildkit/check-env.sh" || { echo "Los eerst de ✗-punten op."; exit 1; }

if [ ! -f "$root/ios/Config/Secrets.xcconfig" ]; then
  cp "$root/ios/Config/Secrets.example.xcconfig" "$root/ios/Config/Secrets.xcconfig"
  echo "→ ios/Config/Secrets.xcconfig aangemaakt. Vul je Supabase URL, sleutel en Team ID in."
fi

echo "→ Xcode-project genereren"
(cd "$root/ios" && xcodegen generate --quiet)

echo "→ Swift packages ophalen"
xcodebuild -resolvePackageDependencies -project "$root/ios/HeartToHeart.xcodeproj" -scheme HeartToHeart >/dev/null

echo "→ Databasetests installeren"
(cd "$root/supabase/tests" && npm install --silent)

echo "Klaar. Open ios/HeartToHeart.xcodeproj of draai buildkit/verify.sh"
