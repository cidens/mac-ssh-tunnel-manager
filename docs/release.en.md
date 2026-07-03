# Release Process

[中文](release.md) | English

This document describes the recommended release process for maintainers.

## Version Preparation

1. Confirm the version in `Sources/SSHTunnelCore/AppVersion.swift`.
2. Update `CHANGELOG.md` and `CHANGELOG.en.md`.
3. Confirm README, architecture, distribution, and troubleshooting documentation are current.
4. Check that example Hosts, IPs, usernames, and paths are sanitized.

## Local Verification

Run:

```bash
swift test
git diff --check
./scripts/build-app-bundle.sh /private/tmp/SSH\ Tunnel\ Manager.app
```

Verify the app bundle:

```bash
find /private/tmp/SSH\ Tunnel\ Manager.app/Contents/Resources -maxdepth 4 -print
plutil -p /private/tmp/SSH\ Tunnel\ Manager.app/Contents/Info.plist
codesign --verify --deep --strict /private/tmp/SSH\ Tunnel\ Manager.app
```

Confirm:

- App/Core localization resource bundles exist.
- `CFBundleDevelopmentRegion` is `en`.
- `CFBundleLocalizations` includes `en` and `zh-Hans`.
- Ad-hoc signing verification passes.

## Create A Distribution Package

Run:

```bash
./scripts/package-app.sh
```

The output is:

```text
dist/SSH Tunnel Manager-<version>.zip
```

`dist/` is a build output directory and should not be committed to Git.

## GitHub Release

A GitHub Release should include:

- Version number and a short summary.
- Main changes.
- Known limitation: the current zip uses local ad-hoc signing and is not notarized with a Developer ID.
- Installation note: first launch may require right-clicking "Open" in Finder or allowing the app from System Settings.
- The zip generated under `dist/`.

## Post-Release Check

1. Download the zip from the Release.
2. Unzip and launch the app.
3. Check the basic menu UI under English and Simplified Chinese system languages.
4. Add a sanitized test tunnel and confirm save, edit, and delete flows work.
