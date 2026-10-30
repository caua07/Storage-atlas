# Third-party notices

Storage Atlas source and original assets are licensed under [MIT](LICENSE). The following materials retain their own terms:

- **Taste development skill** — [Leonxlnx/taste-skill](https://github.com/Leonxlnx/taste-skill), MIT, copyright 2026 Leonxlnx. The vendored skill is a development resource, not part of the app bundle. Its [license](.agents/skills/design-taste-frontend/LICENSE) and [pinned provenance](.agents/skills/design-taste-frontend/UPSTREAM.md) are preserved.
- **SQLite** — Atlas links to the macOS system library; SQLite source is not vendored. SQLite documents its [public-domain dedication](https://www.sqlite.org/copyright.html).
- **Apple frameworks and system symbols** — SwiftUI, AppKit, Foundation and SF Symbols are used through macOS system APIs. No Apple SDK or exported symbol artwork is included in the repository. These platform materials are not relicensed by the project MIT license.

Sparkle is the only third-party Swift package currently required.

## Sparkle 2.10.1

[The Sparkle Project](https://github.com/sparkle-project/Sparkle), copyright Sparkle contributors. Sparkle is bundled for secure updates, under its [upstream license](https://github.com/sparkle-project/Sparkle/blob/2.10.1/LICENSE). The complete license is copied into the packaged application's Resources/Sparkle-LICENSE. Package.swift pins version 2.10.1 and SwiftPM verifies the upstream binary checksum. Its components retain their original notices.
