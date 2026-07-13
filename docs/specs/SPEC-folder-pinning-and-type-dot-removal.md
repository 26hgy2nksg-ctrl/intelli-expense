# SPEC: Folder pinning + retire the compact-row type-dot strip

**Status:** Draft — ready for implementation (owner request, 2026-07-10)
**Owner screens:** Folders home featured card and compact rows ([GroupsViews.swift](../../IntelliExpense/UI/GroupsViews.swift)), capture default-destination resolution ([ContentView.swift](../../IntelliExpense/ContentView.swift)), Mac sidebar folder list ([MacContentView.swift](../../IntelliExpense/Mac/MacContentView.swift))
**Owner logic:** `ExpenseGroup` model and sorting helpers ([PersistenceModels.swift](../../IntelliExpense/Persistence/PersistenceModels.swift), [ReceiptStore.swift](../../IntelliExpense/Persistence/ReceiptStore.swift))
**Docs this spec amends:** `DESIGN.md` (§4 "Featured folder card" bullet — the "degrades to the type-dot row" sentence; §hard rules "type dots and breakdown chips only" line; §Mac parity list mentioning type dots), `design/ui-spec.html` (folder-card `.glyphs`/`.dot` markup in the Folders home and Mac mockups, the "Tiny type dots" rationale bullet, the Mac parity and screen-inventory table cells naming type dots, plus new pinned-row/context-menu treatment). Amends `SPEC-featured-card-rails-redesign.md` (its `ViewThatFits` dots fallback and "density ladder" rationale) and `SPEC-trips-rename-and-featured-home.md` §D2 (featured selection is no longer purely most-recent-activity) where they conflict.

## 1. Problem

Two owner complaints about the Folders home, both about the list of folders below the featured card:

1. **The per-category color dot strip on every compact row is distracting.** Each `GroupRow` renders `ExpenseTypeGlyphs` — a row of 7 pt category-colored circles — under the subtitle. After `SPEC-per-category-distinct-colors` widened the palette, a screen of six folders shows thirty-plus saturated dots of unrelated hues. The dots were introduced as the bottom rung of a "density ladder" (compact row = dots → featured card = chips → folder detail = amounts, per `SPEC-featured-card-rails-redesign` D-rationale), but in practice they read as noise, not glanceable information: at 7 pt the hues are hard to tell apart, they carry no counts, and they repeat information one tap away in folder detail. The owner wants them gone.

2. **The list order is not user-controllable.** Folders sort strictly by most-recent activity (`ExpenseGroup.sortedByMostRecentActivity`), and the top folder becomes the featured card (`SPEC-trips-rename-and-featured-home` D2: "featured ≡ the trip that is already sorted to the top today"). A folder the owner cares about — an open claim being assembled, a trip awaiting export — sinks as soon as any other folder receives a receipt. The owner wants Notes-style pinning: long-press a folder, pin it to the top, any number of folders, unpin the same way.

## 2. Goals

- Compact folder rows show icon tile, name, subtitle, and totals — no category dot strip anywhere in the app; the `ExpenseTypeGlyphs` component is deleted, not orphaned.
- Pinned compact rows keep the labeled icon + count category rail so every pinned folder retains its glanceable breakdown; unpinned rows stay quiet and dot-free.
- The featured card keeps its chip rail and still never scrolls and never clips at accessibility sizes, with a fallback that no longer depends on dots.
- Any folder can be pinned/unpinned via long-press (right-click on Mac); pinned folders always sort above unpinned ones, the top of the resulting order is still the featured card, and the state syncs via CloudKit like every other folder attribute.
- Pinned rows are visibly (but quietly) marked, and VoiceOver announces the pinned state.
- `DESIGN.md` and `ui-spec.html` are amended in the same change (anti-drift rule).

## 3. Non-goals

- **No manual drag-to-reorder** of folders, pinned or otherwise. Pinning is a boolean promotion; within each band the order stays algorithmic. (Reorder would demand persistent user ordering across sync — out of proportion to the request.)
- **No "Pinned" section header.** See D4.
- No pinning of archived folders, unfiled receipts, or individual receipts.
- No change to what the featured card *shows* — only to which folder can occupy it.
- No new colors, no red (hard rule), no second accent: the pin indicator uses secondary foreground style.
- No change to widget/App Intents destination logic beyond what D7 states.

## 4. Design decisions

### D1 — Delete the dot strip from compact rows; delete the component

`ExpenseTypeGlyphs` (GroupsViews.swift) leaves the iOS `GroupRow` (the macOS branch never had it). The row keeps its existing anatomy — profile glyph tile, name, subtitle, right-aligned tabular totals — which already satisfies the DESIGN.md row rules ("Always tabular numerals", base-4/8 spacing). Category color remains meaningful where it carries information with a label: featured-card chips, folder-detail breakdown rows, receipt rows, selector tiles ("Category color means category identity — used identically in review chips, list badges, breakdown chips, and glyph tiles", DESIGN.md §2). The compact-row dots were the only surface using color *without* a glyph or label, which is exactly why they read as noise. The component is removed entirely so no future surface resurrects it; `CategoryUsage.orderedCategories` stays (other callers).

**Rejected:** keeping dots but capping the count or desaturating — still a labelless color strip, still the complaint.

### D2 — Featured-card accessibility fallback: chips wrap, dots die

DESIGN.md currently mandates: "The rail never scrolls; at accessibility sizes it degrades to the type-dot row." With dots gone, the `ViewThatFits(in: .horizontal)` fallback in `FeaturedBreakdownRail` (GroupsViews.swift) becomes: the same icon + count chips flow onto additional leading-aligned lines instead of a single row. This keeps both halves of the guarantee ("never scrolls, never clips") because the chips are deliberately amount-free ("Dropping amounts is what makes 'always fits, never scrolls' guaranteeable", `SPEC-featured-card-rails-redesign`), so even at AX5 a chip is one glyph plus a one-or-two-digit count. Precedent for vertical degradation already exists in the design language: the category selector and breakdown rows both stack vertically at accessibility sizes.

`DESIGN.md` §4 featured-card bullet is amended to end: "…The rail never scrolls; at accessibility sizes the chips wrap onto additional lines." The hard-rules line becomes "❌ No charts, rings, or dashboards (PRD non-goal) — breakdown chips only." The Mac parity sentence drops "type dots".

### D3 — Pin state is `pinnedAt: Date?` on `ExpenseGroup`

A single optional timestamp, default `nil`, set to the pin moment. This is CloudKit-safe by construction (optional attribute with a default, no `.unique` — the schema rules in CLAUDE.md/PRD §3), migrates existing folders with no action, and does double duty as the sort key among pinned folders (D5). Sync conflicts resolve last-writer-wins like every other folder attribute; a pin/unpin race between devices converges to whichever wrote last, which is the correct semantic for a toggle.

**Rejected:** `isPinned: Bool` + separate order index — two fields to keep consistent across sync for no added capability.

### D4 — Pinned folders promote in place; no separate section, featured stays "the top folder"

The Folders home keeps its featured-first monotonic structure (`SPEC-trips-rename-and-featured-home` D2: "it never restructures when the trip count crosses a threshold"). Pinning changes *ordering only*: the sorted-active-folders helper returns pinned folders first, then unpinned folders in the existing most-recent-activity order. The first element — now the most recently pinned folder, when any pin exists — is still the featured card, so "pin it to the top" literally puts that folder in the hero slot. Nothing about the layout branches on whether pins exist.

All remaining pinned folders use the compact row anatomy but retain the same non-interactive icon + count category rail as the featured card. Unpinned compact rows have no rail. This preserves category context for the intentionally elevated set without bringing back unlabeled dots across the full list.

**Rejected:** a Notes-style "Pinned" section header above the list. Notes needs one because its pinned band is collapsible and its rows are homogeneous; here the home already has a two-density hierarchy (featured card + compact rows), and inserting a header between them would restructure the screen the moment the first pin appears — precisely the "layout rule firing" the featured-first spec was designed to avoid.

**Rejected:** pinned folders stay in the compact list and the featured card remains most-recent-activity. That would mean pinning a folder can leave it *below* an unpinned featured folder — visibly not "the top".

### D5 — Order within the pinned band: most recently pinned first

Among pinned folders, sort by `pinnedAt` descending; ties (theoretically possible after sync) fall back to the existing activity comparator. Pinning something new puts it at the very top — the direct reading of "pin it to the top" — and the user can therefore arrange the pinned band deliberately by pinning in reverse order of importance.

**Rejected:** activity-recency within the pinned band (Notes' behavior). It makes the pinned band churn on its own, recreating in miniature the instability pinning exists to stop.

### D6 — Affordance: context menu on the featured card and every compact row

`.contextMenu(menuItems:)` (docset `/documentation/swiftui/view/contextmenu(menuitems:)`, Platforms: iOS 13.0+, macOS 10.15+) on the row/card content: one toggle item — **Pin** (`pin` symbol) when unpinned, **Unpin** (`pin.slash`) when pinned. Long-press activates it on iOS; on macOS the same modifier produces the right-click menu with no preview (per the docset note), so the Mac sidebar rows get the feature for free. Archived-folder rows get no pin item (non-goal). The existing `.animation(.default, value: sortedGroupIDs)` on the list already animates the reorder when a pin lands.

**Rejected:** a leading swipe action (Mail-style). The app's swipe vocabulary is deliberately single-purpose — trailing swipe = archive, tinted Ledger Green — and the owner explicitly asked for long-press.

### D7 — Pinning does not steer capture

`mostRecentlyUsedGroup` (ContentView.swift) — the fallback default destination for scans — keeps pure most-recent-activity ordering. Pinning is a *presentation* preference ("keep this visible"), not a routing preference; scanning at a cash register must land in the folder you're actively filling, not the folder you pinned last week ("capture must never be blocked" — and never mis-routed — at a cash register, PRD §6.4 spirit). Concretely: the activity-only sorted helper remains and keeps its current callers in capture routing; the Folders home and Mac sidebar switch to a new pinned-first helper.

### D8 — Archiving a pinned folder clears the pin

Archive sets `pinnedAt = nil` alongside `archivedAt`. The archived list keeps its own archive-recency order, and a later unarchive must not teleport a long-forgotten folder above current pins. Re-pinning after restore is one long-press.

### D9 — Pinned-row indicator

Pinned compact rows and a pinned featured card show a small `pin.fill` glyph in secondary foreground style (caption scale, `@ScaledMetric`-free — it rides the text style), placed at the leading edge of the trailing totals stack on rows and beside the metadata line on the featured card. Quiet by design: no fill, no accent color (single-accent rule; the pin is state, not an action), no red (hard rule). The glyph is `accessibilityHidden`; the state is conveyed through the row's combined accessibility label instead (§6).

Pin/unpin reorder uses a short ease-in/out transition instead of SwiftUI's spring-like default list animation. The transition stays calm when a row crosses between compact and featured densities and respects the system Reduce Motion behavior.

## 5. Edge cases

- **Every folder pinned:** order is entirely pin-recency; featured = most recently pinned. No special casing.
- **Single folder:** pinning is a visual no-op (already featured); the menu still works and the indicator shows, so state isn't mysterious.
- **Pin then immediate activity elsewhere:** pinned folder stays featured — that is the feature.
- **Sync races:** two devices toggling the same folder converge last-writer-wins (D3). Two devices pinning *different* folders both survive; band order = `pinnedAt` descending across both.
- **Equal `pinnedAt` after sync:** fall back to the activity comparator, then name (existing tie-break chain) — sort must stay strict-weak.
- **Archive → unarchive:** pin cleared on archive (D8); restored folder re-enters the unpinned band by activity.
- **Deleting a pinned folder:** nothing special — next folder in order becomes featured (existing path from the featured-home spec).
- **Agent-pending entries / unfiled section:** unaffected; they don't participate in folder ordering.

## 6. Accessibility & localization

New String Catalog keys (`Localizable.xcstrings`):

| Key | English value | Where |
|---|---|---|
| `folder.pin` | `Pin` | Context-menu item label |
| `folder.unpin` | `Unpin` | Context-menu item label |
| `folder.pinned` | `Pinned` | Appended to the combined accessibility label of pinned rows and the pinned featured card; also the Mac row tooltip suffix if the sidebar help string gains it |

No plural variants; no locale-dependent data involved. No existing key changes value.

Accessibility:

- New identifiers: `folder.action.pin`, `folder.action.unpin` (context-menu buttons — matching the `trip.action.archive` naming precedent), `folder.pinned.indicator` on the glyph if UI tests need to assert its presence; the glyph itself is `accessibilityHidden`.
- Rows keep `.accessibilityElement(children: .combine)`; the pinned state reads as part of the single row utterance via `folder.pinned`.
- Dynamic Type: the pin glyph uses a text-relative size; featured-rail AX behavior per D2 (chips wrap, nothing scrolls or clips — verify at AX5, light and dark).
- The context menu is reachable through VoiceOver's actions rotor as standard for `.contextMenu`.

## 7. Test impact

- **Unit (IntelliExpenseTests, PersistenceTests/new file):** pinned-first ordering — pinned above unpinned regardless of activity; pin-recency order within the band; tie fallback; archive clears `pinnedAt`; activity-only helper unaffected by pins (D7). Model change is additive-optional, so existing store fixtures need no migration handling.
- **UI (IntelliExpenseUITests):** long-press a compact row → tap `folder.action.pin` → assert the folder becomes the featured card and shows the pinned indicator; unpin restores activity order. Existing folder-list assertions must not reference dots (none currently do — `ExpenseTypeGlyphs` had no identifier).
- **Catalog audit (FolderUserFacingRenameTests):** new keys are folder-language, pass the no-trip-language audit as written.
- **Manual matrix:** pin/unpin on iPhone (long-press) and Mac (right-click); AX5 featured card with 4+ categories — chips wrap, no clipping, no dots anywhere; light/dark.

## 8. Acceptance criteria

1. No category color dots render on any folder row or card at any type size; `ExpenseTypeGlyphs` no longer exists in the codebase. Every pinned iPhone row keeps the labeled icon + count category rail; unpinned compact rows do not.
2. At AX text sizes the featured card's chip rail wraps onto additional lines; nothing clips, nothing scrolls horizontally.
3. Long-press (iOS) / right-click (Mac) on the featured card or any active compact folder row offers Pin or Unpin; archived rows offer neither.
4. A pinned folder sorts above every unpinned folder on the Folders home and Mac sidebar; the most recently pinned folder is the featured card; multiple pins order by pin recency.
5. Pinned rows and a pinned featured card show the quiet pin indicator; VoiceOver reads "Pinned" as part of the row.
6. Scan-capture default destination still follows most-recent activity, ignoring pins.
7. Archiving a pinned folder unpins it; pin state syncs across devices via CloudKit with no schema violation (optional attribute, default nil).
8. `DESIGN.md` and `design/ui-spec.html` are updated in the implementation commit per the "Docs this spec amends" header.
9. Pin/unpin promotion uses a short ease-in/out reorder rather than the default spring-like list motion.
