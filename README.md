# MyNotch

**Repository:** [github.com/Aadhavm10/MyNotch](https://github.com/Aadhavm10/MyNotch)

MyNotch turns the MacBook's camera notch into a small, always-there control center. At rest it looks like the normal notch, with a few live indicators beside it. Hover over it and it opens into a panel with your music, calendar, a Pomodoro timer, a file tray, clipboard history, recent screenshots and sound output controls.

It's a personal, open-source take on apps like [NotchNook](https://lo.cafe/notchnook). It's written in Swift (SwiftUI + AppKit), has no Dock icon, lives in the menu bar, and starts at login. Macs without a notch get a drawn "fake" notch.

> MyNotch isn't affiliated with NotchNook or lo.cafe. It uses a private macOS API for Now Playing (see [Media](#media)), so it's built for personal use and can't be distributed through the Mac App Store.

---

## Features

### The closed notch: live activities
While the notch is closed, it can show a small indicator on each side of the camera:

| Activity | Left | Right | When |
|---|---|---|---|
| **New screenshot** | Thumbnail | Green 📸 | For 4 seconds after you take a screenshot |
| **Pomodoro** | Progress ring | `mm:ss` countdown | While a Pomodoro session is active |
| **Now Playing** | Album art | Animated visualizer | While music or video plays (hides after it's been paused for 10s) |
| **Tray** | Tray icon | File count | When the tray has files in it |

If several apply at once, the one highest in the table wins. Each one can be turned off in **Settings → General → Live Activities**.

### The open notch: tabs
Hover over the notch (or click it, if you prefer) to open it. The header has one tab per feature:

| Tab | What it does |
|---|---|
| **Nook** ▦ | The main widgets: **Media**, **Calendar** and **Pomodoro**. **Shortcuts** and a webcam **Mirror** can be added in Settings. |
| **Tray** 📥 | Drag files from Finder onto the notch to keep them handy. Drag them back out, open them, AirDrop or share them, or clear the tray (it asks first). |
| **Clipboard** 📋 | Everything you've copied (text, links, colors, images, Finder files). Click a card to copy it again; pin favorites. Password managers' copies are never recorded. |
| **Screenshots** 📸 | Your recent screenshots and screen recordings. Click to copy, drag into any app, keep in the tray, or move to the Trash. |
| **Sound** 🔊 | Switch audio output (speakers, AirPods, monitors, AirPlay) with one click, and set the volume or mute. |

### Widgets in the Nook
- **Media**: album art (click it to jump to the app), title and artist, a draggable scrubber, play/pause/skip, and a visualizer tinted by the artwork. Works with Spotify, Apple Music, Safari, Chrome and anything else that reports Now Playing to macOS.
- **Calendar**: today's and upcoming events from the calendars you choose. Click an event to open Calendar.
- **Pomodoro**: focus and break cycles with a progress ring, play/skip/reset, a daily goal and a 7-day history. Plays a sound and shows a notification when a phase ends.
- **Shortcuts** (optional): buttons that run the Siri Shortcuts you pick.
- **Mirror** (optional): a live webcam preview for checking yourself before a call. The camera only runs while the Nook is open.

### Customization
Everything is in **Settings** (menu bar icon → Settings…, or the ⚙ in the notch):
- **General**: open on hover or click, hover and close delays, open the tray when you drag in files, haptics, fake notch on screens without one, live activities, launch at login.
- **Layout**: Nook and tab sizes, widget spacing and dividers, padding, corner radius, notch width fine-tuning. "Keep the notch open while editing" lets you watch changes live.
- **Widgets**: which widgets appear in the Nook and in what order, calendar selection, Shortcuts buttons, Mirror camera.
- **Pomodoro**, **Tray**, **Clipboard**, **Screenshots**: durations and alerts, storage and retention, history size, ignored apps, and so on.

### Menu bar and automation
The menu bar icon has Open Notch, Open Tray, Hide/Show Notch, Pomodoro controls, Settings and Quit.
MyNotch also responds to `mynotch://` links, which you can use from Shortcuts, Raycast, Alfred or a script:

| URL | Action |
|---|---|
| `mynotch://open` | Open the notch (add `?tab=nook`, `tray`, `clipboard`, `screenshots` or `sound`) |
| `mynotch://close` | Close the notch |
| `mynotch://settings` | Open Settings |
| `mynotch://pomodoro/toggle` · `/skip` · `/reset` | Control the Pomodoro timer |

For example, from Terminal: `open "mynotch://open?tab=clipboard"`.

---

## Getting started

### Requirements
- **Any MacBook with a notch**: 14" and 16" MacBook Pro (2021 and later), 13" and 15" MacBook Air (M2 and later), at any display scaling ("Larger Text" through "More Space"). Macs and displays without a notch get a drawn notch instead.
- macOS 14 Sonoma or later. Made on an M1 Pro MacBook Pro running macOS 15.
- Xcode 16 or later (developed with Xcode 26.3).
- [Homebrew](https://brew.sh), for two build tools.

### 1. Install the build tools
```sh
brew install xcodegen cmake
```
- **XcodeGen** generates `MyNotch.xcodeproj` from `project.yml`.
- **CMake** builds the bundled Now Playing adapter. This happens automatically during the first build.

### 2. Get the code
```sh
git clone https://github.com/Aadhavm10/MyNotch.git
cd MyNotch
```

### 3. Create a signing certificate (once per Mac)
```sh
sh scripts/make-signing-cert.sh
```
This adds a self-signed **"MyNotch Local Signing"** code-signing certificate to your login keychain. Signing every build with the same certificate means macOS remembers the permissions you grant (Downloads, Calendar, Camera). Without it, each rebuild looks like a new app and you'd be asked again. It's normal for the certificate to show as `CSSMERR_TP_NOT_TRUSTED`.

> Prefer not to? In `project.yml`, set `CODE_SIGN_IDENTITY: "-"` to sign ad-hoc. Everything still works, but macOS re-asks for permissions after each build.

### 4. Build and install
```sh
./scripts/install.sh
```
This builds a Release copy, installs it to **`/Applications/MyNotch.app`**, and launches it. The installed copy registers itself to open at login. Run the script again any time to update your installed copy.

### 5. First launch: permissions
macOS asks for each permission the first time a feature needs it:

| Permission | Asked when | Used for |
|---|---|---|
| **Files in Downloads/Desktop** | At launch | Screenshot shelf (whichever folder your screenshots are saved to) |
| **Calendars** | You click "Allow Calendar Access" | Calendar widget |
| **Notifications** | You first start a Pomodoro | End-of-phase alerts |
| **Camera** | You turn on the Mirror | Mirror widget |
| **Automation** (may not be asked) | You first run a Shortcut | Shortcuts widget |

If you denied one by accident, turn it back on in **System Settings → Privacy & Security**.

> Running NotchNook as well? Turn it off in **System Settings → General → Login Items** so the two apps don't fight over the notch.

### Developing
```sh
xcodegen generate            # after adding or removing source files
open MyNotch.xcodeproj       # then ⌘R in Xcode
```
Or from the command line:
```sh
xcodebuild -project MyNotch.xcodeproj -scheme MyNotch -configuration Debug \
  -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/MyNotch.app
```
Only one MyNotch runs at a time, so launching a debug build quits the installed copy. Debug builds never take over the login item; only the copy in `/Applications` registers itself. When you're done, run `./scripts/install.sh` to update the installed app.

Debug builds also accept a few extra links:

| URL | Action |
|---|---|
| `mynotch://debug/simulate?screenWidth=1024&notchWidth=128&notchHeight=26` | Lay the notch out as if on another MacBook (any parameter can be left out; no parameters resets) |
| `mynotch://debug/pin?on=1` · `?on=0` | Keep the notch open, even when the mouse is elsewhere (handy for screenshots) |
| `mynotch://debug/snapshot` | Render the notch to `~/Library/Application Support/MyNotch/debug-snapshot.png`. `ImageRenderer` can't draw scroll views or AppKit-backed views, so prefer `screencapture`. |

If MyNotch is also installed in `/Applications`, a plain `open "mynotch://…"` goes to the **installed** copy, which launches it and quits your debug build. Send links to the debug build explicitly, with an absolute path:
```sh
open -a "$PWD/build/DerivedData/Build/Products/Debug/MyNotch.app" "mynotch://debug/pin?on=1"
```

### Uninstalling
1. Quit MyNotch from its menu bar icon.
2. Delete `/Applications/MyNotch.app`. If it's still listed in **System Settings → General → Login Items**, remove it there.
3. Optionally delete your data: `~/Library/Application Support/MyNotch` and `defaults delete com.aadhav.MyNotch`.
4. Optionally remove the signing certificate: open Keychain Access and delete "MyNotch Local Signing".

---

## Architecture

### Overview
```
                 ┌───────────────────────────── AppKit ──────────────────────────────┐
 mouse events ──►│ EventMonitor (global + local) ─► NotchWindowManager ─► NotchPanel │
 screen changes ─┤                                   │ picks the screen,   (borderless,│
                 │                                   │ positions the panel  transparent,
                 │                                   ▼                     above menu bar)
                 │                             NotchViewModel  ◄── state: closed/peek/open,
                 └─────────────────────────────────  │  ▲          tab, geometry, live activity
                                                     │  │
                 ┌──────────────────────────── SwiftUI │ ───────────────────────────────┐
                 │ NotchRootView ─► ClosedNotchView (live activities)                    │
                 │               └► OpenNotchView ─► Nook widgets / Tray / Clipboard /   │
                 │                                   Screenshots / Sound                  │
                 └───────────────────────────────────────────────────────────────────────┘
                                                     ▲
   Feature services (singletons, @Observable) ───────┘
   NowPlayingModel · TrayStore · ClipboardStore · ScreenshotStore · AudioOutputService ·
   CalendarService · ShortcutsService · CameraService · PomodoroTimer · SettingsStore
```

The app is **SwiftUI for everything you see** and **AppKit for everything around it**: the floating window, mouse tracking, drag and drop, the menu bar, sharing and the Settings window. Each feature is a self-contained service (an `@Observable` singleton) plus a view. The view model decides what's on screen; the views simply read from the services, so changes appear instantly.

### Project layout
```
MyNotch/
├── project.yml                  XcodeGen spec (targets, Info.plist keys, signing, build scripts)
├── scripts/
│   ├── install.sh               Release build → /Applications → relaunch
│   ├── make-signing-cert.sh     One-time local code-signing certificate
│   └── build-adapter.sh         Builds MediaRemoteAdapter.framework with CMake
├── Vendor/mediaremote-adapter/  Now Playing helper (ungive/mediaremote-adapter, BSD-3)
├── THIRD_PARTY_LICENSES.md
└── MyNotch/
    ├── App/          MyNotchApp (menu bar), AppDelegate (startup, URL scheme, single instance)
    ├── Window/       NotchPanel, NotchWindowManager, EventMonitor, NSScreen+Notch
    ├── Core/         NotchViewModel (state machine + geometry), SettingsStore, Haptics
    ├── UI/           NotchRootView, ClosedNotchView, OpenNotchView (+ Nook layout),
    │                 NotchShape, ConfirmOverlay
    ├── Features/
    │   ├── Media/        MediaRemoteAdapter, NowPlayingModel, MediaWidget, VisualizerView
    │   ├── Calendar/     CalendarService, CalendarWidget
    │   ├── Pomodoro/     PomodoroTimer (+ stats), PomodoroWidget
    │   ├── Shortcuts/    ShortcutsService, ShortcutsWidget
    │   ├── Mirror/       CameraService, MirrorWidget
    │   ├── Tray/         TrayStore, TrayView, Thumbnailer, Share
    │   ├── Clipboard/    ClipboardStore, ClipboardView
    │   ├── Screenshots/  ScreenshotStore, ScreenshotShelfView
    │   └── Audio/        AudioOutputService, SoundView
    ├── Settings/     SettingsWindowController, SettingsView (all panes)
    └── Resources/    Info.plist, entitlements, asset catalog
```

### The window
- **`NotchPanel`** is a borderless, transparent, **non-activating** `NSPanel` at `.statusBar + 8`, so it sits above the menu bar, on every Space and over full-screen apps. It never becomes the key or main window, so using the notch never steals focus from the app you're in. `NotchHostingView` accepts the first click anyway, so buttons still respond instantly.
- The panel is a fixed, full-width, 520pt-tall strip at the top of the screen. It never resizes; SwiftUI animates the notch shape inside it. **Fully transparent pixels let clicks fall through**, so the menu bar keeps working around the notch.
- **`NotchWindowManager`** picks the screen: the active screen if it has a notch, otherwise the active screen with a fake notch (if enabled), otherwise the built-in display. It re-checks when screens change, on Space and app switches, on wake, and once a second as a safety net. It never moves the notch while it's open.
- **`NSScreen+Notch`** measures the real notch from `safeAreaInsets.top` and the `auxiliaryTopLeftArea`/`auxiliaryTopRightArea` gaps.

### State and geometry: `NotchViewModel`
- A small state machine: **closed → peek → open**. Peek is the "about to open" bump used in click mode.
- **Opening:** `EventMonitor` feeds every mouse move and click, even ones meant for other apps, to the view model. In hover mode, resting over the notch's hot area for `hoverDelay` (0.15s) opens it, and leaving the open area for `closeDelay` (0.2s) closes it. Click mode peeks on hover and opens on click.
- **Drag to open:** `NotchRootView` puts an almost-invisible drop zone around the closed notch. When a file drag enters it, the notch opens straight to the Tray.
- **Geometry:** nothing assumes a particular MacBook. The notch's width and height are measured on each screen at runtime, and everything is sized from them: the closed notch, the live-activity icons, and the header row.
  - The **open size** comes from Layout settings, then gets two limits: it's never wider than the screen minus a margin (a 13" Air at "Larger Text" is only 1024pt wide), and never narrower than the header needs to fit on both sides of the camera (the notch is wider in points at "More Space").
  - The **header** keeps a gap exactly the notch's width plus a little clearance, centered, with equal-width sides for the tabs and the settings button. That way controls never end up behind the camera, whatever the notch size.
  - The Nook row is laid out with **explicit widths** (fixed-width widgets like Mirror first, then the rest split by weight), so widgets can never overflow and clip each other.
- **Live activity priority:** screenshot flash → Pomodoro → Now Playing → tray count.

### Settings: `SettingsStore`
Settings are grouped into Codable structs (general, layout, widgets, liveActivities, pomodoro, tray, clipboard, screenshots). Each is saved as JSON in `UserDefaults` under `settings.<group>`. When loading, **saved values are layered over the defaults**, so adding a new option in an update never resets the rest of a group.

### How each feature works

#### Media
Since macOS 15.4, apps can no longer call Apple's private **MediaRemote** framework directly. [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) works around this by loading a small framework into `/usr/bin/perl`, which Apple still allows. A build step compiles it (with CMake) and copies it into the app's `Resources`.
- `MediaRemoteAdapter` runs `perl mediaremote-adapter.pl … stream` and reads its newline-delimited JSON (title, artist, artwork, timing, playing state, source app). If the helper dies, for example after sleep, it restarts it with a back-off. On launch it also cleans up helpers left behind by a force-quit.
- Commands (play/pause, next, previous, seek) run the same script with `send`/`seek`.
- `NowPlayingModel` merges the updates. It works out the elapsed time locally so the scrubber moves smoothly, and picks a tint color from the artwork.
- The visualizer is **animated, not audio-reactive**, so it needs no microphone or screen-recording permission.

#### Tray
- Dropped files are **copied** into `~/Library/Application Support/MyNotch/Tray/<id>/`, with an index in `tray.json`. The tray survives restarts, even if the originals are moved or deleted.
- Dragging an item out hands over a **temporary copy**, so the receiving app can't empty the tray by moving the file.
- Quick Look thumbnails are generated and cached by `Thumbnailer`. AirDrop and Share go through `NSSharingService`.
- "Clear tray" asks first with `ConfirmOverlay`, a confirmation shown inside the notch. A system alert would take focus from the non-activating panel.

#### Clipboard
- macOS doesn't announce clipboard changes, so `ClipboardStore` checks the pasteboard's `changeCount` every 0.5s. That's a single integer read, so it costs almost nothing.
- It records Finder files, then text (keeping rich text for small items), then images (saved as PNG). Copying the same text again moves it to the top instead of adding a duplicate.
- **Privacy:** copies marked concealed or transient ([nspasteboard.org](http://nspasteboard.org) conventions, which 1Password, Bitwarden and others use) are skipped. So is anything copied while an app on the ignore list is in front (password managers by default; editable in Settings).
- History goes in `Clipboard/clipboard.json` plus `Clipboard/Images/`, or stays in memory only if "Remember history after quitting" is off.

#### Screenshots
- `ScreenshotStore` reads your screenshot folder from the Screenshot app's settings (`com.apple.screencapture location`, Desktop by default) and **watches it** with a file-system event source.
- It recognizes captures by the `com.apple.metadata:kMDItemIsScreenCapture` attribute that macOS stamps on every screenshot and screen recording, so it works in any language, whatever the file is named.
- *Why not Spotlight?* A Spotlight query silently returns nothing for protected folders (Desktop, Downloads) to apps that haven't been granted access, and it never shows a prompt. Reading the folder directly triggers the normal permission prompt.
- Folder access runs on a background queue. The first read waits on the macOS permission prompt, and on the main thread that would freeze the notch until it was answered.

#### Sound
- `AudioOutputService` uses **CoreAudio**. It lists devices that have output streams and aren't hidden, reads each one's name and transport type (built-in, Bluetooth, HDMI, AirPlay, USB…) to pick an icon, and sets `kAudioHardwarePropertyDefaultOutputDevice` to switch.
- Volume and mute use the device's virtual main volume. Some devices, like many HDMI monitors, don't expose one, and the tab says so.
- CoreAudio listeners on the device list, the default device and the current device's volume keep everything in sync, including changes made in Control Center and AirPods connecting.

#### Calendar, Shortcuts, Mirror
- **Calendar**: EventKit with full access, filtered to your chosen calendars and number of days. It refreshes whenever `EKEventStoreChanged` fires.
- **Shortcuts**: lists shortcuts with `/usr/bin/shortcuts list`, and runs one with `shortcuts run "<name>"` in the background.
- **Mirror**: an `AVCaptureSession` shown through a mirrored preview layer. It only runs while the Nook is open, so the camera light never stays on.

#### Pomodoro
`PomodoroTimer` stores the **end time** of the current phase rather than counting down seconds, so the timer stays correct across sleep. It cycles focus → short break (with a long break every N rounds), can auto-start the next phase, and plays a sound and posts a notification at the end of each phase. Completed sessions are counted per day in `UserDefaults` for the daily goal and 7-day history.

### Data and storage
| What | Where |
|---|---|
| Settings, Pomodoro stats | `UserDefaults` domain `com.aadhav.MyNotch` |
| Tray files | `~/Library/Application Support/MyNotch/Tray/` (+ `tray.json`) |
| Clipboard history | `~/Library/Application Support/MyNotch/Clipboard/` |
| Screenshots | Not copied. Shown from where macOS saved them. |

### Signing, sandbox and login item
- The app is **not sandboxed**. It has to launch `/usr/bin/perl` for Now Playing, read your screenshot folder, and run `shortcuts`. That's also why it isn't App Store-ready.
- It's signed with the local certificate from `make-signing-cert.sh`. The designated requirement is "this bundle ID, signed by this certificate", which stays the same across builds, so privacy permissions persist.
- Launch at login uses `SMAppService.mainApp`. On every launch, the copy in `/Applications` (or `~/Applications`) registers itself, replacing any registration that pointed elsewhere. Copies run from other places, like build folders, never register.

---

## Troubleshooting
| Problem | Fix |
|---|---|
| Notch doesn't appear | Check the menu bar icon: is "Show Notch" available (meaning it's hidden)? On a Mac without a notch, turn on **Settings → General → Show a notch on screens without one**. |
| Nothing in Media | Start playing something; Media only shows while an app reports Now Playing. If it stops updating after a macOS update, the MediaRemote workaround may need updating in `Vendor/mediaremote-adapter`. |
| Screenshot shelf empty | Allow access to your screenshot folder (the shelf shows a button when it's blocked). Only real screenshots appear, not ordinary images. |
| Permission prompts after every rebuild | You're signing ad-hoc. Run `sh scripts/make-signing-cert.sh` and make sure `project.yml` uses `MyNotch Local Signing`. |
| Doesn't start at login | Run `./scripts/install.sh` so the copy in `/Applications` registers itself, and approve MyNotch in **System Settings → General → Login Items**. |
| Two notch apps fighting | Quit NotchNook (or similar apps) and remove them from Login Items. |

---

## Credits and license
MyNotch is released under the [MIT License](LICENSE) © 2026 Aadhav Manimurugan.

It builds on these open-source projects (full notices in [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md)):
- [NotchDrop](https://github.com/Lakr233/NotchDrop) by Lakr Aream (MIT): window setup, event monitors, notch detection, and the basis of the tray.
- [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) by Kai Azim (MIT): the notch shape.
- [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) by Jonas van den Berg (BSD-3-Clause): Now Playing on macOS 15.4+.

The feature set is inspired by [NotchNook](https://lo.cafe/notchnook). No NotchNook code or assets are used.
