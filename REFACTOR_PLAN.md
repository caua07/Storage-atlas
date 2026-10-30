# Storage Atlas: global storage map

Status: **implemented; native verification and delivery notes below.** The user authorized implementation with task-appropriate subagents after the planning request.

Subsequent UX definition: [UX_SPEC.md](UX_SPEC.md) adds the requested explicit folder tree, meaningful category separation, and utility/quality policies. Those refinements are implemented in v0.3 while preserving this global-map direction and the existing UI identity. IMPLEMENTATION_PLAN.md and VERIFICATION.md record the delivery and validation limits; the v0.2 checklist below remains historical evidence for v0.2.

This plan supersedes the v0.1 interface and folder-first workflow. The user rejected that direction on 2026-10-29 and subsequently authorized implementation. Filesystem/index accounting, proportional map layout, and the native workspace are implemented as separate subagent workstreams with coordinated integration and verification.

## 1. Product correction

Build a personal developer tool whose main screen answers: **what is taking space across my Mac, and where?**

The screen is a large, interactive rectangular treemap, like a market heatmap. Area represents allocated storage. Large consumers should be obvious without navigating through pages or reading explanatory copy.

Binding requirements from the user:
- Global view of the Mac’s internal storage; no directory chooser required to start using it.
- A large map of proportional rectangular tiles, with the largest files and storage-heavy areas visible.
- Minimal chrome and direct labels. No taglines, onboarding slogans, promotional headings, or decorative information cards.
- No permanent navigation sidebar. Details are available in a collapsible, initially closed drawer.
- Optimize the small set of interactions that provide most of the value. Do not turn this into a suite of settings pages.
- Local macOS use. Retain read-only operation, explainable classifications, and honest coverage limitations.

Success: open the app, spot a large consumer, inspect what it is, and reveal its location without leaving the main workspace.

## 2. Research and what to borrow

These are interaction references, not templates to copy or new dependencies.

| Reference | Relevant pattern | Application here |
| --- | --- | --- |
| [GrandPerspective](https://grandperspectiv.sourceforge.net/) | Files occupy proportional rectangles; related files share a region. Supports hierarchy navigation and inspection. | Make actual storage area the main interface. Preserve folder relationships and show the path for a selected tile. |
| [Finviz market maps](https://finviz.com/knowledge-base/market-data-research/maps-groups/map-view) | Relative magnitude is encoded by tile area; grouping and color provide a second dimension. | Translate magnitude to allocated bytes and grouping to filesystem areas. Do not borrow trading controls or imply storage is live market data. |
| [TradingView heatmaps](https://www.tradingview.com/support/solutions/43000766446-tradingview-heatmaps-from-global-trends-to-details/) | Separate size, color, and grouping to support global-to-detail analysis. | Use size for bytes, category colors consistently, and zoom for detail. Keep controls few and legible. |
| [WizTree](https://diskanalyzer.com/) | A disk-focused treemap identifies large files and folders. | Pair the map with a compact optional largest-items list, rather than making tables the default workspace. Do not copy Windows-specific scanning claims. |

Decision: **a dense, readable, flat storage treemap with restrained category colors.** Rectangles should be reasonably square when the distribution allows it, but proportional area takes precedence over forcing square tiles. No radial chart, gauge dashboard, or System Settings layout.

## 3. The main screen

Conceptual wireframe; labels indicate controls and data positions, not measured values:

```text
┌───────────────────────────────────────────────────────────────────┐
│ Atlas   Internal storage   Free …   Search …   Refresh   Details   │
│ Mac › [focused area, when zoomed]                     Category key │
├───────────────────────────────────────────────────────────────────┤
│                                                                   │
│              PROPORTIONAL STORAGE TREEMAP                         │
│                                                                   │
│     Grouped regions: user files, applications, shared data         │
│     Visible tiles: large files, packages, collapsed folders        │
│     Larger occupied footprint → larger area                       │
│                                                                   │
│                        [details drawer opens over the right edge] │
│                                                                   │
├───────────────────────────────────────────────────────────────────┤
│ Hovered path + size             Scan time · coverage · scan status │
└───────────────────────────────────────────────────────────────────┘
```

### Screen rules
- The map uses at least 85% of the usable content area with the drawer closed at the reference desktop size. A compact toolbar, breadcrumbs, and status line are the only persistent surrounding UI.
- Launch into the most recent global map when one exists. First launch starts the default global metadata scan automatically. No introductory page or folder-selection prerequisite.
- The global scope is the startup internal storage/volume group. An attached disk, mounted installer, network mount, or backup is not silently included. Additional disk selection can live in a small scope menu later.
- Restore a cached global snapshot immediately; show its measurement time. Refresh is an explicit rescan. Continuous monitoring and background daemons are deferred.
- The old folder-only snapshot must not be relabeled as a global scan. Explain its limited scope until a global snapshot exists.
- Choose the final light/dark treatment during implementation review. The binding direction is density, clarity, flat surfaces, and limited color—not a new branding exercise.

### Tile rules
- Default area metric: **allocated bytes on disk**. Logical size is secondary information in details, with an advanced metric switch only if useful.
- Group regions by real filesystem hierarchy/location, so the user can identify where space is concentrated. Coloring by recognized category supplies another cue; it must not invent application ownership.
- A tile can represent a file, an application/package, or an explicitly collapsed folder. Its kind must be distinguishable. A folder tile is never mislabeled as a single file.
- A visible partition contains either a collapsed parent or its children, never both as additive areas. Folder boundaries and totals may annotate a region without adding duplicate area.
- Large tiles show name and size. Smaller tiles show only labels that fit; very small entries combine into an honestly labeled rollup with exact summed size and item count.
- Rollups remain inspectable and searchable. A small tile is not a file excluded from the scan.
- Zero-allocation entries, including some hard-link paths, remain findable through search/list inspection without being given fabricated tile area.
- Grouping and ordering are deterministic for the same snapshot and viewport. Selection, hover, and search should not reshuffle the map.
- Colors encode category, not an unmeasured cleanup risk or a fabricated growth trend. Include text labels and an unobtrusive key.

### Interactions
1. **Hover:** show the path, size, and kind in the status line or a small tooltip.
2. **Click:** select a tile and open concise details. Closing details restores the unobstructed map.
3. **Double-click a folder/group:** zoom into that area using the existing index; do not rescan or open another page. Breadcrumbs and Backspace go up; Home returns to the global map.
4. **Search:** highlight matches and dim other tiles without changing the area denominator. A compact matching-items list can expose entries too small to hit. Clearing search restores the same map.
5. **Details:** name, full path, kind, allocated/logical size, scan time, one factual classification sentence, one consequence sentence where known. Reveal in Finder and Copy path are the main actions. Expand evidence only on demand.
6. **Escape:** close the drawer or clear the active search. Normal keyboard focus and an accessible largest-items list must support use without precise tile pointing.

The drawer overlays or temporarily occupies the edge only when opened; opening it must not silently recalculate tile proportions. Exact overlay width is an implementation choice to verify on the laptop and a large desktop window.

## 4. The 80/20 scope

### Implement first, in this order
1. **Global scan + cached map.** One default scope, real coverage, background scan, cancel/refresh.
2. **Useful proportional map.** Large contributors, folder grouping, zoom and return to global view.
3. **Fast inspection.** Select, understand the item briefly, reveal it in Finder.
4. **Search + developer-artifact highlight.** Highlight recognized build output, dependencies, package caches, and other indexed categories in this same map. Keep uncertain items uncertain.
5. **Largest-items fallback.** A compact optional list in the drawer/overlay for precision and keyboard access, not another main section.

### Keep off the main screen / defer
- Separate Overview, Explorer, Developer, and Review destinations.
- A permanently visible explanation column, large page headings, welcome copy, brand slogans, tips, decorative cards, and narrative footers.
- Space planner as a primary destination. Preserve the calculation code; reconsider a compact utility only after the map meets acceptance criteria.
- Growth dashboards, notifications, automatic/live monitoring, duplicate hashing, content-reading AI, elaborate filters, and tool-specific maintenance integrations.
- Delete buttons, automated cleanup, privileged helpers, uninstallers, and claims of guaranteed recovered space.

This refactor succeeds through the map and its data coverage. Adding additional screens does not count as progress on the core task.

## 5. Backend work required for “global”

This is not a change from a folder picker to the literal path `/`.

Apple documents separate System and Data volumes in a startup [APFS volume group](https://support.apple.com/guide/disk-utility/add-delete-or-erase-apfs-volumes-dskua9e6a110/mac), with traversal between them through [firmlinks](https://developer.apple.com/videos/play/wwdc2019/710/). The current `ScanEngine` rejects a different `st_dev`; a global scan therefore needs explicit topology and accounting rules.

### Global scope and accounting
- Add a `GlobalScanPlan`/volume-discovery layer to select the startup group’s relevant physical volumes. Verify discovery on this Mac before making a claim of global coverage.
- Enumerate each selected underlying namespace once. Keep actual filesystem paths for Finder actions, while normalizing display paths to familiar locations where appropriate.
- Exclude redundant aliases/mount traversals, backups, mounted images, network volumes, unrelated external volumes, and Atlas’s own metadata. A global session must share its identity/deduplication state across its selected roots.
- Preserve symbolic-link non-traversal. Do not remove mount protections wholesale; allow only explicitly planned constituent volumes.
- Keep hard-link identity and allocation accounting; test alias/firmlink duplication separately from ordinary hard links.
- Count container capacity/free space once. APFS shared capacity must not be summed per volume into an imaginary larger disk.
- Separate volume-used bytes, measured file allocation, and coverage gaps. The map’s denominator is its measured data; unknown sizes must not be invented to fill it.
- Show inaccessible locations and unattributed differences concisely. A positive difference can be labeled as unattributed, never automatically as “System Data.” Measured allocation may also exceed volume-used figures because of shared blocks and other accounting differences; do not force a fake reconciliation.
- Full Disk Access is a user-controlled macOS permission, not proof of complete visibility. Continue presenting useful partial results when some paths remain inaccessible. No root helper or permission change is part of this refactor.

### Index and presentation
- Preserve the existing SQLite index, deterministic classifiers, cancellation, and atomic row/summary checkpoints.
- Extend the schema to represent a global scan session and its component scopes/volume identities. Keep historical folder scans distinguishable. Use a non-destructive migration and a schema version.
- Add dedicated projection queries for the visible treemap frontier and rollups. The current capped 500-row explorer query cannot be used as the entire map dataset: it would silently omit most storage.
- Compute totals and layout off the main thread. Use one native drawing surface or another measured rendering strategy rather than one heavyweight SwiftUI view per indexed file.
- Keep hit testing and keyboard/list selection tied to stable entry IDs and exact index records. Reuse existing Finder actions.
- During scanning, update a clearly partial map at a bounded cadence. Never infer a percent complete without a known denominator. A refresh must keep the last completed snapshot available until the new one can replace it coherently.
- For large datasets, roll up by available pixels rather than by an arbitrary file-count cutoff. The bytes of all entries must still be represented once.

## 6. Implementation sequence

The later implementation request authorized these phases. Preserve the acceptance gates and the explicit runtime limits in VERIFICATION.md.

| Phase | Work | Completion gate |
| --- | --- | --- |
| A. Global correctness | Inspect startup-volume topology; implement global scope planning, index migration, alias exclusion, and coverage reporting. | Fixture/accounting tests pass; a read-only real-machine validation identifies exactly what is covered. No global label on a folder-only scan. |
| B. Map engine | Implement deterministic proportional rectangle layout, hierarchical frontier/rollups, hit testing, and scale-aware labels. | Every measured byte represented once; no overlap, negative areas, missing rollup bytes, or parent/child duplication. Validate skewed and very large synthetic index datasets. |
| C. Single workspace | Replace the five-destination shell with the thin toolbar, map, breadcrumbs, status line, and initially closed detail drawer. | Primary task works without selecting a directory or navigating to another section. Proportions stay stable during inspection/search. |
| D. Developer utility | Wire indexed classifications, highlight/search, Finder reveal, copy path, and accessible largest-items fallback. | Find a large real artifact, inspect its explanation, and reveal it from the same workspace. No unsolicited cleanup action. |
| E. Verification and handoff | Build, test accounting, inspect real native UI at compact and large sizes, record limits, and update design docs from the finished app. | User-facing acceptance checklist below is met. Screenshots show real measurements, not a demo masquerading as the scan. |

Reuse the tested scanner/index foundations where possible. Rewrite the composition and interaction model; avoid a backend rewrite merely to deliver a new visual surface. The global-scope correction and map-specific queries are justified backend changes.

## 7. Acceptance checklist

- [x] On launch, see a global map or the global scan in progress; no required folder picker.
- [x] No permanent sidebar, marketing sentence, large welcome block, or multi-page dashboard.
- [x] With details closed, the map occupies at least 85% of the main content area at the agreed desktop reference size.
- [x] The largest measured contributors are visually obvious. Every tile/region has honest size and kind semantics.
- [x] Directory/package folding preserves totals; large files remain individually discoverable.
- [x] Hover gives useful facts; click opens concise details; Escape closes them.
- [x] Zoom into a region and return to the global map without a new scan.
- [x] Search finds entries outside the visible frontier and keeps their bytes accounted for.
- [x] Recognized developer artifacts can be highlighted in the same map without implying that they are unused.
- [ ] Finder reveal and keyboard/list access work on real indexed items.
- [x] System/Data aliases and shared capacity do not double count the internal disk.
- [x] Partial scans, denied access, stale data, and unattributed differences remain visible without dominating the screen.
- [ ] Cancel and refresh preserve a usable state; the UI remains responsive on a large realistic dataset.
- [x] Existing filesystem/index tests pass; new global and layout invariants have meaningful tests.
- [x] Native screenshots at compact and large sizes prove the actual workflow. No web mock is accepted as native verification.

## 8. Decisions already settled / still open

Settled by the user: global by default; big rectangular storage map; minimalist developer utility; no marketing copy; no permanent sidebar; optional collapsible details. Planning was followed by implementation authorization.

Working assumptions to use unless corrected: internal startup storage first, allocated bytes as area, filesystem grouping with category colors, first scan automatic, later refresh explicit, read-only actions.

Implementation choices: dark charcoal with muted category colors, 20-square-point pixel rollup threshold, a 324-point overlay, and deferred planner UI. Projection expands up to 128 immediate entries per level / 1,800 nodes, then preserves all omitted bytes in exact rollups. This bounded-query tradeoff precedes pixel rollup; the implementation does not claim pixel-only expansion.

## 9. Delivery evidence and remaining runtime limits

37 core tests pass; the release app is packaged and locally signed. Independent native checks use a real global **partial** snapshot whose private measurements are retained only in local evidence. Map bytes equal the snapshot exactly. The surface occupies 88.12% of the actual usable workspace (1436×767 over 1440×868 points); the separate 84.985% raw-window fraction includes native titlebar space. Native normal/compact captures, hover/select/zoom/Home/Escape/list-arrow checks, positive and empty search, category query, rollup inspection, and progressive file loading pass. See VERIFICATION.md and `.impeccable/review/v0.2/native-verification.json`.

The remaining unchecked acceptance rows identify runtime limits, not omitted controls: Finder reveal is wired but its final Finder interaction was not independently exercised; cancellation/completed-refresh retention are fixture-tested, but prolonged native cancel and a completed real global/cached-complete session were not observed. The first scan was interrupted following an integration-time signature mismatch from rebuilding a running app; packaging now guards against this. The delivered window displays the useful saved partial map. No privacy setting was changed or scanned file cleaned.

An interrupted scan retains aggregate coverage count but may lack individual error paths because those are saved at normal finish. Coverage discloses that gap. The global map is a partition of measured bytes, not a claim of complete physical-disk attribution.

Final independent finish-review disposition: **SHIP with documented validation limits**. The reviewer confirmed the native UI matrix, quantitative usable-area gate, and actual coverage disclosure. Documentation is complete in DESIGN.md and VERIFICATION.md.


## v0.3 functional UX delivery

UX_SPEC.md P0/P1 behaviors are implemented with the existing visual system preserved: actual lazy filesystem tree, depth navigation/history, scoped search/composition, versioned Models classification, stable panels/selection and refresh, unknown/access-gap states, and bounded match highlighting. Final 54-test and native fixture/real-global evidence, performance measurements, and remaining runtime limits are in VERIFICATION.md. This supplements the original global treemap direction; it does not restore the rejected sidebar/destination architecture.


## v0.4 visual direction

The user explicitly requested a new modern, minimal and fluid UI with floating components, using Impeccable and Taste. This replaces the earlier visual-preservation requirement while retaining the global treemap, read-only scope and all v0.3 UX/accounting protections. `.impeccable/UI_REDESIGN.md` records the native direction: floating transport and status/filter shelf, softer separated blocks, larger numeric hierarchy, a floating inspector and coverage popover, transient hover readout, and Reduce Motion-aware motion. DESIGN.md records the actual finished tokens; VERIFICATION.md records native evidence and limits. Do not restore fixed System Settings-like chrome or a permanent sidebar.
