# TripCheck for iPhone

TripCheck reads trip offers on screen and shows, in a small floating window, whether each
offer meets your minimums: £ per mile, £ per hour (including the drive to the pickup)
and passenger rating. Green means it meets your minimum, red means it's below, and amber
means it nearly meets it (within the "nearly range" you set) or TripCheck couldn't tell.
Offers priced outside your fare range are shown in faded colours.

## What's new in 0.3.0

- **Floating window closes by itself after Stop**: after Stop Broadcast, Apple's sheet stays
  over TripCheck, and while it's up iOS ignores requests to close the window. TripCheck
  now keeps asking for several seconds, again as soon as TripCheck is back on screen, and
  as a last resort replaces the window. If it ever stays open, there's a
  *Close the floating window* button under the Start button.
- **Screenshot shortcut (second way of capturing offers)**: TripCheck adds a
  **Check Trip Offer** action to the Shortcuts app. Make a shortcut with *Take Screenshot*
  then *Check Trip Offer*, and put it on the AssistiveTouch button (or Back Tap). One tap
  when an offer appears: TripCheck reads the screenshot on the phone, saves the offer in
  History and shows the result at the top of the screen for a few seconds, as a coloured
  banner (🟢 meets, 🟠 nearly / couldn't tell, 🔴 below) and, if *Show When Run* is on,
  as Shortcuts' result panel with the same picture as the floating window. Setup steps are
  in the app under **Screenshot shortcut**. The screenshot isn't saved.
- **History shows how each offer was captured**: screen broadcast, screenshot shortcut, or
  both (the same card caught both ways is saved once). The export has a *Captured by* column.

## What's new in 0.2.0

- **Locations**: offers that arrive while you're parked (several at home, at a rank) now
  get your location too. Before, only the first one did, because the iPhone sends no new
  position until you move about 10 metres.
- **No addresses**: pickup and drop-off addresses are no longer read or saved. Addresses
  saved by the older version are removed from the phone the first time 0.2.0 opens.
- **Trip types** come only from the top of the card, matched against UberX, Electric,
  Comfort, Business, Priority, Teens, Pet, XL, XXL, Lux and Assist. A trip can have several
  (for example Business + Comfort + Electric). If none is found it says "Type not read"
  rather than guessing. Older history entries keep only the real trip types they had.
- **Fewer made-up offers**: a card only counts when it has the fare, the drive to the
  pickup, the trip and then an Accept / Confirm / Match button, in that order, and when two
  reads half a second apart agree. Scrolling the driver app's history no longer makes up
  offers. An offer with exactly the same numbers as one already saved (for example a
  screenshot of it opened in Photos) isn't saved again.
- **Start and stop**: the floating window now opens only once the broadcast has actually
  started, and closes by itself when it stops. It no longer pops up saying "Not reading".
- **Sliders** for the three minimums, each with a **nearly range** (amber), and a
  **fare range** (minimum and maximum fare, £0 to £50 in 50p steps; £50 means unlimited).
  The History tab keeps plain green / red.

## How it works on the phone

1. **Start reading offers**: this big button in TripCheck opens Apple's *Screen Broadcast*
   sheet with TripCheck already chosen. Tap **Start Broadcast**. The floating window opens
   once the broadcast has started.
2. **Screen broadcast reader**: while the broadcast is on, a small part of TripCheck looks
   at the lower part of the screen about twice a second. It reads the offer card's words
   with Apple's on-device text recognition. Nothing is uploaded, and it never logs in to
   your driver account.
3. **Floating window**: TripCheck shows the result in a picture-in-picture window that
   floats over the driver app. You can drag it, pinch it, or tuck it to the side.
4. **Stop reading offers** opens the same sheet; tap **Stop Broadcast** (or tap the red
   pill at the top of the screen). The floating window closes by itself.

## Offer history

While reading offers is on, every offer card is saved in the **History** tab, newest first.
TripCheck records the date and time, offer amount, minutes and miles to pickup, journey
minutes and miles, passenger rating, trip types, your location when the offer appeared,
whether it was exclusive or trip radar, and the holiday pay. Addresses are not saved. The
analysis next to each one uses your current minimums. **Export** (top right) shares the
history as a spreadsheet file, with one column listing the trip types and one yes/blank
column per trip type, so you can filter or count by type. The first time you tap Start
reading offers, the iPhone asks whether TripCheck may use your location; choose
**Allow While Using App**.

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
3. Look at the **Shared folder / Screen reader** line under the Start button. Signing with a
   free Apple ID usually leaves out the shared folder (the "app group"). That's fine: TripCheck
   then uses its **direct link**, a private connection inside the phone. Once the broadcast
   is on, the line should say *Screen reader: last heard … s ago*. If it still says *not heard
   from yet* after about 10 seconds, tell Claude.
4. If the iPhone asks whether TripCheck may use the local network, tap **Allow**. The direct
   link only talks to the phone itself.

## What's in this folder
- `Sources/Shared`: the rules, the offer reader (same as the desktop prototype) and the
  on-device text recognition used by both ways of capturing offers
- `Sources/App/CheckTripOfferIntent.swift`: the Check Trip Offer shortcut action
- `Sources/Broadcast`: the screen broadcast reader
- `Sources/App`: the app screens, Start button and floating window
- `Config`: app settings and permissions
- `project.yml`: the project description used by the build
- `.github/workflows/build-ipa.yml`: the build recipe for GitHub's cloud Macs

Version 0.3.0 was written on Windows after live testing of 0.2.0; its first GitHub build is
also the first time these changes are compiled (the shortcut action is new and untested). If the build shows a red cross, send the
build-log to Claude.
