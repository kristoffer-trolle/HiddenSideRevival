#!/usr/bin/env bash
# Installs the patched APK + OBB on a USB-connected phone (USB debugging enabled).
# Uses a package-manager "session" install, which also works on Xiaomi/HyperOS phones
# where plain `adb install` fails with INSTALL_FAILED_USER_RESTRICTED.
#
# Usage: bash scripts/install.sh <patched.apk> <main.1100100.com.lego.ar.hidden.obb>
set -euo pipefail
export MSYS_NO_PATHCONV=1   # Git Bash on Windows: don't mangle /sdcard paths
APK="${1:?usage: install.sh <patched.apk> <obb>}"; OBB="${2:?usage: install.sh <patched.apk> <obb>}"
for f in "$APK" "$OBB"; do [ -f "$f" ] || { echo "File not found: $f" >&2; exit 1; }; done
# adb.exe on Windows can't read Git Bash paths like /c/Users/... (path conversion is off, see above)
if command -v cygpath >/dev/null; then APK="$(cygpath -w "$APK")"; OBB="$(cygpath -w "$OBB")"; fi
PKG=com.lego.ar.hidden

# adb: $ADB, adb on PATH, or the Android SDK's platform-tools
ADB="${ADB:-$(command -v adb || true)}"
if [ -z "$ADB" ]; then
  for d in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "${LOCALAPPDATA:-}/Android/Sdk" \
           "$HOME/Library/Android/sdk" "$HOME/Android/Sdk"; do
    for f in "$d/platform-tools/adb.exe" "$d/platform-tools/adb"; do
      [ -z "$ADB" ] && [ -n "$d" ] && [ -f "$f" ] && ADB="$f"
    done
  done
fi
[ -n "$ADB" ] || { echo "adb not found. Install Android SDK platform-tools or set ADB=/path/to/adb." >&2; exit 1; }
if [ "$("$ADB" get-state 2>/dev/null | tr -d '\r')" != "device" ]; then
  echo "No phone found. Connect it by USB, enable USB debugging, and tap 'Allow' on the phone's prompt." >&2
  exit 1
fi

echo "== Device ABIs (must include armeabi-v7a):"
"$ADB" shell getprop ro.product.cpu.abilist

echo "== Removing any existing $PKG (different signature)..."
"$ADB" uninstall "$PKG" >/dev/null 2>&1 || true

echo "== Installing APK..."
"$ADB" push "$APK" /data/local/tmp/hs.apk >/dev/null
SIZE=$("$ADB" shell stat -c %s /data/local/tmp/hs.apk | tr -d '\r')
SESSION=$("$ADB" shell pm install-create -r -g -S "$SIZE" | tr -d '\r' | grep -oE '[0-9]+')
"$ADB" shell pm install-write -S "$SIZE" "$SESSION" base.apk /data/local/tmp/hs.apk
"$ADB" shell pm install-commit "$SESSION"
"$ADB" shell rm /data/local/tmp/hs.apk

echo "== Copying OBB (~490 MB)..."
"$ADB" shell mkdir -p /sdcard/Android/obb/$PKG
"$ADB" push "$OBB" /sdcard/Android/obb/$PKG/main.1100100.$PKG.obb

echo "Done. Start 'Hidden Side' on the phone (tap OK on Android's 32-bit warning if shown)."
