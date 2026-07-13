# SPEC — Intelli-Expense for Mac (native macOS 26 target)

**Status:** proposed
**Owner screens/targets:** new macOS app target in `project.yml`; new Mac-adapted root navigation; all existing feature views reused with platform adaptations; `ExpenseCore` unchanged
**Docs this spec amends:** DESIGN.md (new §: Mac adaptation rules), `design/ui-spec.html` (new section: Mac three-pane layout), PRD §3 (platform statement gains macOS)
**Related specs:** SPEC-agent-import-bridge.md depends on this target existing.

---

## 1. Problem

The app is iPhone-only, but the workflow has a natural desk-half: receipts are *captured* on the phone at the register, then *reviewed, organized, and exported* — tasks better done on a large screen with a keyboard, drag-and-drop, and a file system. CloudKit private-database sync is already the app's backbone, so a Mac app is not a port with a sync problem to solve — sync is free by construction if the Mac app shares the container and schema.

## 2. API grounding (offline Apple docset, version 24703)

Feasibility hinges on the pipeline, not the UI. Platform lines as read:

- **FoundationModels `SystemLanguageModel`** — `/documentation/foundationmodels/systemlanguagemodel` — iOS, iPadOS, **macOS**, visionOS 26.0+. On-device guided generation works natively on the Mac (Apple Silicon + Apple Intelligence enabled — same availability states the app already models behind its protocol).
- **Vision `RecognizeDocumentsRequest`** — `/documentation/vision/recognizedocumentsrequest` — iOS 26.0, iPadOS 26.0, Mac Catalyst 26.0, **macOS 26.0**, tvOS 26.0, visionOS 26.0. The OCR stage runs natively.
- **VisionKit `VNDocumentCameraViewController`** — `/documentation/visionkit/vndocumentcameraviewcontroller` — iOS 13.0, iPadOS 13.0, Mac Catalyst 13.1, visionOS 1.0. **Not available on macOS.** The scan camera does not exist on the Mac; capture must be import-first (D3).
- SwiftUI, SwiftData, CloudKit mirroring: native macOS platforms throughout (same `ModelContainer`/`ModelConfiguration` code; the CloudKit container identifier is platform-neutral).

Conclusion: every stage of the pipeline except the *camera* is macOS-native at the exact API level already used. The Mac app is the same pipeline with a different front door.

## 3. Goals

- A **native macOS 26 SwiftUI app target** (not Mac Catalyst) sharing `ExpenseCore`, the SwiftData models, the extraction pipeline, and the CloudKit container `iCloud.com.nags.intelliexpense` — a receipt saved on either device appears on the other via existing sync.
- A Mac-appropriate structure: three-pane split view, menu bar commands, keyboard shortcuts, drag-and-drop import — not a stretched phone layout.
- Import-first capture that reuses the entire post-camera pipeline (OCR → parser → guided generation → merge → review).
- The design system holds: same asset-catalog tokens, single brand accent, no red, system text styles only, no `colorScheme` branches.

## Non-goals

- No iPad target (separate decision; this spec's split-view work would however make it cheaper later).
- No Mac Catalyst and no "Designed for iPad" distribution — rejected in D1.
- No camera capture on Mac beyond Continuity Camera (D3); no scanner-hardware (ImageCaptureCore) integration.
- No Mac-exclusive features (menu-bar extra, multi-window editing, agent bridge) in this pass — the agent bridge is SPEC-agent-import-bridge.md.
- Share extension remains iOS-only.

## 4. Design decisions

### D1 — Native SwiftUI target, not Catalyst

The app is pure SwiftUI with `@Observable` view models and no UIKit dependencies outside capture (VisionKit) and small utilities. A native target gets real menu-bar commands, window behavior, keyboard focus, and pointer affordances; Catalyst would drag UIKit idioms onto a codebase that doesn't otherwise have them, and its only advantage — `VNDocumentCameraViewController` availability (Catalyst 13.1+) — is worthless on a device without a document camera. Shared code moves behind the existing protocol seams; the few iOS-only leaves (scanner presentation, camera-permission view, share-inbox handling) get macOS counterparts or are compiled out.

### D2 — Structure: three-pane `NavigationSplitView`

- **Sidebar**: Trips (recency-sorted, featured-first is a phone pattern — the sidebar *is* the trip list), Unfiled, Archived (per SPEC-trip-archiving), Settings via the standard app-settings scene. `SPEC-mac-sidebar-refinement.md` later refines this contract: Folders is a collapsible destination section, Unfiled/Archived use system count badges, and New Folder lives in the bottom sidebar bar rather than the list or window toolbar.
- **Content column**: the selected trip's receipt list (existing rows, filters as a toolbar menu).
- **Detail column**: receipt detail / review form — the review-and-confirm UI gains room to show the receipt image beside the fields instead of above them (side-by-side at regular widths; this is the single biggest UX win of the Mac).
- Menu bar + shortcuts: File → New Trip (⌘N), Import Receipts… (⌘I), Export Trip… (⌘E); standard Edit/View menus free from SwiftUI commands scaffolding.
- Empty/gate states reuse existing views; the Apple Intelligence gate copy already fits (macOS surfaces the same eligibility/enabled states through the same availability protocol and fakes).

### D3 — Capture on the Mac is import-first

Grounded in §2: no document camera exists on macOS. Capture becomes:

1. **Drag-and-drop** images/PDFs onto the window (any pane) — primary path, one continuous drop target.
2. **File → Import Receipts…** open panel (images + PDF; multi-select) — same pipeline, batch-friendly.
3. **Continuity Camera** ("Import from iPhone") as an enhancement if the standard system affordance composes with SwiftUI file importers cleanly; not an acceptance-blocking requirement.

Every import enters the *existing* pipeline exactly as a photo-library import does on iOS today; multi-file drops queue sequentially with the existing processing overlay pattern. The capture-never-blocked rule translates: import is always accepted; extraction degrades per PRD §6.4 when the model is transiently unavailable.

**Seam for the agent bridge (build it this way now, even though the bridge ships later):** the ingestion entry point must be callable headlessly — a function taking file URLs (and later a structured payload), not an action wired to the drop target or open panel. SPEC-agent-import-bridge.md's folder watcher drives this same entry point without any UI event; if ingestion is coupled to the drop/import UI, the bridge becomes a refactor instead of an addition. Likewise the Settings scene (D2) is where that spec's "Agent entries require in-app review" toggle will live — no work now, just the scene existing.

### D4 — Design adaptation rules (the DESIGN.md amendment)

**One product, one design language — the sync doctrine.** The Mac and iPhone apps are two windows onto the same product, not two apps: one `DESIGN.md` governs both (its tokens and laws are platform-neutral; it gains a *Mac adaptation* section, never a second design system); one `design/ui-spec.html` holds the canonical mocks for both platforms (Mac screens are new sections in the same file, in the same visual language); one String Catalog, one asset catalog, one `ExpenseCore`. Shared components (rows, cards, chips, review form) are the same SwiftUI views adapted by size class and idiom — never Mac-only rewrites of iOS components. Distribution follows: one App Store product (universal purchase), one version number, features ship to both platforms in the same release unless a platform lacks the capability (e.g. camera scanning). Any future spec that touches shared UI must state its effect on both platforms or explicitly scope to one.

- Tokens are platform-neutral: the nine asset-catalog pairs and semantic colors resolve on macOS unchanged; no new colors.
- Type: the same semantic text styles; macOS renders its own scale — no fixed sizes now or ever, so nothing to convert.
- Density: list rows may adopt the platform-default compact metrics; the ledger rules (tabular numerals, right-aligned money, per-currency lines, one hero number per screen) apply per *pane*, with the detail pane owning the hero.
- Hover/pointer: standard system hover effects only; no custom cursor work.
- The phone's capture accessory bar and tab bar do not exist on Mac; their functions live in the toolbar, menu commands, and sidebar.

### D5 — Project mechanics

New target in `project.yml` (`xcodegen generate` as usual): macOS 26.0 deployment, same Swift 6 strict concurrency, entitlements for CloudKit (same container) + sandboxed file access (user-selected read for imports). App unit tests split platform-neutral (most) from platform-specific; `ExpenseCore` tests unchanged. The sandbox side-by-side lane is iOS-only for now (screenshot needs are App Store/iPhone); a Mac sandbox variant is future work if Mac App Store screenshots need it. Makefile gains a `build-mac`/`run-mac` lane so verification is scripted like the phone lane.

### D6 — Considered and rejected

- **Mac Catalyst / Designed-for-iPad**: D1; also both render phone idioms that read as low-effort on macOS, against the app's quality bar.
- **Camera scanning via ImageCaptureCore/scanner hardware**: real flatbed-scanner support is a niche; drag-drop + iPhone capture covers the workflow. Revisit on demand.
- **Immediate iPad target "since split view is done"**: iPad deserves its own capture story (it *does* have the document camera); deliberately separate.

## 5. Edge cases

- **Apple Intelligence off/ineligible on the Mac** (Intel machines can't run macOS 26; Apple Silicon with AI disabled can): the existing gate states apply verbatim; receipts synced from the phone are still fully viewable/exportable (gates block *extraction*, not the library) — this ordering already exists in the iOS availability handling and must be preserved on Mac.
- **Same receipt edited on both devices offline**: existing SwiftData+CloudKit last-writer-wins semantics; nothing new.
- **Huge multi-file drop (50+)**: sequential queue with progress; import never rejects by count; the stale-draft cleanup rules (SPEC-draft-cleanup) apply unchanged.
- **PDF multi-page receipts**: same handling as the existing iOS file-import path (pages become draft pages).
- **Window resizing below three panes**: standard `NavigationSplitView` collapse; no custom breakpoints.

## 6. Accessibility & localization

- No new user-facing strings for shared features (existing keys render on macOS); new keys only for Mac menu items not covered by system-provided menus: `menu.importReceipts` ("Import Receipts…"), plus reuse of `groups.create` and `group.export` values for menu titles where they fit naturally. Full keyboard navigation and VoiceOver come from standard controls; verify the review form's field order with VoiceOver on macOS.
- The String Catalog is shared across targets — adding a language remains one translation task covering both platforms.

## 7. Test impact

- **ExpenseCore**: unchanged, runs on macOS in CI trivially (`swift test` already platform-neutral).
- **App unit tests**: pipeline/availability/store tests join a shared test target compiled for both platforms; capture-flow tests stay iOS.
- **New Mac UI tests**: import via the open panel lands a receipt in review; drag-drop (XCTest drag APIs) files a receipt into the selected trip; ⌘E export produces the zip; three-pane navigation sanity.
- **Manual**: two-device sync check (save on Mac → appears on iPhone and vice-versa), gate states on a Mac with AI disabled, light/dark, large content sizes, VoiceOver pass on review.

## 8. Acceptance criteria

1. The Mac app builds from the same repo via `xcodegen generate` + a scripted Makefile lane, shares `ExpenseCore` and the model layer with zero model-code forks, and syncs with the iPhone app through the existing CloudKit container with no schema change.
2. Dropping or importing a receipt image/PDF on the Mac runs the identical OCR → parser → guided-generation → merge pipeline and lands in the same review-and-confirm flow, with image-beside-fields layout in the detail pane.
3. The app is structured as sidebar/content/detail with working menu commands and shortcuts (⌘N/⌘I/⌘E); New Folder uses the bottom sidebar bar while retaining ⌘N and File-menu behavior per `SPEC-mac-sidebar-refinement.md`; no phone tab bar or capture accessory appears on macOS.
4. All design-system laws hold on macOS (tokens, single accent, no red, no fixed sizes, no `colorScheme` branches) — verified against the amended DESIGN.md Mac rules; ui-spec.html gains the Mac layout section in the same change.
5. Apple Intelligence gate states behave per PRD §5.0/§6.4 on macOS via the existing availability protocol and are testable with the existing fakes; synced content remains viewable when gated.
6. Money remains `Decimal` end-to-end with locale-aware formatting; every user-facing string (including new menu items) lives in the shared String Catalog.
7. All existing tests pass; new shared/unit/Mac-UI tests pass; the iOS app is byte-for-byte unaffected except code moved (not changed) behind platform seams.
