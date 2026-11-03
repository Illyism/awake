#!/bin/sh
# Installs Awake (CLI + Control Center widget + Menu Bar app) on macOS.
# Usage:
#   curl -fsSL https://il.ly/awake/install.sh | sh
#   curl -fsSL https://il.ly/awake/install.sh | sh -s -- uninstall
#   ./install.sh [uninstall]
set -eu

AWAKE_VERSION="1.0.1"
REPO_TARBALL="https://github.com/Illyism/awake/archive/refs/tags/v${AWAKE_VERSION}.tar.gz"
RELEASE_ZIP_URL="https://github.com/Illyism/awake/releases/download/v${AWAKE_VERSION}/Awake-${AWAKE_VERSION}-macos-arm64.zip"
RELEASE_ZIP_SHA256="b96b1f8e86e6f58706c967308d0b8c26b08a3bec0b70dce8a647a7cb4a663030"

INSTALL_BIN_DIR="${AWAKE_BIN_DIR:-$HOME/.local/bin}"
SHARE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/awake"
CACHE_DIR="$HOME/.cache/awake"
DEFAULT_APP_DIR="$HOME/Applications"
if [ -d "/Applications/Awake.app" ] && [ -w "/Applications" ]; then
  DEFAULT_APP_DIR="/Applications"
fi
APP_DIR="${AWAKE_APP_DIR:-$DEFAULT_APP_DIR}"
APP_BUNDLE="$APP_DIR/Awake.app"
SUDOERS_PATH="/etc/sudoers.d/awake"

fail() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

if [ "$(uname -s)" != "Darwin" ]; then
  fail "Awake only supports macOS."
fi

safe_dir() {
  path="$1"
  if [ -L "$path" ]; then
    fail "Refusing symlinked directory: $path"
  fi
  mkdir -p "$path"
  if [ "$(stat -f %u "$path")" != "$(id -u)" ]; then
    fail "Directory is not owned by current user: $path"
  fi
}

uninstall() {
  printf 'Uninstalling Awake...\n'
  if [ -x "$INSTALL_BIN_DIR/awake" ]; then
    "$INSTALL_BIN_DIR/awake" stop >/dev/null 2>&1 || true
  fi
  killall Awake AwakeControl 2>/dev/null || true

  rm -rf "$HOME/Applications/Awake.app" "$SHARE_DIR" "$CACHE_DIR"
  if [ -d "/Applications/Awake.app" ] && [ -w "/Applications" ]; then
    rm -rf "/Applications/Awake.app"
  fi
  rm -f "$INSTALL_BIN_DIR/awake" "$INSTALL_BIN_DIR/asleep"

  if [ -f "$SUDOERS_PATH" ]; then
    printf 'Removing %s (requires administrator privileges)...\n' "$SUDOERS_PATH"
    if [ -r /dev/tty ]; then
      sudo rm -f "$SUDOERS_PATH" </dev/tty || true
    else
      sudo -n rm -f "$SUDOERS_PATH" 2>/dev/null || true
    fi
  fi
  printf 'Uninstalled Awake.\n'
  exit 0
}

if [ "${1:-}" = "uninstall" ] || [ "${1:-}" = "--uninstall" ]; then
  uninstall
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/awake-install.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' HUP INT TERM

# Determine source directory (local checkout vs remote curl | sh)
SCRIPT_DIR=""
if [ -n "${0:-}" ] && [ -f "$0" ]; then
  SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
fi

if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/awake" ] && [ -d "$SCRIPT_DIR/control" ]; then
  SRC_DIR="$SCRIPT_DIR"
  LOCAL_CHECKOUT=1
else
  LOCAL_CHECKOUT=0
  printf 'Downloading Awake %s from GitHub...\n' "$AWAKE_VERSION"
  curl --location --proto '=https' --proto-redir '=https' \
    --silent --show-error --fail --connect-timeout 10 --max-time 60 \
    "$REPO_TARBALL" -o "$WORK/awake.tar.gz"
  tar -xzf "$WORK/awake.tar.gz" -C "$WORK"
  SRC_DIR="$(find "$WORK" -mindepth 1 -maxdepth 1 -type d -name 'awake-*' | head -1)"
  [ -n "$SRC_DIR" ] && [ -f "$SRC_DIR/awake" ] || fail "Downloaded archive did not contain awake."
fi

safe_dir "$CACHE_DIR"
chmod 700 "$CACHE_DIR"
safe_dir "$INSTALL_BIN_DIR"
if [ "$APP_DIR" != "/Applications" ]; then
  safe_dir "$APP_DIR"
fi

# Install CLI script
if [ "$LOCAL_CHECKOUT" = 1 ]; then
  chmod +x "$SRC_DIR/awake"
  xattr -d com.apple.quarantine "$SRC_DIR/awake" 2>/dev/null || true
  ln -sf "$SRC_DIR/awake" "$INSTALL_BIN_DIR/awake"
else
  safe_dir "$SHARE_DIR"
  install -m 0755 "$SRC_DIR/awake" "$SHARE_DIR/awake"
  xattr -d com.apple.quarantine "$SHARE_DIR/awake" 2>/dev/null || true
  ln -sf "$SHARE_DIR/awake" "$INSTALL_BIN_DIR/awake"
fi
ln -sf awake "$INSTALL_BIN_DIR/asleep"

# Check existing Awake.app bundle identifier before replacing
if [ -e "$APP_BUNDLE" ] || [ -L "$APP_BUNDLE" ]; then
  if [ -L "$APP_BUNDLE" ]; then
    fail "Refusing to replace symlink at $APP_BUNDLE"
  fi
  existing_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true)"
  case "$existing_id" in
    com.illyism.awake | "") ;;
    *) fail "Refusing to replace $APP_BUNDLE (unexpected bundle identifier: $existing_id)" ;;
  esac
fi

# Build Awake.app from source if full Xcode is active, else download release bundle
BUILT_APP=""
TEAM=""
if xcodebuild -version >/dev/null 2>&1; then
  TEAM="${DEVELOPMENT_TEAM:-}"
  if [ -z "$TEAM" ]; then
    CERT_CN="$(security find-identity -v -p codesigning 2>/dev/null \
      | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -1 || true)"
    if [ -n "$CERT_CN" ]; then
      TEAM="$(security find-certificate -c "$CERT_CN" -p 2>/dev/null \
        | openssl x509 -noout -subject 2>/dev/null \
        | sed -n 's/.*OU=\([A-Z0-9]\{10\}\).*/\1/p' | head -1 || true)"
    fi
  fi
  if [ -n "$TEAM" ]; then
    printf 'Building Awake.app (Control Center + Menu Bar) with local Apple Development team...\n'
    if (cd "$SRC_DIR/control" && xcodebuild -project Awake.xcodeproj -scheme Awake -configuration Release \
      -destination "platform=macOS,arch=$(uname -m)" \
      -derivedDataPath "$WORK/derived" DEVELOPMENT_TEAM="$TEAM" -quiet build 2>/dev/null); then
      BUILT_APP="$WORK/derived/Build/Products/Release/Awake.app"
    fi
  else
    printf 'Building Awake.app (Menu Bar + CLI) with ad-hoc signing...\n'
    if (cd "$SRC_DIR/control" && xcodebuild -project Awake.xcodeproj -scheme Awake -configuration Release \
      -destination "platform=macOS,arch=$(uname -m)" \
      -derivedDataPath "$WORK/derived" CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM="" AD_HOC_CODE_SIGNING_ALLOWED=YES -quiet build 2>/dev/null); then
      BUILT_APP="$WORK/derived/Build/Products/Release/Awake.app"
    fi
  fi
fi

if { [ -z "$BUILT_APP" ] || [ ! -d "$BUILT_APP" ]; } && [ "$(uname -m)" = "arm64" ]; then
  printf 'Downloading prebuilt Awake.app release bundle...\n'
  if curl --location --proto '=https' --proto-redir '=https' \
    --silent --show-error --fail --connect-timeout 10 --max-time 60 \
    "$RELEASE_ZIP_URL" -o "$WORK/Awake.zip"; then
    actual_sha="$(shasum -a 256 "$WORK/Awake.zip" | awk '{print $1}')"
    if [ "$actual_sha" != "$RELEASE_ZIP_SHA256" ]; then
      fail "Downloaded Awake.zip SHA-256 mismatch (expected $RELEASE_ZIP_SHA256, got $actual_sha)."
    fi
    /usr/bin/ditto -x -k "$WORK/Awake.zip" "$WORK/unpacked"
    BUILT_APP="$WORK/unpacked/Awake.app"
  fi
fi

if [ -n "$BUILT_APP" ] && [ -d "$BUILT_APP" ]; then
  killall Awake AwakeControl 2>/dev/null || true
  rm -rf "$APP_BUNDLE"
  /usr/bin/ditto "$BUILT_APP" "$APP_BUNDLE"
  xattr -dr com.apple.quarantine "$APP_BUNDLE" 2>/dev/null || true
  open -g "$APP_BUNDLE" || true
  "$APP_BUNDLE/Contents/MacOS/Awake" --reload 2>/dev/null || true
fi

# Install /etc/sudoers.d/awake if not already configured
if [ ! -f "$SUDOERS_PATH" ]; then
  cat >"$WORK/awake.sudoers" <<'EOF'
# Lets `awake` / `asleep` toggle lid sleep without a password prompt,
# so the background watcher and the Control Center toggle can always
# restore sleep. Only these two exact commands are allowed.
%admin ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1
EOF
  if /usr/sbin/visudo -cf "$WORK/awake.sudoers" >/dev/null 2>&1; then
    printf 'Installing passwordless pmset sudo rule to %s...\n' "$SUDOERS_PATH"
    if [ -r /dev/tty ]; then
      sudo install -m 0440 -o root -g wheel "$WORK/awake.sudoers" "$SUDOERS_PATH" </dev/tty || \
        printf 'Note: run `awake setup` later to enable passwordless lid-sleep toggling.\n'
    else
      sudo -n install -m 0440 -o root -g wheel "$WORK/awake.sudoers" "$SUDOERS_PATH" 2>/dev/null || \
        printf 'Note: run `awake setup` in your terminal to enable passwordless lid-sleep toggling.\n'
    fi
  fi
fi

printf '\nInstalled Awake %s\n' "$AWAKE_VERSION"
printf '  CLI:            %s/awake (and asleep)\n' "$INSTALL_BIN_DIR"
if [ -d "$APP_BUNDLE" ]; then
  printf '  App:            %s (Menu Bar cup icon active)\n' "$APP_BUNDLE"
  printf '  Control Center: Control Center -> Edit Controls -> search "Awake"\n'
fi
case ":${PATH:-}:" in
  *":$INSTALL_BIN_DIR:"*) ;;
  *) printf '  PATH note:      export PATH="%s:$PATH"\n' "$INSTALL_BIN_DIR" ;;
esac
printf '  Usage:          awake | awake 45m | awake -- <cmd> | awake status | asleep\n'
printf '  Uninstall:      curl -fsSL https://il.ly/awake/install.sh | sh -s -- uninstall\n'
