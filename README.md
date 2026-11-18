# Smoke

A native macOS menu bar app built with SwiftUI and AppKit. It lists open graphical apps by descending memory footprint. The sort icon switches between memory and alphabetical order. Expand an app to see the processes observed in its resource coalition, including each PID and individual footprint.

On hover, Quit, Force Quit, and Restart take the place of the memory value. They are also available from the context menu. Restart waits for the selected instance to exit before reopening the app. Force Quit asks for confirmation.

## Settings

- **Open at Login** registers the app with macOS Login Items.
- **Menu bar** shows an icon, estimated RAM used, or estimated RAM available. Both percentage modes use the same adjustable warning and critical thresholds. The defaults are orange at 80% used and red at 90% used, equivalent to 20% and 10% available. In icon-only mode, macOS memory pressure can also raise the alert color.
- **Language** follows macOS by default. English and French can also be selected in the app.
- **Per-app thresholds** control the orange and red marks. They default to 2 GB and 4 GB.

The status percentage estimates physical use excluding reclaimable cache. A kernel-counter read every minute, with tolerance, updates the status indicator while the panel is closed. macOS memory pressure events also trigger refreshes.

## Build and open

Build with Xcode or the Swift 6 command-line tools. Use an existing Apple Development signing identity or its certificate fingerprint. Keep the bundle ID and identity stable between builds.

```sh
MEMORY_MENU_SIGNING_IDENTITY='<certificate fingerprint>' ./build-app.sh
```

The script creates [Smoke.app](dist/Smoke.app). Open the bundle and click the chip icon in the menu bar. Smoke has no third-party dependencies. Run `swift test` for the automated checks.

The bundle runs on macOS 15 or later. Coalition totals and process details are available on macOS 26.5, where the private ABI was checked. Those measurements appear as unavailable on other versions. The global RAM indicator and app actions use public APIs.

## Sampling

The aggregate is the `phys_footprint` field returned by `coalition_info_resource_usage`, the same counter used by Apple's low-memory panel. Process membership is resolved through the resource coalition ID, and individual footprints come from `proc_pid_rusage`. The list and measurements are snapshots, so processes can appear or disappear between reads. See the [XNU coalition counter](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/mach/coalition.h).

The Apple panel listens for memory pressure, then samples every two seconds with 500 ms tolerance while active. Smoke samples when opened, on changes to the macOS application list, and every five seconds with one second of tolerance while the app list is visible. It stops that sampling in Settings and when the panel closes. It only enumerates processes while a row is expanded.
