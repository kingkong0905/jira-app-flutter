#!/usr/bin/env bash
# Setup Jira Flutter app: install Flutter (if needed), deps, and platform folders.
# Usage: ./scripts/setup.sh   or   bash scripts/setup.sh

set -e
cd "$(dirname "$0")/.."

# Flutter command: use PATH or path we install to
FLUTTER_CMD=""
FLUTTER_INSTALL_DIR="${FLUTTER_INSTALL_DIR:-$HOME/flutter}"

install_flutter_macos() {
  echo "==> Trying to install Flutter on macOS..."
  if command -v brew &> /dev/null; then
    echo "==> Installing Flutter via Homebrew (this may take a few minutes)..."
    brew install --cask flutter
    # Homebrew puts flutter in PATH; ensure it's available in this shell
    if [ -x "/opt/homebrew/bin/flutter" ]; then
      export PATH="/opt/homebrew/bin:$PATH"
    elif [ -x "/usr/local/bin/flutter" ]; then
      export PATH="/usr/local/bin:$PATH"
    fi
    return 0
  fi

  echo "==> Homebrew not found. Installing Flutter via git clone to $FLUTTER_INSTALL_DIR ..."
  if [ -d "$FLUTTER_INSTALL_DIR" ]; then
    echo "    Directory exists. Updating..."
    (cd "$FLUTTER_INSTALL_DIR" && git pull)
  else
    git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$FLUTTER_INSTALL_DIR"
  fi
  export PATH="$FLUTTER_INSTALL_DIR/bin:$PATH"
  FLUTTER_CMD="$FLUTTER_INSTALL_DIR/bin/flutter"
  echo "    Add to your shell profile (e.g. ~/.zshrc): export PATH=\"$FLUTTER_INSTALL_DIR/bin:\$PATH\""
  return 0
}

install_flutter_linux() {
  echo "==> Installing Flutter via git clone to $FLUTTER_INSTALL_DIR ..."
  if [ -d "$FLUTTER_INSTALL_DIR" ]; then
    echo "    Directory exists. Updating..."
    (cd "$FLUTTER_INSTALL_DIR" && git pull)
  else
    git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$FLUTTER_INSTALL_DIR"
  fi
  export PATH="$FLUTTER_INSTALL_DIR/bin:$PATH"
  FLUTTER_CMD="$FLUTTER_INSTALL_DIR/bin/flutter"
  echo "    Add to your shell profile (e.g. ~/.bashrc): export PATH=\"$FLUTTER_INSTALL_DIR/bin:\$PATH\""
  return 0
}

install_flutter() {
  case "$(uname -s)" in
    Darwin)  install_flutter_macos ;;
    Linux)   install_flutter_linux ;;
    *)
      echo "Error: Automatic Flutter install is only supported on macOS and Linux."
      echo "Install Flutter manually: https://flutter.dev/docs/get-started/install"
      exit 1
      ;;
  esac
}

echo "==> Checking Flutter..."
if ! command -v flutter &> /dev/null; then
  echo "Flutter not found in PATH."
  read -r -p "Install Flutter now? [y/N] " response
  if [[ "$response" =~ ^[yY](es)?$ ]]; then
    install_flutter
  else
    echo "Install Flutter manually: https://flutter.dev/docs/get-started/install"
    exit 1
  fi
fi

# Use explicit path if we just installed via git clone; otherwise use flutter from PATH
FLUTTER_BIN="${FLUTTER_CMD:-flutter}"

echo "==> Flutter doctor..."
"$FLUTTER_BIN" doctor -v

echo ""
echo "==> Installing dependencies..."
"$FLUTTER_BIN" pub get

if [ ! -d "android" ] || [ ! -d "ios" ]; then
  echo ""
  echo "==> Platform folders missing. Creating them..."
  "$FLUTTER_BIN" create . --project-name jira_app_flutter
  echo "==> Platform files created."
else
  echo ""
  echo "==> Platform folders (android/, ios/) already present."
fi

echo ""
echo "==> Setup complete. Run: ./scripts/install_device.sh   to install on a connected device."
