#!/usr/bin/env bash
# Patches the original Hidden Side 3.5.4 APK so it no longer shuts itself down after 2022.
#
# Usage:  bash scripts/patch_apk.sh <original-3.5.4.apk> [output.apk]
#
# Needs: Android SDK build-tools (zipalign + apksigner), a JDK (keytool/java), unzip, xxd, 7-Zip (7z).
# Set ANDROID_HOME (or ANDROID_SDK_ROOT) if the SDK is not in the default location.
set -euo pipefail

SRC="${1:?usage: patch_apk.sh <original-3.5.4.apk> [output.apk]}"
OUT_APK="${2:-HiddenSide-3.5.4-patched.apk}"
EXPECTED_SHA256="9a0cfbb135445453214647dc5eebcaae507e0dc3cea0b8c4a797e0578fb72e20"

# --- locate tools ------------------------------------------------------------------------------
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [ -z "$SDK" ]; then
  for d in "${LOCALAPPDATA:-}/Android/Sdk" "$HOME/Library/Android/sdk" "$HOME/Android/Sdk"; do
    [ -d "$d" ] && SDK="$d" && break
  done
fi
[ -d "$SDK/build-tools" ] || { echo "Android SDK build-tools not found. Set ANDROID_HOME." >&2; exit 1; }
BT="$SDK/build-tools/$(ls "$SDK/build-tools" | sort -V | tail -1)"
ZIPALIGN="$BT/zipalign"; APKSIGNER="$BT/apksigner"
[ -f "$ZIPALIGN.exe" ] && ZIPALIGN="$ZIPALIGN.exe"
[ -f "$APKSIGNER.bat" ] && APKSIGNER="$APKSIGNER.bat"
SEVENZ="$(command -v 7z || command -v 7za || command -v 7zz || true)"
for f in "${PROGRAMFILES:-}/7-Zip/7z.exe" "/c/Program Files/7-Zip/7z.exe"; do   # Windows installer skips PATH
  [ -z "$SEVENZ" ] && [ -f "$f" ] && SEVENZ="$f"
done
[ -n "$SEVENZ" ] || { echo "7-Zip (7z) not found on PATH." >&2; exit 1; }
for t in unzip xxd; do command -v $t >/dev/null || { echo "$t not found on PATH." >&2; exit 1; }; done
# apksigner and keytool need Java: use JAVA_HOME or java on PATH, else Android Studio's bundled JDK
if [ -z "${JAVA_HOME:-}" ] && ! command -v java >/dev/null; then
  for d in "${LOCALAPPDATA:-}"/Android/jdk* "${PROGRAMFILES:-}/Android/Android Studio/jbr" \
           "/Applications/Android Studio.app/Contents/jbr/Contents/Home" "/opt/android-studio/jbr"; do
    [ -x "$d/bin/java" ] || [ -x "$d/bin/java.exe" ] || continue
    export JAVA_HOME="$d"; break
  done
fi
if [ -n "${JAVA_HOME:-}" ]; then   # cygpath: a Windows "C:\..." path would break PATH on the colon
  JBIN="$JAVA_HOME/bin"; command -v cygpath >/dev/null && JBIN="$(cygpath -u "$JBIN")"
  export PATH="$JBIN:$PATH"
fi
command -v keytool >/dev/null || { echo "Java (JDK) not found. Set JAVA_HOME." >&2; exit 1; }

# --- verify input ------------------------------------------------------------------------------
SHA=$(sha256sum "$SRC" | cut -d' ' -f1)
if [ "$SHA" != "$EXPECTED_SHA256" ]; then
  echo "WARNING: input APK sha256 is $SHA"
  echo "         expected           $EXPECTED_SHA256 (Hidden Side 3.5.4, versionCode 1100100, armeabi-v7a)"
  echo "         Continuing anyway - the patch itself checks the bytes it changes."
fi

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
unzip -q "$SRC" lib/armeabi-v7a/libil2cpp.so -d "$WORK"
SO="$WORK/lib/armeabi-v7a/libil2cpp.so"

# patch <hex offset> <expected bytes> <new bytes> <description>
patch() {
  local off=$(( $1 )) cur
  cur=$(xxd -s "$off" -l $(( ${#2} / 2 )) -p "$SO")
  if [ "$cur" != "$2" ]; then echo "ERROR ($4): expected $2 at $1, found $cur - wrong APK version?" >&2; exit 1; fi
  printf "$(echo "$3" | sed 's/../\\x&/g')" | dd of="$SO" bs=1 seek="$off" conv=notrunc status=none
  echo "patched: $4"
}

# ConnectingSceneController.IsDiscontinued(): `DateTime.Now.Year > 2022`  ->  `> 9999`
# movw r1,#0x7e6 (e30017e6)  ->  movw r1,#0x270f (e302170f)
patch 0x8BF3CC e61700e3 0f1702e3 "sunset time bomb (year > 2022 -> year > 9999)"

# --- repack, align, sign -----------------------------------------------------------------------
cp "$SRC" "$WORK/unsigned.apk"
( cd "$WORK" && "$SEVENZ" d -bso0 -tzip unsigned.apk 'META-INF/*' \
             && touch lib/armeabi-v7a/libil2cpp.so \
             && "$SEVENZ" a -bso0 -tzip -mx=6 unsigned.apk lib/armeabi-v7a/libil2cpp.so )
"$ZIPALIGN" -f -p 4 "$WORK/unsigned.apk" "$WORK/aligned.apk"

KS="$HOME/.android/debug.keystore"
if [ ! -f "$KS" ]; then
  mkdir -p "$HOME/.android"
  keytool -genkeypair -keystore "$KS" -storepass android -keypass android -alias androiddebugkey \
    -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US" >/dev/null
fi
"$APKSIGNER" sign --v4-signing-enabled false --ks "$KS" --ks-pass pass:android --key-pass pass:android --ks-key-alias androiddebugkey \
  --out "$OUT_APK" "$WORK/aligned.apk"
"$APKSIGNER" verify "$OUT_APK"
echo "Done -> $OUT_APK"
