#!/usr/bin/env bash
# Patches an original Hidden Side 3.5.4 APK (32-bit or 64-bit) so it no longer shuts itself down after 2022.
#
# Usage:  bash scripts/patch_apk.sh <original-3.5.4.apk> [output.apk]
#
# Needs: Android SDK build-tools (zipalign + apksigner), a JDK (keytool/java), unzip, xxd, 7-Zip (7z).
# Set ANDROID_HOME (or ANDROID_SDK_ROOT) if the SDK is not in the default location.
set -euo pipefail

SRC="${1:?usage: patch_apk.sh <original-3.5.4.apk> [output.apk]}"
OUT_APK="${2:-HiddenSide-3.5.4-patched.apk}"

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

# --- detect build and verify input ---------------------------------------------------------------
# LEGO shipped 3.5.4 as two APKs: 32-bit (versionCode 1100100) and 64-bit (versionCode 1200100).
if unzip -l "$SRC" lib/arm64-v8a/libil2cpp.so >/dev/null 2>&1; then
  ABI=arm64-v8a;   EXPECTED_SHA256="23bce33bdeffc43d2b3e515a2cdb7ecfdb5b555a882b89c47f69334b29a1d58e"; VC=1200100
else
  ABI=armeabi-v7a; EXPECTED_SHA256="9a0cfbb135445453214647dc5eebcaae507e0dc3cea0b8c4a797e0578fb72e20"; VC=1100100
fi
echo "input: Hidden Side 3.5.4 $ABI build (expected versionCode $VC)"
SHA=$(sha256sum "$SRC" | cut -d' ' -f1)
if [ "$SHA" != "$EXPECTED_SHA256" ]; then
  echo "WARNING: input APK sha256 is $SHA"
  echo "         expected           $EXPECTED_SHA256 (Hidden Side 3.5.4, versionCode $VC, $ABI)"
  echo "         Continuing anyway - the patch itself checks the bytes it changes."
fi

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
LIB="lib/$ABI/libil2cpp.so"
unzip -q "$SRC" "$LIB" AndroidManifest.xml -d "$WORK"

# patch <file> <hex offset> <expected bytes> <new bytes> <description>
patch() {
  local f="$WORK/$1" off=$(( $2 )) cur
  cur=$(xxd -s "$off" -l $(( ${#3} / 2 )) -p "$f")
  if [ "$cur" != "$3" ]; then echo "ERROR ($5): expected $3 at $2, found $cur - wrong APK version?" >&2; exit 1; fi
  echo "$4" | xxd -r -p | dd of="$f" bs=1 seek="$off" conv=notrunc status=none
  echo "patched: $5"
}

# ConnectingSceneController.IsDiscontinued() returns `DateTime.Now.Year > 2022`.
if [ "$ABI" = arm64-v8a ]; then
  # cmp w0,#0x7e6 ; cset w0,gt (1a9fd7e0)  ->  cmp w0,#0x7e6 ; mov w0,#0 (52800000): never discontinued
  patch "$LIB" 0x126A280 e0d79f1a 00008052 "sunset time bomb (IsDiscontinued -> always false)"
else
  # movw r1,#0x7e6 (e30017e6)  ->  movw r1,#0x270f (e302170f): year > 9999
  patch "$LIB" 0x8BF3CC e61700e3 0f1702e3 "sunset time bomb (year > 2022 -> year > 9999)"
fi

# targetSdkVersion 30 -> 29. With 30, Android 11+ package visibility hides the ARCore app from the game
# (no <queries> entry), so Vuforia reports "ARCore is not installed" and the mid-air ghosts in the
# minifig scan never appear. Binary manifest attribute: size 8, type TYPE_INT_DEC (0x10), value 0x1e.
patch AndroidManifest.xml 0x1894 080000101e000000 080000101d000000 "targetSdkVersion 30 -> 29 (lets Vuforia find ARCore)"

# --- repack, align, sign -----------------------------------------------------------------------
cp "$SRC" "$WORK/unsigned.apk"
( cd "$WORK" && "$SEVENZ" d -bso0 -tzip unsigned.apk 'META-INF/*' \
             && touch "$LIB" AndroidManifest.xml \
             && "$SEVENZ" a -bso0 -tzip -mx=6 unsigned.apk "$LIB" AndroidManifest.xml )
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
