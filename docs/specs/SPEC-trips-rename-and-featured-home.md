# SPEC — "Trips" rename + featured-first Trips home

**Status:** proposed (user-approved direction: rename = **Trips**, sparse layout = **featured-first**)

> **Amendment (2026-07-10):** `SPEC-folder-pinning-and-type-dot-removal.md`
> adds active-folder pinning. Featured selection now uses pinned-first order
> (pin recency, then activity) while preserving the same featured-first layout.
**Owner screens:** Trips home (`IntelliExpense/UI/GroupsViews.swift`, `GroupsTabView`), tab bar (`IntelliExpense/ContentView.swift`), Receipts-tab filter (`IntelliExpense/UI/ReceiptsViews.swift`), receipt review group field
**Docs this spec amends:** `DESIGN.md` §4/§5, `design/ui-spec.html` §2 (Groups home), PRD §5.1 (UI naming note only — data model untouched)

---

## 1. Problem

Two independent issues on the home tab, fixed together because both live on the same screen:

1. **"Groups" is the wrong user-facing word.** The PRD deliberately made the *data model* generic ("a 'trip' is just a group the user names", PRD §4.1), but the UX copy is already trip-first — the empty state says "Start your first trip". No comparable app calls this concept "Groups"; the word reads as "people groups" (Messages, Contacts). Industry precedent: Zoho Expense, SAP Concur, and Ramp all present the container as **Trips** (Expensify/Smart Receipts use "Reports", which implies a submit/approve workflow this app deliberately lacks).
2. **The home screen looks bare at 1–3 trips.** Today every trip renders as one compact inset-grouped row regardless of count. A realistic steady state for this app is *one or two active trips*, so the primary screen is usually a ~90pt row floating in black. Apple's pattern language (Wallet single-pass card, Apple Invites event cards, Fitness summary cards) solves this by making items rich cards whose size is justified by their content — not by leaving rows small.

Field evidence: device screenshot with one group ("Bengaluru Conference") — a single row plus "New Group…" occupies <15% of the screen.

## 2. Goals

- The container is called a **Trip** everywhere the user reads it; the code keeps `ExpenseGroup`, `GroupsTabView`, `groups.*` string keys, and `groups.*` accessibility identifiers unchanged. Adding a language stays a pure translation task (PRD §3.2).
- The top trip in pinned-first order is always a **featured card** — rich enough (hero total, date range, type breakdown, receipt thumbnails) that a 1-trip screen looks deliberate, not empty.
- The layout is **monotonic**: it never restructures when the trip count crosses a threshold. At 1 trip: featured card only. At 12 trips: same featured card + compact rows. No count-based branching, so no "where did my big card go?" jump (the documented pitfall of hero-at-1/cards-at-3/rows-at-4 tiering).
- Zero regressions to existing laws: swipe-to-delete with the keep/delete-receipts dialog, Unfiled section, ledger typography (tabular numerals, right-aligned money), single brand accent, Dynamic Type only.

## Non-goals

- **No data-model or code-identifier rename.** `ExpenseGroup`, SwiftData schema, CloudKit record types, export CSV column names, string-catalog *keys*, and accessibility identifiers all keep "group". This is a strings-and-layout change only.
- No dashboards or charts on the featured card (PRD §2 non-goal) — the breakdown chips are the same glanceable count·amount chips the trip detail already uses, not a visualization.
- No change to trip detail, Receipts tab layout, capture flow, or export.
- No iPad/adaptive-grid work.

## 3. Design decisions

### D1 — Rename: string-catalog *values* change, keys don't

All changes are in `IntelliExpense/Resources/Localizable.xcstrings` (English values). Keys are stable so no Swift file changes for the rename itself.

| Key | Current value | New value |
|---|---|---|
| `tab.groups` | Groups | **Trips** |
| `groups.create` | New Group | **New Trip** |
| `groups.create.row` | New Group... | **New Trip...** |
| `groups.empty.title` | Start your first trip | *(unchanged — already correct)* |
| `groups.empty.message` | Make a group for a trip, then scan receipts into it. | **Create a trip, then scan receipts into it.** |
| `filter.allGroups` | All groups | **All trips** |
| `filter.group` | Group | **Trip** |
| `filter.group.section` | Group | **Trip** |
| `group.detail.empty.title` | No receipts in this group | **No receipts in this trip** |
| `group.delete.title` | Delete %d groups? | **Delete %d trips?** |
| `group.editor.edit.title` | Edit Group | **Edit Trip** |
| `receipt.field.group` | Group | **Trip** |

Unchanged on purpose:

- **"Unfiled"** (`groups.unfiled.*`, `capture.accessory.unfiled` "Files to Unfiled until you choose") — reads naturally as "not yet assigned to a trip"; Concur/Zoho demonstrate users hold "trips + a loose pool of unassigned expenses" comfortably.
- `group.editor.name/start/end/includeDates/section.details`, `groups.receipt.count`, `groups.row.subtitle.dated`, `group.detail.meta`, `group.breakdown.item`, `group.delete.keep/deleteAll` bodies — none of them contain the word "group" except as covered above.

**Iconography stays folder** (`folder` tab symbol, `folder.fill` row/card tile, `folder.badge.plus` create, `tray` Unfiled). Rationale: the filing metaphor is the app's honest mechanic (receipts are filed into containers; export literally produces date-named folders), it pairs with "Unfiled", and a suitcase/airplane symbol would be wrong for non-travel trips like "Q3 client visits". Considered and rejected: `suitcase` (breaks non-travel containers; also "trip" = single drive in mileage apps, so leaning harder into travel iconography invites that confusion).

### D2 — Featured-first structure (Fitness-app model)

`GroupsTabView`'s `List` becomes three sections; still a `List` (inset-grouped) so swipe-to-delete, the Unfiled section, and the capture accessory bar all keep working unchanged:

1. **Featured section** (no header): the *first* element of `ExpenseGroup.sortedPinnedFirst(groups)` — pinned trips first by pin recency, then the existing activity/name comparator. One `NavigationLink` to the same `GroupDetailView`, labeled with the new `FeaturedTripCard` (D3). Swipe-to-archive applies here too; context menu provides Pin/Unpin.
2. **Compact section** (no header): `sortedGroups.dropFirst()` rendered with the existing `GroupRow`, followed by the existing "New Trip..." row (`groups.create.row`). With exactly 1 trip this section contains only the create row — which is desirable: it visually invites trip #2.
3. **Unfiled section**: unchanged (header, `tray` row, count, `groups.unfiled.link`).

Empty state (0 trips and 0 unfiled): unchanged `AppEmptyStateView` block.

Why this shape: it is monotonic in count (nothing moves or re-styles when trip #2..#n arrives). Activity keeps unpinned trips self-prioritizing, while an explicit pin keeps an important trip in the hero slot. Pinning is presentation-only; the capture bar's default destination remains activity-based.

### D3 — `FeaturedTripCard` anatomy

A single vertically-stacked card inside the list row (16pt internal padding via the row's default insets + `.padding(.vertical, 8)` like the trip-detail hero section). Top to bottom:

1. **Identity line**: `folder.fill` icon tile (same `LedgerGreen` on `LedgerGreenSoft` treatment as `GroupRow`, `@ScaledMetric` size) + trip name in `.title3.weight(.semibold)` + chevron provided by the `NavigationLink`.
2. **Hero total**: reuse the exact `GroupTotalsHero` presentation from trip detail — primary currency total in `.title.weight(.light)` `.monospacedDigit()`, secondary currency lines in `.footnote` `.secondary`, metadata line (`group.detail.meta`: "%d receipts | %@") beneath. This is the screen's **one hero number** (DESIGN.md §4); the compact rows below keep their `.subheadline` totals, which are not hero-weight, so the rule holds. `GroupTotalsHero` and `GroupMetadata.detailMeta` are currently `private`/`private enum` members of GroupsViews.swift — same file, so reuse is free.
3. **Type breakdown chips**: the existing `BreakdownChips` horizontal strip (icon + "%d · %@" per expense type present), rendered **non-interactive** on the card — pass a constant binding or add a `Bool` to suppress the button action; the whole card is one tap target that opens detail. (A tappable chip inside a `NavigationLink` row is a nested-tap-target trap; filtering lives in detail.)
4. **Receipt thumbnail strip**: up to 3 most-recent receipt thumbnails (`ReceiptThumbnail`, the component `ReceiptRow` already uses — promote its access level if needed) in an `HStack(spacing: 8)`, each clipped to the standard continuous-corner radius. Receipts without images (manual entries) render the thumbnail's existing placeholder. If the trip has **zero receipts**, omit the strip and the breakdown row entirely; the card is then identity + hero total ("0 receipts") + nothing — still substantial, never broken-looking.
5. Whole card: `.accessibilityElement(children: .combine)`, identifier **`groups.featured.card`** (new).

No new colors, no glass (DESIGN.md §6's two-element glass budget is untouched), no fixed point sizes — every text role above is an existing Dynamic Type style already used elsewhere in the app. At accessibility text sizes the chips/thumbnail strips scroll horizontally (BreakdownChips already does) and the card simply grows taller.

### D4 — Motion & edge cases

- **Featured swap**: pin/unpin or activity within the unpinned band can move a trip to the top; the change rides the default `List` animation (`.animation(.default, value:)` on the sorted IDs if needed). No `matchedGeometryEffect` — the featured card and compact row are intentionally the same identity elements (icon tile, name, total) at different densities, Wallet-style, so the default move/fade reads correctly.
- **Deleting the featured trip**: next most-recent trip becomes featured; if it was the only trip, the screen falls back to compact-section create row + Unfiled (or the empty state when Unfiled is also empty). All existing paths.
- **Unfiled is never featured** — it is a holding pen, not a trip; keeping it compact and pinned below is what makes "Unfiled" legible as *not yet filed*.
- **Very long trip names**: name line wraps (no `lineLimit(1)` truncation on the featured card; compact rows keep current behavior).

### D5 — Documentation amendments (same commit)

- **DESIGN.md §4** gains a component rule: *"Trips home: the top trip in pinned-first order is always a featured card — icon tile + name (title3 semibold), hero per-currency total (title light, tabular), meta line, non-interactive breakdown chips, up to 3 receipt thumbnails. Remaining trips are standard compact rows. One hero number per screen: the featured card owns it."* §5's list-order rule becomes "pinned first, then activity, top trip featured."
- **design/ui-spec.html §2** (Groups home): retitle to Trips, update all mock copy ("New Trip...", tab label), and replace the uniform-rows mock with the featured-first layout at two states (1 trip; 4 trips + Unfiled).
- **PRD §5.1**: add one sentence: *"UI label for ExpenseGroup is 'Trip' (tab: Trips); the model stays the generic Group per §4.1."* No other PRD change.

## 4. Layout spec

| Element | Value |
|---|---|
| Featured card sections/padding | standard inset-grouped row + 8pt extra vertical padding (matches trip-detail hero section) |
| Identity line | icon tile 34pt `@ScaledMetric(relativeTo: .body)`, name `.title3.weight(.semibold)`, 12pt spacing |
| Hero total | `.title.weight(.light)` + `.monospacedDigit()`; secondary currencies `.footnote` `.secondary` |
| Meta line | `.footnote` `.secondary` (`group.detail.meta` format) |
| Breakdown chips | existing `BreakdownChips` sizing (caption semibold, 10/6pt padding, capsule at 0.14 opacity type color), non-interactive |
| Thumbnail strip | up to 3 × `ReceiptThumbnail`, `HStack(spacing: 8)` |
| Vertical rhythm inside card | 12pt between blocks (matches detail hero section) |
| Compact rows | unchanged `GroupRow` |

All colors from existing asset-catalog tokens; no `colorScheme` branches; base-4/8 grid throughout.

## 5. Accessibility & localization

- **Original rename strings:** every original label on the featured card reuses existing keys (`group.detail.meta`, `group.breakdown.item`, `groups.receipt.count`). The later pinning amendment adds `folder.pin`, `folder.unpin`, and `folder.pinned`.
- New accessibility identifier: `groups.featured.card`. All existing identifiers (`groups.create.row`, `groups.unfiled.link`, `group.export`, …) unchanged.
- Featured card is a single VoiceOver element combining name, total(s), meta, and pinned state; chips/thumbnails are `accessibilityHidden` details.
- Dynamic Type: no fixed text sizes introduced; verify card at AX5 (name and breakdown chips wrap without clipping or horizontal scrolling).

## 6. Test impact

- **UI tests** (`IntelliExpenseUITests/IntelliExpenseUITests.swift:15,27,118,140,244,317`): `app.tabBars.buttons["Groups"]` → `app.tabBars.buttons["Trips"]`. Any assertions on navigation bar "Groups" title likewise become "Trips". `app.navigationBars["Unfiled"]` (line 121) unchanged.
- **New UI test — featured card**: seed one trip with receipts → assert `groups.featured.card` exists, contains the trip name, and tapping it lands on the trip-detail screen (existing `group.export` button visible).
- **New UI test — monotonic layout**: create a second trip → assert `groups.featured.card` still exists exactly once and the other trip appears as a plain row; delete the featured trip via swipe → confirmation dialog (now titled "Delete 1 trips?" — see note below) → remaining trip becomes featured.
- **Unit tests:** pinning adds explicit coverage for pinned-first ordering, pin-recency ties, archive clearing, and the unchanged activity-only capture helper.
- **Manual verification**: 0 / 1 / 2 / 5 trips + Unfiled states in the simulator, light/dark, default and AX5 type sizes.

## 7. Acceptance criteria

1. Tab bar, navigation title, create actions, filters, editor, delete dialog, and review form all say Trip/Trips; the words "Group"/"Groups" appear nowhere in the running UI. "Unfiled" is unchanged.
2. `ExpenseGroup`, string-catalog keys, accessibility identifiers, CloudKit schema, and export format are byte-for-byte unchanged (rename is values-only) — verified by diff scope: `Localizable.xcstrings`, `GroupsViews.swift`, `IntelliExpenseUITests.swift`, DESIGN.md, ui-spec.html, PRD.md only.
3. With exactly 1 trip, the home screen shows the featured card (hero total, meta, chips, thumbnails when receipts exist) + "New Trip..." row (+ Unfiled when applicable) — no full-width dead zone below the fold caused by a lone compact row.
4. With N ≥ 2 trips, the top trip in pinned-first order is the featured card and the rest are compact rows; pinning and activity may change which trip occupies the featured slot without restructuring the layout.
5. Exactly one hero-weight number on the screen (the featured card's primary total); compact rows keep subheadline totals; money everywhere remains tabular-numeral, per-currency, never summed across currencies.
6. Swipe-to-delete works on both the featured card and compact rows with the existing keep/delete-receipts dialog; VoiceOver reads the featured card as one element and can navigate to detail.
7. All ExpenseCore tests, app unit tests, and the migrated + new UI tests pass.

## 8. Out of scope (noted during this review)

- `group.delete.title` "Delete %d trips?" and `groups.receipt.count` "%d receipts" do not vary by plural — "Delete 1 trips?", "1 receipts" are pre-existing pluralization bugs the rename inherits; fix via `.xcstrings` plural variants in a separate pass.
- The trip-detail screen's own hero (`GroupTotalsHero`) is now visually echoed by the home featured card; if that repetition feels heavy in practice, a follow-up may differentiate the detail hero (e.g., larger, with per-day sparkline — currently a PRD non-goal).
- Receipts-tab month sections and Settings are untouched; if the "Trips" mental model ever warrants a dedicated trip picker in capture, that is a separate spec.
