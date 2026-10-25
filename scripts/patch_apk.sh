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

# SkuController.Initialize: `if (!AreSessionGhostSelected(sku)) SelectRandomSessionGhosts(sku);`
# Session ghosts are only cleared on the results screen, so a minifigure scan that is left early keeps them in the
# save, and the next scan spawns an extra, see-through ghost that can't be hurt. Always picking new session ghosts
# (removing the conditional branch) avoids that. Side effect: a set gets new session ghosts each time it's opened.
if [ "$ABI" = arm64-v8a ]; then
  # tbnz w0,#0,<skip> (370000e0)  ->  nop (d503201f)
  patch "$LIB" 0x11FF264 e0000037 1f2003d5 "always pick new session ghosts (fixes see-through minifigure scan ghost)"
else
  # bne <skip> (1a00000a)  ->  nop (e320f000)
  patch "$LIB" 0x83B724 0a00001a 00f020e3 "always pick new session ghosts (fixes see-through minifigure scan ghost)"
fi

# EXPERIMENTAL (GHOST_OFFLINE=1): Ghost mode without LEGO's dead Photon account. MultiplayerManager.ConnectToMaster
# ends with PhotonNetwork.ConnectUsingSettings(); replace it with PhotonNetwork.OfflineMode = true, so Photon runs a
# local room and the host can fill the match with simulated players.
if [ "${GHOST_OFFLINE:-0}" = 1 ]; then
  if [ "$ABI" = arm64-v8a ]; then
    # mov x0,xzr ; bl ConnectUsingSettings  ->  mov w0,#1 ; bl set_OfflineMode
    patch "$LIB" 0x139DF5C e0031faad3af2f94 2000805277a62f94 "EXPERIMENTAL: Ghost mode in Photon offline mode"
  else
    # mov r0,#0 ; bl ConnectUsingSettings  ->  mov r0,#1 ; bl set_OfflineMode
    patch "$LIB" 0xA3681C 0000a0e3b62639eb 0100a0e3181b39eb "EXPERIMENTAL: Ghost mode in Photon offline mode"
  fi
  # Before Ghost mode starts, SessionManager.PingInternetReachable pings the dead game server and also needs a player
  # ID from its login, so the game shows "NEED INTERNET". Make its result callback always take the success branch.
  if [ "$ABI" = arm64-v8a ]; then
    # tbz w20,#0,<fail>  ->  b <success>
    patch "$LIB" 0x156BB38 f4000036 31000014 "EXPERIMENTAL: internet check always succeeds"
  else
    # beq <fail>  ->  b <success>
    patch "$LIB" 0xC717B0 0800000a 310000ea "EXPERIMENTAL: internet check always succeeds"
  fi
  # MultiplayerConnectionPanel.StartSearchForRooms: in offline mode Photon's JoinRandomRoom "succeeds" with an empty
  # local room and the game waits forever for a host. Call FailedToFindRoom() instead of JoinRoom(), so after a few
  # retries the player becomes the ghost host, who fills the match with a simulated hunter.
  if [ "$ABI" = arm64-v8a ]; then
    # mov x0,x21 ; mov w1,w20 ; bl JoinRoom ; tbz w0,#0,<popup>  ->  mov x0,x19 ; mov w1,w20 ; bl FailedToFindRoom ; nop
    patch "$LIB" 0x13AC1C0 e00315aae103142a22caff97a0000036 e00313aae103142a730800941f2003d5 \
      "EXPERIMENTAL: room search fails, so the player hosts a match"
  else
    # mov r0,r6 ; ... ; bl JoinRoom ; cmp r0,#0 ; beq <popup>  ->  mov r0,r4 ; ... ; bl FailedToFindRoom ; cmp ; nop
    patch "$LIB" 0xA489B0 0600a0e10510a0e10720a0e137bbffeb000050e30100000a \
      0400a0e10510a0e10720a0e14c0a00eb000050e300f020e3 "EXPERIMENTAL: room search fails, so the player hosts a match"
  fi
  # Shorter lobby: MatchmakingSettings.WaitTimeUntilGhostHost (6 s, read in ConnectionResponse) -> 1 s and
  # WaitTimeUntilAutoStartWithBots (45 s, read in GhostHostWaitForPlayerCo) -> 3 s. Both are ints converted to float;
  # load the float constant directly and drop the conversion.
  # Private match needs room codes from the dead server; its buttons now start "Play multiplayer" instead
  # (OnClickFriendsMulti / OnClickCreateGhostFriendMulti / OnClickJoinFriendsMulti -> b OnClickGhostMulti).
  if [ "$ABI" = arm64-v8a ]; then
    patch "$LIB" 0x13AD6F8 010140bd 01102e1e "EXPERIMENTAL: become host after 1 s (ldr s1 -> fmov s1,#1.0)"
    patch "$LIB" 0x13AD704 21d8215e 1f2003d5 "EXPERIMENTAL: become host after 1 s (scvtf -> nop)"
    patch "$LIB" 0x13B0748 010540bd21d8215e 0110211e1f2003d5 "EXPERIMENTAL: start with computer players after 3 s"
    patch "$LIB" 0x11F0BA4 f657bda9 7cffff17 "EXPERIMENTAL: private match button -> Play multiplayer"
    patch "$LIB" 0x11F0E40 f44fbea9 d5feff17 "EXPERIMENTAL: create private match -> Play multiplayer"
    patch "$LIB" 0x11F0D1C f657bda9 1effff17 "EXPERIMENTAL: join private match -> Play multiplayer"
  else
    patch "$LIB" 0xA4A318 000a91edc00ab8ee 000ab7ee00f020e3 "EXPERIMENTAL: become host after 1 s"
    patch "$LIB" 0xA4E340 010a91edc00ab8ee 080ab0ee00f020e3 "EXPERIMENTAL: start with computer players after 3 s"
    patch "$LIB" 0x828BB8 f0482de9 52ffffea "EXPERIMENTAL: private match button -> Play multiplayer"
    patch "$LIB" 0x828EF4 30482de9 83feffea "EXPERIMENTAL: create private match -> Play multiplayer"
    patch "$LIB" 0x828D88 f0482de9 defeffea "EXPERIMENTAL: join private match -> Play multiplayer"
  fi
  # End the match when the player's own ghost is captured instead of watching the computer players: in
  # DigitalStealthGameLocalGhost.DeathCo (only reached for the player's ghost) call
  # DigitalStealthGameState.OnGameEnded(GameResult.GhostsCaptured = 2) instead of ActivateSpectatorMode().
  if [ "$ABI" = arm64-v8a ]; then
    # cbz x0,<throw> ; bl ActivateSpectatorMode  ->  mov w1,#2 ; bl OnGameEnded
    patch "$LIB" 0x11BB078 a01e00b4ee010094 41008052746b0094 "EXPERIMENTAL: match ends when your ghost is captured"
  else
    # cmp r0,#0 ; bne ; bl <throw> ; mov r0,r5 ; bl ActivateSpectatorMode
    #   ->  mov r1,#2 ; mov r2,#0 ; nop ; mov r0,r5 ; bl OnGameEnded
    patch "$LIB" 0x7E4018 000050e30000001aa258feeb0500a0e1b70100eb 0210a0e30020a0e300f020e30500a0e1ea8b00eb \
      "EXPERIMENTAL: match ends when your ghost is captured"
  fi
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
