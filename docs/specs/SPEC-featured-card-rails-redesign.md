# SPEC — Featured trip card: breakdown rail + thumbnail strip redesign

**Status:** proposed
**Owner screen:** Trips home featured card (`IntelliExpense/UI/GroupsViews.swift` — `FeaturedTripCard`, `BreakdownChips`, `BreakdownChipLabel`, `FeaturedReceiptThumbnailStrip`, `FeaturedReceiptThumbnail`)
**Supersedes:** SPEC-trips-rename-and-featured-home §D3 items 3–4 (breakdown chips and thumbnail strip on the featured card). Everything else in that spec stands.
**Docs this spec amends:** `DESIGN.md` §4 (featured-card component rule), `design/ui-spec.html` §2 (featured-card mock)

> **Amendment (2026-07-10):** `SPEC-folder-pinning-and-type-dot-removal.md`
> retires the compact-row type-dot strip. The featured chip rail now wraps onto
> additional leading-aligned lines at accessibility sizes instead of falling back
> to dots. The amended decisions and acceptance criteria below reflect that rule.

---

## 1. Problem

Field evidence: device screenshot of the shipped featured-first home with one trip ("Bengaluru Conference", ₹38,642.75, 12 receipts, 4 expense types, 3 most-recent receipts are photo-less taxi entries). Two visual defects, both in the bottom half of the card:

### P1 — The breakdown chip rail clips and demands scrolling

`BreakdownChips` is a horizontal `ScrollView` whose chips render `"%d · %@"` with the **full-precision** per-type amount (`ExpenseFormatters.compactTotals` is not actually compact — it joins full money strings). With 3+ types present the rail overflows the card width and the last capsule is **sliced mid-glyph at the card edge** ("✈ 1 ·" cut off). Compounding defects:

- **No affordance.** A capsule cut mid-content looks like a rendering bug, not a scroll hint. Nothing fades or peeks deliberately.
- **Wrong gesture context.** The card is one `NavigationLink` row; a horizontal scroll region nested inside a vertically scrolling `List` row is a gesture trap for a strip that is deliberately non-interactive here.
- **Inaccessible remainder.** The strip is `accessibilityHidden(true)` (correct — the card is one combined element), so content hidden behind the clip has no fallback; sighted users must discover an invisible scroll to read it.
- **Information overweight.** Full amounts per type duplicate what trip detail's interactive chips already show one tap away, and put four+ money strings on a card whose design contract is **one hero number** (DESIGN.md §4).

### P2 — Photo-less receipts render as three identical full-saturation tiles

`FeaturedReceiptThumbnail` falls back, when a receipt has no `thumbnailData`/`imageData`, to the receipt-row badge treatment: a 44 pt rounded tile **filled with the full-saturation type color** and a white SF Symbol. Taking `receipts.prefix(3)` regardless of photo presence means three recent manual taxi entries render as **three identical bright teal car tiles** — the loudest element on the card, louder than the hero total and the brand accent. Defects:

- **Hierarchy inversion.** Three saturated color blocks outshout the hero number; DESIGN.md's "one hero number per screen / everything else steps down" rule is violated in spirit.
- **Zero information.** Three identical icons say nothing the taxi chip doesn't already say once. The strip's purpose is *texture* — "these are real scanned receipts" — and an icon placeholder carries none of it.
- **Looks interactive.** Three equal rounded squares in a row read as segmented buttons, inside a card that is a single tap target.

(The same full-saturation tile is fine where it originated — `ReceiptRow`/Receipts-tab rows, one badge per row beside text, established list-badge pattern. The defect is only its repetition as *hero-adjacent decoration* on the featured card.)

### P3 — Two competing rails

Even when both rows behave, they are two adjacent horizontal rails of similar-height rounded elements (28 pt capsules over 44 pt tiles) with uniform 12 pt gaps — they read as clutter, not as a stats line plus an imagery strip.

## 2. Goals

- The featured card **never clips content and never scrolls horizontally** at default type sizes; every element on it is fully visible or deliberately absent.
- The card keeps exactly **one money value** (the hero total). Per-type amounts live where they already are: trip detail.
- The thumbnail strip shows **only real receipt photos** — its job is texture and proof, not iconography.
- Everything steps down from the hero number; no element on the card is more saturated than the brand accent.
- No new colors, no new strings, no layout restructuring of the card's identity/hero blocks; Dynamic Type only.

## Non-goals

- No change to the **trip-detail** `BreakdownChips` (interactive filter chips with full amounts — a full-width screen section where horizontal scrolling is an acceptable filter-strip convention). A scroll-edge fade there is a possible follow-up, out of scope.
- No change to `ReceiptRow` / Receipts-tab type badges (full-saturation tile stays the list-badge pattern).
- No charts, rings, or proportion bars (PRD §2 non-goal) — considered and rejected below.

## 3. Design decisions

### D1 — Featured chips become count-only and always fit (no ScrollView)

New rendering variant for the featured card only (e.g. a `showsAmounts: Bool` on `BreakdownChipLabel` or a sibling `FeaturedBreakdownRail` view):

- Each chip is **icon + count** (`Label { Text(count, format: .number) } icon: { Image(systemName: type.systemImageName) }`) — e.g. "🍴 1  🛏 2  ✈ 1  🚗 8". Same capsule treatment as today: `.caption.weight(.semibold)`, 10/6 pt padding, type color at 0.14 opacity fill, type-color foreground.
- The rail is a plain `HStack(spacing: 8)` — **no ScrollView**. Worst case is 5 types × (icon + 1–3 digits), which fits a 361 pt card at default Dynamic Type with room to spare.
- **Dynamic Type wrapping:** the icon + count chips flow onto additional leading-aligned lines when one row no longer fits. The rail never clips and never scrolls horizontally.
- Rail stays non-interactive and `accessibilityHidden(true)`; the card remains one combined VoiceOver element. Counts are already spoken via the meta line ("12 receipts | …"); per-type detail is one tap away.

**Why counts, not amounts.** The hero total owns money on this card (one-hero rule). Dropping amounts is what makes "always fits, never scrolls" *guaranteeable* rather than hoped-for — amounts have unbounded width (₹15,887.50). Unpinned compact rows stay deliberately quiet; pinned compact rows retain the labeled icon + count rail, the featured card gives that rail more breathing room, and trip detail adds interactive chips with **full amounts**.

**Considered and rejected:**
- *Compact-notation amounts* ("₹15.9K"): still unbounded (multi-currency types render two amounts per chip), rounds money on screen (invites "the numbers don't add up" confusion against the exact hero total), and keeps 4+ money strings on a one-hero card.
- *Top-2 chips + "+N more"*: hides categories arbitrarily; a "+2" chip is a dead-end tease on a non-interactive rail.
- *Proportion bar*: it's a chart (PRD §2 non-goal, DESIGN.md "no charts, rings, or dashboards").

### D2 — Thumbnail strip shows real photos only

`FeaturedTripCard` selects the **3 most recent receipts that have image data** (`thumbnailData` preferred, `imageData` fallback — same source order as today), instead of the 3 most recent receipts unconditionally:

- Receipts without photos are simply skipped; the strip shows 1–3 actual photo thumbnails.
- **Zero photo receipts → the strip is omitted entirely.** The card is identity + hero + chip rail — still substantial (this is also the existing rule for zero receipts).
- The full-saturation icon-placeholder branch of `FeaturedReceiptThumbnail` is **deleted** (it exists only for this card; `ReceiptRow` has its own badge). What remains is a plain photo tile: 44 pt `@ScaledMetric`, `scaledToFill`, continuous 9 pt corner radius, plus a **hairline stroke** (`.strokeBorder(.separator)` on the clip shape) so pale receipt paper doesn't bleed into light-mode backgrounds — this matches the ui-spec mock, which draws `border: 1px solid var(--hair)` on every thumbnail.

**Why.** The strip's value is *evidence texture* — glimpses of actual scanned paper (the mock's gradients simulate exactly that). A placeholder icon is category information, which is the chip rail's job; repeating it as saturated 44 pt tiles is triple-stated noise at maximum volume. Photos-only makes the strip self-justifying: it appears exactly when it has something real to show.

### D3 — Rhythm: stats read as one block, imagery as another

Keep the card's 12 pt block rhythm but group the rails: chip rail sits **8 pt** under the hero/meta block (it is part of the stats), thumbnail strip keeps **12 pt** separation (it is a different texture). Concretely: the card `VStack` stays `spacing: 12`; the hero + chip rail nest in an inner `VStack(spacing: 8)`. This kills the "two competing rails" reading (P3) — spacing declares the chips as the hero's caption line, and D1/D2 have already made the two rails visually distinct (small text capsules vs. photographic tiles).

## 4. Layout spec (featured card, top to bottom — deltas from SPEC-trips-rename-and-featured-home §4 in bold)

| Element | Value |
|---|---|
| Identity line | unchanged — icon tile 34 pt `@ScaledMetric`, name `.title3.weight(.semibold)` |
| Hero total + meta | unchanged — `.title.weight(.light)` `.monospacedDigit()`, meta `.footnote` `.secondary` |
| Breakdown rail | **icon + count capsules in a leading-aligned wrapping layout, no ScrollView; 8 pt below meta** |
| Thumbnail strip | **up to 3 most-recent receipts *with photos*, 44 pt `@ScaledMetric` tiles, continuous 9 pt radius, `.separator` hairline stroke; omitted when no photos; 12 pt below rail** |
| Colors | existing tokens only; **no full-saturation type-color fills anywhere on the card** (0.14/0.22-opacity capsule fills and photo content only) |

## 5. Accessibility & localization

- **New strings: none.** The count is a bare localized number (`Text(count, format: .number)`); chip rail and strip remain `accessibilityHidden` inside the card's combined element, exactly as today.
- VoiceOver output of the card is unchanged (name, totals, meta).
- Dynamic Type: `ViewThatFits` degrades chips → dots; thumbnails scale via existing `@ScaledMetric`. Verify at AX5: no horizontal clipping anywhere on the card.

## 6. Test impact

- **UI test (existing featured-card test):** unchanged — `groups.featured.card` identity, name, navigation.
- **New unit-level check (view-model-free, on the selection logic):** given receipts `[taxi(no photo), taxi(no photo), food(photo), hotel(photo)]` sorted by recency, the strip source is `[food, hotel]` — i.e. photo-less receipts are skipped, order preserved, max 3. Extract the selection into a small pure helper (e.g. `FeaturedThumbnailSelection.receipts(from:limit:)`) so it is testable without SwiftData images.
- **Manual verification matrix:** trip with (a) 4+ types & 0 photos → chip rail only, one line, no clipping; (b) 1 photo among recent receipts → single bordered thumbnail; (c) 3+ photos → 3 thumbnails; (d) AX5 → dots replace chips; light/dark.

## 7. Acceptance criteria

1. At default type sizes the featured card contains **no horizontally scrollable or clipped content**; every chip is fully visible.
2. The chip rail shows icon + count per expense type present, in the existing 0.14-opacity capsule treatment; **no per-type amounts on the card**; the hero total is the card's only money value.
3. The thumbnail strip renders **only actual receipt photos** (hairline-stroked, continuous-corner 44 pt tiles) and is absent when no recent receipt has a photo; the full-saturation icon-tile fallback no longer appears on the featured card (Receipts-tab and detail rows unchanged).
4. At AX text sizes the chip rail wraps onto additional leading-aligned lines; nothing clips or scrolls horizontally.
5. No new colors, strings, or string-catalog keys; no `colorScheme` branches; diff scope limited to `GroupsViews.swift`, tests, `DESIGN.md`, `design/ui-spec.html`.
6. ExpenseCore, app unit, and UI test suites pass; `make install-device` succeeds.

## 8. Documentation amendments (same commit)

- **DESIGN.md §4** featured-card rule gains: *"…non-interactive per-type chips (icon + count only — amounts live in trip detail), and up to three real photo thumbnails with a hairline stroke; photo-less receipts never render placeholder tiles on the featured card. The rail never scrolls; at accessibility sizes its chips wrap onto additional leading-aligned lines."*
- **design/ui-spec.html §2** featured-card mock: chips become count-only ("🍴 2 · 🛏 5" style, matching implementation), thumbnails keep their photo-like gradients + hairline border (already correct).

## 9. Out of scope (noted during this review)

- Trip-detail `BreakdownChips` can still clip mid-capsule behind its (interactive, conventional) horizontal scroll; a scroll-edge fade mask or `scrollClipDisabled` bleed is a candidate polish pass.
- `ExpenseFormatters.compactTotals` is misnamed (it renders full-precision money). After D1 its only remaining caller is trip detail; rename or make genuinely compact in a separate cleanup.
- `FeaturedReceiptThumbnail`'s deleted fallback hardcoded `.white` foreground — the deletion removes the last hardcoded white on this screen; no further action.
