---
# ============================================================
# DESIGN.md — Intelli-Expense (iOS 26, SwiftUI)
# Machine-readable design tokens. The markdown body below
# explains how and why to apply them. Agents: read both.
# Sources: design/ui-spec.html (canonical mockups) + PRD.md v1.1
# ============================================================
name: Intelli-Expense
platform: ios + macOS
minimum_os: "26.0"
ui_framework: SwiftUI
design_language: "Apple Liquid Glass (iOS 26) — content-first, system components"

colors:
  # Every custom token is a light/dark PAIR — one asset-catalog color set
  # (Any + Dark appearances) per token. Code references the named color only.
  brand:
    ledger_green:      { light: "#1E7A55", dark: "#34C08A" }          # Save, selection, active tab, links. The only brand accent.
    ledger_green_soft: { light: "#E7F2ED", dark: "rgba(52,192,138,0.16)" }  # Selected-chip fill, onboarding icon tiles, verdict surfaces
  category_palette:                 # Category identity hues. Symbols belong to categories, not hues.
    orange: { light: "#FF9500", dark: "#FF9F0A", system: systemOrange }
    amber:  { light: "#B26B00", dark: "#E5A421", system: systemYellow }
    brown:  { light: "#A2845E", dark: "#AC8E68", system: systemBrown }
    mint:   { light: "#0E9F8E", dark: "#3BD6C3", system: systemMint }
    teal:   { light: "#2AA8BD", dark: "#3FC2D9", system: systemTeal }
    cyan:   { light: "#1E96D1", dark: "#4CC2FF", system: systemCyan }
    blue:   { light: "#007AFF", dark: "#0A84FF", system: systemBlue }
    indigo: { light: "#5856D6", dark: "#5E5CE6", system: systemIndigo }
    purple: { light: "#AF52DE", dark: "#BF5AF2", system: systemPurple }
    plum:   { light: "#96419B", dark: "#D678DB", system: systemPurple }
    slate:  { light: "#5D6B85", dark: "#93A2C0", system: systemBlue }
    gray:   { light: "#8E8E93", dark: "#8E8E93", system: systemGray }  # systemGray: same in both
  semantic:                         # Always the SwiftUI/UIKit semantic color, never the hex — these adapt to dark automatically
    background: systemGroupedBackground
    surface: secondarySystemGroupedBackground
    label: label
    secondary_label: secondaryLabel
    separator: separator
    fill: systemFill
  attention:                        # Uncertainty/duplicate treatments — warm, never red
    field_edge_tint: { light: "#FF9500", dark: "#FF9F0A" }   # 2.5pt leading inset edge on uncertain fields
    duplicate_bg:    { light: "#FFF8EC", dark: "#2B2013" }
    duplicate_text:  { light: "#8A4D05", dark: "#F0B35E" }
  dark_mode:
    strategy: "Token problem, not layout problem — nothing moves or reflows in dark. Semantic colors adapt free; the sixteen custom pairs above ship as asset-catalog color sets. No raw hex and no colorScheme branches in feature code."
    receipt_images: "Never dimmed, tinted, or inverted — the paper renders identically in both appearances"

symbols:
  source: "SF Symbols first. Every built-in category has a validated system symbol name plus a safe fallback."
  fallback_builtin: "tag.fill"
  custom_category_default: "tag.fill"
  custom_symbols: "Allowed only for high-value gaps after product usage proves need; must match SF Symbols optical weight, simplicity, alignment, and accessibility labeling."
  restricted_use: "Never use SF Symbols or confusingly similar custom symbols in the app icon, logo, or trademark-like surfaces."

typography:
  family: "SF Pro (system default) — no custom fonts"
  rule: "Dynamic Type text styles only; never fixed point sizes in code"
  roles:                            # Exactly five roles. Do not add more.
    large_title: { style: largeTitle, weight: bold, size_ref: 34 }
    hero_money:  { style: title1-adjacent, weight: light, size_ref: 31, numerals: tabular }
    body:        { style: body/subheadline, weight: regular–medium, size_ref: "17/15" }
    footnote:    { style: footnote, weight: regular, size_ref: 13 }
    caption_label: { style: caption, weight: semibold, size_ref: 11, transform: uppercase }
  money: "Always tabular numerals (monospacedDigit); hero money in LIGHT weight"

spacing:
  grid: 4                           # base-4/8 grid
  content_margin: 16
  card_padding: "12–16"
  section_gap: 24

shape:
  rule: "System-provided radii; custom cards use concentric corners relative to container"
  never: "Hand-tuned per-view corner radii"

elevation:
  glass_budget:                     # Liquid Glass is rationed (Apple guidance)
    system_owned: "Tab bar, toolbars, sheets, menus — always system material, no custom bar backgrounds"
    custom_allowed: ["capture accessory bar", "floating Save bar"]
    excluded: "WidgetKit widgets and system controls render outside the app in their own containers — not counted in this in-app budget"
  shadows: "System defaults only; no decorative drop shadows"

widgets:                            # WidgetKit surfaces. App-rendered content wears the app; system-chromed surfaces don't.
  quick_capture:                    # Home Screen widget — see SPEC-quick-capture-widget.md
    families: [systemSmall, systemMedium]
    actions: [scan, photo, file, manual]     # each a SwiftUI Link → intelliexpense://capture?kind=<action>
    layout: "medium = neutral hero Scan panel (small Ledger Green camera chip + label) + Photo/File/Manual overflow list with soft action-hue glyph chips; small = 2×2 grid; both offer all four"
    accent: "Widget-scoped exception to the single-accent rule: Scan is the only saturated fill (Ledger Green chip/tile with white glyph); Photo, File, and Manual use soft-tint chips with matching blue, indigo, and amber-orange glyphs. No large hue flood, no saturated secondary fills, no white text on color."
    action_hues: { photo: CapturePhoto, file: CaptureFile, manual: CaptureManual } # widget-scoped asset tokens; borrowed values, not category semantics
    container: ".containerBackground(for: .widget) — calm system surface; color lives on chips, never floods the container; never a gradient"
    data: "none — action launcher only, no totals/counts/thumbnails (PRD dashboard non-goal)"
    glyphs: { scan: camera.viewfinder, photo: photo, file: doc, manual: square.and.pencil }  # doc not folder — folder is the container concept
  system_controls:                  # Control Center / Lock Screen / Action button / Spotlight / Siri — see SPEC-scan-receipt-everywhere.md
    rendering: "system-chromed — system tint/rendering only, no brand color or custom background (document.viewfinder)"

capture_sheet:
  entry_points: ["accessory More", "toolbar +"]
  actions: [scan, photo, file, manual]
  layout: "medium detent first, large available; title + destination caption; LedgerGreenSoft hero Scan panel with small saturated Ledger Green camera chip; quiet Photo/File/Manual rows with one-line captions"
  accent: "In-app one-green family: saturated fill only on the small Scan chip; rows use LedgerGreenSoft tiles with Ledger Green glyphs. The Home Screen widget action-hue exception does not apply inside the app."
  chrome: "system sheet material, not custom glass; does not count against the in-app glass budget"
  tip: "TipKit popover anchored to More after first successful scanned-receipt save; opening the sheet invalidates it"

haptics:
  save_success: .success
  chip_selection: .selection
  duplicate_notice: .warning        # the only .warning in the app

motion:
  processing: "Scan-line sweep over the captured receipt image (~2.4s ease-in-out loop)"
  reduced_motion: "Scan line becomes static shimmer; stage text carries progress alone"

accessibility:
  dynamic_type: required
  dark_mode: "Required (acceptance #10). Semantic colors adapt free; custom tokens carry Dark variants via asset catalog. Re-verify contrast in dark, incl. Increased Contrast + Reduce Transparency"
  voiceover: "Every control labeled; capture→review→save completable end-to-end"
  rtl: "Leading/trailing only, never left/right"
---

# Intelli-Expense — Design System

**Who reads this:** any agent or engineer generating UI for this app. `PRD.md` defines
*what* to build; this file defines *how it must look and feel*. The screen-by-screen
canonical mockups live in [design/ui-spec.html](design/ui-spec.html) — when in doubt,
that file wins on layout, this file wins on tokens and rules.

---

## 1. Visual Theme & Atmosphere

Calm, native, finance-adjacent. The bar is Flighty's Apple Design Award philosophy:
*"so well that it feels almost boringly obvious."* This is not a dashboard and not a
fintech brand exercise — it is a quiet iOS 26 utility that borrows the two artifacts
its users already trust:

- **The paper receipt** — the scan is always visible, always primary. Thumbnails of
  actual paper in lists, the full image anchored at the top of review and detail.
- **The finance ledger** — tabular numerals, right-aligned amounts, per-currency
  subtotals, date-grouped rows. Screens read like the expense report the user will
  eventually submit.

Density is standard iOS inset-grouped lists. Chrome is glass and stays out of the way;
content scrolls under it. Nothing needs explaining because it looks like what it replaces.

## 2. Color Palette & Roles

| Token | Light | Dark | Role |
|---|---|---|---|
| Ledger Green | `#1E7A55` | `#34C08A` | The single brand accent: Save button, selected chips, active tab, links. Money-adjacent and deliberately *not* default-blue. |
| Ledger Green Soft | `#E7F2ED` | `rgba(52,192,138,.16)` | Fill behind selected choice chips and onboarding icon tiles. |
| Category Orange | `#FF9500` | `#FF9F0A` | Category identity hue (systemOrange family). |
| Category Amber | `#B26B00` | `#E5A421` | Category identity hue for gold/yellow family items. |
| Category Brown | `#A2845E` | `#AC8E68` | Category identity hue for physical goods/materials. |
| Category Mint | `#0E9F8E` | `#3BD6C3` | Category identity hue for health/service-adjacent items. |
| Category Teal | `#2AA8BD` | `#3FC2D9` | Category identity hue for transport/tooling family items. |
| Category Cyan | `#1E96D1` | `#4CC2FF` | Category identity hue for parking, tech, and delivery family items. |
| Category Blue | `#007AFF` | `#0A84FF` | Category identity hue for travel/water/equipment family items. |
| Category Indigo | `#5856D6` | `#5E5CE6` | Category identity hue for lodging, venues, and protection family items. |
| Category Purple | `#AF52DE` | `#BF5AF2` | Category identity hue for administrative/actionable service items. |
| Category Plum | `#96419B` | `#D678DB` | Category identity hue; must read purple-side, never pink/red. |
| Category Slate | `#5D6B85` | `#93A2C0` | Category identity hue for calm paperwork/registration items. |
| Category Gray | `#8E8E93` | `#8E8E93` | `Other` and unresolved categories only (systemGray — same in both appearances). |
| Attention edge | `#FF9500` | `#FF9F0A` | 2.5pt warm leading edge on uncertain fields. |
| Duplicate banner | `#FFF8EC` / `#8A4D05` | `#2B2013` / `#F0B35E` | Non-blocking duplicate notice surface / text. |
| Everything else | Semantic system colors | (adapt automatically) | `systemGroupedBackground`, `label`, `secondaryLabel`, `separator`, `systemFill` — never raw hex in code. |

**Hard rules:**
- Category color means category identity — used identically in review chips,
  list badges, breakdown chips, and glyph tiles. Each built-in category owns one
  permanent hue from the 12-hue category palette, and no profile repeats a hue in
  its default + suggested set. Users never pick colors; there is no color picker.
- Folder profile identity uses the same small-tile language: preset profiles own a
  permanent SF Symbol + palette hue, while the Custom profile keeps the existing
  Ledger Green `folder.fill` tile.
- Category glyphs are SF Symbols first. Each built-in category carries a curated
  `symbolName`; the glyph creates recognition, while the label carries accounting
  precision. Reuse strong generic symbols for related categories instead of adding
  weak custom artwork.
- **No red.** Uncertainty and duplicates use warm amber treatments (attention edge,
  duplicate banner). Red walls are banned; the app never alarms — in either appearance.
- **Home Screen Quick Capture is the only action-hue exception.** In-app UI remains
  single-accent: Ledger Green is the only brand accent for app chrome, sheets, rows,
  controls, and selection. The app-rendered Quick Capture Home Screen widget may use
  three fixed widget-scoped action hues (Photo blue, File indigo, Manual amber-orange)
  as soft chips only, because it competes on the wallpaper without app chrome or
  surrounding context. This exception does not apply to the Add receipt sheet, system
  controls, future widgets, or category semantics.
- Semantic colors give dark mode and contrast for free — hardcoding a surface or
  label color is a defect.

### Dark mode

Dark mode is a **token problem, not a layout problem** — nothing moves, resizes, or
reflows. If a screen needs a different layout in dark, the light design was wrong.

- **Semantic first.** Backgrounds, labels, separators, fills, and all system glass
  come from semantic colors and adapt automatically: true-black grouped canvas,
  `#1C1C1E` cards, elevation read through surface rather than shadow.
- **Sixteen custom pairs, defined once.** Each token above is one asset-catalog color
  set with Any + Dark appearances (`LedgerGreen`, `CategoryOrange`, `CategorySlate`, …). Feature code
  references the named color — `@Environment(\.colorScheme)` branches and raw hex
  are both defects.
- **AccentColor is an alias, not a new token.** The asset catalog's `AccentColor`
  must byte-match `LedgerGreen`; it exists only so system controls, focus rings,
  and macOS list selection inherit the brand accent.
- **Custom colors brighten the way Apple's do:** deep pigment on white, luminous on
  black. Identity never changes — same symbol, same meaning.
- **The receipt image is never dimmed, tinted, or inverted.** The paper is the
  content and the trust anchor; it renders identically in both appearances. (The
  processing screen was designed dark-first for exactly this reason.)
- **Re-verify contrast in dark** — amber treatments on `#1C1C1E`, white on dark
  Ledger Green — and test with Increased Contrast and Reduce Transparency (which
  replaces glass with solid surfaces). Acceptance criterion #10 makes dark mode a
  shipping requirement, not a nice-to-have.

Dark reference mockups: the "Dark mode" section of
[design/ui-spec.html](design/ui-spec.html) shows Folders home and Review & Confirm
in dark with the full token pair table.

## 3. Typography

SF Pro only, via Dynamic Type text styles — **never fixed point sizes in code**.
Exactly five roles (reference sizes at default content size):

| Role | Ref size / weight | Used for |
|---|---|---|
| Large title | 34 bold | Tab root titles (Folders, Receipts, Settings) |
| Hero money | ~31 **light**, tabular | The one big number per screen (folder total, extracted total, manual-entry amount) |
| Body | 17/15 regular–medium | Row titles, field values |
| Footnote | 13 | Row subtitles, provenance lines, privacy notes |
| Caption label | 11 semibold UPPERCASE | Form field labels, section kickers |

Hierarchy is expressed through **weight and color, not size**. Money is always
tabular-numeral so amounts align down every list; the hero figure is *light* weight —
elegant, not shouty.

## 4. Components

- **Cards / lists:** iOS 26 inset-grouped `List` rows on `systemGroupedBackground`.
  Row anatomy: thumbnail (or type glyph for photo-less manual entries) → title +
  subtitle in descending weight → right-aligned tabular amount → chevron.
- **Agent-entry confirmation cards:** shared iPhone/Mac card for structured agent
  drafts only. It uses the same thumbnail, ledger typography, tabular amount, type
  names, payment names, and Ledger Green primary action as existing receipt rows.
  Placement is pinned above the featured card on Folders home and above the Mac
  content-column receipt list. Body tap reviews details; only the explicit Confirm
  button saves. No confirm-all action in v1.
- **Review image header:** image-backed review starts with the real receipt image,
  page count, and zoom affordance. Photo-less manual entry omits this header
  entirely and starts at the Fields section; never substitute a manual placeholder
  card for missing paper.
- **Review date editor:** the date row opens a system sheet with the native
  graphical calendar. Calendar changes are staged: Cancel or swipe dismissal
  preserves the receipt date, while Done commits it. Do not use the compact
  date picker's implicit outside-tap dismissal for this review flow.
- **Chips:** pill filters (composable, each removable with ✕); selected = Ledger Green
  fill, white text. Choice chips (ambiguity) are bordered rectangles with a tiny
  provenance caption ("bottom line SUMME") and a dashed **Edit** third option.
- **Create Folder category composer:** the New Folder sheet stays an inset-grouped
  form. Details come first, then Categories: Selected defaults as compact removable
  pills/rows, Suggestions directly below as tap-to-add pills/rows, Browse Existing
  Categories as the escape hatch into the built-in catalog, then Add Custom Category.
  Tap add/remove is the primary path; drag/long-press reorder exists only inside
  Selected. `Other` is locked at the end. At large Dynamic Type, the composer becomes
  a vertical list with explicit add/remove/reorder controls.
- **Featured folder card:** one hero total, metadata, non-interactive per-type chips
  (icon + count only — amounts live in folder detail), and up to three real photo
  thumbnails with a hairline stroke. Photo-less receipts never render placeholder
  tiles on the featured card. The rail never scrolls; at accessibility sizes its
  chips wrap onto additional leading-aligned lines.
- **Folder pinning:** active folders sort pinned first, most-recently pinned first
  within that band, then by activity. The top folder remains the featured card.
  Long-press on iPhone or right-click on Mac exposes Pin/Unpin; a quiet secondary
  `pin.fill` marks pinned rows and VoiceOver announces the state. On iPhone, every
  pinned compact row retains the labeled icon-and-count category rail; unpinned
  compact rows stay quiet and dot-free. Pin/unpin reordering uses a short ease-in/out
  transition. Pinning never changes capture's activity-based default destination,
  and archiving clears it.
- **Folder-detail breakdown rows:** one slim full-width row per category inside
  the hero card, in fixed category order — small category-colored glyph tile, "6 Food"
  count caption, amount right-aligned in tabular footnote weight, echoing the
  receipt-row anatomy below it. Rows stack vertically, never scroll horizontally,
  and are symmetric for any type count (1–5) — no grids, no orphan cells, nothing
  reorders as spending changes. Rows are quiet neutral fills
  (`quaternarySystemFill`-class), tap to toggle that type's filter; the active row
  fills with its category hue's soft tint. At accessibility sizes caption and amount
  stack within the row. Amounts here step down (footnote weight) — the hero total
  stays the screen's one hero number.
- **Category selector:** folder-scoped category tiles (symbol in colored square +
  caption); selected tile tints background and rings in that category hue.
  Up to five categories use equal tiles, six to eight use a two-row adaptive grid,
  and accessibility sizes become a vertical list. No horizontal scrolling for the
  primary selector.
- **Category symbol catalog:** built-in category metadata includes
  `id`, localized display key, `symbolName`, fallback symbol, and category hue.
  Validate system symbols against the minimum OS. Custom folder categories default
  to `tag.fill`; a later picker must be curated, not the full SF Symbols library.
- **Segmented control:** system style, for Card/Cash only.
- **Currency picker:** searchable inset-grouped list, Suggested section pinned on
  top, rows show localized name + ISO code + symbol (Foundation-localized, never
  hardcoded), single-accent checkmark selection, Dynamic Type only. Currency is
  always picked, never typed.
- **Capture accessory:** `tabViewBottomAccessory` glass bar — camera circle in Ledger
  Green, "Scan Receipt" label, context subtitle naming the destination folder, and a
  quiet More trigger with visible "More" caption in expanded placement. Tapping the
  bar scans immediately; tapping More opens the Add receipt sheet. Long-press keeps
  direct Photo / File / Manual shortcuts. Hidden on Settings.
- **Add receipt sheet:** system sheet, not custom glass. Medium detent first with
  large available: title, destination caption, one LedgerGreenSoft hero Scan panel
  with a small saturated Ledger Green camera chip, then quiet Photo / File / Manual
  rows with one-line captions. Toolbar + and accessory More use the same sheet.
- **System-surface scan control:** Control Center, Lock Screen slot, Action button,
  Spotlight, Siri, and Shortcuts all expose the same "Scan Receipt" doorway. Use
  SF Symbol `document.viewfinder`, system tint/rendering only, no custom backgrounds
  or Ledger Green overrides; system surfaces own their glass and color. This
  system-tint rule governs *system-chromed* surfaces only — controls and Spotlight/Siri
  tiles that iOS draws and tints. The Quick Capture widget below is *app-rendered*
  content and instead follows the app's tokens (brand allowed, rationed).
- **Quick Capture widget (Home Screen):** a WidgetKit widget exposing the four capture
  actions — **Scan · Photo · File · Manual** — as `Link`s into
  `intelliexpense://capture?kind=…` (bare `capture` still means Scan). Because a widget
  is drawn by the app, it wears the app's hierarchy while using the one scoped
  action-hue exception above: **Scan is the only saturated fill** (Ledger Green camera
  chip in medium, filled Ledger Green tile in small, both with a white glyph), while
  Photo, File, and Manual are soft-tint chips with matching saturated glyphs
  (blue, indigo, and amber-orange respectively; Manual uses the darker amber-orange
  light glyph value for contrast on its soft tint). Saturation carries rank; hue carries
  action identity. **Medium** uses a neutral semantic-fill Scan hero panel so no
  green slab exists, with Photo/File/Manual as a quiet overflow list beside it;
  **small** is a 2×2 grid with Scan anchoring the top-leading cell; both offer all
  four actions. The container is a calm system surface via
  `.containerBackground(for: .widget)` — color lives on chips and never floods the
  container, never a gradient. The action hues copy validated palette values into
  widget-scoped assets named for actions, not categories; category color semantics
  remain untouched. No white *text* on colored fills, no saturated secondary fills,
  and no data on the widget (no totals, counts, or thumbnails): it is a launcher,
  not a dashboard. Glyphs `camera.viewfinder` / `photo` / `doc` /
  `square.and.pencil` (`doc`, not `folder`, because folder is the container concept). Adds no App
  Intent and no App Group — it is `Link`s into the existing route. Canonical mockup:
  `ui-spec.html` §Quick Capture; full layout/routing spec:
  `SPEC-quick-capture-widget.md`; color treatment:
  `SPEC-quick-capture-widget-action-hues.md`.
- **Save bar:** `safeAreaBar` glass with one full-width Ledger Green button only.
  Discard lives in the top-leading X and confirms only when dirty. The bar yields
  to the keyboard; Done in the keyboard toolbar dismisses it. Incomplete Save
  remains tappable at 60% opacity and shows the missing-field reason inline when
  tapped.
- **Banners:** duplicate warning is a non-blocking amber banner with a "View" peek —
  never a modal.
- **Empty states:** `ContentUnavailableView`-shaped — icon tile, one-line title,
  short guidance, one primary action, one escape hatch. Never a blank list.
- **Provenance:** "Entered by agent" is a quiet footnote/secondary-label line in
  confirmation cards and receipt detail. It is not a badge, warning, color state, or
  trust score. The extraction disclosure continues to hold the audit payload.

## 5. Layout Principles

- Base-4/8 grid: 16pt content margins, 12–16pt card padding, 24pt between sections.
- **One hero number per screen.** Everything else steps down through weight and
  color, not size.
- Standard navigation: three tabs, large titles at roots, inline titles when pushed.
  Search lives in `.searchable` on the Receipts tab.
- Lists group by what users think in: active folders pinned first and otherwise by
  recency, with the top folder promoted to one featured card; folder detail by receipt *issue* date
  ("Saturday, June 14"), Receipts tab by month.
- Archiving is the reflex gesture for putting content away and is always safe
  (accent-tinted, full-swipe, no dialog); a receipt is effectively archived when
  it or its folder is archived; destructive delete never rides a reflex swipe on
  active content — it lives only behind archived surfaces or explicit editor
  actions, styled with the system destructive role, never app-palette red.
- RTL-safe by construction: leading/trailing only, SF Symbols, standard stacks.

## 6. Depth, Elevation & Glass

Liquid Glass exists to bring focus to content, so it is **rationed**:

- System-owned glass only for bars, sheets, menus — no custom bar backgrounds,
  scroll-edge effects instead of opaque headers, tab bar minimizes on scroll.
- Exactly **two custom glass elements** in the whole app: the capture accessory bar
  and the floating Save bar. Adding a third requires a design decision, not a whim.
  WidgetKit widgets and system controls do not count against this budget — they render
  outside the app in their own system containers (`.containerBackground(for: .widget)`,
  system control chrome), not as in-app custom glass.
- One-time reveals are allowed only for onboarding: staggered fade-and-rise, ≤1s
  total, settle and stop; Reduce Motion replaces all movement with opacity-only
  fades; never use this pattern on recurring screens.
- Sheets are system: inset from edges, grabber on top, content peeking beneath.
- No decorative shadows or gradients anywhere.

## 7. Motion & Haptics

- **Processing is the signature moment:** a scan-line sweeps over the *actual captured
  receipt* (never a spinner) with truthful stage hints ("Reading text…" →
  "Understanding receipt…") and an always-present Cancel. Respect
  `accessibilityReduceMotion` — static shimmer, text carries the story.
- Haptics close loops: `.success` on save, `.selection` on chip picks, `.warning`
  only for the duplicate notice. Nothing else vibrates.
- Save success also shows the receipt visibly landing in its folder row.

## 8. Voice & Uncertainty UX (the product's soul)

- **Uncertainty is a choice, never an error.** When extraction is torn, show at most
  two tappable value chips + Edit, with a calm "which is correct?" line. More than ~3
  ambiguous fields ⇒ fall back to empty editable fields.
- Attention treatment = 2.5pt warm leading edge tint + label. Confirmed fields earn
  small green checkmarks — the screen visibly completes as you resolve it.
- Degradation is quiet: model-not-ready gets one secondary-label line ("Smart
  extraction is getting ready"), never a gate, never the word "error".
- Copy discipline: value in one line, every button says exactly what it does
  ("Open Settings", not "Learn more"). All strings live in the String Catalog.
- Agent-entry copy is factual and calm: "Needs confirmation", "Entered by agent",
  "Confirm", and "Review details…". The UI never explains the bridge protocol to
  end users; it simply offers a complete record to accept or edit.

## 9. Do's and Don'ts

**Do**
- Use semantic system colors and Dynamic Type styles exclusively; custom tokens only
  via their named asset-catalog color sets (each carries its Dark variant).
- Check every new screen in both appearances before calling it done.
- Keep money in `Decimal`, format with locale-aware `FormatStyle`, render tabular.
- Show per-currency totals side by side ("€1,284.50 + US$62.00") — primary large,
  secondary small in `secondaryLabel`.
- Design every state: empty, loading, degraded, offline, denied-permission.
- Reuse the review form for post-save editing — one component, one muscle memory.
- Reserve the review image header for image-backed review; photo-less manual entry
  begins directly at the form.

**Don't**
- ❌ No charts, rings, or dashboards (PRD non-goal) — breakdown chips only.
- ❌ No red error walls, no blocking modals for warnings.
- ❌ No custom fonts, no gradients, no emoji in UI, no "AI-slop" layouts.
- ❌ No custom tab/nav bar backgrounds; never fake glass with blur views.
- ❌ Never sum across currencies; never hardcode currency symbols.
- ❌ No in-app language picker; no fixed font sizes; no left/right (use leading/trailing).
- ❌ No `colorScheme` branches in feature code, no dimming/inverting receipt images
  in dark mode, no dark-only layout changes.

## 10. Native Mac Adaptation

The Mac app is the same product, not a second design system. It uses the shared
models, formatters, review form behavior, Ledger Green accent, folder pin state, export
language, and receipt-image treatment from the iPhone app.

- Structure: use `NavigationSplitView` with a system `DisclosureGroup` for the Folders
  hierarchy and plain Unfiled/Archived destinations in the sidebar, receipt date sections
  in the content column, and the selected receipt or review form in the detail column.
  The detail column owns the single hero object.
- Detail: selected receipts use a native Mac pane with the receipt image beside grouped fields.
  The form column starts with one light, tabular hero
  amount; the image column never dims or tints the paper. Photo-less receipts show
  the expense-type glyph tile in the image column, not an in-form Add Photo row.
- Density: Mac sidebar and receipt-list rows adopt platform-compact metrics while
  preserving the ledger rules — right-aligned tabular money, primary text first,
  secondary metadata quiet. Sidebar folders show name + natural-width primary total
  on one line; the name owns layout priority and truncates only after the money column
  has surrendered any reserved slack. Date range and full multi-currency totals live
  in help text.
- Capture: Mac is import-first. Toolbar, menu command, keyboard shortcut, file
  importer, and drag-and-drop all feed the same headless ingestion path before
  opening review. Do not couple ingestion to the Mac view hierarchy.
- Agent entries: the Mac watcher owns the folder protocol and feeds structured
  entries through the shared confirmation card or confirmed-save path. The card is
  the same component on iPhone and Mac; only placement adapts to the split view.
- Review: preserve the existing anchored review contract, adapted to a wider
  split layout with receipt preview beside the editable form. Confirmation still
  requires an explicit Save; nothing autosaves after extraction.
- Modals: shared form behavior stays shared, but Mac presentation is explicit.
  New/Edit Folder and Add Custom Category use grouped forms with the system
  form presentation role; searchable category and reassignment catalogs use the
  page presentation role with a bounded, scrollable viewport. Do not rely on a
  flexible `List` to give an automatic sheet intrinsic height, and do not force
  every modal into one fixed rectangle. System chrome, material, focus rings,
  dimming, default/cancel actions, and sheet curvature remain system-owned.
- Controls: New Folder lives in the standard bottom-aligned sidebar bar and remains in
  the File menu with Command-N; the folder list contains destinations only. Use standard
  toolbar/menu commands for Import Receipts and Export Folder. Receipt object commands live in the Mac detail toolbar and row context
  menus: Add Photo for photo-less receipts, Archive/Restore as the safe accent
  action, and Delete only behind an explicit destructive menu/confirmation. Do not
  bring the iPhone capture accessory, tab bar, or in-form action-button sections to
  Mac.
- Paging: multi-page receipt images on Mac use previous/next pager controls and a
  page indicator in the image column. The iPhone page-style `TabView` remains an
  iPhone-only idiom.
- Sync: Mac and iPhone read/write the same SwiftData + private CloudKit schema.
  Mac-only state belongs in app storage or transient view state, not the mirrored
  data model.
- Desktop editing: the Mac model context uses the window undo manager. Field edits,
  archive/restore, delete, folder reassignment, and batch operations participate in
  system Undo/Redo; import, extraction, export, and agent confirmation do not.
- Selection and search: the receipt column is a multi-select system `List` with a
  standard searchable field scoped to the current sidebar destination. Multiple
  receipts replace the detail with one count hero and per-currency totals; Select All
  selects only visible filtered rows, and hidden rows are pruned from selection.
- Direct manipulation: Space opens collection Quick Look, receipt rows drag onto
  folder/Unfiled/Archived source-list rows, and receipt pages plus prepared export zips
  drag out as files. Continuity Camera uses the system Import from iPhone commands and
  enters the same headless ingestion path as file import.
- Keyboard and menus: Archive/Delete, Move to Folder, Quick Look, Find, Select All,
  inline Rename, Show Archived, and Zoom are advertised in the menu bar with their
  standard shortcuts. Remove menu groups the app cannot use; keep system Undo/Redo.
- Zoom and restoration: View-menu Zoom In/Out/Actual Size persist a Mac-only semantic
  font-scale step and the receipt viewer temporarily owns those same commands for image
  magnification. Apple documents that `dynamicTypeSize` does not change text size on
  macOS, so the Mac implementation uses macOS 26 `Font.scaled(by:)` over semantic text
  styles rather than a no-op Dynamic Type environment override. Window restoration stays
  system-owned; sidebar selection and Folders disclosure state use lightweight per-scene
  restoration with graceful fallback when a folder no longer exists or disclosure state
  is missing or invalid.
- Attention: the Dock badge is exactly the number of structured agent drafts awaiting
  confirmation and clears when that count reaches zero. It never counts auto-confirmed
  entries or raw capture drafts.
- Never custom-paint list selection or rebuild list panes from scroll views on macOS.
  System `List` owns active/inactive window subduing, focus-emphasized selection,
  keyboard traversal, and context-menu focus rings.
- Folder profile glyph tiles intentionally retain their category tint on macOS 26 as
  content identity shared with iPhone; Unfiled and Archived remain monochrome system
  destination symbols.

## 11. Agent Prompt Guide

Quick reference when generating any screen:

- Accent = **Ledger Green** (`#1E7A55` light / `#34C08A` dark) for tint, Save,
  selection. `AccentColor` aliases Ledger Green for system-owned tint/selection.
  Category palette = orange, amber, brown, mint, teal, cyan, blue, indigo,
  purple, plum, slate, gray. Each built-in category owns one permanent hue; no
  profile repeats a hue in its default + suggested set. Category color + SF
  Symbol always travel together; every custom color is a light/dark asset-catalog
  pair, referenced by name.
- Folder profile identity = preset profile SF Symbol + palette hue. Custom and
  unknown profiles use `folder.fill` in Ledger Green.
- One light-weight hero number per screen; all other text steps down by weight.
- Inset-grouped lists, 16pt margins, system radii, glass only where §6 allows.
- Uncertain field → two chips + Edit + warm edge tint. Confirmed → green check.
- Canonical layouts, per screen, are in `design/ui-spec.html` (chosen options:
  capture accessory bar = Option A; review = Option A anchored form with ambiguity
  auto-scroll). Match them.

**Example prompt:** *"Build the Folder Detail screen per DESIGN.md: hero total
€1,284.50 in light tabular type with secondary currency small, per-type breakdown
rows with right-aligned amounts, filter chip row, receipts in date sections, export in the toolbar,
capture accessory naming this folder."*
