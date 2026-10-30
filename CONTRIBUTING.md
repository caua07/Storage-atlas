# Contributing

Atlas is a native, local, read-only macOS storage explorer. Keep contributions focused on understanding storage and navigating measured data. Read [PRODUCT.md](PRODUCT.md) and [AGENTS.md](AGENTS.md) before changing behavior.

Build with `./scripts/build-app.sh release` and run `swift test`. Quit the app before replacing its bundle. Interface changes need actual native checks at normal and compact window sizes; see [VERIFICATION.md](VERIFICATION.md).

Preserve allocated versus logical size, honest unknowns, canonical paths, symlink non-traversal, hard-link accounting, index exclusion and atomic scan checkpoints. Do not add deletion, privilege escalation, telemetry or external services without an agreed scope change.

Use synthetic fixtures for issues, screenshots and tests. Never attach a real scan index, private filenames, credentials, signing keys or screenshots of personal storage. Describe the macOS/toolchain version and reproducible steps when reporting a bug.

Contributions are submitted under the project's [MIT license](LICENSE). Keep third-party notices intact.
