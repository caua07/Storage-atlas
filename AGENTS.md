# Working on Storage Atlas

## Project skills

- **Taste** (`design-taste-frontend`): [.agents/skills/design-taste-frontend/SKILL.md](.agents/skills/design-taste-frontend/SKILL.md). Use when explicitly requested or relevant to authorized interface work. For application screens, read its `references/app-screens.md`; apply its design guidance within this native SwiftUI/AppKit project. Its browser/CSS inspection tools do not verify native macOS behavior: use the native verification required below. The user's current scope, UX_SPEC.md, and the existing visual constraints remain authoritative; installation alone does not authorize changing the UI. Upstream commit and license are recorded in the skill's `UPSTREAM.md` and `LICENSE`.

## Project direction and verification

Before implementation, read PRODUCT.md, IMPLEMENTATION_PLAN.md, VERIFICATION.md, and the relevant Swift sources. For interface changes, also read DESIGN.md and .impeccable/surface.md. The plan records scope, acceptance scenarios, and a resumption protocol; use it to preserve direction across sessions.

The latest product direction is REFACTOR_PLAN.md: global rectangular storage treemap, one large workspace, minimal toolbar, no marketing copy or permanent sidebar, optional collapsible details. The user rejected the v0.1 navigation/UI direction and subsequently authorized implementation with subagents. Follow the refactor acceptance gates; do not restore the old five-destination sidebar. DESIGN.md and .impeccable/surface.md must describe the finished treemap workspace after verification.

Version 0.4.6 is a delivered local, read-only native macOS app with a floating treemap workspace, licensed MIT. Follow current DESIGN.md and .impeccable/surface.md rather than restoring old fixed chrome. Native checks cover synthetic fixtures and private saved global snapshots; VERIFICATION.md records actual limits. Never commit private local scan evidence. Do not add cleanup execution, privilege escalation, external services, telemetry, inferred ownership claims, or unmeasured savings unless a subsequent user request explicitly expands scope. Unknowns and inaccessible locations must remain visible.

Keep allocated size, logical size, volume capacity, selected-scope totals, and hypothetical recovery distinct. Preserve canonical path handling, symlink non-traversal, hard-link accounting, index self-exclusion, and atomic row/summary checkpoints.

Run `swift test` for changes to filesystem logic, classification, SQLite, or planning math. Build/package with `./scripts/build-app.sh release`. Inspect native UI changes in the running app, including compact layout; do not rely on web screenshots or placeholder data as proof of native behavior. Record material validation evidence and limits in VERIFICATION.md. Update the implementation plan when scope or evidence changes. Never modify scanned files as part of analysis.

Local packaging requires the pinned certificate-backed development identity; never silently fall back to ad-hoc signing or weaken designated requirements. Public distribution requires Developer ID. See docs/SIGNING.md; .signing/ and all key/signing evidence stay out of Git.
