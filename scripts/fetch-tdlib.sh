#!/bin/bash
# Download prebuilt libtdjson.so from GitHub Releases into entry/libs/arm64-v8a/
set -eu
REPO="miramira8295/TelegramForHarmony"   # 发布后替换为实际 owner/repo
TAG="${1:-tdlib-latest}"
DEST="$(dirname "$0")/../entry/libs/arm64-v8a"
mkdir -p "$DEST"
URL="https://github.com/$REPO/releases/download/$TAG/libtdjson.so"
echo "Downloading $URL ..."
if ! curl -fL "$URL" -o "$DEST/libtdjson.so"; then
  echo "ERROR: download failed. Either the release is not published yet,"
  echo "or you are offline. Build from source instead: scripts/build-tdlib.sh"
  exit 1
fi
file "$DEST/libtdjson.so"

# The published artifact must advertise SONAME "libtdjson.so" so it matches the
# packaged filename and libentry.so's DT_NEEDED (see build-tdlib.sh for why a
# mismatch causes a silent runtime load failure). Verify, and self-heal if the
# tools are available.
if command -v patchelf >/dev/null 2>&1; then
  SONAME="$(patchelf --print-soname "$DEST/libtdjson.so" 2>/dev/null || echo '')"
  if [ "$SONAME" != "libtdjson.so" ]; then
    echo "WARN: downloaded SONAME is '$SONAME', normalizing to libtdjson.so"
    patchelf --set-soname libtdjson.so "$DEST/libtdjson.so"
  fi
else
  echo "NOTE: patchelf not found; skipping SONAME check. If the app's native"
  echo "      bridge loads as undefined at runtime, install patchelf and run:"
  echo "      patchelf --set-soname libtdjson.so \"$DEST/libtdjson.so\""
fi
echo "Done: $DEST/libtdjson.so"
