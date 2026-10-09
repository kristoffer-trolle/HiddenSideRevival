#!/usr/bin/env bash
# Installs the patched APK + OBB on a USB-connected phone (USB debugging enabled).
# Uses a package-manager "session" install, which also works on Xiaomi/HyperOS phones
# where plain `adb install` fails with INSTALL_FAILED_USER_RESTRICTED.
#
# Keeps your progress: if the installed app can't simply be updated (e.g. it's the original LEGO app),
# the save file (game.lego) is backed up to ./savegame-backup-<date>/ first and copied back afterwards.
#
# Usage: bash scripts/install.sh <patched.apk> <OBB from Hidden Side 3.5.4, main.1100100.com.lego.ar.hidden.obb>
set -euo pipefail
export MSYS_NO_PATHCONV=1   # Git Bash on Windows: don't mangle /sdcard paths
APK="${1:?usage: install.sh <patched.apk> <obb>}"; OBB="${2:?usage: install.sh <patched.apk> <obb>}"
for f in "$APK" "$OBB"; do [ -f "$f" ] || { echo "File not found: $f" >&2; exit 1; }; done
win() { if command -v cygpath >/dev/null; then cygpath -w "$1"; else echo "$1"; fi; }  # adb.exe needs Windows paths
PKG=com.lego.ar.hidden
DATA=/sdcard/Android/data/$PKG/files
OBBDIR=/sdcard/Android/obb/$PKG

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
ash() { "$ADB" shell "$@" 2>&1 | tr -d '\r'; }   # adb shell, output without CRs

echo "== Phone ABIs: $(ash getprop ro.product.cpu.abilist)"

# Session install; prints pm's result line
session_install() {
  "$ADB" push "$(win "$APK")" /data/local/tmp/hs.apk >/dev/null
  local size session
  size=$(ash stat -c %s /data/local/tmp/hs.apk)
  session=$(ash pm install-create -r -g -S "$size" | grep -oE '[0-9]+')
  ash pm install-write -S "$size" "$session" base.apk /data/local/tmp/hs.apk >/dev/null
  ash pm install-commit "$session" || true
  ash rm -f /data/local/tmp/hs.apk
}

echo "== Installing APK (accept the prompt on the phone if one appears)..."
SAVE_BACKUP=""
RESULT=$(session_install)
if [ "$RESULT" != "Success" ]; then
  case "$RESULT" in
    *UPDATE_INCOMPATIBLE*|*VERSION_DOWNGRADE*) ;;   # different signature or older version: must uninstall first
    *USER_RESTRICTED*) echo "Install was cancelled on the phone. Run the script again and tap Install/Allow." >&2; exit 1 ;;
    *) echo "Install failed: $RESULT" >&2; exit 1 ;;
  esac
  echo "== The installed Hidden Side can't be updated in place, so it has to be uninstalled first."
  "$ADB" shell am force-stop $PKG
  if ash "[ -f $DATA/game.lego ] && echo yes" | grep -q yes; then
    SAVE_BACKUP="savegame-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$SAVE_BACKUP"
    "$ADB" pull $DATA/game.lego "$(win "$SAVE_BACKUP/game.lego")" >/dev/null
    echo "== Your progress (game.lego) is backed up in $SAVE_BACKUP/"
  fi
  "$ADB" uninstall $PKG >/dev/null
  RESULT=$(session_install)
  [ "$RESULT" = "Success" ] || { echo "Install failed: $RESULT" >&2; exit 1; }
fi
VC=$(ash dumpsys package $PKG | grep -oE 'versionCode=[0-9]+' | head -1 | cut -d= -f2)
echo "== Installed versionCode $VC"

# The OBB has to be named after the installed versionCode. Both 3.5.4 builds (1100100 = 32-bit,
# 1200100 = 64-bit) share the same OBB content, so it is copied under the right name.
echo "== Copying OBB as main.$VC.$PKG.obb (~490 MB)..."
ash mkdir -p $OBBDIR
ash "rm -f $OBBDIR/main.*.$PKG.obb"
"$ADB" push "$(win "$OBB")" $OBBDIR/main.$VC.$PKG.obb

if [ -n "$SAVE_BACKUP" ]; then
  # The app creates its data folder on first start; then the save can be put back.
  echo "== Restoring your progress: starting Hidden Side once (keep the phone unlocked)..."
  "$ADB" shell am start -n $PKG/.UnityPlayerActivity >/dev/null
  for _ in $(seq 1 60); do
    ash "[ -f $DATA/game.lego ] && echo yes" | grep -q yes && break
    sleep 2
  done
  "$ADB" shell am force-stop $PKG
  if ash "[ -d $DATA ] && echo yes" | grep -q yes; then
    "$ADB" push "$(win "$SAVE_BACKUP/game.lego")" $DATA/game.lego >/dev/null
    echo "== Progress restored."
  else
    echo "Could not restore the save automatically. Start Hidden Side once, close it, then copy" >&2
    echo "$SAVE_BACKUP/game.lego to Internal storage/Android/data/$PKG/files/ on the phone." >&2
  fi
fi

echo "Done. Start 'Hidden Side' on the phone."
[ "$VC" = 1100100 ] && echo "(32-bit build: tap OK if Android warns that the app isn't compatible with the latest version.)"
exit 0
