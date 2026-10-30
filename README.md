# Storage Atlas

A free, MIT-licensed macOS storage explorer for developers. Atlas turns files into an interactive map: larger blocks mean more allocated disk space. Explore folders, find large files, and understand developer artifacts, apps, caches, archives, models, and personal documents before deciding what to keep.

## Download

[Download Storage Atlas for macOS — Apple Silicon](https://github.com/caua07/Storage-atlas/releases/latest/download/StorageAtlas-macOS-arm64.dmg)

Requires macOS 14 or later. Open the DMG and drag **Storage Atlas** into Applications. No compiling, account, or subscription is required.

Community releases use a persistent signing certificate but are **not Apple-notarized**. macOS may require first-launch approval in **System Settings → Privacy & Security → Open Anyway**. Approve only a download you trust from this repository. Atlas will guide you through Full Disk Access for protected folders. [Apple’s first-launch guidance](https://support.apple.com/en-us/102445).

New releases are offered inside the app. Choose **Update and restart**, or **Update after scan** if a scan is running. Updates are verified using Sparkle’s Ed25519 signatures. Use **Storage Atlas → Check for Updates…** to check manually; automatic checks can be disabled in the same menu.

## What it does

- Maps accessible startup-disk files, including hidden files and application contents.
- Lets you enter folders, browse a tree, search paths, and inspect the largest files.
- Separates allocated size, logical size, whole-volume usage, and inaccessible data.
- Saves a local index and preserves it between launches and updates.

Atlas is **read-only**: it does not delete files, run cleanup commands, or upload storage data. Optional update checks contact GitHub; no accounts, telemetry, or hardware profiling are added. GitHub receives ordinary connection metadata such as IP addresses.

A completed scan can still have inaccessible files and deliberate exclusions. Snapshots, other volumes, and filesystem accounting can explain differences from volume-used space. Unknown sizes stay unknown; mapped bytes are not guaranteed recoverable space.

## Build and contribute

Built with SwiftUI, AppKit, SQLite, and [Sparkle](https://sparkle-project.org/). Configure a development signing identity once as described in [SIGNING.md](docs/SIGNING.md), then:

```sh
swift test
python3 -m unittest discover -s Tests/SigningTests -v
./scripts/build-app.sh release
open "dist/Storage Atlas.app"
```

Quit Atlas before rebuilding. Development and CI builds do not query the public update feed. See [CONTRIBUTING.md](CONTRIBUTING.md), [release instructions](docs/RELEASING.md), and [VERIFICATION.md](VERIFICATION.md) for checks and known limits. Intel builds are not distributed or runtime-certified yet.

## License

[MIT](LICENSE). Third-party licenses and attribution are preserved in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
