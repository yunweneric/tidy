# Mac Uninstaller

A macOS desktop app to browse installed applications and uninstall them (including leftover support files). Built with Flutter.

![Screenshot](docs/screenshot.png)

## Features

- **Application list** — View all apps in `/Applications` with name, version, size, and icon
- **Search & filter** — Find apps quickly
- **Summary cards** — Total app count, disk usage, system junk placeholder, unused apps placeholder
- **Bulk selection** — Select multiple apps for batch uninstall
- **Clean uninstall** — Removes the `.app` bundle and common support/cache/preference files under your home directory

## Prerequisites

- [Flutter](https://docs.flutter.dev/get-started/install) (macOS)
- macOS (app reads `/Applications` and uses `iconutil`, `plutil`, `du`, `rm`)

## Getting started

```bash
# Clone and enter the project
cd mac_uninstaller

# Install dependencies
flutter pub get

# Run on macOS
flutter run -d macos
```

## Building for release

```bash
flutter build macos
```

The built app is under `build/macos/Build/Products/Release/`.

## Project structure

- `lib/core/` — Theme and shared widgets
- `lib/features/apps/` — App list feature: data (models, services), logic (BLoC), presentation (screens, widgets)

## License

Private / unpublished (`publish_to: 'none'` in `pubspec.yaml`).
