#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/.build-package"
MODULE_CACHE_DIR="${BUILD_DIR}/module-cache"
DIST_DIR="${ROOT_DIR}/dist"
APP_NAME="PlotMeasure Pro.app"
APP_DIR="${DIST_DIR}/${APP_NAME}"
EXECUTABLE_NAME="PlotMeasurePro"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP_VERSION="${APP_VERSION:-1.1.0}"
ZIP_PATH="${DIST_DIR}/PlotMeasure-Pro-v${APP_VERSION}.zip"
LEGACY_ZIP_PATH="${DIST_DIR}/PlotMeasure-Pro-Release.zip"

mkdir -p "${MODULE_CACHE_DIR}" "${DIST_DIR}"
SWIFT_MODULECACHE_PATH="${MODULE_CACHE_DIR}" \
CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" \
swift build \
  --configuration release \
  --disable-sandbox \
  --scratch-path "${BUILD_DIR}/scratch"

rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"

cp "${BUILD_DIR}/scratch/release/${EXECUTABLE_NAME}" "${APP_DIR}/Contents/MacOS/${EXECUTABLE_NAME}"
chmod +x "${APP_DIR}/Contents/MacOS/${EXECUTABLE_NAME}"

cat > "${APP_DIR}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>PlotMeasurePro</string>
    <key>CFBundleIdentifier</key>
    <string>com.tanik.plotmeasurepro</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>PlotMeasure Pro</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${APP_VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
PLIST

perl -0pi -e "s/\\\${APP_VERSION}/${APP_VERSION}/g" "${APP_DIR}/Contents/Info.plist"

codesign --force --deep --sign "${SIGN_IDENTITY}" "${APP_DIR}"
codesign --verify --deep --strict --verbose=2 "${APP_DIR}"

rm -f "${ZIP_PATH}" "${LEGACY_ZIP_PATH}"
ditto -c -k --sequesterRsrc --keepParent "${APP_DIR}" "${ZIP_PATH}"
cp "${ZIP_PATH}" "${LEGACY_ZIP_PATH}"

echo "Packaged app bundle at ${APP_DIR}"
echo "Created release archive at ${ZIP_PATH}"
echo "Created compatibility archive at ${LEGACY_ZIP_PATH}"
echo "Signed with identity: ${SIGN_IDENTITY}"
