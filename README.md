# Hidden Side Revival

Get the discontinued **LEGO® Hidden Side™** AR app (2019–2023) running again on Android.

LEGO ended support for the app on 1 January 2023, and since then it shows
*"The LEGO® Hidden Side App is now discontinued"* and quits. This project fixes that with a **one-instruction patch**.
Single-player, the Newbury map, ghost hunting and local saves work again. Multiplayer doesn't (yet): LEGO turned off
those servers.

## What was wrong

You might expect the app died because LEGO shut down its servers. It didn't. **LEGO built a time bomb into the
final version of the app.**

The last release, 3.5.4, was LEGO's "sunset" update. When the app starts, it checks the phone's clock:

```csharp
bool IsDiscontinued() => DateTime.Now.Year > 2022;
```

From 1 January 2023 that returns `true`, so the app shows the "now discontinued" message, and the OK button closes it.
The year 2022 is written directly into the app's code (hard-coded); no server or setting is involved.

Everything else the game needs is still there: the map, scenes, ghosts, game data and AR targets ship with the app
and its OBB data file. Set a phone's date back to 2022 and the unmodified app runs fine without any server.

**The fix:** in the app's compiled code (`lib/armeabi-v7a/libil2cpp.so`, offset `0x8BF3CC`), the number 2022 is
changed to 9999. That's 2 bytes. The check is still there, but it won't trigger until the year 10000.
See [docs/TECHNICAL.md](docs/TECHNICAL.md) for how it was found.

A second, unrelated reason people couldn't get it working: Google Play used to download the ~490 MB **OBB** game
content file separately. APK download sites usually only have the APK, and without the OBB the app has no content.

> **This repo contains no LEGO files.** You need your own copy of the original APK and its OBB data file.
> The scripts only modify your copy. Not affiliated with or endorsed by the LEGO Group.
> LEGO and Hidden Side are trademarks of the LEGO Group.

---

## Quick guide

### Step 1: Check that your phone can run it

Hidden Side 3.5.4 is a **32-bit** app. Many phones from 2023 and later (Pixel 7 and newer, some recent flagships)
only run 64-bit apps and **can't** run it. Your phone also needs ARCore support for the AR scanning.
See [Phone requirements](#phone-requirements) for how to check.

### Step 2: Get the two game files

The game files are copyrighted by LEGO, so this project can't include them or link to them.
**Search the internet for them yourself.** Get exactly these versions:

| File | What to look for | SHA-256 (to check you got the right file) |
|---|---|---|
| **APK** (the app) | LEGO Hidden Side **3.5.4**, versionCode **1100100**, `armeabi-v7a` | `9a0cfbb135445453214647dc5eebcaae507e0dc3cea0b8c4a797e0578fb72e20` |
| **OBB** (game content, ~490 MB) | `main.1100100.com.lego.ar.hidden.obb` | `07cd79c47bb360429f7b6feef38e3f791c2256c71e1a3102142c176d12f42a49` |

The OBB **must** be the one for 3.5.4 (the `1100100` in its name). OBBs from other versions, like `main.809145…`
(3.4.0), **won't work**, and the app won't start without the OBB.

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
├── original.apk                            <- the 3.5.4 APK you downloaded
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

You should see:

```
patched: sunset time bomb (year > 2022 -> year > 9999)
Done -> HiddenSide-3.5.4-patched.apk
```

`HiddenSide-3.5.4-patched.apk` is now in the project folder. The script checks that you gave it the right APK. If you
get `wrong APK version?`, you have a different version than 3.5.4.

<details>
<summary>APK somewhere else, or a different output name?</summary>

You can give the script any path. The second argument (optional) is the output file:

```bash
bash scripts/patch_apk.sh ~/Downloads/com.lego.ar.hidden_3.5.4.apk ~/Desktop/HiddenSide-patched.apk
```

Put quotes around paths that contain spaces or parentheses. Tip: in Git Bash you can drag a file onto the window
to paste its path.
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

This removes any existing Hidden Side app (the patched APK has a different signature), installs the patched APK and
copies the OBB to the right place. Copying the OBB takes a minute or two.

The script also works on **Xiaomi/HyperOS** phones, where the normal `adb install` fails with
`INSTALL_FAILED_USER_RESTRICTED` (it uses a `pm install-create/-write/-commit` session install).

**Option B: by hand**

1. Uninstall any existing Hidden Side app from the phone.
2. Copy `HiddenSide-3.5.4-patched.apk` to the phone, open it in the phone's file manager and install it
   (allow installing from unknown sources if asked).
3. Connect the phone to the PC as a USB drive (*File transfer*) and copy the OBB to this exact location:
   `Internal storage/Android/obb/com.lego.ar.hidden/main.1100100.com.lego.ar.hidden.obb`
   (create the `com.lego.ar.hidden` folder if it doesn't exist; the file name must be exactly this).

### Step 6: Play

Start **Hidden Side** on the phone. On recent Android versions you may see a warning that the app
*"isn't compatible with the latest version of Android"* (because it's 32-bit). Tap **OK** and the game starts.

---

## Phone requirements

- It must run **32-bit ARM apps**. With USB debugging on, run `adb shell getprop ro.product.cpu.abilist`;
  the output must include `armeabi-v7a`.
- ARCore support for the AR scanning.
- Tested: Xiaomi 13 Pro, HyperOS 3 / Android 16.

The OBB must match the APK exactly: Unity ties them together with a build ID (`3d831307-2e2e-45e9-9482-9603eb45051e`).

### No tools at all? (quick test only)
The unpatched 3.5.4 also works if the device date is set to **2022**. That's fine for a quick try or an emulator,
but not something you want on your everyday phone.

## What works

| Works ✅ | Doesn't work ❌ |
|---|---|
| Startup, Newbury map, tutorial | Multiplayer (Photon servers shut down) |
| Single-player gameplay, ghost hunting | Online extras: mail, events, leaderboards, LEGO ID |
| Game data (bundled in the OBB) | |
| Local saves (`game.lego` on the device) | |

## Troubleshooting

| Problem | Fix |
|---|---|
| `Android SDK build-tools not found` | Install Build-Tools in Android Studio's SDK Manager (Step 3), or set `ANDROID_HOME` to your SDK folder. |
| `Java (JDK) not found` | Install Android Studio (it includes Java), or set `JAVA_HOME`. |
| `7-Zip (7z) not found` | Install [7-Zip](https://www.7-zip.org/). |
| `wrong APK version?` | Your APK isn't 3.5.4 (1100100, armeabi-v7a). Compare its SHA-256 with the table in Step 2. |
| `No phone found` | Check the USB cable, turn on USB debugging and tap **Allow** on the phone. |
| `INSTALL_FAILED_NO_MATCHING_ABIS` | Your phone is 64-bit only and can't run 3.5.4. |
| The app doesn't get past startup | Most likely the OBB is missing, in the wrong folder, misnamed or from another version. Check Step 5. |

## To do / help wanted

Contributions are welcome. Open an issue or pull request.

- **Multiplayer with a self-hosted server.** Multiplayer uses [Photon](https://www.photonengine.com/) (`ns.exitgames.com`),
  and LEGO's Photon app ID has been disabled. Possible routes: register a new (free tier) Photon Cloud app ID and patch
  it into the app, or run a self-hosted Photon-compatible server (Photon Server, or an open-source reimplementation).
  The game also asks its own game server for multiplayer settings (`ic_multiplayer/*`), so that part probably
  needs a replacement server too. Not investigated yet.
- **Replacement game server.** The original Kung Fu Factory server (`projectbanana.ninja`) is gone. Its address is in
  `server_settings.json` inside the OBB (plain HTTP, no TLS), so a self-hosted server could stand in for it.
  First step: find out which features (mail, events, currency, multiplayer) actually need it.
- **64-bit-only phones.** 3.5.4 only exists as 32-bit. The older 3.4.0 has a 64-bit (arm64) build that might run on
  newer phones like the Pixel 7+. It needs its own analysis: does it have the same time bomb, and does its OBB work?

## How it was found

See [docs/TECHNICAL.md](docs/TECHNICAL.md) for the full write-up: IL2CPP analysis, startup flow, the dead
backends and the patch itself.

## License

Scripts and documentation: MIT (see [LICENSE](LICENSE)). The game, its assets and trademarks belong to the LEGO Group.
