#!/usr/bin/env bash
# Install and run the Jira Flutter app on a connected device for testing.
# Usage: ./scripts/install_device.sh [device_id]
#   - No args: run on default device (Flutter picks one)
#   - device_id: e.g. "ios", "android", or full ID from "flutter devices"

set -e
cd "$(dirname "$0")/.."

echo "==> Checking Flutter..."
if ! command -v flutter &> /dev/null; then
  echo "Error: Flutter not found in PATH. Install Flutter: https://flutter.dev/docs/get-started/install"
  exit 1
fi

echo "==> Dependencies..."
flutter pub get

echo ""
echo "==> Connected devices:"
flutter devices

echo ""
if [ -n "$1" ]; then
  echo "==> Installing and running on device: $1"
  flutter run -d "$1"
else
  echo "==> Installing and running (use first available device; pass device_id to choose, e.g. ./scripts/install_device.sh ios)"
  flutter run
fi
