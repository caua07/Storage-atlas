---
name: Storage Atlas
description: A native measured storage map with floating navigation and inspection.
colors:
  canvas: "#101214"
  chrome: "#1B1D1F"
  panel: "#222426"
  field: "#2B2E30"
  line: "#35383B"
  text: "#F4F5F5"
  secondary: "#B5B9BD"
  muted: "#969CA1"
  accent: "#9DD8D1"
  warning: "#E5C280"
  development: "#355C66"
  applications: "#3B526C"
  caches: "#4A5159"
  archives: "#6B5A42"
  media: "#3E6058"
  models: "#47635B"
  documents: "#66534E"
  other: "#354045"
  mixed: "#303336"
typography:
  body:
    fontFamily: "SF Pro (system)"
    fontSize: "12pt"
    fontWeight: 400
  tile:
    fontFamily: "SF Pro (system)"
    fontSize: "11pt"
    fontWeight: 600
  tile-medium:
    fontFamily: "SF Pro (system)"
    fontSize: "13pt"
    fontWeight: 600
  tile-large:
    fontFamily: "SF Pro (system)"
    fontSize: "18pt"
    fontWeight: 600
  tile-size-large:
    fontFamily: "SF Pro (system, tabular digits)"
    fontSize: "26pt"
    fontWeight: 500
  label:
    fontFamily: "SF Pro (system)"
    fontSize: "11pt"
    fontWeight: 400
  navigation:
    fontFamily: "SF Pro (system)"
    fontSize: "12pt"
    fontWeight: 500
  tree-name:
    fontFamily: "SF Pro (system)"
    fontSize: "13pt"
    fontWeight: 500
  item-title:
    fontFamily: "SF Pro (system)"
    fontSize: "22pt"
    fontWeight: 600
  allocated-figure:
    fontFamily: "SF Pro (system, tabular digits)"
    fontSize: "30pt"
    fontWeight: 500
  path:
    fontFamily: "SF Mono (system monospaced)"
    fontSize: "11pt"
    fontWeight: 400
rounded:
  floating: "18pt"
  toolbar: "16pt"
  shelf: "12pt"
  field: "10pt"
  action: "10pt"
  inspector-action: "8pt"
  tile: "10pt, reduced for small regions"
spacing:
  workspace-side: "12pt"
  controls: "12pt"
  panel-inset: "20pt"
  detail: "22pt"
  coverage: "24pt"
components:
  search:
    backgroundColor: "{colors.field}"
    textColor: "{colors.text}"
    rounded: "{rounded.field}"
    padding: "0pt 11pt"
    width: "208pt"
    height: "34pt"
  toolbar:
    backgroundColor: "{colors.panel}"
    textColor: "{colors.text}"
    rounded: "{rounded.toolbar}"
    height: "56pt"
  navigation:
    textColor: "{colors.text}"
    typography: "{typography.navigation}"
  status:
    backgroundColor: "{colors.panel}"
    textColor: "{colors.secondary}"
    rounded: "{rounded.shelf}"
    typography: "{typography.label}"
    height: "32pt"
    padding: "0pt 13pt"
  drawer:
    backgroundColor: "{colors.panel}"
    textColor: "{colors.text}"
    rounded: "{rounded.floating}"
    width: "360pt"
  tile:
    textColor: "{colors.text}"
    typography: "{typography.tile}"
  native-action:
    textColor: "{colors.secondary}"
---

# Design System: Storage Atlas

The user authorized a modern, minimal floating workspace in v0.4, superseding the v0.3 appearance-preservation requirement. Read-only scope, the global treemap, accounting and every [UX_SPEC.md](UX_SPEC.md) flow remain binding. This document describes the implemented v0.4 workspace and completed native fixture/saved real-global verification. The real-global snapshot remains interrupted/partial; helper completion is not a completed scan.

## Direction

**The storage map is the workspace.** One measured field supports the question: where is storage concentrated, and what is inside it? Navigation, search, category emphasis and inspection are instruments around that field. There is no permanent sidebar, dashboard, marketing header or primary planner destination.

The chosen visual world draws on a mixing desk's aligned instruments, translated into floating neutral transport and inspection surfaces rather than an audio metaphor. The Taste app direction is markets/dark, true-black-flat. The user's explicit floating brief adds soft offset shadows on floating surfaces; data remains flat. Native San Francisco text, SF Symbols, AppKit tree behavior and menus keep this a macOS utility.

The shipping token source is `MapStyle` in [AtlasStyle.swift](Sources/StorageAtlas/AtlasStyle.swift). Composition lives in [WorkspaceView.swift](Sources/StorageAtlas/WorkspaceView.swift), native map drawing in [TreemapCanvasView.swift](Sources/StorageAtlas/TreemapCanvasView.swift), and inspection in [MapInspectorView.swift](Sources/StorageAtlas/MapInspectorView.swift) and [FolderTreeView.swift](Sources/StorageAtlas/FolderTreeView.swift); coverage is implemented in [MapCoverageView.swift](Sources/StorageAtlas/MapCoverageView.swift). All dimensions are logical points; browser previews do not verify native layout.

## Color and measurement

The frontmatter records the built sRGB values. Canvas, chrome, panel and field step through neutral lightness. Text and secondary text establish rank; muted text carries freshness. Mint is reserved for the small Atlas mark and focused/contained map selection, while warning sand accompanies text and a symbol. Actions and panel/tree selection remain neutral.

Category color belongs to measured content: Development teal, Applications blue, Caches slate, Archives brown, Media green, Models green, Documents clay and Other blue slate. New version-2 snapshots keep Models separate from Media. Legacy version-1 snapshots retain model weights under Media and show a refresh notice; Models emphasis is disabled. The distinct v0.4 display colors do not reinterpret historical classification.

Ordinary mixed folders and exact rollups use neutral `mixed`; expanded parent groups use chrome and non-additive boundary outlines. They do not imply that all descendants share one category. Search/category nonmatches blend 72% toward canvas and their labels use 60% opacity; matching labels retain normal contrast and a 38%-text outline.

**Stable denominator:** selection, category emphasis, search and opening the panel never repartition or resize the map. Allocation, logical size, volume used/free/capacity and hypothetical recovery remain distinct. Zero-allocation items and inaccessible unknowns never gain invented area. Category bars use measured category bytes divided by the selected folder's measured composition total.

## Type

Use system San Francisco throughout. Paths use system monospaced text; numerical quantities use monospaced digits. Name labels can middle-truncate during comparison, with full paths available in inspection, tooltips and accessibility labels.

- Controls and prose use 12pt; supporting labels, paths, dates and scoped shares use at least 11pt.
- Map names use 11pt semibold, 13pt above 170 × 95pt, and 18pt above 300 × 180pt. Corresponding size figures use 11/18/26pt, with fit guards.
- Atlas uses 16pt semibold and a small rectangle-derived mark. It names the tool without taking the map's visual role.
- Inspector names use wrapping selectable 22pt semibold text; allocated bytes use 30pt medium tabular figures. Logical length and dates remain separate 11pt rows.
- Native tree names use 13pt medium; kind/current/coverage, allocated size and parent share use 11pt. Numbers are right aligned in a 112pt value column.

## Workspace geometry

The hidden-title-bar window defaults to 1500 × 940pt, with a 960 × 600pt minimum. The same workspace adapts through content fit, with no separate compact screen.

| Component | Built geometry |
| --- | --- |
| Map surface | 12pt horizontal inset; 72pt top and 44pt bottom inset |
| Floating transport | 56pt tall; 12pt side and 8pt top inset; 16pt corner radius |
| Search | 208 × 34pt; 11pt inner horizontal inset; 10pt radius |
| Lower filter/status shelf | 32pt tall; 12pt side and 6pt bottom inset; 12pt radius |
| Optional inspector | 360pt wide; 20pt right, 80pt top and 52pt bottom inset; 18pt radius |
| Inspector header | 54pt tall; three 30pt neutral mode tabs plus a 28pt close action |
| Native folder tree | 48pt rows, 1pt intercell gap, 10pt indentation per level |
| Coverage popover | 480 × 500pt body; 24pt padding; observed native window 506 × 526pt |

Transport contains the Atlas mark/name, Back/Forward/Up, ancestor breadcrumbs and the displayed map's actual Mapped allocation, scoped search, named Folders, Results, Details and Refresh/Stop. Breadcrumbs fit through full segments, an ancestor menu plus the final segment, then the menu. The shelf contains scan/partial status, freshness, a scoped category key/menu and whole-volume used/total/free bytes. On compact windows, the key gives way to the category menu; long paths stay available through ancestors and inspection.

The inspector overlays the map's stable layout. Opening it obscures part of the field rather than reallocating tile area. Folders, Results and Details are modes of the same optional panel. Close preserves focus, selection, expansion and scroll context. Footer actions and coverage notes can change the outline's viewport height; scroll restoration retains the requested anchor through native geometry changes.

During a scan, the same 32pt shelf replaces the idle status/date with Preparing, Scanning or Stopping, a 112pt native indeterminate activity bar, and the current scan's real file count and allocated bytes. Categories collapse to their menu to keep progress readable at compact width; free capacity remains separate. The current path and unknown-total explanation are available in the scan group's tooltip. No percentage or ETA is inferred from used disk space. Reduce Motion and cancellation use a stationary center marker instead of a repeating animation. Completion/cancellation removes activity and restores snapshot status/freshness. The implementation is in ScanActivityBar.swift and WorkspaceView.swift; no scanner/accounting behavior changes.

## Surface, shape and feedback

Floating transport/shelf/readout surfaces use one neutral shadow: black at 28%, 18pt blur, offset 8pt down. The inspector uses black at 32%, 24pt blur, offset 10pt down. No second outer border, gradient, decorative blur or glow is applied. Inside panels, restrained 1pt separators and field-tone selection establish structure.

Tiles retain exact allocated layout rectangles. Painting insets 2.5pt per edge when the short side is at least 24pt, 1.5pt from 10pt, and at most 0.5pt below that. Large neighbors therefore expose 5pt seams. Rounded painted regions use a 10pt radius when their short side reaches 60pt, otherwise a bounded smaller radius. Group boundaries use a 1.5pt inset and 12pt radius. Visual gutters do not change stored bytes or area accounting.

A selected tile has a 2pt outline; hover has a 1pt outline and a 10% lightness lift. Selected map focus uses mint; other selected outlines use primary text at 95%, hover at 65%. A selected indexed item without an exact visible rectangle receives a dashed mint outline around its nearest real represented container, together with explicit Contained in text. That mark does not assert an exact-file selection or add area.

Non-additive folder annotations are 28pt floating labels, with 12pt name and 11pt size. They appear only above 190pt width, 90pt height and 28,000pt², and omit collisions. Their small shadow is black at 24%, 7pt blur, offset 2pt down. Hit testing follows rounded painted tiles and annotations; gutters fall through to a represented parent group when one exists.

## Motion implementation

Lift-and-focus is implemented as restrained state feedback. Transport control hover eases out over 0.12s. The optional inspector uses a 0.22s ease-out slide/fade. Entering a different folder crossfades the native backing contents once over 0.18s; measured rectangles and pointer targets update immediately and never interpolate in size. Tree hover/selection is native drawing without an authored transition.

Both the SwiftUI environment and `NSWorkspace.accessibilityDisplayShouldReduceMotion` govern the relevant effects; `--reduce-motion` is an explicit verification override. The source removes authored travel/fades under Reduce Motion. The fixture workflow ran with `--reduce-motion` and recorded the override and effective reduced-motion state as true. The real workflow recorded the normal effective state as false. Authored duration values above are code values; animation timing, perceived smoothness and every system Reduce Motion preference path were not independently measured.

## Interaction and states

Map click selects; double-click or Open contents enters a directory without scanning. Selecting while Folders is open preserves that mode, and Details remains a visible action. Exact rollups open a clearly labeled parent-scoped file list; they do not pretend to identify only omitted members. Global hierarchy preview stays bounded; entering a folder compares immediate children. Packages and recognized artifacts remain aggregated until entered.

Folders uses a lazy AppKit `NSOutlineView`. Disclosure changes expansion without entering. Native arrows select/expand/collapse; Return and double-click enter a folder or inspect a file. Siblings remain sorted by allocated bytes then path; children load in 200-record pages. Native selection and user-scroll observers, pending anchors and generation checks preserve history and protect against late results. Cell widths use a stable scroll-viewport width with column/bounds fallbacks during reconstruction, and numeric trailing constraints account for the actual viewport after indentation. Final native checks confirm deep and compact share text fits within the attached outline. Rows show allocated bytes and a valid textual percent of parent. An inaccessible unmeasured path says Unknown size; measured portions and incomplete descendants retain measured/partial labels. Context menus group navigation/inspection and Finder/Copy path actions.

Results retain explicit scope, shown count, path, allocation, loading, selection, paging, Open folder and Inspect/Return. Rows have a 44pt content minimum with 4pt vertical insets and 11pt secondary paths. Filtered empty results offer Clear filters and, where applicable, Search Mac snapshot. Unknown allocation is labeled separately from a measured zero. List position observers remain native.

Details separate large allocated bytes from logical size, file count, measurement freshness and modification date. A mixed directory says Mixed contents; uncomputed composition says so. Category values and quiet 3pt bars use actual scoped totals. Recognition evidence remains a native disclosure reset on selection; rules keep their evidence, consequence and limits. Unknown ownership/recreatability remains explicit. Reveal in Finder and Copy path are neutral actions. Allocation is not presented as exclusive recoverable space.

Scanning, reading index, no measured files and inaccessible unknown size have distinct empty states. Opening a folder preserves the last map with an Opening path notice. Partial coverage stays visible in the shelf and tree. Errors use text, a warning symbol and a dismiss action. Coverage uses a 20pt heading, 28pt measured-allocation figure, separate volume-capacity rows and 13pt section headings; it distinguishes measured allocation from whole-volume totals and unattributed difference, and discloses missing retained notes. Refresh/cancel preserves a usable baseline and valid focus; the redesign does not change scanner, SQLite or filesystem policy.

Native menu shortcuts remain ⌘R Refresh, ⌘0 global root, ⌘↑ parent, ⌘[ / ⌘] history, ⌘\ Folders, ⌘F search, ⌘L Results and ⌘I Details. With map focus, Backspace/Delete goes up and Home returns to root. Escape dismisses auxiliary state without navigating. Tree accessibility labels include name, kind, allocated size, valid share and path. The canvas exposes a labeled group and directs users to the native tree; it does not create millions of accessibility children.

## Native verification and limits

Native fixture and saved global-snapshot workflows validated map accounting, navigation, tree behavior and normal/compact fit. Detailed machine-specific reports stay in Git-ignored local evidence. Current validation and unverified behavior are recorded in [VERIFICATION.md](VERIFICATION.md). No browser screenshot substitutes for native verification.

## Native application icon — v0.4.2

The application icon reuses AtlasMark's three rectangular regions: mint left, primary-text upper right, and secondary-text lower right at 70% opacity over the panel color. A flat #222426 rounded square has transparent outer padding and no authored shadow, gradient, lettering or added symbol. The editable 1024-unit source is Resources/AppIcon.svg; the symbol uses the toolbar mark's 10:11 column ratio and 9:12 row ratio with 2-unit gaps.

`scripts/generate-app-icon.swift` renders this rectangle-only SVG at every standard macOS iconset resolution (16–1024px) using AppKit, and iconutil packages Resources/AppIcon.icns. The build copies it into Contents/Resources and declares CFBundleIconFile. Finder icon/list rendering and large/small source previews were inspected. The icon build is packaged separately as `dist/Storage Atlas 0.4.2.app` while the original 0.4.1 scan continues; its Dock icon becomes active on opening the new build. VERIFICATION.md records the packaging and native evidence.


## Completion and coverage feedback — v0.4.3

The header says Mapped for global measured allocation; folder snapshots retain their explicit scope. The same 32pt shelf now labels a completed traversal with notes as Scan finished · N notes, using a warning symbol without disguising it as an interrupted scan. Cancelled/interrupted status remains explicit; unknown coverage is never relabeled complete attribution. A clickable volume readout exposes used / capacity · free at normal and compact width, with the category key falling back to its menu when needed.

Coverage separates traversal status, mapped allocation, volume used/free/total and a positive unattributed difference, without attributing that difference entirely to access denial. It explains that repeated scans without changed access can produce the same result. Retained notes prioritize the current home folder and keep their exact messages; recorded count and the 500-note retention limit stay visible. Instructions for user-controlled Full Disk Access include Open System Settings, Show this app in Finder and the selectable current bundle path. The app never changes permissions.

Actual finalization progress now labels Finalizing and Saving index around final aggregation/checkpoints and index finishing/retention; stable byte counts during these steps do not imply ongoing enumeration. Scope, accounting, map geometry, palette, floating layout and Reduce Motion behavior are preserved.


Access discoverability: idle snapshots with coverage notes show a dismissible floating Limited scan coverage notice below the transport. Review access opens the coverage popover with Full Disk Access instructions, settings/Finder buttons and exact bundle path in the first viewport. Dismissing affects only that snapshot in the current window; status coverage remains available. Notes include exclusions, so the notice does not assert that Full Disk Access is absent. No privacy preference or scanned file is changed.

User-requested access copy: “Allow Atlas to read your storage” explains that Full Disk Access enables a more complete map and is used only to read file information and sizes, without modifying or deleting files. Set up access opens the guide; macOS Settings retains the actual permission grant. The notice is dismissible and does not assert the current privacy setting.


Permission notice refinement: a 510pt maximum-width floating notice uses 18pt padding and 12pt vertical gaps. A single title row holds the storage warning symbol, 13pt semibold title and dismiss control. The readable explanation occupies the full body width; the action sits below it. Set up access uses reusable AtlasNoticeActionStyle: 34pt minimum height, 13pt horizontal padding, 9pt corners, neutral light fill and dark text, trailing arrow, hover/press feedback, disabled dimming and a focus outline. The guide action, text, scan state and permission policy are unchanged.


0.4.4 supersedes the earlier coverage-count notice trigger. Only a fresh background protected-user-folder read denial can show the existing floating request. Checking, readable, missing/unknown access and scope notes alone do not show it. Dismissal persists in UserDefaults; current capability is rechecked at launch, activation and via Check read access again. Coverage shows the timestamp, readable/restricted counts and explicit sampled-access wording; it never claims to read macOS's Full Disk Access setting. The last observation is saved informationally, never trusted as live permission. Old map notes remain historical until refresh.


0.4.5 completion semantics: Saving index now covers the atomic snapshot commit only. Retention of old Atlas index rows runs separately after the scan ends; it never keeps the progress bar visible. The saved real result was restored and inspected at compact size with idle Scan finished. No visual layout/tokens changed. Full-volume coverage remains separate from completed traversal.


Updates (0.5.1): a separate 440pt native update panel reuses the dark palette, Atlas mark and existing primary action style. It shows the release, download/verification progress and scan-safe restart state. The workspace geometry is unchanged. The real 0.5.0→0.5.1 prompt and restored workspace were inspected natively; broader updater error-state accessibility remains unverified.
