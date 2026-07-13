# SPEC — Mac visual polish: native detail pane, brand accent, desktop density

**Status:** proposed
**Owner screens/files:** `IntelliExpense/Mac/MacContentView.swift` (detail pane, sidebar, receipt list column, toolbar); new `IntelliExpense/Mac/MacReceiptDetailPane.swift`; `IntelliExpense/UI/ReceiptsViews.swift` (`ReceiptRow`, `ReceiptDetailView` platform seams); `IntelliExpense/UI/GroupsViews.swift` (`GroupRow`); `IntelliExpense/UI/PlatformImageSupport.swift` (page-viewing seam); `IntelliExpense/Resources/Assets.xcassets` (new `AccentColor` color set); `project.yml` (global accent build setting)
**Docs this spec amends:** DESIGN.md §10 (Native Mac Adaptation — detail-pane anatomy, accent wiring, density rules), DESIGN.md §2/§11 (AccentColor alias note), `design/ui-spec.html` `#mac` section (detail-pane mockup and contract rows)
**Related specs:** SPEC-mac-app.md (this spec finishes its acceptance criterion 4 — "all design-system laws hold on macOS"); SPEC-agent-import-bridge.md (agent-entry receipts are the common photo-less case in the detail pane); SPEC-review-save-discard-redesign.md (review contract reused for editing)

---

## 1. Problem

The Mac target is structurally correct (native SwiftUI, three-pane split, shared pipeline, sync) but visually it is an iPhone app poured into a Mac window:

- Selecting a receipt shows the iOS `ReceiptDetailView` — a `Form` with **no form style** — in the detail column. On macOS the automatic form style resolves to the AppKit *columns* layout: no grouped cards, no insets, labels and controls floating loose, vertically centered in a pane that can be 1,400 pt wide. The currency row's value floats to the far trailing edge of the window.
- List selection renders **system blue**. There is no `AccentColor` color set and no global-accent build setting, so macOS falls back to the system accent for list selection and default controls — a direct violation of the single-brand-accent law.
- Rows and the sidebar keep iPhone proportions at Mac text sizes (macOS body is 13 pt against iOS's 17 pt reference), so subtitles land at 10–11 pt, trip rows truncate name and total, and money is not aligned as a ledger column.
- Multi-page receipt viewing silently degrades: the page-style `TabView` is iOS-only, so macOS shows a default tab control inside the form.
- Archive, Restore, Delete, and Add Photo render as small stray bordered buttons inside the form — phone list idioms, not Mac ones.
- The detail pane has no hero: the one screen region that DESIGN.md §10 says "owns the single hero object" shows no hero amount, no receipt image beside fields — the side-by-side layout SPEC-mac-app D2 calls "the single biggest UX win of the Mac" exists only in the drop-review pane, not in receipt detail.

None of this is a Catalyst or universal-purchase artifact; every defect is view-level and fixable inside the existing target.

## 2. Grounding (design system + platform behavior)

Rules that constrain everything below, quoted so decisions cite their law:

- DESIGN.md §11: "Accent = **Ledger Green** (`#1E7A55` light / `#34C08A` dark) for tint, Save, **selection**." CLAUDE.md: "single brand accent (Ledger Green), no red anywhere."
- DESIGN.md §5: "**One hero number per screen.**" — SPEC-mac-app D4 scopes this per *pane*, "with the detail pane owning the hero"; DESIGN.md §10: "The detail column owns the single hero object."
- DESIGN.md §3: hero money is "~31 **light**, tabular" *by reference role, not fixed size* — "never fixed point sizes in code"; "Money is always tabular-numeral so amounts align down every list."
- DESIGN.md §4 row anatomy: "thumbnail (or type glyph…) → title + subtitle in descending weight → right-aligned tabular amount."
- DESIGN.md §5: "destructive delete never rides a reflex swipe on active content — it lives only behind archived surfaces or explicit editor actions, styled with the system destructive role, never app-palette red"; "Archiving is the reflex gesture… always safe (accent-tinted…)."
- DESIGN.md §6: "System-owned glass only for bars, sheets, menus"; exactly two custom glass elements, both iPhone-only — the Mac adds **zero** custom glass.
- DESIGN.md §9: "Reuse the review form for post-save editing — one component, one muscle memory"; no `colorScheme` branches; no fixed sizes.
- Platform behavior (verified against current SwiftUI documentation and the WWDC25 "Build a SwiftUI app with the new design" guidance): on macOS the automatic `Form` style is columns, and the grouped form style is the one that renders inset-grouped cards matching the iPhone's editing surfaces; page-style `TabView` does not exist on macOS; macOS list selection and default control tinting follow the app's global accent color from the asset catalog; standard toolbars get Liquid Glass treatment from the system with no custom work.

## 3. Goals

- The Mac detail pane reads as the product's signature screen: receipt image beside a grouped editing form, one light tabular hero amount, Ledger Green everywhere the system shows selection or tint.
- The whole window obeys the ledger rules per pane: right-aligned tabular money columns in sidebar and receipt list, hierarchy by weight and color, platform-native density.
- Phone-only idioms (page-dot pager, in-form action buttons, "Add photo" as a form row) are replaced by their Mac equivalents (pager controls, toolbar + context-menu actions) without forking shared components.
- Zero new design language: every change either applies an existing DESIGN.md rule on macOS or amends DESIGN.md/ui-spec.html in this same change.

## Non-goals

- No iOS visual changes; the iPhone app must be pixel-identical after this spec (shared components gain platform seams, not new behavior).
- No custom window chrome, translucency, or glass beyond system defaults (DESIGN.md §6).
- No new data model or sync surface; purely presentational plus action placement.
- No multi-window or menu-bar-extra work; no changes to import, agent bridge, or export flows beyond toolbar labeling.
- No Mac-specific color tokens or fonts (Dynamic-Type-only and shared tokens are law).

## 4. Design decisions

### D1 — `AccentColor` asset wired as the global accent, defined as an alias of Ledger Green

Add an `AccentColor` color set (light `#1E7A55`, dark `#34C08A` — exactly the LedgerGreen values) and set the global accent-color build setting for **all** targets in `project.yml`. This is what makes macOS list selection, default button tint, focus rings, and menu highlights render in the brand accent; it also hardens iOS, which today gets green only from view-level tints.

Rule satisfied: §11 "Accent = Ledger Green … for tint, Save, selection." Drift control: DESIGN.md names "nine asset-catalog token pairs"; `AccentColor` is **not a tenth token** — it is the system's required alias of LedgerGreen. DESIGN.md §2 gains one sentence stating this, and any future change to LedgerGreen must update both color sets together. Feature code continues to reference `LedgerGreen` by name; `AccentColor` exists only for the system.

Considered and rejected: tinting every Mac list/control in code (`tint` at the root) — it does not reach macOS list-selection or focus-ring rendering, and per-view tinting is exactly the fragility that let the blue leak in.

### D2 — A Mac detail pane with the review pane's anatomy: image beside grouped form, hero header

Selecting a receipt shows a new `MacReceiptDetailPane` (owner: `IntelliExpense/Mac/`) with the same two-column anatomy already shipped in `MacReceiptReviewPane`: receipt image column on the leading side, editing form on the trailing side, divider between. Specifics:

- **Hero header** at the top of the form column: vendor name (body-weight emphasis) and the receipt amount in the hero-money role — light weight, tabular, locale-formatted via the shared formatters. This is the detail pane's *one* hero (§5, §10); the receipt list column keeps only row-level amounts so the window never shows two competing heroes.
- **Fields** use the grouped form style (the same style `MacReceiptReviewPane` already uses) so macOS renders inset-grouped cards matching the iPhone's editing surface. Field order, bindings, validation, currency picker, group menu, and provenance disclosure are the existing `ReceiptDetailView` semantics — reused behavior, not a rewrite (§9 "one component, one muscle memory"). The form column is width-capped (ideal ~440 pt, consistent with the review pane's field column) so controls never stretch across the full pane.
- **Image column**: full-height, receipt image fit with generous padding on the plain window background (§ "no dimming/inverting receipt images"), matching `MacReviewImageColumn`. Clicking the image opens the existing image viewer sheet. Photo-less receipts (typical for agent entries) show the expense-type glyph tile — the §4 row-anatomy fallback — not an "Add photo" button marooned in the pane; **Add Photo** moves to the detail toolbar (D4).
- The `NavigationStack` wrapper around the detail column is removed; the split view's detail column supplies the navigation context and title.

Rules satisfied: §10 "detail column owns the single hero object"; SPEC-mac-app D2 "image beside the fields… the single biggest UX win"; §3 hero role; §9 reuse of the review form.

Considered and rejected: presenting fields in a system inspector panel with the image as the whole detail — the inspector pattern hides editing behind a toggle and breaks the "screen visibly completes" review muscle memory; the side-by-side pane is already the app's proven Mac pattern. Also rejected: keeping one cross-platform `ReceiptDetailView` with conditional styling — the phone's vertical stack and the Mac's two-column anatomy differ structurally, while the *field semantics* stay shared; the seam goes at the layout level, mirroring how review already splits.

### D3 — Ledger density: platform-native rows, aligned money columns

- `ReceiptRow` and `GroupRow` keep their semantic text styles (no size changes — §3) but adapt metrics behind platform seams: on macOS, rows use platform list metrics with slightly reduced thumbnail scale, and the trailing amount is a right-aligned tabular column at consistent trailing alignment so amounts align down the list (§3, §4). The type label under the amount collapses to icon + color on macOS row heights to stop the 10 pt caption clutter; full type names remain in the detail pane.
- The sidebar becomes a standard source-list: trip name (primary) with the trip total as a right-aligned secondary tabular amount on the same line, and the date range demoted to a tooltip/help tag rather than a squeezed third line. The iPhone's type-dot row does not render in the sidebar (it is a featured-card element; the sidebar "is the trip list" per SPEC-mac-app D2). `SPEC-mac-sidebar-refinement.md` supersedes this spec's original fixed trailing-money reservation and 260 pt column: money now claims natural width, the name owns layout priority, and the sidebar uses 240/280/360 pt limits.
- Receipt-list date section headers use the platform's standard section-header treatment; the day grouping and formatter output are unchanged.

Rule satisfied: SPEC-mac-app D4 "list rows may adopt the platform-default compact metrics; the ledger rules (tabular numerals, right-aligned money…) apply per pane." Hierarchy stays weight/color, never size (§3).

### D4 — Actions move to where Mac users look: toolbar and context menus

- **Detail toolbar** (trailing): Add Photo (photo-less receipts), Archive/Restore (accent-tinted, §5 "always safe"), and an overflow menu holding Delete with the system destructive role and the existing confirmation dialog (§5 "explicit editor actions… never app-palette red"). The in-form Archive/Delete/Add-Photo sections compile out on macOS.
- **Context menus** on receipt rows (Archive/Restore, Delete for archived only, Move to Trip submenu) and on sidebar trips (Rename, Archive, Export) — the Mac reflex equivalent of the iPhone's swipe gestures, same safety rules.
- Existing window toolbar items for Import and Export stay; `SPEC-mac-sidebar-refinement.md` supersedes the former New Trip/New Folder toolbar-or-row placement with the standard bottom-aligned sidebar bar while preserving File-menu and ⌘N commands. No custom toolbar backgrounds — system Liquid Glass only (§6).

Considered and rejected: keeping action buttons inside the grouped form for cross-platform uniformity — on macOS in-form command buttons read as web-form idioms; the HIG places object commands in the toolbar/context menu, and §5 already frames delete as an "explicit editor action", which the toolbar is.

### D5 — Multi-page receipts get Mac pager controls

The page-style `TabView` seam (`receiptPageTabViewStyle`) currently no-ops on macOS. In the Mac image columns (detail and review), multi-page receipts render one page at a time with previous/next pager controls and a "page m of n" caption reusing the existing `review.page.count` format. No thumbnail filmstrip in this pass (scope control; most receipts are 1–2 pages). The image-viewer sheet keeps its existing paging.

### D6 — Window and empty states

- Window minimum size stays 900×600; the detail pane's empty state remains the existing `ContentUnavailableView` (§4 empty-state shape) — unchanged, it already complies.
- Selection behavior: selecting a trip with no receipt selected keeps the empty detail state; the first receipt is **not** auto-selected (auto-selection would fight the agent-entry confirmation section at the top of the content column).

### D7 — Docs amendments carried in this change

- DESIGN.md §10 gains: detail-pane anatomy (image beside grouped fields, hero header), the toolbar/context-menu action mapping, the density rules from D3, and the pager rule from D5.
- DESIGN.md §2/§11 gain the one-line `AccentColor`-aliases-LedgerGreen note (D1).
- `design/ui-spec.html` `#mac` section gains a detail-pane mockup in the shared visual language and updates its contract table rows (detail column, actions, accent).

## 5. Edge cases

- **Photo-less receipts** (manual entries, agent entries): image column shows the type-glyph tile; Add Photo lives in the toolbar; the hero amount still renders. Never an "Add photo" button as the pane's visual centerpiece.
- **Archived receipt selected**: hero and fields render read-consistently with iOS behavior; toolbar shows Restore (accent) and Delete (destructive, overflow); archived-on footnote stays in the form.
- **Zero-amount / unparsed amount**: hero renders the formatted zero/empty state exactly as the shared formatter produces it; validation footnote behavior unchanged.
- **Very long OCR text** in the provenance disclosure: scrolls within the form; text selection enabled (existing behavior preserved).
- **Window narrower than three panes**: standard split-view collapse (SPEC-mac-app edge case) — the detail pane's two columns stack is *not* required; below the image column's minimum width the image column hides and the image is reachable via the viewer sheet.
- **AX text sizes on macOS**: the hero and field labels scale with the system; the two-column detail layout must tolerate the form column growing (image column yields width first).
- **Mixed currencies in one trip**: sidebar trip total keeps the existing per-currency primary+secondary treatment (§9 "never sum across currencies"); the narrow sidebar shows the primary currency line and the full side-by-side rendering appears in the tooltip and content column header.
- **RTL**: all new layouts are leading/trailing-defined; the image column leads, form trails, mirrored automatically.

## 6. Accessibility & localization

New string-catalog keys (English values):

| Key | Value | Notes |
|---|---|---|
| `receipt.detail.addPhoto.toolbar` | `Add Photo` | Toolbar label; existing `receipt.detail.addPhoto` ("Add a photo") stays for the iOS form row |
| `receipt.pager.previous` | `Previous Page` | Pager control accessibility label |
| `receipt.pager.next` | `Next Page` | Pager control accessibility label |
| `mac.sidebar.trip.help` | `%1$@ · %2$@` | Tooltip: date range · full per-currency total (arguments locale-formatted by Foundation, never composed in the catalog) |

Changed values on stable keys: none. Plural variants: none new (`review.page.count` already carries the count format). Everything else reuses existing keys (`receipt.archive`, `receipt.restore`, `common.delete`, `receipt.field.*`, `groups.unfiled.title`, `review.page.count`). Dates, currency names, and amounts come from Foundation formatters only.

New accessibility identifiers: `mac.detail.hero.amount`, `mac.detail.toolbar.addPhoto`, `mac.detail.toolbar.archive`, `mac.detail.toolbar.restore`, `mac.detail.toolbar.delete`, `mac.detail.pager.previous`, `mac.detail.pager.next`, `mac.row.contextMenu.archive`, `mac.row.contextMenu.delete`. Existing `receipt.action.archive`/`receipt.action.restore` remain on the iOS form buttons.

VoiceOver: the hero header is one grouped element ("vendor, amount"); the image column announces as "Receipt image, page m of n, button" opening the viewer; pager controls are buttons with the labels above; toolbar actions get standard labeling. Full-keyboard-access order: hero → fields top-to-bottom → provenance → toolbar.

## 7. Test impact

- **ExpenseCore**: untouched.
- **Unit tests**: no pipeline/store changes; `ReceiptDetailAmountEditor` reused as-is.
- **Mac UI tests** (extend the existing Mac suite): selecting a receipt shows `mac.detail.hero.amount`; archive via `mac.detail.toolbar.archive` moves the receipt to Archived; delete is absent from the form and present (destructive) in the toolbar overflow; pager identifiers appear only for multi-page receipts; the empty-detail state still renders when nothing is selected.
- **iOS regression**: existing iOS UI tests must pass unchanged — they are the guard that the shared-component seams didn't alter phone behavior.
- **Manual verification** (scripted lane `build-mac`/`run-mac`): light/dark appearance pass (accent selection green in both), AX text-size pass on the detail pane, VoiceOver order per §6, RTL smoke (pseudo-locale), and a two-device sync sanity check after editing in the new pane.

## 8. Acceptance criteria

1. macOS list selection, focus rings, and default control tint render in Ledger Green in light and dark; no system blue anywhere; `AccentColor` values are byte-identical to `LedgerGreen`'s and the alias rule is written into DESIGN.md.
2. Selecting a receipt on Mac shows image-beside-fields with a grouped-style form at a capped width and exactly one hero amount in light tabular type; no columns-style floating fields remain anywhere in the app.
3. Archive/Restore/Delete/Add-Photo appear in the detail toolbar and row context menus with the safety styling of DESIGN.md §5, and no action buttons render inside the Mac form; iOS keeps its existing form actions untouched.
4. Sidebar and receipt-list amounts align as right-aligned tabular columns; trip rows show name + natural-width total on one line without truncated card idioms; the refined sidebar uses 240/280/360 pt limits, a collapsible Folders section, system destination badges, and a bottom New Folder bar per `SPEC-mac-sidebar-refinement.md`; multi-page receipts page via labeled pager controls on macOS.
5. All new/changed strings are in the shared String Catalog per the §6 table; all new accessibility identifiers exist; money remains `Decimal` with locale-aware formatting throughout.
6. DESIGN.md §10 (+§2/§11 accent note) and `design/ui-spec.html` `#mac` are amended in the same change; no `colorScheme` branches, no fixed point sizes, no new custom glass, no red.
7. The iOS app is visually and behaviorally unchanged: full iOS test suite green, and shared components diff only by platform seams.
