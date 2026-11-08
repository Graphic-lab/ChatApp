#!/usr/bin/env bash
# Checks the dev machine. Exit code 1 when a required tool is missing.
set -u
fail=0
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; fail=1; }

echo "Heart to Heart — omgevingscheck"

macos=$(sw_vers -productVersion)
major=${macos%%.*}
if [ "$major" -ge 26 ] || { [ "$major" -eq 15 ] && [ "$(echo "$macos" | cut -d. -f2)" -ge 6 ]; }; then
  ok "macOS $macos (Xcode 26+ mogelijk → Liquid Glass)"
else
  warn "macOS $macos: Xcode 26 vraagt macOS 15.6+. De app bouwt, maar zonder Liquid Glass."
fi

if xcodebuild -version >/dev/null 2>&1; then
  xv=$(xcodebuild -version | head -1)
  case "$xv" in
    "Xcode 1"*) warn "$xv: bouwt met fallback-glas. Xcode 26+ voor Liquid Glass." ;;
    *) ok "$xv" ;;
  esac
else
  bad "Xcode niet gevonden (App Store)"
fi

if xcrun simctl list runtimes 2>/dev/null | grep -q "iOS"; then
  ok "iOS-simulator geïnstalleerd"
else
  warn "Geen iOS-simulator. Installeer: xcodebuild -downloadPlatform iOS"
fi

command -v xcodegen >/dev/null && ok "xcodegen $(xcodegen --version 2>/dev/null)" || bad "xcodegen ontbreekt: brew install xcodegen"
command -v node >/dev/null && ok "node $(node --version) (voor databasetests)" || bad "node ontbreekt: brew install node"

root=$(cd "$(dirname "$0")/.." && pwd)
if [ -f "$root/ios/Config/Secrets.xcconfig" ]; then
  if grep -q "YOUR-" "$root/ios/Config/Secrets.xcconfig"; then
    warn "ios/Config/Secrets.xcconfig bevat nog placeholders"
  else
    ok "ios/Config/Secrets.xcconfig ingevuld"
  fi
else
  warn "ios/Config/Secrets.xcconfig ontbreekt (bootstrap.sh maakt hem aan)"
fi

exit $fail
