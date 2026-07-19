# Release Process

[中文](release.md) | English

This document describes the recommended release process for maintainers.

## Version Preparation

1. Confirm the version in `Sources/SSHTunnelCore/AppVersion.swift`.
2. Query GitHub Releases and use the most recent actually published Release as the comparison baseline. An intermediate tag without a Release is not a baseline.
3. Archive the Unreleased entries under the target version, update `CHANGELOG.md` and `CHANGELOG.en.md`, and keep an empty Unreleased section.
4. Draft the exact Release title and body from the `<previous-published-version>...<target-version>` commit and file diff, then review that text before publishing.
5. Confirm README, architecture, distribution, and troubleshooting documentation are current. Do not mechanically replace version numbers in historical validation records.
6. Remove or replace screenshots and example assets that clearly describe an obsolete UI.
7. Check that example Hosts, IPs, usernames, and paths are sanitized. Use only `example-*`, `203.0.113.0/24`, loopback addresses, or other explicitly reserved example values.
8. Confirm `.vscode/`, `.DS_Store`, `dist/`, exported JSON, logs, backups, temporary files, and local configuration are not included in the commit.

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

- App/Core localization resource bundles exist under `.app/Contents/Resources`.
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

For local review, also run `unzip -t`, verify the extracted signature and version, and generate a SHA-256 checksum. The Release workflow publishes both the zip and its `.sha256` file.

`dist/` is a build output directory and should not be committed to Git.

## GitHub Release

The `.github/workflows/release.yml` workflow runs automatically when a `v*` tag is pushed. It:

1. Validates the tag and checks that it matches `AppVersion.current`.
2. Runs `swift test`.
3. Builds the zip through `scripts/package-app.sh`.
4. Verifies the zip, app signature, and SHA-256 checksum.
5. Creates the GitHub Release or replaces assets when the same tag is rerun.

The generated GitHub Release should include:

- Version number and a short summary.
- Main changes.
- Known limitation: the current zip uses local ad-hoc signing and is not notarized with a Developer ID.
- Installation note: first launch may require right-clicking "Open" in Finder or allowing the app from System Settings.
- The zip generated under `dist/` and its SHA-256 file.

Treat generated notes as a draft only. Before making the Release public, verify its comparison baseline, title, and body again. If they differ from the approved draft, update only the Release metadata without deleting the tag or assets.

Create the tag from a commit that already contains the Release workflow. A version mismatch stops the workflow before publishing assets.

If a transient GitHub failure happens after the tag is pushed, run the `Release` workflow manually from the Actions page and provide the existing tag. Do not delete and recreate a published tag just to retry the workflow.

## Post-Release Check

1. Download the zip from the Release.
2. Unzip and launch the app.
3. Check the basic menu UI under English and Simplified Chinese system languages.
4. Add a sanitized test tunnel and confirm save and edit work. Start deleting it and cancel to confirm it remains, then confirm deletion and verify it is removed.
