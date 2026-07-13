# SPEC — Quick Capture widget action hues (one brand hit, three quiet accent chips)

**Status:** proposed
**Owner screens/targets:**
- `IntelliExpenseControls/QuickCaptureWidget.swift` — the small (2×2 grid) and medium (hero + overflow list) families; the `WidgetPalette`, `HeroScanTile`, `OverflowRow`, and `GridTile` components.
- `IntelliExpenseControls/WidgetAssets.xcassets` — `LedgerGreenSoft.colorset` is removed from the extension; six new action-hue colorsets are added (see D3/D5).
- `project.yml` — no target changes; asset-catalog folder reference unchanged. No new Swift files, so no `xcodegen generate` needed.

**Docs this spec amends:**
- `DESIGN.md` frontmatter — `widgets.quick_capture.layout` and `widgets.quick_capture.accent` are rewritten (the "no second hue / no gray" wording is replaced by the action-hue exception, D2), and the `capture_sheet.accent` line that couples the sheet to the widget is decoupled (D6).
- `DESIGN.md` body — the "Quick Capture widget (Home Screen)" component entry (§4 Components) is rewritten, and the single-accent rule ("Ledger Green … the only brand accent") gains an explicit, narrowly-scoped Home Screen widget exception with rationale (D2) so the rule stays true rather than silently violated.
- `design/ui-spec.html` §`#capture-widget` — mockup CSS updated (light + dark, medium + small) to the new treatment; the lede's "three quiet neutral tiles" sentence is updated to "three quiet tinted chips."
- `docs/specs/SPEC-quick-capture-widget.md` — remains the layout/routing authority; this spec supersedes only its color treatment (its decisions on `Link`s, families, `CaptureKind`, deep links, and Dynamic Type fallback are untouched).

**Related specs:** `SPEC-quick-capture-widget.md` (layout, routing — unchanged), `SPEC-per-category-distinct-colors.md` (category palette = *category identity*; this spec borrows three of its validated hue values for *action* chips on one surface without touching category semantics — see D3).

---

## 1. Problem

On a real Home Screen (owner screenshots, 2026-07-09, dark wallpaper) the widget reads as a monochrome green block, not a designed launcher:

- **Small family:** four tiles, all green — one saturated `LedgerGreen` (Scan) and three `LedgerGreenSoft` tiles with `LedgerGreen` glyphs. At 2×2 scale the saturated/soft distinction collapses: everything reads "green tile," so the accent stops marking Scan as primary, and the four actions are indistinguishable at a glance — you must read the labels to tell Photo from File.
- **Medium family:** the `LedgerGreenSoft` hero panel is the widget's largest surface. In dark mode `LedgerGreenSoft` is translucent green (`rgba(52,192,138,0.16)`) over the container, rendering as a large murky green slab — exactly the "large green flood" the existing rule (`DESIGN.md` `widgets.quick_capture.accent`) says to avoid. The rule's letter ("everything else … is LedgerGreenSoft") defeats its intent at widget scale.
- **Contrast:** green glyph on green-tinted tile is a tone-on-tone pairing that gets muddier in dark mode and has no Increased Contrast variant.
- **Docs already drift:** the `ui-spec.html` §capture-widget lede promises quiet non-green secondary tiles while its mockup CSS and the shipped widget paint them soft-green.

The owner has explicitly authorized a scoped exception to the single-accent rule for this surface, provided the result is classy rather than gimmicky.

## 2. Goals

- **Glanceable action identity.** Each of the four actions is recognizable by color + glyph before the label is read — the iOS-native "tinted chip" idiom (Reminders lists, Settings rows, Shortcuts tiles).
- **The brand still ranks first.** Scan remains the only *saturated fill*; the three secondary hues appear only as soft-tint chips with matching glyphs. One loud element, three quiet ones — hierarchy by saturation, identity by hue.
- **Calm ground.** The container and the medium hero panel are neutral; color lives only on the four chips. No slab of any hue, in either appearance.
- **Pure token change.** Same families, layout, glyphs, labels, `Link` targets, and accessibility behavior. Dark mode is a token swap.
- `DESIGN.md`, `ui-spec.html`, and the shipped widget agree again — including an honest, written-down exception to the single-accent rule instead of a silent violation.

## 3. Non-goals

- **No in-app adoption of action hues.** Inside the app the single-accent rule stands untouched: Ledger Green remains the only accent in app UI, and the capture sheet keeps its shipped treatment (D6). The exception is Home-Screen-widget-only.
- **No category semantics.** These are *action* hues on a launcher; they do not name, recolor, or interact with expense categories. The category palette's meaning (`SPEC-per-category-distinct-colors.md`) is unchanged; this spec only reuses three of its validated light/dark hex pairs as values (D3).
- **No red, ever** (`DESIGN.md`: "no red anywhere") — the chosen hues are blue, indigo, and amber-orange.
- **No layout, family, data, or routing changes.** Small stays 2×2; medium stays hero + overflow; `.systemLarge`, Lock Screen accessories, and on-widget data remain non-goals per `SPEC-quick-capture-widget.md`.
- **No new strings or accessibility identifiers.**

## 4. Design decisions

### D1 — Hierarchy by saturation, identity by hue

Rule being satisfied: the widget rule's intent — "the brand stays rationed … no large green flood" — and the design system's core philosophy of restraint. The widget carries exactly **one saturated fill**: the Ledger Green Scan chip (medium) / Scan tile (small) with its white glyph. Photo, File, and Manual each get a **soft-tint chip** (their hue at low intensity) holding a **saturated glyph of the same hue**. Saturation encodes rank (Scan first); hue encodes identity (which doorway is which). This is the established Apple pattern for multi-action launcher surfaces — Shortcuts widget tiles, Reminders list chips, Settings glyph tiles — which is why it reads native and premium rather than decorated.

Rejected alternatives:
- **All-neutral secondaries** (one green hit, gray everything else) — maximally restrained and defensible, but the owner reviewed the direction and chose glanceable color; at 2×2 scale neutral tiles also make the three secondaries mutually indistinguishable without reading.
- **Four saturated tiles** (each action a full-color fill) — a candy grid; four loud elements means no hierarchy, and it floods the widget with exactly the slab problem this spec removes.
- **Status quo** (green family only) — the monochrome block in the screenshots; no action identity, dark-mode flood.

### D2 — A written, scoped exception to the single-accent rule

Rule being amended (not silently broken): `DESIGN.md` — "Ledger Green … **The only brand accent**." Per the anti-drift rules, a feature that conflicts with a DESIGN.md rule must amend the rule explicitly. The amendment: *in-app UI remains single-accent; the Home Screen Quick Capture widget may additionally carry three fixed action hues as soft chips, because it competes on the wallpaper among third-party widgets without app chrome, captions, or context, and its job is split-second action recognition.* The exception names this one surface; it does not license second hues anywhere in the app, in system-chromed controls (which stay untinted per `widgets.system_controls`), or in future widgets by default.

### D3 — The three action hues are borrowed values from the category palette

Rule being satisfied: "Every custom token is a light/dark PAIR — one asset-catalog color set per token" and the dark-mode strategy ("no raw hex … in feature code"). Rather than inventing new colors, the three hues reuse already-validated light/dark pairs from `DESIGN.md` `colors.category_palette`:

| Action | Hue | Light | Dark | Why this hue |
|---|---|---|---|---|
| Scan | Ledger Green (existing) | `#1E7A55` | `#34C08A` | The brand; unchanged |
| Photo | blue | `#007AFF` | `#0A84FF` | iOS's own Photos/photo-picker association |
| File | indigo | `#5856D6` | `#5E5CE6` | Files/documents association; distinct from blue at chip size |
| Manual | orange (amber) | `#FF9500` | `#FF9F0A` | Warm "by hand" counterpoint; already the app's attention family, never red |

Blue–indigo–orange plus the green brand is a balanced spread around the wheel (two cools, one warm, one brand) — harmonious rather than rainbow. The values are *copied into widget-scoped tokens*, not shared symbols: the widget extension gets its own colorsets named for actions (e.g. `CapturePhoto`, `CaptureFile`, `CaptureManual`), because (a) asset catalogs are per-target and (b) naming them by action keeps category semantics out of the launcher. Each hue also gets a paired soft colorset (`…Soft`) following the exact `ledger_green` / `ledger_green_soft` pattern: an explicit light hex tint and a low-alpha dark variant, tuned to match `LedgerGreenSoft`'s visual weight so all four chips sit at equal intensity.

### D4 — The medium hero panel goes neutral; chips carry all the color

Rule being satisfied: "no large green flood" — the panel is the flood, in any hue. The `HeroScanTile` panel's `LedgerGreenSoft` fill is replaced with a quiet **semantic system fill** (one step of visual weight above the overflow area, so the hero still reads as a panel and a tap-target). The saturated Ledger Green camera chip is unchanged and becomes the panel's single color hit; the "Scan" label reads primary-on-neutral — better contrast than primary-on-soft-green today. The small family needs no panel change (tiles sit directly on the container).

Rejected: keeping the soft-green panel alongside colored overflow chips (the dark-mode slab remains, and the panel's green would visually swallow the small chips' hues).

### D5 — Component-level treatment and asset cleanup

- **Small family (`GridTile`):** Scan = saturated `LedgerGreen` fill, white glyph (unchanged). Photo/File/Manual = their `…Soft` fill with the saturated hue glyph. Labels stay primary. Tile sizes, radii, spacing, and the accessibility-size glyph-only fallback are untouched.
- **Medium family (`OverflowRow`):** each row's glyph tile swaps `LedgerGreenSoft`/`LedgerGreen` for its action's soft fill/hue glyph. Row text stays primary.
- **Palette:** the widget's private palette holds the brand plus the three action hue pairs; `LedgerGreenSoft.colorset` is deleted from `IntelliExpenseControls/WidgetAssets.xcassets` (after this change nothing in the extension references it — `ScanReceiptControl` is system-chromed and colorless). The app catalog's `LedgerGreenSoft` is untouched.
- No `colorScheme` branches anywhere — every hue adapts via its asset-catalog pair.

### D6 — The in-app capture sheet is explicitly *not* changed; the coupling rule is reworded

`DESIGN.md` `capture_sheet.accent` currently says "Same one-green family as the Quick Capture widget," which this change would falsify. The sheet stays as shipped — soft-green hero panel, neutral rows with soft-green glyph circles — and the rule is reworded to stand alone. Rationale: the sheet lives inside the app where the single-accent rule governs and captions carry action identity; the widget lives on the wallpaper where color must do the captions' job. If a later pass wants the sheet to echo the action hues, that is its own spec and would need its own D2-style amendment.

## 5. Edge cases

- **Dark mode:** pure token behavior — each hue pair and soft pair adapts; nothing reflows. Verify the three soft chips and `LedgerGreen` chip sit at equal perceived intensity over the dark container (tune the soft-dark alphas together, one value shared across hues).
- **Tinted/themed Home Screen (system rendering modes):** the system flattens widget colors to its tint; with four distinct hues the flattening is more visible than today, but this is system-owned behavior every colored widget (Shortcuts, Calendar) accepts. Glyph shapes + labels keep the actions distinguishable when hue is stripped — color is additive, never the sole differentiator (also the color-blindness story).
- **Accessibility sizes:** the small family's existing glyph-only fallback is unchanged; chips keep their hues, VoiceOver labels intact.
- **Increased Contrast / Reduce Transparency:** fixed-alpha soft fills have no system high-contrast variant — same limitation as today's `LedgerGreenSoft`; the saturated glyph on soft fill of the *same hue* must be re-verified for contrast in all four hues, both appearances (the amber pair is the one to watch; use the darker amber `#B26B00`-family value for the light-mode glyph if plain orange fails on its own tint).
- **Placeholder/redacted rendering:** launcher shows no data; unchanged.

## 6. Accessibility & localization

- **No new or changed strings.** All widget strings (`widget.capture.*`, `widget.quickCapture.*`, `AppShortcuts` table) untouched. Key/value table: *empty by design.*
- **No new or changed accessibility identifiers or labels**; chip glyphs remain `accessibilityHidden` where already hidden; per-tile labels ("Scan a receipt", "Choose photo", …) unchanged.
- Color is never the sole carrier of meaning: glyph + label (or glyph + VoiceOver label at accessibility sizes) always disambiguate.
- Contrast: verify each saturated glyph on its own soft tint in light, dark, and Increased Contrast (per `DESIGN.md` acceptance #10).

## 7. Test impact

- **No unit or UI test changes** — styling only; no logic, routing, timeline, or string changes. Existing deep-link/`CaptureKind` tests unaffected.
- `cd ExpenseCore && swift test` and the app test plan gate the commit as usual.
- Visual verification: both families, light and dark (Xcode widget gallery or `make install-device`; sandbox lane for screenshots), compared against the updated `ui-spec.html` §capture-widget mockups via the `design-spec` preview server.

## 8. Acceptance criteria

1. Exactly one saturated fill per family: the Ledger Green Scan chip (medium) / Scan tile (small). Photo, File, and Manual render as soft-tint chips (blue, indigo, orange respectively) with matching saturated glyphs — never saturated fills.
2. The medium hero panel is a neutral semantic fill; no soft-green (or any-hue) slab exists in either appearance. The widget container remains a calm system surface.
3. All six new colors ship as asset-catalog light/dark pairs in `WidgetAssets.xcassets`, named for actions (not categories); `LedgerGreenSoft.colorset` is removed from the extension; the app catalog is untouched; both lanes (durable + sandbox) build. No raw hex or `colorScheme` branches in the widget code.
4. Layout, families, glyphs, labels, `Link` URLs, `widgetURL` fallback, and the accessibility-size fallback are behaviorally identical to before; actions remain distinguishable with color removed (glyphs/labels).
5. Dark mode is a token swap — same layout, four chips at equal perceived intensity, saturated glyphs pass contrast on their own tints in both appearances and under Increased Contrast.
6. `DESIGN.md` carries the explicit, widget-scoped exception to the single-accent rule (frontmatter + body), the reworded `capture_sheet.accent`, and the updated component entry; `design/ui-spec.html` §capture-widget lede + mockups match the shipped widget.
7. The in-app capture sheet and all system-chromed controls are visually unchanged.
