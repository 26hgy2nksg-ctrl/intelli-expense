# SPEC — Quick Capture widget (Home Screen, four capture actions)

**Status:** proposed
**Owner screens/targets:**
- `IntelliExpenseControls/` — new `QuickCaptureWidget.swift` added to the existing `IntelliExpenseControlsBundle` (`ScanReceiptControl.swift:44-49`); the widget-extension target already exists in both lanes.
- `IntelliExpense/App/DeepLinkRouting.swift` — new shared `CaptureKind` enum; `AppDeepLinkRoute.capture` gains a kind; `DeepLinkRequestState` carries the requested kind.
- `IntelliExpense/ContentView.swift` — `handleExternalCaptureRequest(_:)` (`:408-413`) dispatches by kind instead of hardcoding `.cameraScan`.
- Extension string catalog (`IntelliExpense/Resources/AppShortcuts.xcstrings`, already shared into the Controls target via `project.yml`) — widget gallery + tile labels.
- `project.yml` — add `QuickCaptureWidget.swift` and a target-owned `IntelliExpenseControls/WidgetAssets.xcassets` (LedgerGreen/LedgerGreenSoft, for the extension bundle — see D4) under both control targets' `sources:`; `CaptureKind`/`DeepLinkRouting.swift` already shared. No new target, no new App Group.

**Docs this spec amends:**
- `PRD.md` §5 (capture entry points: add the Home Screen widget as a fourth system surface alongside the control and App Shortcut).
- `design/ui-spec.html` — new section `#capture-widget` ("Quick Capture on the Home Screen") with medium + small mockups in light and dark, and a behavior/deep-link table.
- `DESIGN.md` — §4 Components (new "Quick Capture widget" entry), the System-surface note (distinguish system-chromed *controls/tiles* from app-rendered *Home Screen widgets*), §6 glass budget clarification (widgets are not in-app glass), and a `home_screen_widget` block in the machine-readable frontmatter.

**Related specs:**
- `SPEC-scan-receipt-everywhere.md` — built `ScanReceiptIntent` (`OpenIntent`) + the control + App Shortcut and the `intelliexpense://capture` route this spec extends. That spec listed "No Home Screen or Lock Screen widgets … separate spec if ever" as a non-goal; **this is that spec.**
- `SPEC-share-extension-import.md` — origin of the `intelliexpense://` deep-link pattern both specs reuse.

---

## 1. Problem

The app's binding rule is that *capture must never be blocked at a cash register* (PRD §6.4). The scan-everywhere work put a single **Scan Receipt** doorway on the Lock Screen, in Control Center, and on the Action button — but only *scan*, and only surfaces the user has to go hunting for (Control Center pull-down, a Lock Screen slot, the Action-button binding). The one place a user actually looks first — the **Home Screen** — offers nothing beyond the app icon, which drops them on the last tab they used, not into capture.

Meanwhile the app already has four first-class ways to bring a receipt in — **Scan document · Choose photo · Import file · Enter manually** (PRD §5; the capture accessory's primary button + ⋯ menu, `ContentView.swift:847-919`). All four are one deep tap inside the app, but zero taps are reachable from the Home Screen. A receipt that isn't captured in the moment fades, gets lost, or never makes the expense report.

iOS gives exactly one Home-Screen affordance that can place several app actions under the user's thumb without opening the app first: a **WidgetKit widget** whose regions are `Link`s into the app. The app defines no widgets today.

## 2. API grounding (offline Apple docset, version 24703; symbol paths + the lines actually read)

- **Open-the-app interactions use `Link`, not App-Intent buttons.** *Adding interactivity to widgets and Live Activities* (`/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities`), the **Important** callout: "An interaction with a button or toggle should do more than open the app. **If you want to offer an interaction that opens the app, use `Link` … and `widgetURL(_:)`.**" All four capture actions *open the app* (a scanner, a photo picker, a file importer, and a manual-entry sheet all live in the app process and cannot run in the widget process), so the widget is built from `Link`s, and this feature adds **no new App Intents.**
- **Small and medium both support multiple tap targets.** *Linking to specific app scenes from your widget or Live Activity* (`/documentation/widgetkit/linking-to-specific-app-scenes-from-your-widget-or-live-activity`): "For widgets with enough space for more than one interaction target — `WidgetFamily.accessoryRectangular`, **`WidgetFamily.systemSmall`**, and larger system family sizes — add one or more `Link` controls … If an interaction targets a `Link` control, the system uses the URL in that control. For interactions anywhere else in the widget, the system uses the URL you specify in the `widgetURL(_:)` view modifier." So both `.systemSmall` and `.systemMedium` can carry all four actions; a whole-widget fallback `widgetURL` still routes stray taps.
- **`containerBackground(for:)` is required.** Same interactivity doc's sample (the Emoji Rangers widget) applies `.containerBackground(for: .widget) { … }`; iOS 17+ widgets must declare a container background or they render blank in several contexts.
- **`WidgetBundle` hosts mixed widget kinds.** `IntelliExpenseControlsBundle` (`ScanReceiptControl.swift:44-49`) is already a `@main WidgetBundle` in a `com.apple.widgetkit-extension`. A bundle may vend any mix of `Widget` and `ControlWidget`; the new `QuickCaptureWidget` (a `StaticConfiguration` `Widget`) joins it — no second extension target.
- **`StaticConfiguration` / `.never` timeline.** The widget shows no data (see Non-goals) — it is a fixed action launcher. It uses `StaticConfiguration` with a one-entry provider and `.never` refresh; there is no App Group, no SwiftData, no CloudKit read, and therefore no widget memory-budget or refresh-cadence risk.
- **Routing carrier — existing, unchanged in shape.** `AppDeepLinkRoute` parses host `capture` → `intelliexpense://capture` (`DeepLinkRouting.swift:3-36`); `ContentView` observes a per-open request-ID (`captureOpenRequestID`) and dispatches in `handleExternalCaptureRequest` (`ContentView.swift:408-413`). This spec threads a `kind` through that same channel.

## 3. Goals

- A **Home Screen widget** that puts all four capture actions — **Scan · Photo · File · Manual** — one tap from the Home Screen, each opening the app straight into that flow.
- Two families: **`.systemMedium`** (all four, glyph + label, in a row) and **`.systemSmall`** (all four, a 2×2 glyph-and-label grid). Both offer the same four actions; only the arrangement changes.
- Feels like the app, not a bolt-on: the Scan action carries the single Ledger Green brand accent exactly as the in-app capture accessory does; the other three are quiet secondary tiles, mirroring the accessory's primary-button-plus-overflow hierarchy.
- Reuses the existing `intelliexpense://capture` route (extended with `kind`) and every existing gate: onboarding wins, camera-permission-denied shows the existing denied view, transient Apple Intelligence unavailability never blocks capture (PRD §6.4).
- Ships in both lanes (durable + sandbox) with per-lane URL schemes; no new target, no new App Group, no signing change to `make install-device`.

## Non-goals

- **No data on the widget.** No trip totals, counts, recent receipts, thumbnails, or "hero number." This is a pure action launcher; showing spend data would violate the PRD non-goal ("no analytics dashboards, charts beyond simple totals") and drag in an App Group + SwiftData read the launcher doesn't need. A data/summary widget, if ever, is a separate spec.
- **No configurable destination trip.** v1 attaches a widget capture to the same destination the in-app external-capture path already uses (`captureDestinationGroup`, nil when launched cold → Unfiled). A `AppIntentConfiguration` "capture into trip X" widget is deferred, exactly as the scan-everywhere spec deferred "scan into trip X."
- **No new App Intents.** The four actions are `Link`s (§2). Exposing Photo/File/Manual to Siri/Spotlight/Shortcuts (new `AppShortcut`s) is a separate, additive scope — out of scope here.
- **No Lock Screen accessory widgets.** `accessoryCircular/Rectangular/Inline` are monochrome, system-tinted, and the Lock Screen scan doorway already exists via the control (scan-everywhere). A four-action launcher does not fit monochrome accessory families; see D6.
- **No `.systemLarge`.** Four actions do not earn large's area without inventing filler or data (a non-goal). Medium is the richest honest size; see D6.
- **No change to the in-app capture UI.** The accessory bar, the "+" menu, and the four flows are untouched; the widget is a new front door onto the same rooms.

## 4. Design decisions

### D1 — A Home Screen widget, built from `Link`s into the existing route

The widget is a `StaticConfiguration` `Widget` named **Quick Capture** whose body is four tappable regions, each a SwiftUI `Link` whose destination is `intelliexpense://capture?kind=<scan|photo|file|manual>` (sandbox: `intelliexpense-sandbox://capture?kind=…`). Per §2 this is Apple's prescribed shape for open-the-app interactions and needs **no App Intent**; per §2 both supported families can host multiple `Link`s. A whole-widget `widgetURL` set to the Scan URL catches any stray tap outside a tile.

Rationale (cite the rule it satisfies): DESIGN.md's capture model is "one primary Scan action + Photo/File/Manual in the overflow." The widget reproduces that exact hierarchy rather than inventing a new one, and it reuses the one uniform channel — the `capture` deep link — that already behaves identically from the control (extension process), Spotlight/Siri (app process), and the share extension. Adding App-Intent buttons here would both contradict Apple's guidance and duplicate a routing channel that already works.

### D2 — `CaptureKind`: one shared enum threaded through the existing request-ID channel

Today the route is scan-only: `AppDeepLinkRoute` has a bare `.capture`, the intent enum `ScanReceiptDestination` has only `.capture`, and `handleExternalCaptureRequest` hardcodes `startAccessoryCapture(sourceType: .cameraScan)` (`ContentView.swift:408-413`). This spec adds a single shared enum **`CaptureKind { scan, photo, file, manual }`** in `DeepLinkRouting.swift` (already compiled into both the app and the widget target), and:

- `AppDeepLinkRoute.capture` carries a `CaptureKind`. Parsing reads the `kind` query item; **absent or unrecognized ⇒ `.scan`** (backward-compatible: the existing control, App Shortcut, and their tests keep working unchanged, because bare `intelliexpense://capture` still means scan).
- `DeepLinkRequestState` carries the requested kind alongside the existing `captureOpenRequestID`; the per-open request-ID idempotency and the `DeepLinkRequestGate` are unchanged.
- `handleExternalCaptureRequest` switches on the kind and calls the flow that already exists for it — no new capture code:

  | `CaptureKind` | Existing method (`ContentView.swift`) | Presents |
  |---|---|---|
  | `.scan` | `startAccessoryCapture(sourceType: .cameraScan)` `:386` | VisionKit document scanner (or camera-denied view) |
  | `.photo` | `startAccessoryCapture(sourceType: .photoImport)` | `PhotosPicker` |
  | `.file` | `startAccessoryFileImport()` `:428` | `fileImporter` (image/PDF) |
  | `.manual` | `startAccessoryManualEntry()` `:433` | manual `ReceiptReviewForm` sheet |

`CaptureKind` maps 1:1 onto the existing `ReceiptAttachmentSourceType` for scan/photo/file and adds the `manual` case the pipeline enum deliberately omits. The tab-normalization and `canStartExternalCapture` guards in the dispatcher are preserved (see Edge cases).

Rationale: one enum, one parse point, one dispatch point — the smallest change that turns a scan-only doorway into a four-action doorway, and it keeps the widget target free of app models (it only constructs URLs from `CaptureKind`).

### D3 — Visual design: the app's hierarchy, rendered as a widget (this is where "native and not out of place" is won)

The widget is **app-rendered content**, not a system-chromed control, so — unlike the control and the Spotlight tile — it follows the app's own tokens. It earns "classy, not out of place" by copying the capture accessory's exact hierarchy and restraint:

- **One brand family, rationed — Scan is the hero.** Scan is treated like the in-app capture accessory: a **small saturated Ledger Green camera chip** (white glyph) with the word **"Scan"**, sitting on a calm **LedgerGreenSoft** panel. Photo/File/Manual are quiet **LedgerGreenSoft** tiles (the app's selected-chip / onboarding-tile token) with **Ledger Green glyphs** and `label`-color text. This is one hue at two intensities — and the **only saturated fills are small chips** (Scan's camera chip, and on small its filled tile), never a large green slab — which reads as personality while still satisfying DESIGN.md's "single brand accent / brand is rationed" rule (one hue, not a four-color rainbow, no expense-type colors). **No white text ever sits on the saturated Ledger Green** — white-on-Ledger-Green fails contrast in dark mode (§6), so the chip carries only the contrast-tolerant white glyph; every word lives on soft-green or the neutral surface. *(Revised twice: from the original gray `quaternarySystemFill` tiles (read as disabled → moved into the green family), then from a large filled-green hero panel (too bright/loud in dark mode → softened to a soft panel + small chip) — see D6.)*
- **Glyphs (SF Symbols, paired with the app):** Scan `camera.viewfinder` (matches the accessory's primary button, `ContentView.swift`), Photo `photo`, File `doc` (deliberately **not** `folder` — folders read as *trips* in this app; `doc` avoids the collision), Manual `square.and.pencil`.
- **Labels:** short single words — **"Scan", "Photo", "File", "Manual"** — in footnote/caption weight. The full phrases live in VoiceOver (D-A11y). The medium hero shows "Scan" beneath its camera chip on the soft-green panel (contrast is comfortable on soft-green, unlike on the saturated fill); its VoiceOver label is the full "Scan a receipt".
- **Container background:** a calm semantic surface via `.containerBackground(for: .widget)` (`systemBackground`-class), **never a Ledger Green flood** and never a gradient — the green lives on the tiles, the card stays quiet. Corners are the system's concentric widget radius; tiles use a continuous system radius.
- **Typography & spacing:** Dynamic Type text styles only (no fixed sizes); base-4/8 spacing; glyph tiles on a consistent `@ScaledMetric` size step. No hero number (there is no number).

**Family layouts** (same four actions, same primary-plus-overflow hierarchy — only arrangement changes, per the design principle that families share structure):

- **`.systemMedium`** — the flagship. **Scan is a large LedgerGreenSoft hero panel** (leading) holding a small saturated Ledger Green camera chip + the "Scan" label, and Photo/File/Manual are a **vertical overflow list** beside it (each a soft-green glyph tile + label) — the in-app capture accessory's primary-button-plus-overflow, rebuilt at widget scale. Each region (the hero panel and each list row) is a `Link` tap target ≥ 44pt.
- **`.systemSmall`** — a 2×2 grid of the four tiles (Scan top-leading as the anchor), glyph above a short label. Scan is the filled Ledger Green tile; the other three are soft-green tiles. Each cell is a `Link` (≈72pt cell ≥ 44pt minimum target). At the largest Dynamic Type sizes, small drops labels to glyph-only (VoiceOver still speaks the full label).

### D4 — Reuse the existing widget extension; add no target, no App Group

`QuickCaptureWidget` is added to the existing `IntelliExpenseControlsBundle` in the `IntelliExpenseControls` extension (and its Sandbox twin). The extension is already a `widgetkit-extension`, already embeds into both apps, and already shares `DeepLinkRouting.swift` + `AppShortcuts.xcstrings` (`project.yml`). Because the widget shows no app data, it needs **no App Group entitlement** (the Controls extension has none today, and this keeps it that way) and no SwiftData/CloudKit access. Per-lane `kind` URLs are built from the same compile-time scheme split the route already uses (`DeepLinkRouting.swift`).

**Brand colors in the extension bundle.** The widget renders brand color (`LedgerGreen`, `LedgerGreenSoft`), and an app extension is a separate bundle whose `Bundle.main` is the `.appex` — it cannot read the app's asset catalog at runtime. So a small, target-owned catalog `IntelliExpenseControls/WidgetAssets.xcassets` (the two color pairs, byte-matching the app's values, plus an `AccentColor` alias) is listed under **both control targets' `sources:`** (this xcodegen setup only bundles resources listed under `sources:`, and merges catalogs by basename — hence a *uniquely named* catalog, not another `Assets.xcassets`). Verified in the built `.appex` with `assetutil`. This is not a new App Group and not a new target — just the color the widget draws with.

Considered and rejected: a dedicated new `IntelliExpenseWidgets` extension (two more targets, two more bundle IDs, provisioning, embedding) — no benefit for a dataless widget that a one-file addition to the existing bundle delivers.

### D5 — Copy and localization (extension catalog, mirroring app copy)

Following the scan-everywhere precedent (its D5: extension/App-Intents strings live in the target's own catalog, not the app UI's `Localizable.xcstrings`), the widget's user-facing strings live in the **extension's `AppShortcuts.xcstrings`** (already wired into the Controls target). New keys, English values (full table in §6): gallery `widget.quickCapture.displayName` = "Quick Capture", `widget.quickCapture.description`; tile labels `widget.capture.scan/photo/file/manual` = "Scan"/"Photo"/"File"/"Manual"; VoiceOver labels `widget.capture.*.a11y` mirroring the app's full phrasing. Keys are never renamed for copy changes; adding a language stays a pure translation task spanning this one extra catalog. No user-facing string is hardcoded in the widget.

### D6 — Considered and rejected

- **Lock Screen accessory widgets** (`accessoryCircular/Rectangular/Inline`): monochrome and system-tinted, so they cannot carry the Scan/secondary hierarchy that makes this widget legible; and the Lock Screen already has the scan control from scan-everywhere. Four tiny monochrome targets on a Lock Screen rectangle is poor ergonomics. Out of scope.
- **`.systemLarge`:** four actions cannot fill large without filler or data (a non-goal). Medium is the largest honest size.
- **App-Intent `Button`s instead of `Link`s:** contradicts Apple's explicit guidance (§2) — App-Intent buttons are for interactions that do *more* than open the app — and would duplicate the working `capture` route. Rejected.
- **A green (brand-flooded) widget *background*:** loud, off-system, and would make the glyphs fight the fill; also breaks "brand is rationed." The green lives on the tiles, never the container.
- **Gray (`quaternarySystemFill`) secondary tiles** *(original plan, revised — see D3):* shipped first and read as **disabled/blah**, especially in dark mode where a gray glyph on a faint gray fill barely separates from the surface. Moving Photo/File/Manual into the **LedgerGreenSoft** family (soft-green tile + Ledger Green glyph) keeps the widget in one hue at two intensities — alive and cohesive — without a second color. Still one brand hue, still no rainbow.
- **A large filled Ledger Green hero *panel*** *(shipped once, revised):* a ~45%-width solid `#34C08A` slab read as **too bright/loud** in dark mode — a brand flood on one tile that fought the calm dark Home Screen. Softened so the large area is **LedgerGreenSoft** and only a small camera **chip** is saturated (the in-app accessory shape). Keeps Scan the hero without the glare.
- **White *text* on the saturated Ledger Green:** rejected on contrast — white-on-`#34C08A` (dark mode) ≈2:1, fails WCAG. The saturated chip shows the white *glyph* only; "Scan" and all other words sit on soft-green / the neutral surface.
- **Four differently-colored tiles (using the expense-type palette):** those colors mean *expense type* (Food/Hotel/Flight/Taxi/Other) everywhere else — reusing them for capture actions would break "color that always means the same thing becomes navigation." Rejected; one green family instead.
- **`folder` for Import file:** collides with the app's trips-as-folders metaphor; `doc` instead.
- **Configurable "capture into trip X" widget** and **exposing Photo/File/Manual to Siri/Spotlight:** deferred (Non-goals) — additive follow-ups, not part of "add the widget."

## 5. Edge cases

- **Widget tapped mid-scan or mid-review (unsaved work on screen):** the existing `canStartExternalCapture` guard (`ContentView.swift:415-426`) and the review flow's save/discard protection apply unchanged — the capture request is dropped and in-progress work is never discarded, regardless of kind.
- **Widget tapped before onboarding completes / at a blocking Apple Intelligence gate:** the gate wins; the pending capture kind is dropped, not queued (first-run users must see the gates), matching scan-everywhere D1.
- **Scan tapped with camera permission denied:** existing `CameraPermissionDeniedView` with its Open Settings path. Photo/File/Manual don't touch the camera and proceed regardless — a denied camera never blocks the other three.
- **Transient model-downloading state:** capture proceeds (PRD §6.4); the widget never checks Apple Intelligence availability.
- **Cold launch (app not running):** the `Link` URL is delivered to `.onOpenURL` after the scene connects; the request-ID channel fires once. Same cold path the scan control already relies on.
- **Repeated taps / same kind twice:** the per-open request-ID makes dispatch idempotent; a second identical tap re-presents at most once and never stacks scanners/pickers.
- **Bare `intelliexpense://capture` (from the existing control/App Shortcut) with no `kind`:** parses to `.scan` — existing behavior and tests unchanged.
- **Unknown/garbage `kind` value:** falls back to `.scan` (never an error, never a dead tap).
- **Destination trip:** a widget capture uses the same `captureDestinationGroup` logic as any external capture (nil when launched cold → Unfiled). The widget does not choose a trip in v1.
- **StandBy / CarPlay:** the small widget may appear in StandBy and (if the user adds it) CarPlay; its `Link`s open the app per system behavior. Nothing special is built; no data means nothing sensitive is shown on a shared surface.
- **Sandbox lane:** widget builds in the Sandbox bundle and emits `intelliexpense-sandbox://capture?kind=…`, opening the sandbox app only.

## 6. Accessibility & localization

**Accessibility identifiers / VoiceOver:**
- Each tile is a single VoiceOver element whose label is the *full* action phrase, not the short visible word: "Scan a receipt", "Choose photo", "Import file", "Enter manually". The glyph is decorative (`accessibilityHidden`); the label carries meaning.
- Widget gallery entry supplies `.configurationDisplayName` ("Quick Capture") and `.description` for the add-widget picker.
- Tap targets meet the 44pt minimum in both families (medium column ≈ 80pt; small cell ≈ 72pt).
- **Dynamic Type:** text styles only, no fixed sizes, no `minimumScaleFactor` hack. Medium labels stay one line and truncate if needed; small drops labels to glyph-only at the largest AX sizes while VoiceOver retains the full label. Layout stays four targets at every size.
- **Dark mode / contrast:** semantic surfaces + the `LedgerGreen` / `LedgerGreenSoft` asset pairs (both compiled into the widget extension's own `WidgetAssets.xcassets` — the extension bundle can't read the app's catalog). White **text** is never placed on Ledger Green: at the dark-mode value `#34C08A`, white-on-green measures ≈2:1 and fails WCAG, so the hero carries only a white *glyph* (a shape, not text) and all words sit on the neutral surface or a soft-green tile (Ledger Green glyph / `label` text — both high-contrast). Re-verify soft-green tile and glyph contrast under Increased Contrast and Reduce Transparency. No `colorScheme` branches; nothing reflows in dark.

**Localization — new keys in `AppShortcuts.xcstrings` (English values):**

| Key | English value | Notes |
|---|---|---|
| `widget.quickCapture.displayName` | Quick Capture | Widget gallery title |
| `widget.quickCapture.description` | Scan, choose a photo, import a file, or enter a receipt by hand. | Widget gallery description |
| `widget.capture.scan` | Scan | Visible tile label (medium; small when it fits) |
| `widget.capture.photo` | Photo | Visible tile label |
| `widget.capture.file` | File | Visible tile label |
| `widget.capture.manual` | Manual | Visible tile label |
| `widget.capture.scan.a11y` | Scan a receipt | VoiceOver label |
| `widget.capture.photo.a11y` | Choose photo | VoiceOver label |
| `widget.capture.file.a11y` | Import file | VoiceOver label |
| `widget.capture.manual.a11y` | Enter manually | VoiceOver label |

No changes to the app's `Localizable.xcstrings`. Locale-dependent data does not appear on the widget (no dates, money, or numbers), so no Foundation-formatter concerns. `CaptureKind` raw values (`scan/photo/file/manual`) are URL tokens, never localized.

## 7. Test impact

- **Unit (extend `IntelliExpenseTests/DeepLinkRoutingTests.swift`):** `intelliexpense://capture?kind=scan|photo|file|manual` parses to `.capture(<kind>)`; bare `capture` → `.capture(.scan)`; unknown kind → `.capture(.scan)`; per-lane scheme split (durable vs `-sandbox`) preserved. `DeepLinkRequestState.apply` carries the kind and consumes the request-ID exactly once.
- **Unit (new, pure):** `CaptureKind` → URL round-trips per lane (the function the widget uses to build each `Link`), so the widget's URLs are verified without instantiating WidgetKit.
- **Unit (dispatch):** `handleExternalCaptureRequest` selects the matching flow per kind and respects `canStartExternalCapture` (extend the seam so the scan/photo/file/manual selection is assertable, mirroring the existing scan test in `ScanReceiptIntentTests.swift`).
- **UI (`IntelliExpenseUITests`):** launch with each `?kind=` deep link → lands on capture and presents the expected flow, asserted via deterministic outcomes (scan → camera-denied fallback in the simulator; photo → `PhotosPicker`; file → `fileImporter`; manual → review form). Deep link during review does not discard the review sheet. Deep link before onboarding shows welcome.
- **Regression:** existing `ScanReceiptIntentTests` and the scan control path stay green (bare `capture` == scan).
- **Build:** `xcodegen generate` after `project.yml` touch-ups; both schemes build; the widget renders in both families (Xcode preview / add-widget gallery); the widget embeds in both lanes and does not break `make install-device` or `make install-device-sandbox`.

## 8. Acceptance criteria

1. A **Quick Capture** widget is available in the Home Screen add-widget gallery in **medium** and **small** sizes, titled and described from the string catalog, in both lanes.
2. **Medium** shows Scan as a large soft-green hero panel (a small Ledger Green camera chip + "Scan" label) with Photo/File/Manual as an overflow list beside it; **small** shows the same four as a 2×2 grid. In both, tapping a region opens the app straight into that flow — scanner, photo picker, file importer, or manual-entry form respectively.
3. **Scan** is the hero — a small saturated Ledger Green camera chip + label on a soft-green panel (the only saturated fills are small chips; no large green slab, no white text on green); Photo/File/Manual are soft Ledger-Green-tinted tiles with Ledger Green glyphs — one green family at two intensities, no gray, so the widget reads as the capture accessory's primary-plus-overflow hierarchy and is at home on the Home Screen in light and dark, including Increased Contrast and Reduce Transparency.
4. The widget adds **no App Intent, no App Group, no SwiftData/CloudKit access, and no new extension target** — it is one `StaticConfiguration` `Widget` of `Link`s added to the existing `IntelliExpenseControlsBundle`, routing through `intelliexpense://capture?kind=…`.
5. Every existing gate holds: onboarding and blocking Apple-Intelligence gates win; camera-denied shows the existing view for Scan while Photo/File/Manual proceed; transient model-downloading never blocks; an in-progress scan or unsaved review is never discarded by a widget tap.
6. Bare `intelliexpense://capture` still means scan; the existing control, App Shortcut, and their tests are unaffected. Unknown `kind` falls back to scan.
7. All widget strings are localized via `AppShortcuts.xcstrings`; no hardcoded user-facing strings; no expense-type colors reused for actions; no red; no gradient; no Ledger Green background flood.
8. `PRD.md` §5, `design/ui-spec.html` (`#capture-widget`), and `DESIGN.md` (§4 component + system-surface distinction + §6 glass note + frontmatter) are amended in the same change; `xcodegen generate` + both build lanes + all tests pass.
