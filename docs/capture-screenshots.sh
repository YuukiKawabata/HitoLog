#!/bin/bash
#
# HitoLog App Store スクリーンショット自動生成
#
# 使い方:
#   ./docs/capture-screenshots.sh
#   IPHONE="iPhone 17 Pro Max" IPAD="iPad Pro 13-inch (M5)" ./docs/capture-screenshots.sh
#
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
BUNDLE_ID="com.yukikawabata.HitoLog"
IPHONE_NAME="${IPHONE:-iPhone 17 Pro}"
IPAD_NAME="${IPAD:-iPad Pro 13-inch (M5)}"
DERIVED_DATA="${HITOLOG_SCREENSHOT_DERIVED_DATA:-/tmp/HitoLogScreenshotDerivedData}"

cd "$ROOT"

echo "▶ HitoLog をビルド中..."
xcodebuild \
  -project HitoLog.xcodeproj \
  -scheme HitoLog \
  -configuration Debug \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build >/dev/null

APP="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/HitoLog.app"
if [ ! -d "$APP" ]; then
  echo "✗ アプリが見つかりません: $APP"
  exit 1
fi

resolve_udid() {
  xcrun simctl list devices available \
    | rg -F "$1 (" \
    | head -1 \
    | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/'
}

capture_device() {
  local device_class="$1"
  local device_name="$2"
  local udid
  local output_dir

  udid="$(resolve_udid "$device_name")"
  if [ -z "$udid" ]; then
    echo "✗ デバイスが見つかりません: $device_name"
    return 1
  fi

  output_dir="$ROOT/AppStoreAssets/Screenshots/Simple/raw/$device_class"
  mkdir -p "$output_dir"

  echo "▶ [$device_class] $device_name"
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b
  xcrun simctl status_bar "$udid" override \
    --time "9:41" \
    --batteryState charged \
    --batteryLevel 100 \
    --cellularBars 4 \
    --wifiBars 3 2>/dev/null || true

  capture_scene() {
    local scene="$1"
    local filename="$2"

    xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true
    xcrun simctl uninstall "$udid" "$BUNDLE_ID" 2>/dev/null || true
    xcrun simctl install "$udid" "$APP"
    xcrun simctl launch "$udid" "$BUNDLE_ID" \
      -HitoLogScreenshotDemo \
      -HitoLogScreenshotScene "$scene" >/dev/null
    sleep 4
    xcrun simctl io "$udid" screenshot "$output_dir/$filename" >/dev/null
    echo "  ✓ $filename"
  }

  capture_scene home    01-home.png
  capture_scene compose 02-compose.png
  capture_scene profile 03-profile.png
  xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true
}

echo "▶ 実機画面を撮影中..."
capture_device iphone "$IPHONE_NAME"
capture_device ipad "$IPAD_NAME"

echo "▶ App Store パネルを生成中..."
swift "$HERE/make-store-panels.swift"

echo "✅ 完了: $ROOT/AppStoreAssets/Screenshots/Simple"
