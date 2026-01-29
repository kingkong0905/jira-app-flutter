#!/usr/bin/env bash
# Full clean rebuild and run on macOS (required after entitlement changes).
# Hot reload does NOT apply entitlement changes; use this script if you see
# "Operation not permitted, errno = 1" when connecting to Jira.
# Usage: ./scripts/run_macos.sh

set -e
cd "$(dirname "$0")/.."

echo "==> Cleaning build..."
flutter clean

echo "==> Getting dependencies..."
flutter pub get

echo "==> Updating CocoaPods repo (so pod install can resolve sqlite3)..."
(cd macos && pod repo update)

echo "==> Building and running on macOS (entitlements will be applied)..."
flutter run -d macos
