<p align="center">
  <img src="Assets/ContainerManager-master.png" width="128" height="128" alt="Container Manager icon">
</p>

<h1 align="center">Container Manager</h1>

<p align="center">The friendly helm for <strong>Apple Containers</strong>.</p>

A native macOS app for managing **Apple Containers** — like Docker Desktop, but
built on Apple's `container` runtime. Container Manager takes the wheel on a
dense CLI: modern SwiftUI design, no terminal required.

![platform](https://img.shields.io/badge/macOS-14%2B-blue) ![swift](https://img.shields.io/badge/Swift-5.9%2B-orange)

## Features

- **Engine control** — start/stop the background container service from the sidebar; a friendly splash guides you when it's offline.
- **Containers** — see running and stopped containers at a glance with live status pills. Start, stop, restart, delete, open published ports in your browser, and inspect details (resources, network, environment, raw JSON) and logs.
- **Images** — browse local images, **pull** new ones (with one-click suggestions and live progress), **run** them through a friendly form, or delete.
- **Run** — a guided sheet that hides CLI flags: name, port mappings, environment variables, shared folders, CPU/memory — with a folder picker for volumes.
- **Machines** — create and manage container machines (lightweight Linux VMs built from any image): boot, stop, set the default, tune CPUs/memory/home-folder sharing, read app & boot logs, and open an interactive login shell right in the app.
- **Build** — point at a folder with a `Dockerfile`/`Containerfile`, tag it, and watch the build stream live.
- **Volumes** — list and remove persistent volumes.

Everything auto-refreshes every few seconds.

## Requirements

- macOS 14 or later (Apple Silicon)
- [Apple Containers](https://github.com/apple/container) — `brew install container`
- **Xcode** (full app) to build/sign/distribute the Xcode project
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen` (generates the `.xcodeproj`)

## Project layout

The Xcode project is generated from [`project.yml`](project.yml) by
**XcodeGen** — the `.xcodeproj` itself is not committed. After cloning (or after
editing `project.yml`), regenerate it:

```bash
xcodegen generate                    # writes "Container Manager.xcodeproj"
open "Container Manager.xcodeproj"
```

## Build & run (development)

Open `Container Manager.xcodeproj` in Xcode and hit Run, or from the command line:

```bash
xcodebuild -project "Container Manager.xcodeproj" -scheme "Container Manager" -configuration Debug build
```

A lightweight SwiftPM path is also kept for quick iteration without Xcode:

```bash
swift build
swift run ContainerUI       # SwiftPM product/binary is named ContainerUI
```

## Distribute to other users (Developer ID + notarization)

To ship a build that other people can open without Gatekeeper blocking it, the
app must be signed with a **Developer ID Application** certificate and
**notarized** by Apple. One-time setup — store a notarization credential:

```bash
xcrun notarytool store-credentials container-manager-notary \
  --apple-id "you@example.com" \
  --team-id MKTMGKS2F9 \
  --password "app-specific-password"   # create at appleid.apple.com
```

Then build, sign, notarize, and staple in one step:

```bash
./scripts/build-release.sh
```

This produces `build/Container Manager.app` (notarized + stapled) and
`build/Container Manager.zip` ready to share. You can also do this from Xcode's
GUI: **Product → Archive → Distribute App → Developer ID**.

Signing is configured in `project.yml` (team `MKTMGKS2F9`, Hardened Runtime
enabled) with entitlements in [`Support/ContainerManager.entitlements`](Support/ContainerManager.entitlements).

> The `build.sh` script instead produces an **ad-hoc-signed** `Container
> Manager.app` via SwiftPM — fine for running locally, but such builds are
> rejected by Gatekeeper on other machines.

## How it works

The app shells out to the `container` CLI and parses its `--format json`
output — there's no private API or daemon integration. The whole CLI surface is
wrapped in [`ContainerEngine.swift`](Sources/ContainerUI/ContainerEngine.swift),
which runs commands out-of-process (draining stdout/stderr concurrently to avoid
pipe deadlocks) and exposes a streaming variant for `pull`/`build`/logs.

```
Sources/ContainerUI/
├── App.swift               # @main entry, window + menu commands
├── AppModel.swift          # observable state, auto-refresh, actions
├── ContainerEngine.swift   # async wrapper around the `container` CLI
├── Models.swift            # Codable models matching the CLI's JSON
└── Views/
    ├── RootView.swift          # split view, sidebar, engine status
    ├── Components.swift         # status pills, cards, flow layout, toasts
    ├── ContainersView.swift     # container list + rows
    ├── ContainerDetailView.swift# overview / logs / inspect tabs
    ├── LogsView.swift
    ├── ImagesView.swift
    ├── RunSheet.swift
    ├── PullSheet.swift
    ├── BuildView.swift
    └── VolumesView.swift
```

## Notes

- The CLI path is auto-detected (`/opt/homebrew/bin/container`, `/usr/local/bin`, or via `which`).
- This is an unofficial project and is not affiliated with Apple.
