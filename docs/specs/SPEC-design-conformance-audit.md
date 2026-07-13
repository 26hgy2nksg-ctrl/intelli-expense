# Spec: Design-system conformance fixes (audit remediation)

**Status:** ready for implementation
**Source:** full audit of the SwiftUI implementation against DESIGN.md (tokens + rules) and design/ui-spec.html (canonical layout). Every finding below was verified in code at the cited lines.
**Scope:** UI layer only — `ContentView.swift`, `UI/*.swift`, `ReviewViews.swift`, String Catalog. No pipeline, persistence, or `ExpenseCore` changes except where noted.
**Related specs (do not duplicate):** full-screen zoomable image viewing is covered by `SPEC-full-resolution-receipt-viewing.md`; export progress & background assembly is `SPEC-prd-conformance-audit.md` A-R8 (the progress-card visual there follows ui-spec.html §export).

Passing areas (no action): asset catalog has all ten token pairs with correct light/dark hexes; no hex/`Color(red:)` literals, no `colorScheme` branches, no `.red`/`systemRed` direct uses; single brand accent; VoiceOver labels on icon buttons; accessory hidden on Settings; `tabBarMinimizeBehavior(.onScrollDown)`; reduce-motion honored in the scan-line animation.

---

## Priority 1 — binding-rule violations (small, do first)

### D-R1 — Remove all red (three `role: .destructive` renders)

DESIGN.md: "no red anywhere; the app never alarms." Violations:

1. `UI/ReviewViews.swift:134` — review screen **Discard** button (`role: .destructive`) renders red directly under the green Save on the hero screen. Fix: plain secondary text button (`.foregroundStyle(.secondary)`, footnote stays), per ui-spec.html:916/1004. Add the spec'd guard: confirm discard **only if the user edited something** (track a `form.isDirty`-style flag: any field changed from initial values); untouched form discards silently (ui-spec.html:1004).
2. `UI/ReceiptsViews.swift:414` — Delete row in receipt detail. Fix: drop `role: .destructive`; style as a plain button with `.foregroundStyle(.secondary)` and `trash` icon; keep the confirmation dialog.
3. `UI/ReceiptsViews.swift:421` — Delete inside the confirmation dialog. Fix: drop the role there too. (Yes, this diverges from the HIG default; the repo's design rule is explicit and binding: never red, deletion safety comes from the confirmation step.)

### D-R2 — Group-detail toolbar: single Export share icon (the "+ Export" alignment report)

`UI/GroupsViews.swift:190–197` puts an icon-only `plus` button and a **text** "Export" button in one `ToolbarItemGroup(.topBarTrailing)`. On iOS 26 the group shares one glass capsule; symbol + text mix with unequal widths and optical baseline mismatch — this is the misalignment the user sees. It also contradicts ui-spec.html:744–745/812: the group screen has exactly **one** trailing control, an icon `ToolbarItem` with `square.and.arrow.up`, "toolbar icons only, labeled for VoiceOver".

Fix:
- Delete the `plus` toolbar button. In-group capture is the capture accessory bar's job (ui-spec.html:806 — "capture bar now targets this group"; see D-R6 which makes that visible). `GroupDetailView.onCapture` stays for the empty-state CTA (GroupsViews.swift:167).
- Replace the text button with:
```swift
ToolbarItem(placement: .topBarTrailing) {
    Button { exportGroup() } label: { Image(systemName: "square.and.arrow.up") }
        .accessibilityLabel(Text("export.button"))
        .accessibilityIdentifier("group.export")
}
```
- Keep the `export.button` key (now the VoiceOver label).

### D-R3 — Dynamic Type: remove fixed point sizes

DESIGN.md: "Dynamic Type text styles only; never fixed point sizes."

- `UI/OnboardingViews.swift:11` `.font(.system(size: 46, …))` and `:86` `.font(.system(size: 42, …))` → `.font(.largeTitle.weight(.semibold))` + `.imageScale(.large)`, or `@ScaledMetric` if a larger glyph is essential.
- `UI/ReceiptsViews.swift:29` `.font(.system(size: 44))` in `AppEmptyStateView` → `.font(.largeTitle)` + `.imageScale(.large)`.
- Sweep the fixed icon frames (34/38/44/28 pt at GroupsViews.swift:96, OnboardingViews.swift:13/64, ReceiptsViews.swift:281/286, ReviewViews.swift:361, ContentView.swift:470): convert to `@ScaledMetric(relativeTo:)` so glyph tiles grow with type size. Acceptance: at AX5 text size nothing truncates into an unreadable fixed box.

### D-R4 — Per-currency totals: primary large, secondary small

`UI/ExpenseFormatters.swift:16–23` (`compactTotals`) joins all currency totals into one equally-sized string, used in the group hero (GroupsViews.swift:151–153) and group rows (:107–110). DESIGN.md §9 + ui-spec.html:749/586 (`hero-amt` + `<small>`, `amt`/`amt2`): the **largest** currency total renders large; other currencies render below in `.footnote`/`secondaryLabel`. Never sum across currencies (already respected).

Fix: add a formatter that returns ordered `(primary: String, secondary: [String])`; hero shows primary in the hero style (see D-R11), secondaries stacked in `.footnote.secondary`; rows show primary trailing with secondaries beneath. Unit-test with 1, 2, and 3 currencies.

## Priority 2 — spec'd structure that's missing

### D-R5 — Group detail: section receipts by issue date

`UI/GroupsViews.swift:159–187` renders one flat section. DESIGN.md §5 + ui-spec.html:766/778 require date sections ("Saturday, June 14") — group detail groups by receipt **issue date** (day), newest day first. Reuse the month-grouping pattern from ReceiptsViews.swift:182–190 with day granularity; header via locale-aware `Date.FormatStyle` (`.dateTime.weekday(.wide).month().day()`).

### D-R6 — Capture accessory: destination-group subtitle + real ⋯ menu

`ContentView.swift:451–491`:
1. Subtitle is static (`capture.accessory.subtitle`). DESIGN.md §4 / ui-spec.html:615/700/725: subtitle names the destination — the open group's name when a group detail is on screen, else "Files to Unfiled until you choose" (`capture.accessory.unfiled` key). Plumb the current destination group up (e.g. `@State` on `MainTabView` set by `GroupDetailView.onAppear/onDisappear` or a preference key).
2. Split actions per ui-spec.html:726: tapping the bar's main area goes **straight to the document camera**; the trailing `ellipsis.circle` (ContentView.swift:480, currently decorative) becomes a real `Menu` with Photo / File / Manual. Long-press on the bar offers the same menu. Keep `-UITestFakeServices` behavior working for both paths.

### D-R7 — Groups home toolbar: follow chosen Option A

`UI/GroupsViews.swift:59–69` shows a leading "New Group" text button and a trailing `plus` capture button; the chosen spec Option A (ui-spec.html:580/729) has an empty large-title row — creation lives in the list ("New Group…" row / empty-state CTA) and capture lives in the accessory bar. Fix: remove both toolbar items; add a "New Group…" affordance as the list's last row (`Label("groups.create", systemImage: "folder.badge.plus")`, plain tint) in addition to the existing empty-state button.

### D-R8 — Duplicate banner: real banner + haptic + peek

`UI/ReviewViews.swift:216–238` is a plain label; `DuplicateBannerBackground` asset is referenced nowhere (dead token). Per ui-spec.html:973–977 + DESIGN.md haptics table:
- Render as a banner row: `DuplicateBannerBackground` fill, `DuplicateBannerText` content, `exclamationmark.triangle` icon, rounded 12 pt.
- Trailing **View** button navigating (push or sheet) to the existing matching receipt's `ReceiptDetailView` (read-only peek is fine).
- Fire `.sensoryFeedback(.warning, trigger:)` exactly once when the banner first appears — the only `.warning` in the app.

### D-R9 — Review polish trio

1. **Save haptic:** `.sensoryFeedback(.success, trigger:)` on successful save (ReviewViews.swift:151–159); DESIGN.md haptics table.
2. **Attention edge:** uncertain fields (choice chips visible & unconfirmed) get the 2.5 pt warm leading edge inset (`AttentionFieldEdge` token) on the row, not just the amber caption (ReviewViews.swift:298–309; ui-spec.html:1002 "law").
3. **Disabled Save explains itself:** keep `.disabled`, add ui-spec.html:1003 behavior — tapping the dimmed Save area shows one inline footnote naming the missing fields (`review.save.missing` key with `%@` list). 60 % opacity comes from the disabled state.

### D-R10 — Notice styling separation

`ReviewViews.swift:195–203` colors model-degradation notices with `DuplicateBannerText` (amber). DESIGN.md §8: degradation notices are **one secondary-label line** (`.footnote`, `.secondary`); amber is reserved for duplicate/attention semantics. Fix `NoticeBanner` accordingly.

### D-R11 — Hero money size token

`GroupsViews.swift:152` uses `.largeTitle.weight(.light)`; DESIGN.md `hero_money` is title1-adjacent. Use `.title.weight(.light)` (+ `.monospacedDigit()` stays). `largeTitle` remains reserved for tab-root navigation titles.

## Priority 3 — smaller fidelity gaps (batch)

- **D-R12** Group rows & detail header metadata: rows show "Jun 12–18 · 14 receipts" when dates exist (GroupsViews.swift:115–118 shows count only); detail header adds the "14 receipts · Jun 12–18, 2026" line under the hero (ui-spec.html:750). Locale-aware interval formatting (`Date.IntervalFormatStyle`); new keys `groups.row.subtitle.dated`, `group.detail.meta`.
- **D-R13** Receipt row layout: expense-type badge moves under the right-aligned amount (ReceiptsViews.swift:245–247 → trailing VStack), per ui-spec.html:1036.
- **D-R14** Type selector selected ring: add the 1.5 pt inset ring in the type's color on selection (ReviewViews.swift:370; ui-spec.html:1141).
- **D-R15** Review sheet gets the ✕ close item (ui-spec.html:876) — `xmark` toolbar button, same discard-guard as D-R1.1.
- **D-R16** Processing overlay: remove decorative `.shadow(radius: 12)` (ContentView.swift:541/545, DESIGN.md elevation rule); replace raw `Color.white`/`.gray` placeholder fills (ContentView.swift:544–551) with semantic (`.background`, `.secondary.opacity`) equivalents. The black scrim (:499) and the badge scrim (ReviewViews.swift:186) may stay — they sit over photographic content by design; the scan-line gradient stays.
- **D-R17** Breakdown chips become tap-to-filter: tapping a type chip in the group hero sets `typeFilter` (GroupsViews.swift:232–260 → bind into `FilterStrip` state); "filters-in-waiting" (ui-spec.html:805).
- **D-R18** Filters as visible removable chips: replace the two `Menu`s in group detail's `FilterStrip` (GroupsViews.swift:263–291) and the Receipts-tab toolbar `Menu` filters (ReceiptsViews.swift:108–158, keep Active/Archived mode in the menu) with a horizontal chip row — selected chip = Ledger Green fill white text with ✕ to remove (DESIGN.md §4; ui-spec.html:759–765/1029–1031). Chips are added via a compact "+ Filter" menu; state you can see.

## Explicitly deferred (need product decisions — not in this spec)

Manual-entry amount-hero sheet (ui-spec.html:1118–1154), review ambiguity auto-scroll + "N fields need a look" header, save-success landing animation, Settings enrichment (sync status, storage row, CSV format row), `ContentUnavailableView`-shaped empty-state restyle. If the implementer finishes everything above, stop — these are separate briefs.

## Localization

All new strings via `Localizable.xcstrings`: `capture.accessory.unfiled`, `review.save.missing`, `review.duplicate.view`, `groups.row.subtitle.dated`, `group.detail.meta`, plus any key noted inline. No literals in views.

## Tests & acceptance

- Unit: totals formatter (D-R4) for 1/2/3 currencies; day-section grouping (D-R5) across month boundaries.
- UI (`-UITestFakeServices`): group detail toolbar exposes `group.export` and **no** plus button; export share sheet still appears; Discard with edits prompts, without edits doesn't; duplicate banner appears for a matching fixture and its View button navigates.
- Manual acceptance: light/dark + AX5 Dynamic Type sweep of Groups, Group detail, Review, Receipts; **zero red pixels anywhere including delete flows**; toolbar icons optically aligned in one glass group; per-currency hero shows large primary + small secondaries.
- Commands: `cd ExpenseCore && swift test` (must stay green, untouched); `xcodebuild -project IntelliExpense.xcodeproj -scheme IntelliExpense -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' test`.
