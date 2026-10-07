# Keeb Clock CLI

A standalone Go tool for syncing the CIDOO ABM066 screen clock over USB
on macOS and Linux. The menu bar app is a separate macOS program.

Build from the project root:

```sh
sh scripts/build-cli.sh
./build/keeb-clock devices
./build/keeb-clock sync-time --dry-run --verbose
./build/keeb-clock sync-time
```

Use `sync-time --utc` for UTC. A dry run reads configuration without writing an
update. Successful updates are verified by reading the clock/configuration back.

Linux builds need a C compiler and libudev headers, such as `build-essential`
and `libudev-dev` on Debian or Ubuntu. Opening the keyboard also requires
permission to its hidraw device.

Run tests and checks from this directory:

```sh
go test ./...
go vet ./...
```

`convert` and `set-image` are experimental offline helpers. `set-image` cannot
upload images. Put options before an image filename:

```sh
../build/keeb-clock convert --out /tmp/frame.rgb565 image.png
```

See the [project README](../README.md) for requirements and research credits.
Dependency licences are in [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).
