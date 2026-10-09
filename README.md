# Remember

A native macOS menu bar app that remembers window layouts for each monitor setup. Arrange your apps on your work monitor, disconnect, then reconnect to return to the same layout. On the built-in screen, windows fill the usable area by default.

## Build the app

Requires macOS 13+ and Swift 5.9+ (Xcode or Command Line Tools: `xcode-select --install`).

```sh
git clone https://github.com/threewisemonkeys-as/remember_layout.git
cd remember_layout
./scripts/build-app.sh
```

This builds `dist/Remember.app` (ad-hoc signed for your Mac) and `dist/Remember.zip`. See [Build and verify](#build-and-verify) for tests and diagnostics.

## Use the app

1. Open `dist/Remember.app`. You can move it to Applications first if you prefer.
2. Click **Enable Accessibility** and enable **Remember** in System Settings → Privacy & Security → Accessibility. On macOS versions that rename this permission, follow the system prompt. If Remember is missing from the list, use the `+` button to add the app.
3. Arrange your windows. With **Automatic layouts** enabled, Remember saves after the windows stop moving for a few seconds.
4. Reconnect the same displays. Remember waits for the screens to settle, then restores the last arrangement.

Click the split-window icon in the menu bar to see the current setup and your saved layouts. Right-click it for quick actions. Closing the dashboard leaves Remember running.

- **Save now** replaces the current setup's snapshot with its open, movable windows. If an app fails to respond, existing slots are retained.
- **Restore layout** reapplies the current setup's layout immediately.
- **Automatic layouts** saves changes and restores layouts on reconnect, app startup, and wake. Reopened windows use remembered slots where a match is available. Pausing still allows manual save and restore.
- **Maximize on MacBook** fills the built-in screen, keeping the menu bar and Dock available. Turn it off to remember laptop window sizes instead.
- **Launch at login** uses macOS Login Items. Enable it after putting the app in its permanent location.
- Click the pencil to rename the current setup. Right-click a saved setup to rename or forget it; click it to expand its preview.

The first connection to a new monitor setup starts learning your arrangement. External-only (closed-lid), laptop-only, and combined laptop/external configurations have separate layouts. The same displays retain their layout when their resolution or physical arrangement changes; window positions scale relative to each display's usable area.

## Local data and permissions

Layouts and settings live in `~/Library/Application Support/Remember/layouts.json`. The file contains app identifiers, window titles, monitor identifiers, and relative window positions. It is saved atomically with owner-only file permissions. Everything stays on your Mac; there are no network services or third-party dependencies. The menu's **Show layout file in Finder** opens its location.

Remember uses Apple's [Accessibility API](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions) to inspect and reposition regular app windows. It needs no screen recording permission. The app does not launch closed apps, change Spaces, or exit full-screen mode. Minimized, hidden, full-screen, utility, and non-resizable windows are skipped. Some apps enforce minimum sizes or expose limited Accessibility support; Remember reports windows it cannot place.

Window matching uses unique Accessibility identifiers first, then exact window titles, then per-app window slots. Apps with several indistinguishable windows may require a manual adjustment. Layouts work on windows exposed by the public Accessibility API; restoring arbitrary windows across separate Spaces is not guaranteed.

This is a locally built, ad-hoc signed app for this Mac, rather than a notarized distribution. Moving or rebuilding it may require re-enabling its Accessibility entry. Keep the app at one path after granting permission.

## Build and verify

Requires macOS 13 or newer and Swift 5.9 or newer (Xcode or current Command Line Tools). No Xcode project or package downloads are needed. The checks use a standalone Swift runner so they also work when Xcode's test frameworks are unavailable.

```sh
./scripts/test.sh
./scripts/build-app.sh
open dist/Remember.app
```

The build script produces `dist/Remember.app` and `dist/Remember.zip` with a native app icon and verifies the local code signature. It builds for the host architecture (Apple silicon on this machine).

```sh
# Inspect display identity and Accessibility status without moving windows.
dist/Remember.app/Contents/MacOS/Remember --diagnose

# Launch the actual interface briefly, without saving data or moving other apps.
dist/Remember.app/Contents/MacOS/Remember --ui-smoke-test

# Save an image of the app's own interface during the smoke test.
dist/Remember.app/Contents/MacOS/Remember --ui-smoke-test --preview-output "$PWD/dist/preview.png"
```

For development, `--data-directory /absolute/path` stores layouts in that directory instead of Application Support.

The core checks cover display identity, coordinate conversion, resolution scaling, laptop maximization, app/window matching, closed-app retention, off-screen recovery, stale captures during display transitions, dragging debounce, persistence, and invalid data. The physical unplug/replug workflow needs verification with your monitors after granting Accessibility access.

In this development workspace, all 18 checks pass and the release bundle's code signature verifies. GUI launch verification was blocked by the workspace's restricted access to the macOS GUI session; the app still needs a first launch and physical monitor test outside that restricted session.
