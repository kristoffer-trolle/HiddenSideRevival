# Technical notes

## App structure
- Unity **2019.4.15f1**, scripting backend **IL2CPP**, in every released version (0.5 → 3.5.4). No Mono build exists.
- `global-metadata.dat` is **not encrypted** (magic `AF1BB1FA`, metadata v24.4), so
  [Il2CppDumper](https://github.com/Perfare/Il2CppDumper) recovers every class, method and string literal.
- Developed by Kung Fu Factory (namespaces `SecureSpace`, `KFFCore`, `com.kungfufactory.banana`, codename "banana").
- **Split binary:** the APK only holds the loader scene (`level0`). About 70 scenes, the game data JSONs
  (`assets/Blueprints/db_*.json`), the Vuforia model targets and `server_settings.json` live in the **OBB**
  (`main.<versionCode>.com.lego.ar.hidden.obb`). Unity only accepts an OBB containing an empty
  `assets/<build-id>` file that matches `unity.build-id` in the APK manifest.

| OBB | Version | Build ID |
|---|---|---|
| `main.1100100` | 3.5.4 | `3d831307-2e2e-45e9-9482-9603eb45051e` |
| `main.809145` | 3.4.0 | `59174637-411c-4d69-a272-a7cadd047655` |
| `main.865908` | 2.2.0 | `1a880265-8b74-4de7-a10f-00be99d6cbda` |

The armeabi-v7a and arm64 builds of one version share a build ID (checked for 3.2.0).

## Why the app stopped working
1. **People installing from APK mirrors have no OBB.** The app then starts without content.
2. **The sunset time bomb (3.5.4):**
   - `ConnectingSceneController.Start()` calls `IsSilentSunsetting()` (PlayerPrefs `"Sunsetting" == 1`) and
     `IsDiscontinued()`. If discontinued, it instantiates `SunsettingMenuController` with the "now discontinued"
     text, and its OK button quits the app.
   - `IsDiscontinued()` is literally `DateTime.Now.Year > 2022`:
     ```
     0x8BF3B0  bl   System.DateTime.get_Now
     0x8BF3C8  bl   DateTime.get_Year
     0x8BF3CC  movw r1, #0x7e6        ; 2022
     0x8BF3D0  cmp  r0, r1
     0x8BF3D4  movwgt r4, #1          ; discontinued = true
     ```
   - **Patch:** `0x8BF3CC` in `lib/armeabi-v7a/libil2cpp.so`: `e6 17 00 e3` → `0f 17 02 e3` (`movw r1, #9999`).

## Backends (state on 2026-10-06)
| Backend | Used for | State |
|---|---|---|
| `lego.com/go/267/1` → `appconfig.services.lego.com/configs/hidden/hiddenside/<platform>/1/<locale>.json` | LEGO app config: kill switch, minimum version, endpoints | **Still online.** `killswitch: "0"`, `minimumversion: "1.0.0"`, so it passes. A bundled fallback config exists too. |
| `http://live-release-3-4.projectbanana.ninja/` (from `server_settings.json` in the OBB) | Kung Fu Factory game server: version check, login, blueprints, mail, multiplayer settings | **Dead (no DNS).** Plain HTTP. The game copes without it, because blueprints and localization are bundled. |
| `*.robotgame.us` (`odl_version_url`) | On-demand loading config | Dead |
| Photon (`ns.exitgames.com`) | Multiplayer | LEGO's app ID is disabled |
| `identity.lego.com`, `avatarinventory`, `gallery`, `friends`, `leaderboards` … | LEGO ID and social features | Mostly dead / 403 |

Startup state machine (`SecureSpace.SessionManager.States`):
`START_VERSION_CHECK → WAITING_FOR_USERID → LOGGING_IN → PATCHING → LOAD_LOCALIZATIONS(_URL) →
LOAD_BLUEPRINTS_DICT(_URL) → LOAD_VARIANT_DICT(_URL) → LOAD_DATA → GET_CURRENCY → LOAD_SERVER_SETTINGS → READY`

The game server URL is read from `server_settings.json` inside the OBB. If a feature ever needs a server,
the OBB (a plain zip) can be repacked to point `server_url` at a self-hosted mock. No TLS is involved.

## Other findings
- `SecureSpace.BananaRunningMode` reads `<persistentDataPath>/serversettings` (`RunningMode: OnLine/OffLine`,
  `GetBlueprints: Local/OnlineBlueprints`), but the shipping build ignores the file and hard-codes online mode
  (`movw r0,#0x101 ; strh r0,[r4,#12]` @ `0xC5B79C`). This wasn't needed.
- Local save: `<persistentDataPath>/game.lego` (encrypted).
- Unity logging is turned off at runtime (`DisableLogging.DisableLogs()`), except warnings and errors.

## Emulator setup that works
- `system-images;android-30;google_apis;x86_64` (has `libndk_translation` for armeabi-v7a), host GPU,
  4 GB RAM, 8 GB data partition. Use `hw.camera.back=emulated`; `virtualscene` crashed the emulator.
- The shell user can't write to `Android/obb` on this image, so use `adb root`, push the OBB,
  `chown` it to the app UID, and `adb shell setenforce 0` (otherwise SELinux denies the app access to the
  root-pushed file). These settings reset on reboot.
- Launch with `adb shell am start -n com.lego.ar.hidden/.UnityPlayerActivity`.

## Tools used
- Il2CppDumper v6.7.46. Disassembly with the Android NDK's `llvm-objdump`, plus a small script that resolves
  IL2CPP GOT/metadata references to string literals and method names.
