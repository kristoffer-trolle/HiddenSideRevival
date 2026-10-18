# Hidden Side Revival

Get the discontinued **LEGO® Hidden Side™** AR app (2019–2023) running again on Android.

LEGO ended support for the app on 1 January 2023, and since then it shows
*"The LEGO® Hidden Side App is now discontinued"* and quits. This project fixes that, and the problems that broke
the **minifigure scan** mini-game, with a small patch to your own copy of the app. Single-player, the Newbury map,
ghost hunting, the minifigure scan, the Ghost Zoo and local saves work again. An optional, experimental patch also
lets you play **Ghost mode against computer-controlled players**. Online multiplayer doesn't work: LEGO turned off
those servers.

## What was wrong

You might expect the app died because LEGO shut down its servers. It didn't. Bugs in the app itself stopped it.

### 1. A time bomb in the final version

The last release, 3.5.4, was LEGO's "sunset" update. When the app starts, it checks the phone's clock:

```csharp
bool IsDiscontinued() => DateTime.Now.Year > 2022;
```

From 1 January 2023 that returns `true`, so the app shows the "now discontinued" message, and the OK button closes it.
The year 2022 is written directly into the app's code (hard-coded); no server or setting is involved.

Everything else the game needs is still there: the map, scenes, ghosts, game data and AR targets ship with the app
and its OBB data file. Set a phone's date back to 2022 and the unmodified app runs fine without any server.

**The fix:** the patch changes this check in the app's compiled code (`libil2cpp.so`) so it never triggers.
That's 2 bytes in the 32-bit build and 4 bytes in the 64-bit build.

### 2. No ghosts in the minifigure scan

In the minifigure scan you scan a minifigure, and if it's possessed you aim your phone around to fight the ghost that
comes out. On today's phones **no ghost ever appeared**. The ghost is placed in mid-air around you, and for that the
AR engine (Vuforia) needs Google's ARCore to track the phone's movement. It couldn't get ARCore, for two reasons:

- **32-bit:** ARCore no longer works for 32-bit apps on 64-bit phones (Google dropped that in 2020). That's why the
  **64-bit build of 3.5.4** is the one to use.
- **Android 11+:** 3.5.4 is built for Android 11 (`targetSdkVersion 30`). From Android 11 on, an app can only "see"
  other apps it declares in its manifest, and Hidden Side doesn't declare ARCore. So even the 64-bit app concluded
  that *"ARCore is not installed"*. On the Android 10 phones of 2022 that didn't matter yet.

**The fix:** the patch also sets `targetSdkVersion` to 29 (Android 10), so the app can see ARCore again. Together with
the 64-bit build, the ghosts appear where they should and the mini-game can be played to the end.

### 3. A see-through ghost that can't be hurt

Sometimes the minifigure scan ghost showed up see-through and took no damage. When a set or the minifigure scan
starts, the game picks three "session ghosts" and stores them in the save file. It only clears them on the results
screen at the end, so if you leave a scan early they stay in the save. The next time, the game reuses them and ends
up spawning a second ghost on top of the real one.

**The fix:** the patch makes the game always pick new session ghosts when a set or the minifigure scan starts.
Side effect: a set may have different ghosts than the last time you opened it.

See [docs/TECHNICAL.md](docs/TECHNICAL.md) for how all of this was found.

A third, unrelated reason people couldn't get it working: Google Play used to download the ~490 MB **OBB** game
content file separately. APK download sites usually only have the APK, and without the OBB the app has no content.

> **This repo contains no LEGO files.** You need your own copy of the original APK and its OBB data file.
> The scripts only modify your copy. Not affiliated with or endorsed by the LEGO Group.
> LEGO and Hidden Side are trademarks of the LEGO Group.

---

## Quick guide

### Step 1: Check your phone

Almost every phone from the last ten years is 64-bit and should use the **64-bit build** of Hidden Side 3.5.4.
The phone also needs ARCore support for the AR features. See [Phone requirements](#phone-requirements).

### Step 2: Get the two game files

The game files are copyrighted by LEGO, so this project can't include them or link to them.
**Search the internet for them yourself.** Get exactly these versions:

| File | What to look for | SHA-256 (to check you got the right file) |
|---|---|---|
| **APK** (the app), **recommended** | LEGO Hidden Side **3.5.4**, versionCode **1200100**, `arm64-v8a` (64-bit). Usually named `com.lego.ar.hidden_3.5.4-1200100_minAPI24(arm64-v8a)(nodpi)…apk` | `23bce33bdeffc43d2b3e515a2cdb7ecfdb5b555a882b89c47f69334b29a1d58e` |
| **OBB** (game content, ~490 MB) | `main.1100100.com.lego.ar.hidden.obb` | `07cd79c47bb360429f7b6feef38e3f791c2256c71e1a3102142c176d12f42a49` |

Both 3.5.4 builds use the **same OBB**, the one named `main.1100100…`. Don't worry that it says 1100100 and not
1200100: the install script gives it the right name on the phone. OBBs from other versions, like `main.809145…`
(3.4.0), **won't work**, and the app won't start without the OBB.

<details>
<summary>Only have the 32-bit build?</summary>

The 32-bit build of 3.5.4 (versionCode **1100100**, `armeabi-v7a`, usually named
`com.lego.ar.hidden_3.5.4-1100100_minAPI24(armeabi-v7a)(nodpi)…apk`, SHA-256
`9a0cfbb135445453214647dc5eebcaae507e0dc3cea0b8c4a797e0578fb72e20`) works with the same script and OBB.
The game runs, but on a 64-bit phone **the minifigure scan won't show any ghosts**, because ARCore isn't available to
32-bit apps there. Only use it for a phone that can't run 64-bit apps.
</details>

### Step 3: Download this project and install the tools

1. Download this project: the green **Code** button → **Download ZIP**, then unzip it.
   (Or `git clone` it.)
2. Install the tools the scripts need:
   - **Windows:**
     - [Git for Windows](https://git-scm.com/download/win), which includes **Git Bash**
     - [7-Zip](https://www.7-zip.org/)
     - [Android Studio](https://developer.android.com/studio). Open it once, then go to **More Actions → SDK Manager →
       SDK Tools** and make sure **Android SDK Build-Tools** and **Android SDK Platform-Tools** are checked.
       Android Studio includes the Java that the scripts need.
   - **macOS / Linux:** Android Studio as above, plus 7-Zip (`brew install sevenzip` or `sudo apt install 7zip`).
     The scripts are written for these too, but they've only been tested on Windows.
3. Copy the APK and the OBB into the unzipped project folder. **Rename the APK to `original.apk`** so the commands
   below work as written.

The folder should now look like this:

```
hidden-side-revival/
├── original.apk                            <- the 3.5.4 APK you downloaded (renamed)
├── main.1100100.com.lego.ar.hidden.obb     <- the OBB you downloaded
├── scripts/
├── README.md
└── ...
```

### Step 4: Build the patched APK

Open a terminal in the project folder. On Windows: right-click inside the folder → **Show more options →
Open Git Bash here**. Then run:

```bash
bash scripts/patch_apk.sh original.apk
```

You should see (for the 64-bit build):

```
input: Hidden Side 3.5.4 arm64-v8a build (expected versionCode 1200100)
patched: sunset time bomb (IsDiscontinued -> always false)
patched: always pick new session ghosts (fixes see-through minifigure scan ghost)
patched: targetSdkVersion 30 -> 29 (lets Vuforia find ARCore)
Done -> HiddenSide-3.5.4-patched.apk
```

`HiddenSide-3.5.4-patched.apk` is now in the project folder. The script detects whether you gave it the 64-bit or the
32-bit build and checks every byte it changes. If you get `wrong APK version?`, you have a different version than 3.5.4.

<details>
<summary>APK somewhere else, or a different output name?</summary>

You can give the script any path. The second argument (optional) is the output file:

```bash
bash scripts/patch_apk.sh ~/Downloads/com.lego.ar.hidden_3.5.4.apk ~/Desktop/HiddenSide-patched.apk
```

Put quotes around paths that contain spaces or parentheses. Tip: in Git Bash you can drag a file onto the window
to paste its path.
</details>

<details>
<summary>Optional: Ghost mode against computer-controlled players (experimental)</summary>

Ghost mode is a multiplayer mode (you play a ghost, someone else hunts you), and it needs LEGO's servers, which are
gone. With this option the game runs Ghost mode on the phone itself, and fills the empty places with computer-controlled
ghosts and a computer-controlled hunter. Build the APK like this instead:

```bash
GHOST_OFFLINE=1 bash scripts/patch_apk.sh original.apk
```

Then in the game: **Ghost mode → Play multiplayer**. The search screen looks for other players for a moment, then
you become the host and the match starts with computer players. Tested on one phone with full matches.

Not working yet: **Private match** stops on a half-black screen after choosing a set (it asks the dead server for a
room code). This option also makes the game's "is there internet?" check always say yes, so online-only features
don't show a "need internet" message anymore; they still don't work.
</details>

### Step 5: Install on the phone

**Option A: with the install script (easiest)**

1. On the phone, enable **Developer options** (tap *Build number* 7 times in *Settings → About phone*),
   then turn on **USB debugging**.
2. Connect the phone by USB and tap **Allow** when it asks about USB debugging.
3. In the same terminal, run:

```bash
bash scripts/install.sh HiddenSide-3.5.4-patched.apk main.1100100.com.lego.ar.hidden.obb
```

This installs the patched APK and copies the OBB to the right place, under the name that matches the installed build
(`main.1200100…` for the 64-bit build). Copying the OBB takes a minute or two. Accept the install prompt on the phone
if one appears.

**Your progress is kept.** If Hidden Side is already on the phone, the script updates it when it can. If the old app
has to be uninstalled first (for example the original app from Google Play, which has a different signature),
the script first copies your save file (`game.lego`) to a `savegame-backup-<date>` folder on your computer and puts it
back after installing. Keep the phone unlocked while it does that.

The script also works on **Xiaomi/HyperOS** phones, where the normal `adb install` fails with
`INSTALL_FAILED_USER_RESTRICTED` (it uses a `pm install-create/-write/-commit` session install).

**Option B: by hand**

1. If Hidden Side is already installed and you want to keep your progress, first copy
   `Internal storage/Android/data/com.lego.ar.hidden/files/game.lego` to your computer. Uninstalling deletes it.
2. Uninstall any existing Hidden Side app from the phone.
3. Copy `HiddenSide-3.5.4-patched.apk` to the phone, open it in the phone's file manager and install it
   (allow installing from unknown sources if asked).
4. Connect the phone to the PC as a USB drive (*File transfer*), copy the OBB to the folder
   `Internal storage/Android/obb/com.lego.ar.hidden/` (create it if it doesn't exist) and **rename it** to match the
   build you installed:
   - 64-bit build: `main.1200100.com.lego.ar.hidden.obb`
   - 32-bit build: `main.1100100.com.lego.ar.hidden.obb`
5. To restore your progress: start Hidden Side once, close it, and copy `game.lego` back to
   `Internal storage/Android/data/com.lego.ar.hidden/files/`.

### Step 6: Play

Start **Hidden Side** on the phone. With the 32-bit build, recent Android versions may show a warning that the app
*"isn't compatible with the latest version of Android"*. Tap **OK** and the game starts.

---

## Phone requirements

- **64-bit build (recommended):** any 64-bit Android phone (Android 7.0 or newer). It should also run on newer phones
  that only run 64-bit apps, like the Pixel 7 and later (not tested yet; reports welcome).
- **32-bit build:** the phone must run 32-bit apps. With USB debugging on, `adb shell getprop ro.product.cpu.abilist`
  must include `armeabi-v7a`. On 64-bit phones the minifigure scan won't show ghosts with this build.
- **ARCore** support ("Google Play Services for AR") for the AR features.
- Tested: Xiaomi 13 Pro, HyperOS 3 / Android 16, with both builds.

The OBB must match the APK exactly: Unity ties them together with a build ID (`3d831307-2e2e-45e9-9482-9603eb45051e`),
which both 3.5.4 builds share.

### No tools at all? (quick test only)
The unpatched 3.5.4 also starts if the device date is set to **2022**. That's fine for a quick try, but not something
you want on your everyday phone, and the minifigure scan still won't show ghosts on Android 11 and newer.

## What works

| Works ✅ | Doesn't work ❌ |
|---|---|
| Startup, Newbury map, tutorial | Online multiplayer with other players (Photon servers shut down) |
| Single-player gameplay, ghost hunting | Ghost mode private match |
| Minifigure scan and its ghost mini-game (64-bit build) | Online extras: mail, events, leaderboards, LEGO ID |
| Ghost Zoo (a showcase: your ghosts move around on your set; there is no scoring) | |
| Ghost mode against computer players (with the optional `GHOST_OFFLINE=1` patch) | |
| Game data (bundled in the OBB), local saves (`game.lego` on the device) | |

## Troubleshooting

| Problem | Fix |
|---|---|
| `Android SDK build-tools not found` | Install Build-Tools in Android Studio's SDK Manager (Step 3), or set `ANDROID_HOME` to your SDK folder. |
| `Java (JDK) not found` | Install Android Studio (it includes Java), or set `JAVA_HOME`. |
| `7-Zip (7z) not found` | Install [7-Zip](https://www.7-zip.org/). |
| `wrong APK version?` | Your APK isn't one of the two 3.5.4 builds. Compare its SHA-256 with the table in Step 2. |
| `No phone found` | Check the USB cable, turn on USB debugging and tap **Allow** on the phone. |
| `Install was cancelled on the phone` | The phone showed an install prompt that wasn't accepted in time. Run the script again and tap **Install**. |
| `INSTALL_FAILED_NO_MATCHING_ABIS` | The build doesn't fit your phone. Use the 64-bit build. |
| The app doesn't get past startup | Most likely the OBB is missing, in the wrong folder, misnamed or from another version. Check Step 5. |
| Minifigure scan: no ghost appears when you aim the phone around | You're running the 32-bit build or an unpatched app. Install the patched 64-bit build. |
| Minifigure scan: the ghost is see-through and can't be hurt | Fixed by the patch (see [What was wrong](#3-a-see-through-ghost-that-cant-be-hurt)). Make sure you installed a build made with the current script. |
| Ghost mode: `NEED INTERNET` | Ghost mode needs the dead servers. Build with `GHOST_OFFLINE=1` to play against computer players (Step 4). |

## Known issues

- **Ghost mode private match** stops on a half-black screen after you choose a set, even with `GHOST_OFFLINE=1`.
  Use *Play multiplayer* instead.
- **Ghost mode ammo** is hard to find. That seems to be how the mode was designed, not a result of the patch.

## To do / help wanted

Contributions are welcome. Open an issue or pull request.

- **Ghost mode private match with computer players.** The game asks the dead server for a room code; skipping that
  request (see [docs/TECHNICAL.md](docs/TECHNICAL.md)) should let a private match start offline too.
- **Online multiplayer with real players.** Multiplayer uses [Photon](https://www.photonengine.com/)
  (`ns.exitgames.com`), and LEGO's Photon app ID has been disabled. Possible routes: register a new (free tier) Photon
  Cloud app ID and patch it into the app, or run a self-hosted Photon-compatible server. Private matches also need
  room codes from the game server (see the next item).
- **Replacement game server.** The original Kung Fu Factory server (`projectbanana.ninja`) is gone. Its address is in
  `server_settings.json` inside the OBB (plain HTTP, no TLS), so a self-hosted server could stand in for it.
  First step: find out which features (mail, events, currency, multiplayer) actually need it.

## How it was found

See [docs/TECHNICAL.md](docs/TECHNICAL.md) for the full write-up: IL2CPP analysis, startup flow, the ARCore problem,
the dead backends and the patches themselves.

## License

Scripts and documentation: MIT (see [LICENSE](LICENSE)). The game, its assets and trademarks belong to the LEGO Group.
