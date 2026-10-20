# Altitude

A personal iOS app that shows your current altitude, and puts it on the CarPlay
screen without a CarPlay entitlement. Three surfaces:

| Surface | Mechanism | Updates |
|---|---|---|
| Phone app | SwiftUI, GPS + barometer fused | every second |
| CarPlay Dashboard / Lock Screen / Dynamic Island / Apple Watch | Live Activity (`.small` activity family) | every 2–15 s while tracking |
| Home Screen / StandBy / CarPlay widget stack | WidgetKit `systemSmall` widget | last known value, ~every 15 min |

No App Store review is involved. Builds go straight from Xcode to your iPhone.

## Why this shape

Apple grants CarPlay *app* entitlements case by case and only for listed
categories, so a dedicated CarPlay app is not something you can just build for
yourself. Since iOS 26, widgets and Live Activities appear in CarPlay with no
entitlement and no CarPlay app. The Live Activity is the live surface; the
widget is the "last known" surface.

## Requirements

* macOS with Xcode 27 (Xcode 26 also builds it, but the CarPlay Simulator then
  comes from "Additional Tools for Xcode" instead of Device Hub).
* iPhone on iOS 26 or later. Barometric altitude needs an iPhone with a
  barometer that reports absolute altitude (iPhone 12 and later); the app
  falls back to GPS-only otherwise.
* Apple Developer Program membership (paid gives one-year installs; a free
  account works but builds expire after 7 days).
* [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`.

## First run

1. Put your Team ID in `Config/Signing.xcconfig` (copy from
   `Config/Signing.xcconfig.example`; the file is gitignored). Find it at
   Xcode > Settings > Accounts, or developer.apple.com/account > Membership.
2. Generate the project and open it:

   ```sh
   xcodegen generate
   open Altitude.xcodeproj
   ```

   If `generateEmptyDirectories` ever misbehaves, deleting `Altitude.xcodeproj`
   and re-running `xcodegen generate` is always safe; the project file is
   derived from `project.yml`.
3. Plug in your iPhone, pick it as the run destination, and run the `Altitude`
   scheme. Xcode registers the App ID, the App Group
   (`group.com.gregcorey.altitude`), and a development profile automatically.
   If signing complains about the App Group, open Signing & Capabilities for
   both targets and let Xcode "fix" it once.
4. On the phone: tap **Start tracking**, allow location ("While Using") and
   motion access. The big number should settle within a few seconds outdoors.

### Installing from the command line

`Scripts/deploy.sh` builds, installs, and relaunches the app on the phone
(device ID as the first argument or in `ALTITUDE_DEVICE`; the default is the
author's phone). It terminates the running app before installing. Installing a
new build over an app that is in the middle of a background location session
can orphan that session, and the location indicator then stays in the status
bar until the phone restarts. Stopping tracking before an install, or letting
the script kill the app, avoids it.

## Putting it in the car

* **Live Activity (the live one).** The Live Activity appears on the CarPlay
  Dashboard (the split view with the Maps tile, not the icon grid). If the
  Dashboard is not visible it arrives as a notification at the bottom of the
  display. Verified 2026-10-17 in the CarPlay Simulator. Two things were
  needed:
  1. On the **car screen**, open CarPlay's own Settings app and turn on
     **Siri Suggestions**. Live Activities was already on and nothing showed
     until Siri Suggestions was on too. These switches live on the car screen,
     not in the iPhone's CarPlay settings.
  2. Connect CarPlay first, then tap **Start tracking**. The activity is placed
     on the Dashboard when it begins.
* **Widget (last known).** On the iPhone, Settings > General > CarPlay > your
  car > Widgets, add "Altitude". It shows in the stacks to the left of the
  Dashboard. It refreshes every 5 minutes while tracking (WidgetKit budget);
  the "ago" timer ticks on its own between refreshes.

### Testing without a car

Xcode 26: download "Additional Tools for Xcode 26" from the developer
downloads page; CarPlay Simulator is in its Hardware folder. Xcode 27: it is
built into Window > Device Hub (choose CarPlay Simulator from the Device
menu). Either way, connect the iPhone by USB and CarPlay starts on the phone
as if it were plugged into a car. Start tracking in the app and walk around (or
drive with a passenger) to see the Live Activity move.

## What to check on the first real drive

These are the things the research could not settle from documentation:

1. **Background Live Activity updates keep flowing.** Some iOS versions
   throttled app-driven updates in the background. The app runs with the
   `location` background mode plus a `CLBackgroundActivitySession`, which is the
   supported way to stay alive, but confirm the number keeps moving on the
   CarPlay screen after the phone has been locked for a while.
2. **Vehicle-supplied GPS.** Some head units feed the phone a GPS fix with
   altitude exactly `0.0`. The service treats that as invalid and leans on the
   barometer. If the number drops to 0 or freezes, that is the thing to look at
   (see `ingest(_:)` in `AltitudeService.swift`).
3. **Cabin pressure.** Closed windows and climate control can shift the
   barometer by a few metres. The fused value anchors to GPS slowly, so short
   blips should wash out.

## Layout

```
project.yml                  XcodeGen spec (targets, Info.plist keys, entitlements)
Config/Signing.xcconfig      your Team ID (gitignored)
Shared/                      compiled into both targets
  AltitudeModel.swift          units, reading, formatting
  SharedStore.swift            App Group storage used by the widget
  AltitudeAttributes.swift     Live Activity payload
Altitude/                    the app
  AltitudeService.swift        Core Location + Core Motion, fusion, climb rate
  LiveActivityController.swift start / throttled update / end
  WidgetRefresher.swift        budget-aware widget reloads
  ContentView.swift            main screen
AltitudeWidget/              widget extension
  AltitudeWidget.swift         home / StandBy / CarPlay / Lock Screen widget
  AltitudeLiveActivity.swift   Lock Screen, Dynamic Island, CarPlay (.small)
```

## Adding data points later

`AltitudeReading` already carries optional latitude, longitude, speed and
course. New fields (pressure, temperature, weather, sunrise) go there as
optionals so stored readings and the Live Activity payload stay compatible.
Keep the Live Activity `ContentState` under 4 KB.

## Glossary

* **CarPlay entitlement**: an Apple-granted permission, per app category, that
  a real CarPlay app must carry in its provisioning profile.
* **Live Activity**: a system-managed card for an ongoing task (ActivityKit).
  Shown on the Lock Screen, Dynamic Island, Apple Watch, and since iOS 26 the
  CarPlay Dashboard.
* **WidgetKit budget**: the system's cap on how often a widget may reload,
  roughly 40–70 times a day.
* **App Group**: a shared container that lets the app and its widget
  extension read the same `UserDefaults`.
* **Activity family `.small`**: the compact Live Activity size used by Apple
  Watch and CarPlay.
