#!/usr/bin/env bash
# Build dist/Smoodle-{version}.dmg — drag-to-install Thai phonetic IME for macOS.
#
# Layout inside the DMG:
#   Smoodle.app                       (universal arm64+x86_64)
#   Input Methods (symlink → /Library/Input Methods)
#   README.txt
#
# User drops Smoodle.app onto the symlink → installs to /Library/Input Methods.
#
# Usage:  ./package/build-dmg.sh
# Output: dist/Smoodle-{version}.dmg

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(git -C "${REPO_DIR}" describe --tags --always --dirty 2>/dev/null || echo dev)"
DIST_DIR="${REPO_DIR}/dist"
STAGING="${DIST_DIR}/.dmg-staging"
APP_SRC="${REPO_DIR}/build/Build/Products/Release/Smoodle.app"
VOL_NAME="Smoodle ${VERSION}"
OUT_DMG="${DIST_DIR}/Smoodle-${VERSION}.dmg"

echo "Smoodle DMG builder"
echo "==================="
echo "  version: ${VERSION}"
echo "  output:  ${OUT_DMG}"
echo

if [ ! -d "${APP_SRC}" ]; then
    echo "ERROR: ${APP_SRC} not found. Run: ARCHS=\"x86_64 arm64\" make release" >&2
    exit 1
fi

# Verify universal
arches=$(lipo -archs "${APP_SRC}/Contents/MacOS/Smoodle" 2>/dev/null || echo "")
echo "  Smoodle arch:  ${arches}"
if ! echo "${arches}" | grep -q "x86_64" || ! echo "${arches}" | grep -q "arm64"; then
    echo "WARNING: not universal — DMG will only run on ${arches}" >&2
fi
echo "  librime arch:  $(lipo -archs "${APP_SRC}/Contents/Frameworks/librime.1.dylib" 2>/dev/null || echo unknown)"
echo

# Stage
rm -rf "${STAGING}"
mkdir -p "${STAGING}"
cp -R "${APP_SRC}" "${STAGING}/"
ln -s "/Library/Input Methods" "${STAGING}/Input Methods"

cat > "${STAGING}/README.txt" <<README
Smoodle ${VERSION} — Thai phonetic input method for macOS
==========================================================

Install
-------
1. Drag Smoodle.app onto the "Input Methods" folder shortcut in this DMG.
   (You may be asked for your password — that's macOS authorizing the install
   into /Library/Input Methods.)

2. Open System Settings → Keyboard → Input Sources.
   Click "+", choose Thai → Smoodle, click Add.

3. Switch to Smoodle from the menu bar input picker (or Ctrl+Space).

Type
----
Romanization → Thai. Examples:
  sawadee     →  สวัสดี       hello
  khob khun   →  ขอบคุณ       thank you
  sabai dee   →  สบายดี       I'm well
  mai pen rai →  ไม่เป็นไร    no problem

Press Space to commit the highlighted candidate, or 1/2/3 to pick by number.

Uninstall
---------
1. System Settings → Keyboard → Input Sources → select Smoodle → click "−"
2. sudo rm -rf "/Library/Input Methods/Smoodle.app"
3. rm -rf ~/Library/Rime/Smoodle    # optional: remove user dictionary cache

Source: https://github.com/LoneExile/smoodle-app
README

# Build DMG
mkdir -p "${DIST_DIR}"
rm -f "${OUT_DMG}"

hdiutil create \
    -volname "${VOL_NAME}" \
    -srcfolder "${STAGING}" \
    -ov \
    -format UDZO \
    "${OUT_DMG}" >/dev/null

rm -rf "${STAGING}"

size_mb=$(( $(stat -f %z "${OUT_DMG}") / 1024 / 1024 ))
sha256="$(shasum -a 256 "${OUT_DMG}" | awk '{print $1}')"

echo "Done."
echo "  file:   ${OUT_DMG}"
echo "  size:   ${size_mb} MB"
echo "  sha256: ${sha256}"
echo
echo "To upload to GitHub Releases:"
echo "  gh release create v${VERSION} \"${OUT_DMG}\" -t \"Smoodle ${VERSION}\" -R LoneExile/smoodle-app"
