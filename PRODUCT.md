# Storage Atlas

<!-- impeccable:product-schema 1 -->

## Platform
Native macOS desktop application; local use, MIT open source.

## Stack
Delegated implementation choice: SwiftUI + AppKit, Foundation filesystem APIs, SQLite metadata index, Swift Package Manager. macOS 14 or later. No server; Sparkle handles signed app updates.

## Users
A programmer building large open-source and personal projects on a MacBook.

## Product Purpose
Provide a global, visual map of what occupies this Mac’s internal storage, with developer-relevant inspection and minimal interaction. Large proportional rectangular tiles are the main interface. Version 0.2 implements the user’s correction on 2026-10-29, superseding the folder-first, sidebar-based v0.1 direction; see REFACTOR_PLAN.md and VERIFICATION.md.

## Operating Context
The user wants a local developer utility modeled on the visual density of market heatmaps: a big storage map with floating navigation, filters/status, and optional collapsible inspection. The v0.4 request explicitly replaces the older solid chrome with a modern, minimal visual system and short, Reduce Motion-aware transitions. No marketing copy, permanent sidebar, or System Settings-style page structure. Global coverage must not require choosing a working directory. Exact toolchains are not yet supplied; classification remains deterministic evidence, not a claim about installed tools.

## Capabilities and Constraints
- Local analysis; no accounts, telemetry, content upload, or content inspection. Optional update checks contact GitHub.
- Version one is read-only. No file deletion, shell cleanup commands, or privileged helper.
- Startup System/Data volume-group scope by default, with verified topology, shared identity accounting, background progress, cancellation, permission gaps, and persistent metadata. Other mounted volumes and auxiliary APFS volumes are excluded. Historical folder scans retain their limited-scope label.
- Rules explain their evidence and limits. Unknown files stay unknown.
- Occupied bytes, logical bytes, whole-volume capacity, and estimated savings remain separate concepts.
- Prioritize map, inspection, zoom, search, and developer-artifact highlighting. The space planner is secondary/deferred. Future cleanup, historical growth, duplicate detection, and deep tool-specific integrations remain outside the refactor’s core scope.

## Product Principles
- Put measured storage on the screen; the map is the workspace.
- Use direct tool labels and progressive disclosure; remove promotional copy and unnecessary destinations.
- Explain before suggesting action.
- Preserve source code, personal files, and persistent application data.
- Never equate age or regenerability with permission to delete.
- Make scan scope, freshness, and incomplete coverage visible.
- Show real data; empty states are preferable to invented measurements.

## UX policy — v0.3

The user's subsequent UX request is specified in [UX_SPEC.md](UX_SPEC.md), using Impeccable's Shape/Operate guidance. Version 0.3 implements the following behavior while preserving the existing visual system:

- A collapsible filesystem tree and the map share one focused folder, selection, snapshot, and navigation history. Expansion is distinct from entering a folder.
- Location answers where storage is; categories answer what it contains. Mixed folders must not be presented as uniformly uncategorized files.
- Every focused folder makes its largest immediate children discoverable, with explicit parent-share denominators and an obvious action to enter.
- Inspection, search, return navigation, and refresh preserve context. Auxiliary panels remain optional; the global map remains the main workspace.
- A feature needs a concrete user question, measured evidence, and a useful next step. Quality gates include task completion, accounting correctness, honest unknowns, native keyboard use, compact layout, and measured responsiveness.

DESIGN.md records the resulting interface. VERIFICATION.md separates native fixture checks, real saved global data, and remaining runtime limits. New snapshots use classification version 2 with Models separated from Media; historical snapshots keep their measured classification.

## Accessibility & Inclusion
Native controls, keyboard shortcuts, readable text, labeled SF Symbols, non-color status labels, and Reduce Motion support.


## Visual direction — v0.4

The user's later explicit redesign request supersedes v0.3's appearance-preservation requirement. The measured map and the established UX remain the product; visual treatment becomes a neutral dark canvas, separated rounded blocks, clearer numerical hierarchy, floating transport/status instruments, and a floating inspector. Color communicates known data, not inferred folder ownership or removability. Coverage, zeros, partial snapshots and freshness keep their meaning. Motion supports entering and inspecting a scope without animating the measured byte denominator. Impeccable and the project-local Taste app-screen guidance informed the implementation; the finished native UI and verification limits are recorded in DESIGN.md and VERIFICATION.md.

## Planned distribution and updates

Community releases are distributed as prebuilt Apple Silicon DMGs on GitHub. Sparkle offers signed updates on launch, with manual checking and an automatic-check preference. One click downloads, verifies, installs and restarts; an active scan finishes first. The index stays local. No landing page is included yet. See [release instructions](docs/RELEASING.md).


## Scan completion versus coverage

A completed traversal may still have inaccessible paths and scope exclusions. v0.4.3 makes completion, finalization/index saving, mapped allocation and volume totals distinct, with retained coverage notes and user-controlled Full Disk Access guidance. It does not claim the volume-used difference is all denied files, does not invent unknown sizes and does not bypass macOS privacy. See VERIFICATION.md for actual observations and remaining attribution limits.


Scan completion is published after its atomic index commit. Obsolete index snapshots are maintained separately in bounded background batches; maintenance cannot turn a saved successful scan into a failed scan or keep the scan progress bar running. This affects Atlas metadata only.


## App identity and permissions

Atlas has no login, user accounts or auth server. Build-time code signing establishes its identity to macOS and is independent of the MIT license. Local builds use a pinned development signing certificate with verified permission continuity across updates. Community releases use a separate persistent self-signed identity. Apple Developer ID signing/notarization is an optional future channel; current downloads may need first-launch approval. See docs/SIGNING.md.
