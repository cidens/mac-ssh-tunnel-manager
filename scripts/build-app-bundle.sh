#!/usr/bin/env bash
set -euo pipefail

APP_NAME="SSH Tunnel Manager"
PRODUCT_NAME="ssh-tunnel-manager"
BUNDLE_ID="io.github.mobius1024.ssh-tunnel-manager"
MIN_SYSTEM_VERSION="14.0"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
APP_VERSION="$(
  sed -n 's/.*public static let current = "\(.*\)".*/\1/p' \
    "${ROOT_DIR}/Sources/SSHTunnelCore/AppVersion.swift" | head -n 1
)"
APP_VERSION="${APP_VERSION:-0.3.0}"

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <output-app-path>" >&2
  exit 2
fi

APP_BUNDLE="$1"
APP_CONTENTS="${APP_BUNDLE}/Contents"
APP_MACOS="${APP_CONTENTS}/MacOS"
APP_RESOURCES="${APP_CONTENTS}/Resources"

echo "Building ${PRODUCT_NAME} ${APP_VERSION}..."
cd "${ROOT_DIR}"
swift build -c release --product "${PRODUCT_NAME}"

BIN_DIR="$(swift build -c release --show-bin-path)"
BIN_PATH="${BIN_DIR}/${PRODUCT_NAME}"
if [[ ! -x "${BIN_PATH}" ]]; then
  echo "Build product not found: ${BIN_PATH}" >&2
  exit 1
fi

echo "Creating ${APP_NAME}.app..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_MACOS}" "${APP_RESOURCES}"
cp "${BIN_PATH}" "${APP_MACOS}/${PRODUCT_NAME}"
chmod 755 "${APP_MACOS}/${PRODUCT_NAME}"

echo "Copying localized resources..."
shopt -s nullglob
RESOURCE_BUNDLES=("${BIN_DIR}/${PRODUCT_NAME}_"*.bundle)
if [[ ${#RESOURCE_BUNDLES[@]} -eq 0 ]]; then
  echo "SwiftPM resource bundles not found in ${BIN_DIR}" >&2
  exit 1
fi
for resource_bundle in "${RESOURCE_BUNDLES[@]}"; do
  cp -R "${resource_bundle}" "${APP_RESOURCES}/"
done
shopt -u nullglob

cat > "${APP_CONTENTS}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${PRODUCT_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>zh-Hans</string>
    </array>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${APP_VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_SYSTEM_VERSION}</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "Signing app bundle..."
codesign --force --deep --sign - "${APP_BUNDLE}"
