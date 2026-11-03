# TripCheck for iPhone

TripCheck reads trip offers on screen and shows, in a small floating window, whether each
offer meets your minimums: £ per mile, £ per minute (including the drive to the pickup)
and passenger rating. Green means it meets your minimum, red means it's below, and amber
means TripCheck couldn't tell.

## How it works on the phone

1. **Start reading offers**: this big button in TripCheck opens Apple's *Screen Broadcast*
   sheet with TripCheck already chosen. Tap **Start Broadcast**.
2. **Screen broadcast reader**: while the broadcast is on, a small part of TripCheck looks
   at the lower part of the screen about twice a second. It reads the offer card's words
   with Apple's on-device text recognition. Nothing is uploaded, and it never logs in to
   your driver account.
3. **Floating window**: TripCheck shows the result in a picture-in-picture window that
   floats over the driver app. You can drag it, pinch it, or tuck it to the side.

## Getting an .ipa without a Mac

### 1. Put this folder on GitHub (once)
1. On github.com, click **New repository**. Name it `tripcheck-ios` and click **Create repository**.
   *Public* gets unlimited free build time. *Private* gets about 200 free Mac minutes a
   month, which is roughly 20 builds.
2. On the new repository's page, click **uploading an existing file**.
3. Open this `ios` folder in File Explorer, select **everything inside it** (including the
   `.github` folder) and drag it all onto the page. `project.yml` must end up at the top
   level, not inside another folder.
4. Click **Commit changes**.

If dragging leaves out the `.github` folder, use GitHub Desktop instead
(File › Add local repository, choose this `ios` folder, then Publish).

### 2. Let GitHub build it (about 5–10 minutes)
1. Open the **Actions** tab. A run called **Build iPhone app** starts by itself after each
   upload. You can also click **Run workflow** to start one.
2. When it shows a green tick, open the run. Under **Artifacts**, download **TripCheck-ipa**.
   Unzip it to get `TripCheck.ipa`.
3. If it shows a red cross instead, download **build-log** and send it to Claude to fix.

### 3. Install it with Sideloadly
1. Connect the iPhone to the PC with a cable, open Sideloadly, drag `TripCheck.ipa` in,
   enter your Apple ID and click **Start**.
2. On the iPhone, turn on **Settings › Privacy & Security › Developer Mode** (it restarts).
   Then trust your Apple ID under **Settings › General › VPN & Device Management**.
3. With a free Apple ID, re-install every 7 days. A paid Apple Developer account
   (about £79 a year) lasts a year.

### 4. First test
1. Open TripCheck and tap **Show a sample offer**. The window at the top should turn green
   or red.
2. Tap **Start reading offers**, then **Start Broadcast**, then switch to the driver app.
   The floating window should say *TripCheck ready*.
3. If TripCheck shows an orange warning about the *shared app group*, the signing step
   left that permission out. Tell Claude: the fix is a different signing option or a paid
   developer account.

## What's in this folder
- `Sources/Shared`: the rules and the offer reader (same as the desktop prototype)
- `Sources/Broadcast`: the screen broadcast reader
- `Sources/App`: the app screens, Start button and floating window
- `Config`: app settings and permissions
- `project.yml`: the project description used by the build
- `.github/workflows/build-ipa.yml`: the build recipe for GitHub's cloud Macs

Not tested on a device yet: this was written on Windows, so the first GitHub build is also
the first time it's compiled.
