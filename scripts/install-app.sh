#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="SSH Tunnel Manager"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ssh-tunnel-manager-app.XXXXXX")"
APP_BUNDLE="${WORK_DIR}/${APP_NAME}.app"
DESTINATION="/Applications/${APP_NAME}.app"

cleanup() {
  rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

"${SCRIPT_DIR}/build-app-bundle.sh" "${APP_BUNDLE}"

echo "Installing to ${DESTINATION}..."
if [[ -w "/Applications" ]]; then
  rm -rf "${DESTINATION}"
  ditto "${APP_BUNDLE}" "${DESTINATION}"
else
  sudo rm -rf "${DESTINATION}"
  sudo ditto "${APP_BUNDLE}" "${DESTINATION}"
fi

echo "Installed: ${DESTINATION}"
echo "Start it from Finder, Spotlight, Launchpad, or run:"
echo "open -a '${APP_NAME}'"
