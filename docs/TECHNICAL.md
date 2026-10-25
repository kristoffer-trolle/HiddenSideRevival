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
   - **Patch (32-bit, versionCode 1100100):** `0x8BF3CC` in `lib/armeabi-v7a/libil2cpp.so`:
     `e6 17 00 e3` → `0f 17 02 e3` (`movw r1, #9999`).
   - The 64-bit build (versionCode 1200100) compiles the same method to:
     ```
     0x126A274  bl   DateTime.get_Year
     0x126A27C  cmp  w0, #0x7e6        ; 2022
     0x126A280  cset w0, gt            ; return year > 2022
     ```
     9999 doesn't fit in an ARM64 `cmp` immediate, so the patch replaces the `cset` instead:
     `0x126A280` in `lib/arm64-v8a/libil2cpp.so`: `e0 d7 9f 1a` → `00 00 80 52` (`mov w0, #0`, never discontinued).
     It's the only `cmp wN, #2022` in the whole library.
3. **No ghosts in the minifigure scan (MSE, `MSEFlowController`).** The ghost is placed with Vuforia's
   `ContentPositioningBehaviour` / `MidAirPositionerBehaviour`, which needs platform tracking (ARCore). The log shows
   why it failed:
   ```
   AR    : ARCore is not available to Vuforia, it reports that this device is supported but ARCore is not installed.
   Unity : ------------ FUSION PROVIDER: VUFORIA_VISION_ONLY
   Unity : Could not create Anchor.
   ```
   - **32-bit build:** ARCore no longer supports 32-bit apps on 64-bit devices (Google's 64-bit requirement, 2020).
     The installed ARCore (1.56 on the test phone) only ships `lib/arm64-v8a/libarcore_c.so`.
   - **Both builds:** 3.5.4 has `targetSdkVersion 30` but no `<queries>` entry for `com.google.ar.core`. With
     Android 11 package visibility, the app can't see the ARCore package, so Vuforia 9.8.13 decides it isn't
     installed. (3.4.0 targets SDK 29 and doesn't have this problem.)
   - **Patch:** `targetSdkVersion` 30 → 29 in the binary `AndroidManifest.xml` (attribute at offset `0x1894`, value
     `08 00 00 10 1e 00 00 00` → `… 1d 00 00 00`; same offset in both builds). With the 64-bit build the log then
     shows `Vuforia Fusion: Detected and enabled use of Google ARCore` and `FUSION PROVIDER: PLATFORM_SENSOR_FUSION`,
     and the mid-air ghosts appear.
   - Both 3.5.4 builds share build ID `3d831307-…`, so the 64-bit build uses the same OBB, named `main.1200100…`.

## Save data and the see-through MSE ghost
- All progress is in `<persistentDataPath>/game.lego` (`SaveManager.SaveData`: inventory, sets, missions, store,
  tutorial, upgrades, quests, stats). It's encrypted JSON (AES via `CbcCrypto.FileDecrypt`). PlayerPrefs only hold
  small settings.
- With one pre-2023 save, the MSE ghost was see-through and took no damage. The log showed a ghost already spawned
  when `MSEFlowController.DialogSeqGhostCapFinished` → `SkuController.StartGhostCapturing` ran, which then logged
  `Trying to spawn a second ghost`. That save had `RedSessionGhostId`/`BlueSessionGhostId`/`YellowSessionGhostId` set
  for the `MSE` entry in `SkuState.Skus`, apparently left over from an unfinished scan. A new save has them empty.
  Clearing them fixed it. The exact code path of the extra spawn isn't proven; the prime suspect is
  `PointOfInterestManager.DoPOIEvent`, which after the MSE branch also processes queued POI drops that can call
  `DoSessionGhostCapture`.
- Why the IDs go stale: `SkuController.Initialize` does
  `if (!SkuStateManager.AreSessionGhostSelected(sku)) SkuStateManager.SelectRandomSessionGhosts(sku);`, and the only
  caller of `ClearSessionGhosts` is `CommonPanelsManager.OpenSabaResultsPanel`. Leave a scan before the results screen
  and the IDs stay in the save; the next start reuses them. Seen again a week later on the same phone.
- **Patch:** remove the conditional branch so `SelectRandomSessionGhosts` always runs:
  64-bit `0x11FF264` `tbz w0,#0,…` → `nop`; 32-bit `0x83B724` `bne …` → `nop`. Tested with a save holding stale MSE
  session ghosts: one ghost, `GhostCaptureComplete`, "MSE cleared".

## Ghost mode offline (optional, `GHOST_OFFLINE=1`)
Ghost mode ("DigitalStealthGame") is a Photon PUN 2 multiplayer mode. The host can already fill empty places with AI
(`DigitalStealthGameAIGhostMP`, simulated hunter), but only inside a Photon room. Three patches get it there offline
(addresses 64-bit / 32-bit):
1. `MainMenuGhostPreLobby.OnClickGhostMulti` calls `SessionManager.PingInternetReachable`, which pings the dead game
   server and also needs a login ID, so it showed "NEED INTERNET". Its result lambda
   (`<>c__DisplayClass121_0.<PingInternetReachable>b__0`) always takes the success branch:
   `0x156BB38` `tbz w20,…` → `b 0x156BBFC`; `0xC717B0` `beq …` → `b 0xC7187C`.
2. `MultiplayerManager.ConnectToMaster` ends with `PhotonNetwork.ConnectUsingSettings()`. It now calls
   `PhotonNetwork.set_OfflineMode(true)` instead (which fires `OnConnectedToMaster` right away):
   `0x139DF5C` `mov x0,xzr ; bl ConnectUsingSettings` → `mov w0,#1 ; bl set_OfflineMode`;
   `0xA3681C` `mov r0,#0 ; bl …` → `mov r0,#1 ; bl set_OfflineMode`.
3. In offline mode `JoinRandomRoom` "succeeds" with an empty local room and the client waits forever for a host.
   `MultiplayerConnectionPanel.StartSearchForRooms` now calls `FailedToFindRoom()` instead of
   `MultiplayerManager.JoinRoom()`; after `hostAtTime` the game logs "B: START GHOST HOST", creates the room itself and
   starts with AI players (`InstantiateAIGhostPlayer`, `OnGameplayStartedAsHost`).
   `0x13AC1C0`: `mov x0,x21 ; … ; bl JoinRoom ; tbz w0,…` → `mov x0,x19 ; … ; bl FailedToFindRoom ; nop`;
   `0xA489B0`: `mov r0,r6 ; … ; bl JoinRoom ; cmp ; beq` → `mov r0,r4 ; … ; bl FailedToFindRoom ; cmp ; nop`.

Quality-of-life patches in the same option:
- Shorter lobby: `MatchmakingSettings.WaitTimeUntilGhostHost` (6 s, read in `ConnectionResponse`) → 1 s and
  `WaitTimeUntilAutoStartWithBots` (45 s, read in `GhostHostWaitForPlayerCo`) → 3 s. Both are ints converted to float;
  the patch loads the float constant directly and drops the conversion
  (`0x13AD6F8`/`0x13AD704`, `0x13B0748`; `0xA4A318`, `0xA4E340`).
- The match ends when the player's ghost is captured: `DigitalStealthGameLocalGhost.DeathCo` (only reached for the
  local ghost) calls `DigitalStealthGameState.OnGameEnded(GameResult.GhostsCaptured = 2)` instead of
  `ActivateSpectatorMode()` (`0x11BB078`; `0x7E4018`).
- Private match: `MainMenuGhostPreLobby.GetPriveRoomCode` tail-calls `SQServer.GetPrivateRoom`, whose callback
  `OnRequestRoomCallback` needs `{"success":…, "data":{"room":…}}` from the dead server. Instead,
  `OnClickFriendsMulti`, `OnClickCreateGhostFriendMulti` and `OnClickJoinFriendsMulti` now start with a branch to
  `OnClickGhostMulti`, so they start a normal match against AI (`0x11F0BA4`, `0x11F0E40`, `0x11F0D1C`;
  `0x828BB8`, `0x828EF4`, `0x828D88`). A real offline private match would still need a faked room code.

## Ghost Zoo
`GhostAquarium` scene / `AquariumManager`: a showcase where collected ghosts walk around a scanned set or the floor
(`AquariumGhost` actions: move, attack animations, "RushDance", periodic "show off"). There is no scoring or
objective beyond the tutorial, so "nothing happens" is the intended design.

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
