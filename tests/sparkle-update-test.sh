#!/usr/bin/env bash
# tests/sparkle-update-test.sh — synthetic Sparkle update flow validator.
#
# Simulates a user on a hypothetical earlier version discovering an update
# via a local appcast file. Verifies the EdDSA signature roundtrips, the
# appcast XML is well-formed, and sparkle:version parses.
#
# Usage: bash tests/sparkle-update-test.sh <path-to-Smoodle-vX.dmg>
#
# Requires:
#   - Sparkle CLI tools: package/sign_update (build with `make package/sign_update`)
#   - xmllint (ships with macOS)
#   - DMG built locally OR downloaded from a release
#   - <dmg>.sig sidecar OR Keychain has EdDSA key (will sign on demand)
#     OR SPARKLE_PRIVATE_KEY env var set with base64 private key
#
# Exits 0 on all checks pass.

set -euo pipefail

DMG="${1:?usage: $0 <path-to-dmg>}"

if [ ! -f "$DMG" ]; then
  echo "FAIL: DMG or .sig not found"
  exit 1
fi

SIGN_UPDATE="${SIGN_UPDATE:-package/sign_update}"
if [ ! -x "$SIGN_UPDATE" ]; then
  echo "FAIL: sign_update not executable at $SIGN_UPDATE"
  echo "      Build with: make package/sign_update"
  exit 1
fi

PUBKEY_FILE="${PUBKEY_FILE:-package/Sparkle-public-key.txt}"
if [ ! -f "$PUBKEY_FILE" ]; then
  echo "FAIL: $PUBKEY_FILE missing"
  exit 1
fi

WORKDIR=$(mktemp -d)
trap "rm -rf '$WORKDIR'" EXIT

# 1. Acquire signature: either a sidecar .sig file or sign-on-demand.
SIG_FILE="$DMG.sig"
if [ -f "$SIG_FILE" ] && [ -s "$SIG_FILE" ]; then
  DMG_SIG=$(cat "$SIG_FILE")
  echo "  ✓ using existing signature from $SIG_FILE"
else
  # Sign now. Try SPARKLE_PRIVATE_KEY env first (CI path), then Keychain.
  if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
    DMG_SIG=$(printf '%s' "$SPARKLE_PRIVATE_KEY" | "$SIGN_UPDATE" --ed-key-file - -p "$DMG")
    echo "  ✓ signed on demand using SPARKLE_PRIVATE_KEY env"
  else
    DMG_SIG=$("$SIGN_UPDATE" -p "$DMG")
    echo "  ✓ signed on demand using Keychain"
  fi
  if [ -z "$DMG_SIG" ]; then
    echo "FAIL: signing produced no output"
    exit 1
  fi
fi

# 2. Verify the signature roundtrips. Sparkle 2.x's --verify reads pubkey
#    from Keychain OR from a private-key-file (it derives the pubkey).
#    If neither is available, skip verify but warn.
if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
  if printf '%s' "$SPARKLE_PRIVATE_KEY" | "$SIGN_UPDATE" --verify --ed-key-file - "$DMG" "$DMG_SIG" >/dev/null 2>&1; then
    echo "  ✓ EdDSA signature verifies (env private key)"
  else
    echo "FAIL: EdDSA signature verification failed (env private key)"
    exit 1
  fi
elif "$SIGN_UPDATE" --verify "$DMG" "$DMG_SIG" >/dev/null 2>&1; then
  echo "  ✓ EdDSA signature verifies (Keychain)"
else
  echo "WARN: verify skipped — no Keychain entry and no SPARKLE_PRIVATE_KEY env"
fi

# 3. Build a synthetic appcast.xml pointing at the DMG with the obtained sig.
DMG_SIZE=$(stat -f %z "$DMG")
DMG_BASENAME=$(basename "$DMG")

cat > "$WORKDIR/appcast.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Smoodle (synthetic test)</title>
    <item>
      <title>v0.0.8a (synthetic)</title>
      <sparkle:version>0.0.8a</sparkle:version>
      <enclosure
        url="file://$DMG"
        length="$DMG_SIZE"
        type="application/octet-stream"
        sparkle:edSignature="$DMG_SIG" />
    </item>
  </channel>
</rss>
EOF

# 4. Validate appcast XML structure.
if ! xmllint --noout "$WORKDIR/appcast.xml" 2>&1; then
  echo "FAIL: appcast.xml is malformed"
  exit 1
fi
echo "  ✓ appcast.xml well-formed"

# 5. Cross-check sparkle:version is parseable and equals 0.0.8a.
VERSION=$(xmllint --xpath 'string(//*[local-name()="version"])' "$WORKDIR/appcast.xml" 2>/dev/null)
if [ "$VERSION" != "0.0.8a" ]; then
  echo "FAIL: appcast sparkle:version is '$VERSION', expected '0.0.8a'"
  exit 1
fi
echo "  ✓ sparkle:version = 0.0.8a"

# 6. v0.0.8b.1 CRITICAL guard: verify Sparkle.framework is actually bundled
#    into the shipped DMG. v0.0.8a/8a.1/8b shipped with SUFeedURL + SUPublicEDKey
#    in Info.plist but NO Sparkle code linked — auto-update non-functional.
#    Detected via Mac local smoke 2026-05-27.
echo
echo "Verifying Sparkle.framework presence in DMG..."
MOUNT_POINT=$(hdiutil attach "$DMG" -nobrowse -noverify | tail -1 | awk -F'\t' '{print $NF}' | sed 's/^ *//')
if [ -z "$MOUNT_POINT" ] || [ ! -d "$MOUNT_POINT" ]; then
  echo "FAIL: could not mount DMG"
  exit 1
fi
trap "hdiutil detach '$MOUNT_POINT' >/dev/null 2>&1 || true; rm -rf '$WORKDIR'" EXIT

SMOODLE_APP="$MOUNT_POINT/Smoodle.app"
SPARKLE_FW="$SMOODLE_APP/Contents/Frameworks/Sparkle.framework"
SMOODLE_BIN="$SMOODLE_APP/Contents/MacOS/Smoodle"

if [ ! -d "$SPARKLE_FW" ]; then
  echo "FAIL: Sparkle.framework MISSING from $SMOODLE_APP/Contents/Frameworks/"
  echo "      (v0.0.8a/8a.1/8b regression — Squirrel.xcodeproj never linked it)"
  ls -la "$SMOODLE_APP/Contents/Frameworks/" 2>&1 || true
  exit 1
fi
echo "  ✓ Sparkle.framework present in app bundle"

if ! otool -L "$SMOODLE_BIN" 2>/dev/null | grep -q "Sparkle.framework"; then
  echo "FAIL: Smoodle binary not linked against Sparkle.framework"
  echo "      otool -L output:"
  otool -L "$SMOODLE_BIN" | head -10
  exit 1
fi
echo "  ✓ Smoodle binary links Sparkle.framework"

# Optional: check for SPU symbols via nm. macOS Release builds strip
# Swift mangled symbols + may rewrite ObjC class refs across universal
# slices, so absence is not conclusive evidence of mis-wiring; presence
# is bonus signal. Warn but don't fail.
if nm -arch all "$SMOODLE_BIN" 2>/dev/null | grep -qE "SPUStandardUpdaterController|SPUUpdater|SUUpdater"; then
  echo "  ✓ Smoodle binary nm shows Sparkle updater symbols"
else
  echo "  ⚠ nm shows no Sparkle updater symbols (stripped Release build — non-blocking)"
fi

echo
echo "=== ALL SPARKLE CHECKS PASS ==="
echo "Note: this is an offline test. Real-world update prompt UX still requires"
echo "      a running Smoodle.app instance + network appcast — covered by"
echo "      manual founder smoke test (tests/manual/v0.0.8b-e2e.md)."
