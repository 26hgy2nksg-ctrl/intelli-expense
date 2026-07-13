# SPEC — Add Receipt sheet (capture-method discoverability)

**Status:** implemented
**Owner screens/files:**
- `IntelliExpense/ContentView.swift` — `MainTabView` (the `capture.add.title` confirmationDialog at `:199-223`, `showAddDialog` at `:377-381`, `canStartExternalCapture` at `:428-439`) and `CaptureAccessoryView` (`:860-932`: the ⋯ `Menu`, `menuContent()`, the `.contextMenu`).
- `IntelliExpense/UI/CaptureViews.swift` — **new file** hosting the `AddReceiptSheet` component (and the TipKit tip definition). New file ⇒ `xcodegen generate` before it compiles into the app target.
- `IntelliExpense/Resources/Localizable.xcstrings` — new keys (§6).
- `IntelliExpense/App/` — TipKit bootstrap (one-time `Tips` configuration at app launch; disabled under UI-test launch configuration).

**Docs this spec amends:**
- `DESIGN.md` — §4 Components: new **"Add Receipt sheet"** entry; amend the **Capture accessory** entry (line ~262: "⋯ menu for Photo / File / Manual" becomes "labeled **More** button opening the Add Receipt sheet; long-press keeps the direct menu"); add a `capture_sheet` note to the machine-readable frontmatter mirroring the `home_screen_widget` block (line 84).
- `design/ui-spec.html` — the accessory mockups (`:514-516` and siblings): trailing zone becomes the labeled More affordance; the camera-first rationale block (`:865-868`) updated to name the sheet; new section `#add-receipt-sheet` with light/dark mockups; the Structure/Add summary row (`:1885`) updated ("B's menu behind ⋯ / long-press" → "A's More + B open the Add Receipt sheet").
- `PRD.md` §5 — one sentence: the four capture entry methods are surfaced in-app by the Add Receipt sheet (accessory More button, toolbar +).

**Related specs:**
- `SPEC-tab-accessory-collapse-and-archive.md` — built the accessory; its A-R7 explicitly deferred "the ⋯ button as a separate Menu … separate spec if ever needed." The menu has since shipped; **this is the follow-up that redesigns it.**
- `SPEC-quick-capture-widget.md` — the widget's medium layout (hero Scan panel + Photo/File/Manual overflow list) is the visual pattern this sheet brings in-app; its D3/D6 color and glyph decisions are inherited wholesale.
- `SPEC-scan-receipt-everywhere.md` — external capture surfaces; untouched here.

---

## 1. Problem

The capture accessory is camera-first by design: tapping the bar opens the document scanner in one tap (`ui-spec.html:865`: "Camera-first, menu-second"; PRD §6.4: capture must never be blocked at a cash register). The other three capture methods — **Choose photo · Import file · Enter manually** — hide behind a bare `ellipsis.circle` glyph (`ContentView.swift:878-887`). In practice (owner's own report) this fails:

- A naked ⋯ has no label and no hint of payload; users do not discover the three methods behind it.
- The ⋯ hit target is small and sits flush against a full-bar scan button — a tap *near* the dots fires the camera instead.
- The same four actions exist a second time behind the toolbar `+` as an undesigned system `confirmationDialog` (`ContentView.swift:199-223`) — two inconsistent surfaces for one task, neither of which explains what the options do or where the receipt will land.

Meanwhile the app already designed the ideal presentation of this exact hierarchy — on the Home Screen. The Quick Capture widget's medium layout (`DESIGN.md:84`): "hero Scan panel (LedgerGreenSoft, holding a small Ledger Green camera chip + label) + Photo/File/Manual overflow list." In-app users never see it.

## 2. API grounding

*Confirmed against the offline Apple docset before implementation lock (Apple API Reference docset v24703, checked 2026-07-09); all are well inside the iOS 26.0 target.*

- `View.presentationDetents(_:)` / `PresentationDetent.medium` / `.large` (`/documentation/swiftui/view/presentationdetents(_:)`, iOS 16.0+) — half-height sheet with user-expandable large detent; `View.presentationDragIndicator(_:)` for the grabber.
- **TipKit** (iOS 17.0+): `Tip` protocol with `Tips.Event` donation and `#Rule` display conditions (`/documentation/tipkit/tip`); `View.popoverTip(_:arrowEdge:)` to anchor a tip to the More button; `Tips.configure(_:)` at launch; `tip.invalidate(reason:)` to retire it permanently; `Tips.hideAllTipsForTesting()` for deterministic UI tests. Tip title/message take `Text`, so String Catalog keys work unchanged.
- `tabViewBottomAccessory` / `tabViewBottomAccessoryPlacement` — already grounded and shipped (SPEC-tab-accessory A2); this spec only rearranges the accessory's trailing content.
- Sheets are system-owned material (`DESIGN.md:75`: "Tab bar, toolbars, **sheets, menus** — always system material"), so the Add Receipt sheet does **not** count against the two-custom-glass-elements budget (`DESIGN.md:329`).

## 3. Goals

- The three non-scan capture methods become **visible, labeled, and explained** — reachable from an affordance a first-time user can read, not a glyph they must gamble on.
- One designed **Add Receipt sheet** replaces both undesigned surfaces (the accessory's system `Menu` and the toolbar `+`'s `confirmationDialog`), so the task has exactly one in-app presentation — and it visually rhymes with the Quick Capture widget, teaching one layout across Home Screen and app.
- The accessory's trailing trigger gains a visible **"More"** label and a comfortably separated hit target, fixing the mis-tap.
- A one-time TipKit tip teaches the affordance to existing users without adding permanent chrome.
- **The one-tap scan path is untouched.** Tapping the bar still opens the document camera immediately, in both accessory placements.

## 4. Non-goals

- **No change to the receipt-detail attach flow** (`receipt.attach.title` dialog, `ContentView.swift:224-242`). It is a different task (add a page to an existing receipt, no Manual option) on a different screen; unifying it onto a sheet variant is a cheap follow-up, listed in D6, not this spec.
- **No change to external surfaces** — widget, control, App Shortcut, deep links, share extension all keep routing through `CaptureKind` exactly as today.
- **No empty-state redesign.** Advertising the four methods in empty trip/receipts states is a valuable follow-up (it composes with this spec) but is separate scope.
- **No change to destination-group logic.** The accessory path keeps `captureDestinationGroup`; the toolbar path keeps `defaultGroup ?? mostRecentlyUsedGroup` (`showAddDialog`, `ContentView.swift:377-381`). The sheet *displays* the destination; it does not let the user change it (that is the review screen's job — one screen, one job).
- **No fifth capture method** (paste, drag-in, etc.).

## 5. Design decisions

### D1 — One designed Add Receipt sheet, mirroring the widget's medium layout

A new `AddReceiptSheet` component presented at `.medium` detent (`.large` also enabled for AX type sizes and user preference; drag indicator visible). Content, top to bottom:

1. **Header** — title from the existing key `capture.add.title` ("Add receipt"), with a destination caption beneath it: `capture.sheet.destination` ("Adding to %@") filled with the same value the accessory subtitle uses today (`captureAccessoryDestinationName`, `ContentView.swift:736` — group name or `capture.accessory.unfiled`). The user sees *where* the receipt will land before choosing *how*.
2. **Hero Scan panel** — a full-width LedgerGreenSoft panel holding a small saturated Ledger Green camera chip (`camera.viewfinder`, white glyph) + "Scan document" (`capture.scan`) + caption `capture.scan.caption`. This is the widget hero at sheet scale (widget spec D3), inheriting its hard-won rules: **the only saturated fill is the small chip, never a large slab; no white text ever sits on saturated Ledger Green** (fails contrast in dark mode).
3. **Three overflow rows** — full-width tappable rows, each: Ledger Green glyph in a small LedgerGreenSoft tile, primary label (existing keys `capture.photo` / `capture.file` / `capture.manual`), and — the discoverability payload — a one-line secondary caption (`capture.photo.caption` / `capture.file.caption` / `capture.manual.caption`). Glyphs match the widget: `photo`, `doc` (deliberately not `folder` — folders mean *trips* in this app; widget spec D6), `square.and.pencil`.

Rules this satisfies: single brand accent, one hue at two intensities, no red (`DESIGN.md:137`); system sheet material, not a third custom glass element (`DESIGN.md:75`, `:329`); Dynamic Type text styles and base-4/8 spacing throughout; no hero number (there is no number); no `colorScheme` branches — the two asset-catalog pairs carry dark mode.

Selecting any option dismisses the sheet and then runs the exact existing handler — `startAccessoryCapture(sourceType:)`, `startAccessoryFileImport()`, `startAccessoryManualEntry()` for the accessory path, or the dialog-equivalent closures for the toolbar path. **Dismiss-then-present**: the scanner/photo picker/file importer/review form are presented from the root as today, so the sheet must fully dismiss before the follow-on presentation triggers (present the follow-on from the sheet's dismissal completion, not concurrently) — never sheet-over-sheet.

### D2 — Both entry points converge on the sheet

- The accessory's trailing trigger opens the sheet (replacing the system `Menu` at `ContentView.swift:878-887`).
- The toolbar `+` (`ReceiptsViews.swift:164-191` and the Groups equivalent) opens the same sheet (replacing the `confirmationDialog` at `ContentView.swift:199-223`), keeping its own default-group logic.
- The sheet is one component with one state flag replacing `isShowingAddDialog`; `canStartExternalCapture` (`ContentView.swift:428-439`) swaps that flag accordingly, so external capture requests are still dropped while it is up.

Rationale: two surfaces for one task is drift; a component that appears identically from both doors (and echoes the widget) is the anti-drift fix. The sheet inherits the confirmationDialog's job wholesale, so no behavior is lost — only gained (captions, destination, hierarchy).

### D3 — The trailing trigger becomes a labeled "More" zone

In the **expanded** accessory placement, the bare `ellipsis.circle` is replaced by a compact vertical stack: the glyph over a caption-size visible label `capture.accessory.moreLabel` ("More"), in `.secondary` style (unchanged from today's glyph treatment — the trigger stays quiet next to the green scan chip). The zone gets a fixed generous width (comfortably ≥ 44pt square) and a leading hairline divider separating it from the scan button, so a near-miss tap hits *something deliberate* rather than the camera.

In the **inline** (minimized) placement the trigger stays glyph-only (`ellipsis.circle`, as today — the inline capsule has no room for a caption), full VoiceOver label retained. The inline trigger opens the same sheet.

The existing accessibility identifier `capture.accessory.menu` and label `capture.accessory.more` **stay on the trigger** (identifier stability for existing UI tests; the label "More capture options" is already correct for the new behavior).

### D4 — Long-press keeps the direct menu (expert shortcut)

The whole-bar `.contextMenu` (`ContentView.swift:891-893`) keeps offering Photo/File/Manual as direct actions. Users who already know the methods keep a one-gesture path that skips the sheet; the sheet is the teaching surface, the context menu the muscle-memory surface. Menus are system-owned material (`DESIGN.md:75`) — no design work needed.

### D5 — One-shot TipKit tip on the More button

A `popoverTip` anchored to the More trigger: title `tip.captureOptions.title`, message `tip.captureOptions.message`. Display rules:

- **Eligible** only after the first successful *scanned* receipt save (donate an event when a review save completes for a camera-scan capture) — the user has proven the primary flow and is now most receptive to "there are other ways."
- **Invalidated permanently** the first time the Add Receipt sheet is opened from *any* door (the user has discovered it; the tip's job is done) and on explicit tip dismissal.
- Never shown on the Settings tab (the accessory is hidden there) and never while processing.
- `Tips` configured once at app launch; under the UI-test launch configuration tips are hidden (`Tips.hideAllTipsForTesting`) so existing UI tests stay deterministic. The sandbox lane behaves like the durable lane (tips on) — screenshot sessions may want the tip visible anyway.

Rationale: discoverability for the installed base without permanent chrome — consistent with the app's minimal-chrome rules (`DESIGN.md:381`: no custom bar backgrounds, restraint everywhere). TipKit is the platform-native mechanism; its persistence store handles "only once" for free.

### D6 — Considered and rejected

- **Bar tap opens the chooser** (scan becomes a sheet row): rejected outright — breaks "camera-first, menu-second" (`ui-spec.html:865`) and adds a tap at the cash register (PRD §6.4). The sheet contains a Scan hero for hierarchy and consistency, but the bar remains the one-tap path.
- **Labeled icon row in the bar** (photo/file/keyboard buttons inline in the accessory): three extra targets crowd a ~52pt bar, collapse badly under Dynamic Type, and dilute the single-primary-action reading that makes the accessory work. Rejected.
- **Keep the system `Menu`, only enlarge/label the trigger**: cheapest option, but a system menu cannot carry captions or the destination line, and it leaves the toolbar `+`'s confirmationDialog as a second inconsistent surface. Discoverability of the *trigger* would improve; comprehension of the *options* would not. Partially adopted (the trigger work is D3) but insufficient alone.
- **Grid-of-four sheet** (2×2 tiles like the small widget): loses the captions — the whole point in-app is to *explain* the methods, which needs a row's horizontal space. The grid stays a widget-small compromise, not the in-app pattern.
- **`confirmationDialog` retained as the sheet** (restyle expectations only): a confirmationDialog cannot host the hero/caption/destination anatomy; it is a list of verbs with no teaching surface. Rejected — it is the current failure, just relocated.
- **Unifying the receipt-detail attach dialog now**: same component minus the Manual row and with an "Attach to <vendor>" header — deliberately deferred (Non-goals) to keep this change reviewable; the component should be built so the variant is trivial later.
- **A destination *picker* in the sheet**: changing the target trip at capture time duplicates the review screen's group field and complicates the fast path. The sheet shows the destination; the review screen changes it.

## 6. Edge cases

- **Processing in flight**: the accessory already sits behind `allowsHitTesting(processingState == nil)` (`ContentView.swift:345`) — neither the bar nor More is tappable. The toolbar `+` keeps whatever gating it has today; the sheet itself is never presentable while processing because its triggers are.
- **External capture (widget/control/deep link) while the sheet is open**: dropped, exactly as with today's dialog — `canStartExternalCapture` includes the sheet's flag (D2).
- **Sheet option → follow-on presentation**: dismiss-then-present (D1). A user who taps Photo must never see the sheet and the photos picker fighting for presentation; if the dismissal is interrupted (swipe mid-animation), no action fires.
- **Sheet swiped away with no selection**: nothing happens; no state leaks (`defaultCaptureGroup`/`attachmentTargetReceipt` reset on next open, as `showAddDialog` does today).
- **Largest AX type sizes**: rows wrap to two lines rather than truncating captions; the sheet content scrolls within the detent; `.large` detent available. Four targets remain four targets at every size.
- **Inline (minimized) accessory**: glyph-only trigger still opens the sheet (D3); long-press on the inline bar keeps the context menu.
- **Camera permission denied**: untouched — Scan (bar, sheet hero, or context menu) routes to the existing `CameraPermissionDeniedView`; Photo/File/Manual never touch the camera.
- **Tip vs. sheet race**: opening the sheet invalidates the tip even if the tip has never displayed (eligibility may lag actual discovery). The tip never re-arms.
- **Fake-services / UI-test lane**: sheet actions honor `usesFakeServices` exactly as the dialog buttons do today (`startUITestFixtureCapture` paths preserved); tips hidden under UI tests (D5).

## 7. Accessibility & localization

**VoiceOver / identifiers:**
- Each sheet row (and the hero panel) is **one** VoiceOver element, button trait, label = primary label, value = caption (e.g. "Choose photo, Pick from your photo library"). Glyphs decorative.
- The destination caption is one element: "Adding to Berlin — June 2026" (or "Adding to Unfiled").
- New identifiers: `capture.sheet`, `capture.sheet.scan`, `capture.sheet.photo`, `capture.sheet.file`, `capture.sheet.manual`, `capture.sheet.destination`. The trigger keeps `capture.accessory.menu` (D3); the bar keeps `capture.accessory`.
- More trigger: visible label "More", VoiceOver label stays `capture.accessory.more` ("More capture options"); ≥ 44pt target in both placements.
- Dynamic Type only; no fixed point sizes; `@ScaledMetric` for the chip/tile steps, matching `CaptureAccessoryView`'s existing `iconTileSize` approach.

**Localization — new keys in `Localizable.xcstrings` (English values):**

| Key | English value | Notes |
|---|---|---|
| `capture.accessory.moreLabel` | More | Visible trigger caption (expanded placement) |
| `capture.sheet.destination` | Adding to %@ | %@ = group name or the existing `capture.accessory.unfiled` value |
| `capture.scan.caption` | Use the document camera | Hero caption |
| `capture.photo.caption` | Pick from your photo library | Row caption |
| `capture.file.caption` | Images or PDFs from Files | Row caption |
| `capture.manual.caption` | Type the details yourself | Row caption |
| `tip.captureOptions.title` | More ways to add receipts | TipKit title |
| `tip.captureOptions.message` | Add receipts from Photos or Files, or enter one by hand. | TipKit message |

Existing keys reused unchanged: `capture.add.title` (sheet title), `capture.scan`, `capture.photo`, `capture.file`, `capture.manual`, `capture.accessory.more`, `capture.accessory.unfiled`. No key renames. No plurals (no counts). No locale-dependent data in the sheet beyond the group name, which is user content.

## 8. Test impact

- **UI tests (`IntelliExpenseUITests`):**
  - Any test that opens the accessory ⋯ menu or the `capture.add.title` confirmationDialog and taps `capture.photo`/`capture.file`/`capture.manual`/`capture.scan` migrates to the sheet identifiers (`capture.sheet.*`). Audit for both entry points (accessory trigger and toolbar `+`).
  - New: More trigger (`capture.accessory.menu`) opens the sheet on Folders and Receipts tabs; sheet shows all four options and the destination line; selecting Manual lands in the review form; swiping the sheet away leaves the app idle; toolbar `+` opens the identical sheet.
  - New: sheet not presentable during processing (fixture processing state → trigger inert).
  - Tips hidden under the UI-test launch configuration so no popover intercepts taps.
- **Unit tests:** none in `ExpenseCore` (no pure-logic change). App-target: `canStartExternalCapture` gains the sheet flag — extend the existing external-capture guard test to assert a request is dropped while the sheet is open.
- **Regression:** external capture (`?kind=` deep links, control, App Shortcut), the attach dialog, and the long-press context menu are all untouched and their tests must stay green.
- **Build:** `xcodegen generate` (new `CaptureViews.swift`); both lanes build; `cd ExpenseCore && swift test`; full app test run per CLAUDE.md commands.
- **Manual:** light/dark, XL Dynamic Type, expanded + inline accessory placements, tip appears once after first scan-save and never again after opening the sheet; verify against the amended `ui-spec.html` via the `design-spec` preview server.

## 9. Acceptance criteria

1. Tapping the capture accessory bar still opens the document scanner in **one tap**, in both expanded and inline placements — no chooser inserted.
2. The accessory's trailing zone shows an **ellipsis glyph with a visible "More" caption** (expanded), separated from the scan button by a hairline, with a ≥ 44pt target; a tap near it never fires the camera.
3. Tapping More — or the toolbar `+` on Folders/Receipts — opens the **same** Add Receipt sheet at medium detent: "Add receipt" title, "Adding to <destination>" caption, a LedgerGreenSoft hero Scan panel with a small saturated Ledger Green camera chip, and three labeled rows (Choose photo / Import file / Enter manually) each with a one-line explanatory caption. The `capture.add.title` confirmationDialog and the accessory's system `Menu` no longer exist.
4. Selecting any sheet option dismisses the sheet, then presents the correct flow (scanner / photos picker / file importer / manual review form); the receipt lands in the destination the sheet displayed. Sheet-over-sheet never occurs.
5. Long-press on the bar still offers the direct Photo/File/Manual context menu.
6. After the first successful scanned-receipt save, a one-time tip appears anchored to More; opening the sheet from any door (or dismissing the tip) retires it permanently.
7. The sheet uses system sheet material — the app still has exactly two custom glass elements; single brand accent, no red, no white text on saturated green, Dynamic Type only, no `colorScheme` branches; all eight new strings resolve from the String Catalog.
8. VoiceOver: each option is one labeled element with its caption as the value; the whole capture → review → save path remains completable.
9. `DESIGN.md`, `design/ui-spec.html`, and `PRD.md` §5 are amended in the same change; `xcodegen generate` + both build lanes + ExpenseCore and app test suites pass.
