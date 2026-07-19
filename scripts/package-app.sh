#!/usr/bin/env bash
set -euo pipefail

APP_NAME="SSH Tunnel Manager"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
APP_VERSION="$(
  sed -n 's/.*public static let current = "\(.*\)".*/\1/p' \
    "${ROOT_DIR}/Sources/SSHTunnelCore/AppVersion.swift" | head -n 1
)"
APP_VERSION="${APP_VERSION:-0.4.0}"

DIST_DIR="${ROOT_DIR}/dist"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ssh-tunnel-manager-package.XXXXXX")"
APP_BUNDLE="${WORK_DIR}/${APP_NAME}.app"
ZIP_NAME="${APP_NAME}-${APP_VERSION}.zip"
ZIP_PATH="${DIST_DIR}/${ZIP_NAME}"

cleanup() {
  rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

"${SCRIPT_DIR}/build-app-bundle.sh" "${APP_BUNDLE}"

echo "Packaging ${ZIP_NAME}..."
mkdir -p "${DIST_DIR}"
rm -f "${ZIP_PATH}"
(
  cd "${WORK_DIR}"
  COPYFILE_DISABLE=1 ditto -c -k --norsrc --keepParent "${APP_NAME}.app" "${ZIP_PATH}"
)

echo "Package created: ${ZIP_PATH}"
echo "Share this zip with users. They should unzip it, move the app to /Applications, then open it."
