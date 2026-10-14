#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="GraceDown"
PRODUCT_NAME="UPSPowerMonitor"
UPDATER_PRODUCT_NAME="GraceDownUpdater"
BUNDLE_ID="com.han.UPSPowerMonitor"
MIN_SYSTEM_VERSION="14.0"
APP_VERSION="${APP_VERSION:-0.1.8}"
APP_BUILD="${APP_BUILD:-$(date +%Y%m%d%H%M)}"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-release}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
APP_UPDATER="$APP_MACOS/$UPDATER_PRODUCT_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_ICON="$ROOT_DIR/Resources/AppIcon.icns"
STATUS_BAR_ICON="$ROOT_DIR/Resources/StatusBarIconTemplate.png"
DMG_BACKGROUND="$ROOT_DIR/Resources/InstallerBackground.png"
DMG_ROOT="$DIST_DIR/dmg-root"
DMG_PATH="$DIST_DIR/$APP_NAME-$APP_VERSION.dmg"
DMG_RW_PATH="$DIST_DIR/$APP_NAME-$APP_VERSION-rw.dmg"
DMG_CHECKSUM_PATH="$DMG_PATH.sha256"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
pkill -x "$PRODUCT_NAME" >/dev/null 2>&1 || true
pkill -x "$UPDATER_PRODUCT_NAME" >/dev/null 2>&1 || true

swift build -c "$BUILD_CONFIGURATION" --product "$PRODUCT_NAME"
swift build -c "$BUILD_CONFIGURATION" --product "$UPDATER_PRODUCT_NAME"
BUILD_BIN_DIR="$(swift build -c "$BUILD_CONFIGURATION" --show-bin-path)"
BUILD_BINARY="$BUILD_BIN_DIR/$PRODUCT_NAME"
BUILD_UPDATER="$BUILD_BIN_DIR/$UPDATER_PRODUCT_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
cp "$BUILD_UPDATER" "$APP_UPDATER"
chmod +x "$APP_BINARY"
chmod +x "$APP_UPDATER"

if [[ -f "$APP_ICON" ]]; then
  cp "$APP_ICON" "$APP_RESOURCES/AppIcon.icns"
fi

if [[ -f "$STATUS_BAR_ICON" ]]; then
  cp "$STATUS_BAR_ICON" "$APP_RESOURCES/StatusBarIconTemplate.png"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>GraceDown</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSLocalNetworkUsageDescription</key>
  <string>GraceDown 需要访问局域网中的 NAS NUT 服务，用于读取 UPS 状态。</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

xattr -cr "$APP_BUNDLE" >/dev/null 2>&1 || true
codesign --force --deep --sign - "$APP_BUNDLE"

create_dmg() {
  rm -rf "$DMG_ROOT"
  rm -f "$DMG_PATH" "$DMG_RW_PATH" "$DMG_CHECKSUM_PATH"
  mkdir -p "$DMG_ROOT"
  ditto "$APP_BUNDLE" "$DMG_ROOT/$APP_NAME.app"
  ln -s /Applications "$DMG_ROOT/Applications"

  if [[ -f "$DMG_BACKGROUND" ]]; then
    mkdir -p "$DMG_ROOT/.background"
    ditto "$DMG_BACKGROUND" "$DMG_ROOT/.background/InstallerBackground.png"

    hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_ROOT" -ov -format UDRW -fs HFS+ "$DMG_RW_PATH"

    local mount_dir
    mount_dir="$(mktemp -d /tmp/gracedown-dmg.XXXXXX)"
    cleanup_dmg_mount() {
      if [[ -n "${mount_dir:-}" && -d "$mount_dir" ]]; then
        hdiutil detach "$mount_dir" >/dev/null 2>&1 || true
        rmdir "$mount_dir" 2>/dev/null || true
      fi
    }
    trap cleanup_dmg_mount RETURN

    hdiutil attach "$DMG_RW_PATH" -readwrite -nobrowse -mountpoint "$mount_dir" >/dev/null
    SetFile -a V "$mount_dir/.background" 2>/dev/null || true

    osascript <<APPLESCRIPT
tell application "Finder"
  set dmgFolder to (POSIX file "$mount_dir") as alias
  open dmgFolder
  delay 1
  set targetWindow to front window
  set current view of targetWindow to icon view
  set toolbar visible of targetWindow to false
  set statusbar visible of targetWindow to false
  set bounds of targetWindow to {120, 120, 1320, 880}
  set theViewOptions to the icon view options of targetWindow
  set icon size of theViewOptions to 160
  set background picture of theViewOptions to (POSIX file "$mount_dir/.background/InstallerBackground.png") as alias
  set position of item "$APP_NAME.app" of folder dmgFolder to {315, 360}
  set position of item "Applications" of folder dmgFolder to {915, 360}
  delay 1
  close targetWindow
end tell
APPLESCRIPT

    sync
    for _ in 1 2 3; do
      if hdiutil detach "$mount_dir" >/dev/null; then
        break
      fi
      sleep 1
    done
    rmdir "$mount_dir" 2>/dev/null || true
    trap - RETURN

    hdiutil convert "$DMG_RW_PATH" -ov -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH"
    rm -f "$DMG_RW_PATH"
  else
    hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_ROOT" -ov -format UDZO "$DMG_PATH"
  fi

  shasum -a 256 "$DMG_PATH" > "$DMG_CHECKSUM_PATH"
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  bundle)
    ;;
  dmg)
    create_dmg
    ;;
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [bundle|dmg|run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
