#!/usr/bin/env bash
# package/test-dmg.sh — verify a built DMG has the expected structure.
#
# Usage: bash package/test-dmg.sh <path-to-dmg> [<expected-sparkle-pubkey-path>]
#
# Checks:
#   1. DMG mounts cleanly via hdiutil
#   2. Mount root contains Smoodle.app
#   3. Smoodle.app/Contents/MacOS/Smoodle is universal binary (arm64+x86_64)
#   4. Smoodle.app/Contents/Info.plist has SUFeedURL pointing at the public appcast
#   5. Smoodle.app/Contents/Info.plist SUPublicEDKey matches package/Sparkle-public-key.txt
#   6. Smoodle.app/Contents/Frameworks/librime.1.dylib contains 'sorted_initial_' symbol (peek-sort patch)
#   7. <dmg>.sig exists alongside the DMG (Sparkle EdDSA signature)
#
# For v0.0.8b: also check Smoodle Config.app present at mount root.

set -euo pipefail

DMG="${1:?usage: $0 <dmg-path> [pubkey-path]}"
PUBKEY_FILE="${2:-package/Sparkle-public-key.txt}"

if [ ! -f "$DMG" ]; then
  echo "FAIL: DMG not found at $DMG"
  exit 1
fi

echo "=== test-dmg: $DMG ==="

# 1. Mount
MOUNT=$(mktemp -d)
hdiutil attach "$DMG" -nobrowse -mountpoint "$MOUNT" -quiet
trap "hdiutil detach '$MOUNT' -quiet -force 2>/dev/null || true; rmdir '$MOUNT'" EXIT

# 2. Smoodle.app at root
if [ ! -d "$MOUNT/Smoodle.app" ]; then
  echo "FAIL: Smoodle.app not found at DMG root"
  ls "$MOUNT/"
  exit 1
fi
echo "  ✓ Smoodle.app present"

# 3. Universal binary
BIN="$MOUNT/Smoodle.app/Contents/MacOS/Smoodle"
if ! lipo -info "$BIN" 2>&1 | grep -qE 'arm64.*x86_64|x86_64.*arm64'; then
  echo "FAIL: $BIN is not universal arm64+x86_64"
  lipo -info "$BIN"
  exit 1
fi
echo "  ✓ Smoodle binary is universal"

# 4. SUFeedURL
PLIST="$MOUNT/Smoodle.app/Contents/Info.plist"
FEED=$(plutil -extract SUFeedURL raw "$PLIST" 2>/dev/null)
if [ "$FEED" != "https://smoodle-type.github.io/smoodle-app/appcast.xml" ]; then
  echo "FAIL: SUFeedURL is '$FEED', expected smoodle-type.github.io appcast"
  exit 1
fi
echo "  ✓ SUFeedURL points at public appcast"

# 5. SUPublicEDKey matches
if [ -f "$PUBKEY_FILE" ]; then
  EXPECTED=$(cat "$PUBKEY_FILE" | tr -d '[:space:]')
  ACTUAL=$(plutil -extract SUPublicEDKey raw "$PLIST" 2>/dev/null)
  if [ "$ACTUAL" != "$EXPECTED" ]; then
    echo "FAIL: SUPublicEDKey mismatch"
    echo "  expected: $EXPECTED"
    echo "  actual:   $ACTUAL"
    exit 1
  fi
  echo "  ✓ SUPublicEDKey matches package/Sparkle-public-key.txt"
fi

# 6. librime patch
DYLIB="$MOUNT/Smoodle.app/Contents/Frameworks/librime.1.dylib"
if [ ! -f "$DYLIB" ]; then
  echo "FAIL: $DYLIB missing"
  exit 1
fi
if ! otool -tV "$DYLIB" 2>/dev/null | grep -q 'sorted_initial_'; then
  echo "FAIL: librime.1.dylib does NOT contain 'sorted_initial_' symbol"
  echo "  → peek-sort patch is missing. Was the submodule re-pinned (smoodle-type/librime@1.16.0-smoodle.1)?"
  exit 1
fi
echo "  ✓ librime peek-sort patch present"

# 7. Sparkle EdDSA sig
SIG="$DMG.sig"
if [ ! -f "$SIG" ]; then
  echo "FAIL: $SIG (Sparkle EdDSA signature) missing"
  exit 1
fi
if [ ! -s "$SIG" ]; then
  echo "FAIL: $SIG is empty"
  exit 1
fi
echo "  ✓ Sparkle EdDSA signature present at $SIG"

echo
echo "=== ALL CHECKS PASS ==="
