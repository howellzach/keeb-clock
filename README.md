# Keeb Clock

<img src="assets/keeb-clock-icon.png" alt="Keeb Clock app icon: a mint clock keycap on a navy background" width="128" height="128">

Keep your CIDOO ABM066 keyboard's screen clock in sync with your Mac.
Use the native menu bar app for automatic syncing or the standalone CLI for
manual updates.

**Unofficial project. Not affiliated with or endorsed by CIDOO.**

## Compatibility

- CIDOO ABM066 connected over USB. Bluetooth syncing is not supported.
- macOS 13 or later is required.
- **Only tested on Apple Silicon Macs.** The app also builds for Intel Macs,
  but Intel compatibility has not been verified.

## Menu bar app

![Keeb Clock menu](assets/menu.png)

*Menu preview with sample sync data.*

To build and install, you need Xcode 16 or later with Swift 6. From the project root:

```sh
sh scripts/build.sh
sh scripts/install.sh
```

Launch **Keeb Clock** from Applications and click its clock-keycap menu bar icon.
The app syncs on launch, after waking, and every 30 minutes by default.

From the menu you can:

- Sync now or turn automatic syncing off.
- Choose a 5, 15, 30 or 60 minute interval.
- Switch between local time and UTC.
- Start the app at login.

Connection status updates when the keyboard is plugged in or removed.
Reconnecting syncs the clock when automatic syncing is enabled.

Once installed, the app runs on its own without Xcode or the CLI.
The installer keeps a backup of the previous app when updating.
Builds are locally signed; notarized downloads are not yet available.

## Command-line tool

The CLI runs on macOS and Linux. To build it, you need Go 1.24 or later.
Linux builds also need a C compiler and libudev headers. From the project root:

```sh
sh scripts/build-cli.sh
./build/keeb-clock devices
./build/keeb-clock sync-time
```

Use `sync-time --utc` for UTC or `sync-time --dry-run` to read the configuration
without updating the clock. Use `--help` for more options.

The CLI builds for the machine you compile it on and works independently of the macOS app.
See the [CLI README](cli/README.md) for its experimental image helpers.

## Troubleshooting

If syncing fails, reconnect the keyboard over USB and try **Sync now**.
If the problem persists, quit and reopen the app.

For other errors, report an issue with the full error message, your macOS
version and whether your Mac uses Apple Silicon or Intel.

## Releases

Update the version and build number in `Config/Version.xcconfig`, then push a
matching version tag such as `v1.1`. The release workflow runs tests and creates
a draft GitHub Release with the app ZIP, CLI ZIPs for macOS (Apple Silicon and Intel)
and Linux (x86_64 and arm64), and checksums. Test the downloads and review the notes before publishing the draft.

## Licence

Licensed under the [MIT License](LICENSE). Third-party dependencies retain their
own licences; see [third-party notices](THIRD_PARTY_NOTICES.md).

## Acknowledgements

Made possible by [ricardobeat's CIDOO ABM066 research](https://github.com/ricardobeat/cidoo-abm066-tool),
which documented the keyboard's HID protocol and clock configuration.
The upstream tools are not bundled with or required by Keeb Clock.
