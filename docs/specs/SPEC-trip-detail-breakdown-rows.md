# SPEC — Trip detail: breakdown chips become ledger rows

**Status:** proposed
**Owner screens:** Trip detail (`IntelliExpense/UI/GroupsViews.swift` — `GroupDetailView` hero section, `BreakdownChips`, `BreakdownChipLabel`)
**Supersedes:** the non-goal in SPEC-featured-card-rails-redesign §Non-goals that accepted trip-detail `BreakdownChips` as a horizontally scrolling rail ("a scroll-edge fade there is a possible follow-up"). Field evidence has overruled that acceptance; this spec replaces the rail. Everything else in that spec stands.
**Docs this spec amends:** `DESIGN.md` §4 (new "Trip-detail breakdown rows" component rule) and its example prompt; `design/ui-spec.html` trip-detail screen (breakrow → stacked ledger rows, lede, figcaption, notes, summary table). *Both docs are already amended in the same change that introduces this spec.*

---

## 1. Problem

Field evidence: device screenshot of the shipped trip detail ("Bengaluru Conference", ₹38,642.75, 12 receipts, 4+ expense types). The per-type breakdown under the hero total is a horizontal `ScrollView` of one-line capsules ("🍴 2 · ₹2,475.00"). With 4–5 types present:

- **The summary hides its own content.** The rail clips mid-capsule at the card edge ("✈ 1 · ₹…" sliced); the remaining types are discoverable only by an invisible horizontal scroll. The detail header exists to show the whole trip at a glance — content that must be scrolled into view is not a summary.
- **No affordance.** A capsule cut mid-glyph reads as a rendering bug, not a scroll hint.
- **Gesture trap.** A horizontal scroll region inside a vertically scrolling `List` hero section fights the dominant gesture.
- **Doc drift.** The canonical mock never scrolled: `ui-spec.html`'s `.breakrow` was a wrapping container of two-line stat cells. The implementation shipped a different, one-line scrolling design. This spec re-converges implementation and mock on one layout — stacked full-width ledger rows — and re-canonicalizes it in both docs.

## 2. Goals

- Every expense type present in the trip is **fully visible at a glance** in the hero card — no horizontal scrolling, no clipping, no empty half-slots — at default Dynamic Type sizes and at accessibility sizes, for any type count (1–5).
- Per-type amount and count remain exact (full-precision money, never rounded/compacted notation).
- The breakdown reads like the ledger it summarizes: amounts on a right edge, tabular, exactly as the receipt rows below it.
- Tap-to-filter behavior is preserved (breakdown rows stay "filters-in-waiting" per the mock's notes).
- The hero total remains the screen's one hero number; breakdown amounts step down in weight and size.
- Layout is **static and order-stable**: nothing reorders or reshapes as spending changes.

## 3. Non-goals

- No change to the **featured-card** breakdown rail on Trips home (`FeaturedBreakdownRail`, icon + count only — governed by SPEC-featured-card-rails-redesign).
- No change to the filter chip strip below the hero section (`FilterStrip`) or to filter semantics/composition.
- No charts, rings, or proportion bars — PRD §2 non-goal; DESIGN.md: "No charts, rings, or dashboards — type dots and breakdown chips only."
- No Mac changes: `GroupDetailView` is referenced only from the iPhone trip flows in `GroupsViews.swift`; the Mac companion has its own layout.

## 4. Design decisions

### D1 — The breakdown is a stack of slim full-width ledger rows, not a rail and not a grid

Replace `BreakdownChips`' horizontal `ScrollView`+`HStack` with a vertical stack of one full-width row per expense type present in `summary.breakdown`, in fixed `ExpenseType.allCases` order (absent types render nothing), inside the existing hero `VStack` under `GroupTotalsHero`. Row spacing 4–8 pt (base-4/8 grid).

Row anatomy — deliberately the same reading pattern as the receipt rows below (DESIGN.md §4 row anatomy: "thumbnail/glyph → title … → right-aligned tabular amount"):

- **Leading:** small type-colored rounded glyph tile (SF Symbol in white on the type color — the "color always means expense type" treatment shared with receipt-row badges), sized with `@ScaledMetric`.
- **Then:** the count caption — "6 Food" (caption-class, `secondaryLabel`), leading-aligned beside the glyph.
- **Trailing:** the per-type amount, right-aligned, footnote-class weight, semibold, tabular numerals, full-precision `ExpenseFormatters.compactTotals`.
- Quiet neutral row fill (`quaternarySystemFill`-class semantic color) with the system small card radius; every row spans the full card width.

**Rules this satisfies:** "One hero number per screen — everything else steps down through weight and color" (row amounts are footnote-weight, far below the ~31 pt light hero); "no charts … type dots and breakdown chips only" (rows are uniform width regardless of amount — no proportions drawn); base-4/8 grid; "Type colors only ever mean expense type"; the ledger convention — this block previews, in miniature, exactly the columnar shape of the receipt list under it, and of the exported CSV.

**Why rows beat every column arrangement.** Full-width rows are symmetric for *any* type count with no special-casing: 1 type = 1 row, 5 types = 5 rows — no orphan cells, no empty slots, no odd/even logic, no ordering heuristics, and therefore none of their tests. Right-aligned tabular amounts give the block the app's core ledger metaphor for free. Multi-currency amounts and accessibility text sizes have the full card width to work with. The cost is height — five types is five slim rows instead of a grid's three — accepted deliberately: the rows are compact (caption + footnote text), and a summary that is calm and complete beats one that is short and clever.

**Considered and rejected (all three column variants were prototyped side-by-side in the design-spec preview):**
- *Keep the rail, add a scroll-edge fade:* an affordance for a problem the header shouldn't have; content still hidden by default.
- *Two-column grid, orphan cell left as-is:* with 1/3/5 types the last cell sits beside empty space — visibly lopsided (the complaint that triggered this redesign's second iteration).
- *Two-column grid, highest-spend cell promoted to a full-width first row:* fills the rectangle and gives the width to the biggest category, but the grid **reorders itself as spending changes** — one hotel bill mid-trip reshuffles cell positions on a screen the user revisits constantly — and in a tappable grid the one wide cell reads as "selected"/"featured" rather than "largest". It also drags in a cross-currency ranking rule (spend can't be compared across currencies) purely to serve layout.
- *Adaptive columns (2+3 for five types):* three-across cells are visibly cramped at iPhone width (amounts collide with glyphs); cell widths differ from trip to trip.
- *Proportional/segmented bar:* it's a chart — explicit PRD §2 non-goal and DESIGN.md "don't".
- *Compact amounts ("₹2.3K"):* rounds money on screen; invites "numbers don't add up" doubt against the exact hero total. Money stays exact everywhere.

### D2 — Rows keep tap-to-filter; selection is the type's soft tint

Each row stays a button that toggles `typeFilter` for its type (tapping the active row clears it — today the chip can only set, never clear). The selected row swaps the neutral fill for the type color at soft-tint opacity (the existing 0.14 treatment used across type-soft fills); unselected rows stay neutral. `.selection` haptic on tap, per DESIGN.md §7 ("haptics close loops: `.selection` on chip picks").

**Why neutral-by-default (a change from today's always-tinted capsules):** five simultaneously color-filled surfaces compete with the hero number; neutral rows with colored glyph tiles keep the color channel meaning "expense type" without shouting, and make the *selected* tint state actually legible.

### D3 — Accessibility sizes wrap within the row, never scroll and never truncate

Rows are already full-width, so no column fallback is needed. At accessibility Dynamic Type sizes (`.accessibility1` and up), the caption and amount stack vertically inside the row (leading-aligned, amount below the caption) instead of competing for one line; the amount may wrap to a second line. Money is never truncated or elided; horizontal scrolling is never introduced at any size.

### D4 — String change: the row caption is "count + localized type name"

The one-line `"%d · %@"` (`group.breakdown.item`) composition is retired with the layout. The caption composes the count with the existing localized type names (`expense.type.food` etc.).

| Key | English value | Notes |
|---|---|---|
| `group.breakdown.cell.caption` | `%1$ld %2$@` | New. Arg 1 = receipt count for the type, arg 2 = localized type display name (from the existing `expense.type.*` keys). Rendered as the row's caption, e.g. "6 Food". No plural variant needed — the noun is the type name, which does not inflect with the count in English; translators can add plural variants per locale in the catalog if their language requires it. |
| `group.breakdown.item` | — | Removed. Its only reference is `BreakdownChipLabel` (`GroupsViews.swift`), which this spec redesigns. Key deleted from the catalog (unused keys don't ship). |

Amounts and counts are formatted by Foundation formatters (`ExpenseFormatters`), never in the catalog. No other user-facing text changes.

## 5. Edge cases

- **One type only:** a single row — inherently symmetric, no special case.
- **All five types:** five rows; the hero card grows vertically and the screen scrolls normally — never horizontally.
- **Multi-currency type** (e.g. Food has EUR + USD receipts): `compactTotals` joins per-currency amounts ("€412.10 + US$62.00"); the amount wraps to a second line within the row, staying right-aligned, rather than truncating.
- **Zero receipts / empty breakdown:** no rows render (existing behavior — `summary.breakdown` empty); hero card is total + metadata only.
- **Filtered-to-empty:** unchanged — the existing designed empty-filter state below handles it; the breakdown always reflects the *whole trip* (it is a summary, not a filtered view).
- **Archived receipts:** excluded, as today — the summary is built from `activeReceipts`.

## 6. Accessibility & localization

- Each row is one combined VoiceOver element with trait *button*: label composed as "«type name», «count as N receipts via existing `groups.receipt.count`», «amounts»"; the active filter row adds the *selected* trait. The stack itself gets no container label.
- New accessibility identifiers: `group.breakdown.food`, `group.breakdown.hotel`, `group.breakdown.flight`, `group.breakdown.taxi`, `group.breakdown.other` (one per rendered row).
- Dynamic Type only; glyph tile via `@ScaledMetric`; in-row stacking fallback per D3.
- Strings per D4; type names, amounts, counts all localized/formatted via existing catalog keys and Foundation formatters. RTL-safe: leading/trailing alignment only — the amount edge flips automatically.

## 7. Test impact

- **Unit (app tests):** row caption composition uses `group.breakdown.cell.caption` with count + localized type name; breakdown source excludes archived receipts (existing coverage stands); tapping a row sets the type filter and tapping it again clears it (new toggle behavior); rows render in `ExpenseType.allCases` order with absent types omitted.
- **UI tests:** trip with 5 types — assert all five `group.breakdown.*` identifiers exist and are hittable without any scroll gesture on the hero card; tapping `group.breakdown.food` filters the receipt list and marks the row selected; tapping again restores the unfiltered list.
- **String catalog:** `group.breakdown.item` removed, `group.breakdown.cell.caption` added — any catalog-completeness test updated accordingly.

## 8. Acceptance criteria

1. On a trip containing receipts of all five expense types, all five breakdown rows are fully visible in the hero card with no horizontal scrolling, clipping, or empty slots, at default Dynamic Type.
2. Rows render full-width in fixed `ExpenseType.allCases` order; layout and order are identical regardless of amounts — nothing reorders as spending changes.
3. Each row shows the type glyph in its type color, a "«count» «Type»" caption, and the exact per-type total right-aligned in tabular numerals; no money string is rounded, compacted, or truncated anywhere.
4. The hero total remains visually dominant: breakdown amounts render at footnote-class size/weight.
5. Tapping a row filters the receipt list to that type and tints the row with the type's soft fill; tapping the same row again clears the filter. A `.selection` haptic fires on each tap.
6. At `.accessibility1` and larger, caption and amount stack within the row; nothing scrolls horizontally and no text truncates.
7. VoiceOver reads each row as one button ("Food, 6 receipts, ₹2,335.00"), with the selected trait on the active filter row.
8. `design/ui-spec.html` (trip-detail screen) and `DESIGN.md` §4 describe these rows — no drift between docs and implementation.
9. All new/changed user-facing strings live in `Localizable.xcstrings` per the D4 table; `group.breakdown.item` no longer exists in catalog or code.
