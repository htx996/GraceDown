# GraceDown

GraceDown is a macOS menu bar UPS monitor for setups where the UPS is connected
to a NAS instead of directly to the Mac. It reads UPS data from Network UPS
Tools (NUT), shows live status in the macOS menu bar, and can request macOS
shutdown when configured power conditions are met.

The original target setup is a UPS connected by USB to a UGREEN NAS, with the
Mac reading UPS status from the NAS NUT service.

## Features

- macOS menu bar UPS status panel
- NAS NUT and local UPS source modes
- Battery percentage, runtime, voltage, load, and power-state display
- Optional automatic macOS shutdown rules
- Multi-condition shutdown triggers
- Right-click menu bar actions
- GitHub Release based update check

## Run Locally

```bash
./script/build_and_run.sh
```

The app is menu-bar-first. It keeps running in the background and can hide the
Dock icon after user windows are closed.

## Build

```bash
swift build --product UPSPowerMonitor
```

To generate the distributable app bundle:

```bash
./script/build_and_run.sh bundle
```

The release DMG is created manually from `dist/GraceDown.app`.

## NAS UPS Mode

Open GraceDown settings and configure:

- NAS address: your NAS LAN IP or hostname
- NUT port: usually `3493`
- UPS name: leave blank to use the first UPS returned by the NAS
- Username/password: optional, only required if the NUT service requires it

GraceDown reads UPS state from the NAS and can request macOS shutdown when the
UPS state, battery level, runtime, or low-battery signal matches the configured
rules. Automatic shutdown is disabled by default and must be explicitly enabled
in settings.

The shutdown command uses macOS System Events through AppleScript. macOS may ask
for Automation permission the first time it runs.

## Update Check

The menu bar right-click menu includes **检查更新**. It checks the latest GitHub
Release from:

```text
https://github.com/htx996/GraceDown/releases/latest
```

## License

MIT License. See [LICENSE](LICENSE).
