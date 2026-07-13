# SPEC — Mac desktop behaviors: undo, search, multi-select, keyboard, Quick Look, drag filing

**Status:** proposed (sequenced after SPEC-mac-visual-polish.md)
**Owner screens/files:** `IntelliExpense/Mac/MacContentView.swift` (receipt list column, sidebar, selection model, drag/drop seams); `IntelliExpense/Mac/MacCommands.swift` (menu commands); `IntelliExpense/Mac/MacReceiptDetailPane.swift` (from SPEC-mac-visual-polish); `IntelliExpense/IntelliExpenseApp.swift` (undo-enabled container wiring, Mac scene); `IntelliExpense/UI/SettingsView.swift` (Mac form styling); `ExpenseCore` untouched
**Docs this spec amends:** DESIGN.md §10 (Native Mac Adaptation — desktop-behavior contract: undo, selection plurality, keyboard map, drag filing, content zoom-as-Dynamic-Type; plus one new "don't": never custom-paint list selection), `design/ui-spec.html` `#mac` section (contract-table rows for search, batch actions, keyboard map, Quick Look, View-menu zoom)
**Related specs:** SPEC-mac-app.md (D3 named Continuity Camera as a non-blocking enhancement — this spec ships it); SPEC-mac-visual-polish.md (context menus and toolbar placement defined there are extended, not changed, here); SPEC-mac-folder-editor-modal-adaptation.md (implemented 2026-07-11 — established the shared `PlatformPresentationSupport` grouped-form/presentation seam that D9 now reuses instead of re-inventing); SPEC-agent-import-bridge.md (Dock badge reflects its pending-entry count); SPEC-trip-archiving.md (archive semantics reused verbatim for batch and keyboard paths)
**Updated:** 2026-07-11 — reconciled against shipped folder-editor-modal work (D9), added View-menu zoom (D11) and window-state polish (D12)

---

## 1. Problem

After SPEC-mac-visual-polish the Mac app will *look* native but still not *behave* like a Mac app. Concretely, today on macOS:

- **⌘Z does nothing.** Every field edit, archive, move, and delete is final. For an app whose Mac role is "review, organize, export", missing undo is the loudest possible "this is a port" signal — and archive/delete already have no confirmation on the reflex path (by design, per DESIGN.md §5 "always safe"), which *assumes* undo exists on a desktop.
- **There is no search.** iOS has `.searchable` on the Receipts tab (`receipts.search.prompt` and its empty states already exist in the catalog); the Mac window — the surface built for working through a trip — has no ⌘F at all.
- **Selection is singular.** The receipt list holds one selection; there is no ⌘-click/⇧-click, no Select All, no batch archive/move/delete. Desktop is exactly where users clean up a trip before export.
- **The keyboard map is incomplete.** Arrow keys work (system `List`), but Delete, Space, and Return do nothing on a selected receipt or trip, and the menu bar doesn't advertise any of these verbs.
- **Receipts can be dragged in but never within or out.** No drag-to-file onto a sidebar trip, no dragging a receipt image or export zip to Finder/Mail.
- **Background agent imports are invisible** until the user looks at the pending section.

Platform grounding: current field reports on SwiftUI-on-macOS (2026) are consistent that system `List`, standard menus/commands, and system selection behavior provide active/inactive-window and focus-emphasis fidelity *for free*, and that the failure mode is custom-painting selection or rebuilding lists from scroll views. This spec therefore adds behavior exclusively through system affordances on the existing `List`-based panes — no custom controls.

## 2. Goals

- The four desktop table stakes — undo/redo, ⌘F search, multi-selection with batch actions, a complete keyboard map advertised in the menu bar — work in the Mac window.
- The window behaves like a Mac document surface: View ▸ Zoom In/Out/Actual Size (⌘+/⌘−/⌘0) scale the content, and window size/position restore across launches.
- The Mac filing gestures exist: drag receipts onto sidebar trips, drag receipt images and export zips out to the Finder, Quick Look with Space, inline sidebar rename.
- Capture gains the system "Import from iPhone" path (Continuity Camera), completing SPEC-mac-app D3's deferred enhancement.
- Pending agent entries surface through the Dock badge, the standard macOS "needs attention" signal.
- iOS remains untouched; all behavior lands behind macOS platform seams on shared components.

## Non-goals

- No sortable-column `Table` view of receipts — rejected in D10.
- No AppleScript, Shortcuts/App Intents, or Spotlight indexing in this pass — rejected in D10 (privacy surface; PRD §2 "cut scope, not quality").
- No menu-bar extra, no multi-window editing (single main window stands; a receipt never opens in its own window in this pass).
- No changes to extraction, sync, export format, or the agent bridge protocol.
- No new visual language: this spec adds verbs, not looks; anything visual it touches must already be specified by SPEC-mac-visual-polish or DESIGN.md.

## 3. Design decisions

### D1 — Undo/redo through the system Edit menu, honestly scoped

The Mac scene runs an undo-enabled model container so SwiftData registers change undos with the window's `UndoManager`, lighting up Edit ▸ Undo/Redo (⌘Z/⇧⌘Z) with no custom menu work. Scope, in order of trust:

1. **In scope, guaranteed:** receipt field edits committed from the detail pane (vendor, date, amount, currency, type, payment, notes), archive/restore of receipts and trips, and receipt delete.
2. **Feasibility-gated:** undo of *group reassignment* (Move to Trip) and of trip delete with receipt reassignment. Community and issue-tracker evidence documents SwiftData undo defects specifically around relationship changes (undoing unlink/relink misbehaving across recent OS releases). Implementation must verify these paths on macOS 26 with a dedicated unit-style test before enabling them; if broken, Move to Trip registers **no** undo action and the Edit menu simply doesn't offer one for that operation — a silent gap is acceptable, a corrupting undo is not.
3. **Explicitly not undoable:** import/extraction (a pipeline run is not an edit; cancel exists during processing per DESIGN.md §7), export (produces a file outside the store), and agent-entry confirmation (its safety mechanism is review-before-save, per the bridge spec).

Rules satisfied: DESIGN.md §5's "archiving… always safe (accent-tinted, full-swipe, no dialog)" — on the desktop, *safe* is delivered by undo rather than dialogs; this decision is what keeps the no-dialog rule honest on Mac. Delete keeps its existing confirmation (destructive role, §5) *and* becomes undoable — confirmation prevents accidents, undo forgives them.

Considered and rejected: a hand-rolled undo stack over `ExpenseCore` operations — duplicates what the framework provides, drifts from SwiftData's actual persisted state, and would have to mirror CloudKit merge semantics. If framework undo fails its gate for a path, that path ships without undo rather than with custom undo.

### D2 — ⌘F search in the receipt list column

The content column gains the standard search field (system placement in the column header), reusing the iOS Receipts-tab search semantics and strings verbatim: `receipts.search.prompt`, matching on vendor and notes with locale-aware, diacritic-insensitive comparison, and the existing `receipts.search.empty.title`/`.message` empty state. ⌘F focuses the field via the standard Find command group; Escape clears and returns focus to the list. Search filters *within the current sidebar selection* (trip / Unfiled / Archived / all) — the column is always "the receipts I'm looking at", searched.

Rule satisfied: DESIGN.md §5 "Search lives in `.searchable` on the Receipts tab" — the Mac content column *is* that surface in the split-view mapping of SPEC-mac-app D2. No new strings, no new empty states.

Known platform limitation, accepted: typing in the search field while arrow-keying the results (Spotlight-style) is not reliably achievable in pure SwiftUI today; the contract is field-then-list focus traversal (Tab/arrow), not simultaneous type-and-navigate.

### D3 — Multi-selection and batch actions

The receipt list's selection becomes a set. With one item selected, behavior is exactly today's (detail pane shows the receipt). With multiple:

- The detail pane shows a **multi-selection summary**: count, and per-currency totals side by side per DESIGN.md §9 ("never sum across currencies") — primary large, others secondary. This is the pane's hero for that state (§5 one hero per pane).
- The row context menu (from SPEC-mac-visual-polish D4) acts on the whole selection: Archive/Restore, Move to Trip ▸ (trip submenu + Unfiled), and — only when every selected receipt is archived — Delete with the existing confirmation naming the count.
- Edit ▸ Select All (⌘A) selects the visible (filtered) list; the export toolbar action continues to export the *pane's* trip, not the selection (export stays trip-scoped per PRD; a selection-scoped export is future work, not this spec).

Batch operations reuse the existing single-receipt store operations one-by-one in a single undo grouping, so ⌘Z reverses the whole batch (subject to D1's gates).

### D4 — The keyboard map, advertised in the menu bar

Standard Mac verbs on the focused list, every one mirrored by a menu item so it is discoverable (menu items are how Mac users learn shortcuts):

| Key | Context | Action |
|---|---|---|
| Delete (⌫) | receipt list, active receipts | Archive selection (safe removal — §5's reflex gesture, desktop form) |
| Delete (⌫) | receipt list, archived receipts | Delete with existing confirmation |
| ⌘⌫ | receipt list, any | Same split: archive active / confirm-delete archived (alias, matches Finder muscle memory) |
| Space | receipt list | Quick Look the selected receipt(s) (D5) |
| Return | sidebar trip | Begin inline rename (D6) |
| ⌘F | window | Focus search (D2) |
| ⌘A | receipt list | Select All (D3) |
| ⌘Z / ⇧⌘Z | window | Undo/Redo (D1) |
| ⌘+ / ⌘− / ⌘0 | window | Zoom In / Zoom Out / Actual Size (D11) |

Menu placement: Archive and Delete join the existing File/Edit command structure in `MacCommands` with their shortcuts shown; unused default menu items are removed per the menu-hygiene pass (D9). Arrow-key navigation, type-to-select, and focus rings come from system `List` and are deliberately left untouched.

### D5 — Quick Look with Space

Space on a selected receipt opens the system Quick Look panel (`quickLookPreview`, available on macOS) over the receipt's page images; multi-page receipts and multi-selections present as a Quick Look collection navigable with arrows. This complements, not replaces, the in-app viewer sheet (which remains the click path from the detail image column). Photo-less receipts: Space is a no-op with the standard system feedback rather than an empty panel.

Rule satisfied: DESIGN.md §9 receipt images are never dimmed/inverted — Quick Look renders the file as-is; and §6 sheets/panels are system-owned.

### D6 — Drag filing, drag-out, and inline rename

- **Drag receipts onto sidebar trips**: receipt rows become draggable (a receipt `Transferable`); sidebar trip rows, Unfiled, and Archived become drop destinations. Drop = the same Move to Trip / archive operation as the context menu, batch-capable, undo-grouped. The dragged row is *not* dimmed or removed during the drag — current SwiftUI provides no reliable drag-session end signal outside the drop target, and a row stuck dimmed after an aborted drag is worse than no effect (documented framework limitation; revisit when a session-scoped API exists).
- **Drag out to Finder/Mail**: dragging a receipt exports its page image file(s); the `Transferable` must carry both a file representation *and* a proxy file-URL representation — field reports document that a file representation alone fails against Finder. Multi-page receipts drag as their page files.
- **Export zip**: the export-ready sheet's zip becomes draggable to Finder and gains a "Show in Finder" button (existing key `export.showInFinder`).
- **Inline sidebar rename**: double-click or Return on a trip name edits it in place via the standard rename affordance, writing through the same validation as the trip editor (empty names rejected, editor unchanged as the full-edit path). Context menu gains Rename.

Rule satisfied: DESIGN.md §10 "Capture: … drag-and-drop all feed the same headless ingestion path" establishes drag as the Mac's direct-manipulation language; this extends it symmetrically to filing and exporting. RTL-safe by construction (§5): drag targets are rows, not edges.

### D7 — Continuity Camera: "Import from iPhone"

The File menu and the content-column context area gain the system Continuity Camera importer (`importsItemProviders` — the system provides the "Import from iPhone" menu with Take Photo / Scan Documents on a paired iPhone). Imported images enter the exact same headless ingestion path as drag-and-drop and ⌘I (SPEC-mac-app D3's seam), meaning the Mac gets a true *scanning* story: phone camera, Mac review. The menu item is system-provided and system-localized — no new catalog strings. If no eligible iPhone is paired, the system hides/disables the item; the app adds no custom gating.

This closes SPEC-mac-app D3 item 3, which shipped as "enhancement if it composes cleanly" — it composes.

### D8 — Dock badge for pending agent entries

The app's Dock tile shows the standard numeric badge equal to the pending agent-entry count (drafts awaiting confirmation), cleared as entries are confirmed/discarded. No local notifications in this pass — the badge is the calm, glanceable signal consistent with DESIGN.md §8's quiet-degradation voice ("Needs confirmation", never urgency); notifications would need their own permission prompt and copy, deferred until real usage shows the badge is insufficient.

### D9 — Menu and Settings hygiene

- Remove default menu items that have no function in this app (Format menu; any default Edit items that never enable) — per Apple's own guidance that the menu bar should reflect only what the app can do. Undo/Redo now *stays* because of D1.
- View menu: "Show Archived" toggles the sidebar's Archived section selection; sidebar show/hide is already system-provided.
- `SettingsView` on macOS gets the grouped form style and width cap consistent with the detail pane. The mechanism now exists: SPEC-mac-folder-editor-modal-adaptation shipped `IntelliExpense/UI/PlatformPresentationSupport.swift` and applied the grouped-form + semantic `presentationSizing` treatment to the folder and category sheets. Settings adopts that same shipped seam — no new pattern, no iOS change; this item is now wiring, not design.
- New DESIGN.md §10 "don't", encoding the platform-fidelity finding: **never custom-paint list selection or rebuild list panes from scroll views on macOS** — system `List` is what provides active/inactive window subduing, focus-emphasized selection, and context-menu focus rings; custom selection painting silently breaks all three.

### D10 — Considered and rejected

- **Sortable-column `Table`**: the most "Mac data app" control, but it conflicts with the date-sectioned ledger (§5 "lists group by what users think in"), duplicates the row anatomy into a second maintained UI, and export already provides the spreadsheet view of the data (`summary.csv`). Cut.
- **AppleScript / App Intents / Spotlight indexing**: expands the data-exposure surface of a deliberately private, on-device app for speculative benefit. Revisit on explicit demand.
- **Selection-scoped export**: export stays trip-scoped (PRD export contract); mixing selection-export into the same toolbar verb would fork the finance-folder format.
- **Local notifications for agent entries**: deferred per D8.
- **Custom drag previews / drag-dimming**: blocked by framework limits (D6); do the reliable thing, not the fragile thing.

### D11 — View-menu zoom: ⌘+ / ⌘− / ⌘0

Standard Mac content zoom, added to the View menu (Zoom In ⌘+, Zoom Out ⌘−, Actual Size ⌘0), with two context-dependent targets:

1. **Window content (default).** The commands step a persisted per-app content scale for the Mac window. Hosted macOS evidence showed that setting `dynamicTypeSize` does not resize explicit semantic SwiftUI fonts, so every app font is routed through one environment-aware modifier that applies macOS 26 `Font.scaled(by:)` to its existing semantic style. This preserves the design system's semantic-font hierarchy, makes explicit `.body`/`.headline`/`.title` styles scale together, and gives their layouts the same reflow pressure as larger Dynamic Type. The ladder runs from 0.85× through 2.2×; ⌘0 returns to 1×; steps beyond either end are no-ops with the menu item disabled. The setting persists across launches and applies to the Mac window only — iOS keeps a factor of 1 and continues to follow system Dynamic Type untouched.
2. **Receipt image surfaces (when frontmost).** While the full-resolution receipt viewer (SPEC-full-resolution-receipt-viewing) is presented, the same three commands drive the viewer's image magnification instead — zoom in/out about the view center on its existing continuous zoom scale, ⌘0 resets to fit. One menu verb, focus-appropriate target, matching Preview's behavior. The detail pane's inline image is not separately zoomable (click-through to the viewer is the zoom path).

Rules satisfied: DESIGN.md Dynamic Type rule (zoom implemented *as* type size, never point-size scaling); §9 receipt images rendered as-is (viewer magnification is spatial, never reprocessing). Considered and rejected: a free-form window scale factor (violates the Dynamic-Type-only rule, duplicates AX-size layout work); browser-style page zoom via layout scaling (SwiftUI provides no supported whole-hierarchy scale that keeps hit-testing and sharpness correct); per-pane zoom levels (unjustified complexity — one window, one content scale).

### D12 — Window-state polish

Small desktop-fidelity items that belong to this behavior pass, all system-provided:

- **Window frame restoration**: the main window restores size and position across launches (SwiftUI window restoration defaults on the `WindowGroup`; verify it is not accidentally suppressed), together with the persisted zoom step from D11.
- **Sidebar width and selection restoration**: last sidebar selection restores on launch so the window reopens where the user left off (scene storage on the selection).
- **Full Screen behaves**: the standard green-button Full Screen presents the three-column layout without clipped minimum widths (min-width audit at the largest zoom step is part of D11's acceptance).

## 4. Edge cases

- **Undo across sync**: a change made on Mac, synced out, then undone on Mac produces a second sync write — existing last-writer-wins semantics apply; undo never attempts cross-device retraction. An incoming synced change does not join and cannot be removed by the local undo stack.
- **Undo of a batch partially invalidated** (e.g. one receipt of the batch deleted on the phone meanwhile): the undo group applies to surviving objects; missing objects are skipped without error UI.
- **Delete key with mixed selection** (some active, some archived): the safe interpretation wins — the whole selection archives; nothing deletes. Delete-with-confirmation is offered only for uniformly archived selections (D3/D4).
- **Search + selection**: changing the search text prunes the selection to visible rows; batch actions act on what the user can see, never on hidden matches.
- **Drag a receipt onto its current trip**: no-op, no error. Drag onto Archived: archives (equivalent to the reflex gesture). Drag *from* Archived onto a trip: restores and files, one undo group.
- **Quick Look while the detail pane has unsaved field edits**: field commits follow the existing focus-loss behavior; Space never discards edits.
- **Continuity Camera cancelled on the phone**: no ingestion starts; no overlay flashes.
- **Dock badge when review is not required** (auto-confirm mode from the bridge spec): confirmed-on-arrival entries never count; the badge only ever shows drafts awaiting a human.
- **Rename to empty/whitespace**: rejected inline, name reverts — same rule as the trip editor.
- **AX / full keyboard access**: every new verb is reachable through menus (and thus assignable in System Settings ▸ Keyboard); Quick Look and rename follow system accessibility behavior.
- **Zoom at the ladder ends**: ⌘+ at the largest supported step (and ⌘− at the smallest) is a no-op with the menu item disabled; ⌘0 always enabled unless already at default.
- **Zoom vs. system text size**: the persisted zoom step is an offset applied in the Mac scene; if the user changes the system text size, content follows the system and the stored step re-applies relative to it — the app never pins an absolute size.
- **Zoom while the receipt viewer is open**: commands drive the viewer (D11 target 2); closing the viewer returns the commands to window-content zoom, and the window's step is unchanged by anything done in the viewer.
- **Window restoration with a missing selection** (trip deleted on another device since last launch): sidebar falls back to the default selection; no error UI.

## 5. Accessibility & localization

New string-catalog keys (English values):

| Key | Value | Notes |
|---|---|---|
| `receipt.action.quickLook` | `Quick Look` | Menu/context-menu item; Space shown as its shortcut |
| `receipt.action.moveToTrip` | `Move to Trip` | Context-menu submenu title |
| `trip.rename` | `Rename` | Sidebar context-menu item |
| `menu.showArchived` | `Show Archived` | View menu item |
| `receipts.selected.count` | `%lld Selected` | Multi-selection summary title; plural variants (one/other) |
| `receipts.batch.archive` | `Archive %lld Receipts` | Menu item when selection > 1; plural variants |
| `receipts.batch.delete.title` | `Delete %lld Receipts?` | Confirmation title; plural variants |
| `menu.zoomIn` | `Zoom In` | View menu, ⌘+ (custom command — not system-provided in SwiftUI) |
| `menu.zoomOut` | `Zoom Out` | View menu, ⌘− |
| `menu.actualSize` | `Actual Size` | View menu, ⌘0 |

Reused keys (no changes): `receipts.search.prompt`, `receipts.search.empty.title`, `receipts.search.empty.message`, `export.showInFinder`, `receipt.archive`, `receipt.restore`, `common.delete`, `groups.unfiled.title`. Undo/Redo, Select All, Find, and the Continuity Camera menu are system-provided and system-localized — never in the catalog. Per-currency totals in the multi-selection summary are Foundation-formatted, composed side by side per DESIGN.md §9, never concatenated in catalog strings.

New accessibility identifiers: `mac.list.search`, `mac.detail.multiSummary`, `mac.detail.multiSummary.total`, `mac.contextMenu.quickLook`, `mac.contextMenu.moveToTrip`, `mac.sidebar.rename.field`, `mac.export.showInFinder`.

VoiceOver: the multi-selection summary is one grouped element ("N selected, total X, plus Y in other currency"); inline rename announces as a standard editable text field; batch confirmations read counts. Full-keyboard-access traversal must reach search, list, detail, and toolbar in that order.

## 6. Test impact

- **ExpenseCore**: unchanged.
- **Unit tests (Mac-compiled)**: the D1 feasibility gate is a test — group-reassignment undo round-trips (move, undo, verify relationship and inverse restored) run against an undo-enabled in-memory container; batch operations register a single undo group; badge count derivation from drafts.
- **Mac UI tests**: ⌘F filters and shows the existing empty state on no match; multi-select via ⌘-click shows `mac.detail.multiSummary` with per-currency totals; Delete key archives the selection and ⌘Z restores it; Space opens Quick Look (panel existence check); drag receipt row onto sidebar trip refiles it (XCTest drag APIs); inline rename commits and rejects empty; Show in Finder button exists on the export sheet; ⌘+/⌘−/⌘0 step and reset the content scale (assert an element's rendered size class changes and persists across relaunch), zoom items disable at ladder ends, and the same commands drive magnification while the receipt viewer is frontmost.
- **iOS regression**: full iOS suite must pass unchanged — every addition sits behind macOS seams.
- **Manual**: undo behavior spot-check on device after CloudKit sync round-trip; Continuity Camera end-to-end with a paired iPhone (simulator can't cover it); Dock badge across confirm/discard; VoiceOver pass on multi-selection and rename; keyboard-only session (no pointer) filing a receipt from import to trip.

## 7. Acceptance criteria

1. ⌘Z/⇧⌘Z undo and redo field edits, archive/restore, delete, and batch operations as whole groups; group-move undo is enabled only if its round-trip test passes, and no operation ever offers a broken undo.
2. ⌘F search works in the content column with the existing iOS search strings and empty states, scoped to the current sidebar selection; Escape clears.
3. The receipt list supports multi-selection with batch Archive/Restore, Move to Trip, and (archived-only) confirmed Delete; the detail pane shows the count + per-currency totals summary without summing across currencies.
4. The keyboard map of D4 works end-to-end and every verb appears in the menu bar with its shortcut; unused default menus are gone; a keyboard-only user can import, review, file, and export a receipt.
5. Space Quick Looks receipt images; receipts drag onto sidebar trips to refile (undoably) and drag out to Finder as image files; the export zip drags out and has a working Show in Finder button.
6. Continuity Camera "Import from iPhone" feeds the existing headless ingestion path and lands in review; the Dock badge equals the pending agent-draft count at all times.
7. Settings renders with grouped form styling on macOS via the shipped `PlatformPresentationSupport` seam; DESIGN.md §10 and ui-spec.html `#mac` are amended in the same change, including the new never-custom-paint-selection rule and the zoom contract; all new strings are in the catalog per §5's table with plural variants; all new identifiers exist.
8. View ▸ Zoom In/Out/Actual Size (⌘+/⌘−/⌘0) step, persist, and reset the Mac window's content scale as Dynamic Type steps; the same commands drive image magnification while the receipt viewer is frontmost; items disable at ladder ends; the three-column layout survives the largest step without clipping, including in Full Screen.
9. The main window restores frame, sidebar selection, and zoom step across launches, falling back gracefully when the restored selection no longer exists.
10. The iOS app is behaviorally and visually unchanged; full iOS and existing Mac test suites pass.
