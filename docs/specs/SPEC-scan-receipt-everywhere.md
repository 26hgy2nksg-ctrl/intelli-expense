# SPEC — Scan Receipt from anywhere (App Intent + Control + App Shortcut)

**Status:** proposed
**Owner screens/targets:** app routing (`IntelliExpense/ContentView.swift` — deep-link handling, capture presentation), new intents definition shared between targets, new widget-extension target for the control (`project.yml` + `xcodegen`), Info.plists (URL scheme host)
**Docs this spec amends:** PRD §5 (capture entry points gain "system surfaces" sentence), `design/ui-spec.html` (new short section: system-surface appearances — control glyph/label, Spotlight tile), DESIGN.md §7-equivalent iconography note (control symbol + tint rule)
**Related specs:** SPEC-share-extension-import.md (established the `intelliexpense://` deep-link pattern this spec extends)

---

## 1. Problem

The app's own binding rule is that *capture must never be blocked at a cash register* (PRD §6.4) — yet today capture requires: find the icon → open the app → land on the right tab → start the scanner. Every step is friction at exactly the moment the user is holding a paper receipt with one hand and a card terminal receipt printer is already spitting out the next customer's slip. Users of receipt apps consistently report "I forgot / couldn't be bothered to scan it at the time" as the top failure, and the receipt then fades or vanishes.

iOS gives exactly one mechanism that puts a single app action on the Lock Screen, in Control Center, on the Action button, in Spotlight, and in Siri/Shortcuts: an **App Intent**, exposed through a **control** and an **App Shortcut**. The app currently defines no intents at all.

## 2. API grounding (offline Apple docset, version 24703; symbol paths + Platforms lines as read)

- `AppIntent` — `/documentation/appintents/appintent` — iOS 16.0+. The single action definition; `perform()` carries out the work.
- `supportedModes: IntentModes` — `/documentation/appintents/appintent/supportedmodes` — **iOS 26.0+**. The modern way to declare foreground behavior ("determine whether the intent performs its action in the background, the foreground, or a combination"). The app is iOS 26-only, so this is used **instead of** the legacy `openAppWhenRun` (iOS 16+); the two must not be mixed.
- `OpenIntent` — `/documentation/appintents/openintent` — iOS 16.0+. Per *Creating controls in your widget extension* (`/documentation/widgetkit/creating-controls`): "Set your control's action to an app intent that conforms to `OpenIntent` to open your app when someone uses a control … take someone to a specific area of your app."
- `ControlWidget` / `StaticControlConfiguration` / `ControlWidgetButton` — `/documentation/widgetkit/staticcontrolconfiguration`, `/documentation/widgetkit/controlwidgetbutton` — iOS 18.0+. The same doc states the reach explicitly: "A control allows your app to execute an action, launch your app to a specific view, or launch a locked camera capture extension **from Control Center, the Lock Screen, or by using the Action button**." One control, three system surfaces. Controls live in a **widget extension** target and are buttons (`ControlWidgetButton` + `OpenIntent`) here — not toggles (`SetValueIntent` is for stateful controls, wrong shape for "scan now").
- `AppShortcutsProvider` / `AppShortcut` — `/documentation/appintents/appshortcutsprovider`, `/documentation/appintents/appshortcut` — iOS 16.0+. Zero-setup exposure in Spotlight, Siri, and the Shortcuts app; `AppShortcut(intent:phrases:shortTitle:systemImageName:)` with phrases that must embed the `\(.applicationName)` token; provider offers `shortcutTileColor` for the Spotlight/Shortcuts tile.
- `LockedCameraCapture` — `/documentation/lockedcameracapture` — iOS 18.0+: "create an extension that allows people to launch your app's camera experience … when the device is locked." Evaluated and **rejected for this pass** (D6).

## 3. Goals

- One **Scan Receipt** action reachable from: Lock Screen control slot, Control Center, Action button, Spotlight search, Siri/Shortcuts ("Scan a receipt in Intelli-Expense") — and it drops the user **directly into the document scanner**, not merely into the app.
- Honors every existing gate in order: onboarding not completed → welcome screen; camera permission denied → the existing `CameraPermissionDeniedView`; Apple Intelligence transiently unavailable → capture proceeds anyway (PRD §6.4 — capture is never blocked; extraction degrades later).
- Ships in both lanes: durable app and sandbox app, with correctly namespaced extension bundle IDs and the sandbox URL scheme.
- Zero new persistent UI inside the app — this feature is entirely system-surface.

## Non-goals

- No locked-device capture extension (D6) — the control opens the app (device unlock is implied by the system when needed).
- No configurable control (no "scan into trip X" parameter) — one static action; the capture flow's existing destination logic (most recent trip / Unfiled) applies unchanged. `AppIntentControlConfiguration`-based configurability is a possible follow-up, not v1.
- No Home Screen or Lock Screen *widgets* (timeline/accessory widgets showing trip totals) — that's a display feature, separate spec if ever.
- No other intents (export, search, add-manual-expense) — one intent, done excellently; a broader App Intents catalog (including Apple Intelligence/Siri integration) is future work.

## 4. Design decisions

### D1 — One intent, one meaning: open the app into the document scanner

A single `ScanReceiptIntent` (final name implementer's choice, one intent only) conforming to `OpenIntent`, with `supportedModes` declaring foreground behavior (D2 grounding: iOS 26 API; do not also set the legacy `openAppWhenRun`). Its `perform()` does no capture work itself — it routes the app to the capture flow and returns. Capture, permissions, and pipeline all remain the app's existing code; the intent is a doorway, not a second pipeline.

Routing mechanism: extend the **existing deep-link pattern** — the app already handles `intelliexpense://shared-inbox` (sandbox: `intelliexpense-sandbox://`) in `ContentView`'s URL handling with a request-ID trigger the tab view observes. Add a `capture` host that switches to the capture tab and presents the document scanner, following the same request-ID idiom so repeated invocations re-trigger presentation. Rationale: the control's intent executes in the widget-extension process — a URL the app already routes is the one mechanism that behaves identically whether the invocation came from the control (extension process), Spotlight/Siri (app process), or a future Shortcuts automation.

Scanner-direct, with graceful ladder: if onboarding is incomplete, land on the welcome screen (the pending capture request is dropped, not queued — a first-run user must see the gates); if camera permission is denied, present the existing denied view with its Open Settings path; otherwise present the VisionKit document scanner immediately. Apple Intelligence availability is *not* checked on this path — per PRD §6.4 capture always proceeds.

### D2 — The control: one button, three system surfaces

A new widget-extension target hosts a `ControlWidget` whose body is a `StaticControlConfiguration` containing a single `ControlWidgetButton` driving the intent. Per the docset, this one control is what users can place in **Control Center**, assign to a **Lock Screen** control slot (replacing e.g. the flashlight), and bind to the **Action button** — no separate work per surface exists or is needed.

Appearance: SF Symbol `document.viewfinder` (receipt-in-frame reading; matches the icon's scan-frame motif) with label "Scan Receipt". Controls render with system-defined styling; the app supplies symbol + label only — no custom colors (the system tints controls; the brand lives in the app and icon, and this also keeps the no-`colorScheme`-branches rule trivially satisfied).

### D3 — The App Shortcut: Spotlight, Siri, Shortcuts for free

An `AppShortcutsProvider` in the app target exposes the same intent as an `AppShortcut` with `shortTitle` "Scan Receipt", `systemImageName` matching D2's symbol, and phrases embedding the application-name token (e.g. "Scan a receipt in ⟨app⟩", "⟨app⟩ scan", "New receipt in ⟨app⟩"). This makes the action appear in Spotlight results as the user types the app name, and utterable to Siri, with zero user setup — the documented behavior of App Shortcuts. `shortcutTileColor` is set to the closest system color to Ledger Green from the fixed tile palette.

### D4 — Two lanes, two schemes, correct nesting

The extension exists in both app variants via `project.yml`: bundle IDs nest under their host app (`com.nags.intelliexpense.controls`, `com.nags.intelliexpense.sandbox.controls`), and the sandbox extension's intent opens `intelliexpense-sandbox://capture` — the scheme split already exists in the app's URL handling and Info.plists; the intent definition reads its scheme the same compile-time way. The sandbox lane keeps its reset-by-default install behavior; `make install-device` / `make install-device-sandbox` remain the verification lanes.

### D5 — Copy and localization

Intent title, control label, shortcut short title, and dialog-free behavior mean very few strings — but App Intents metadata (intent title, App Shortcut phrases) is localized through the **App Shortcuts / App Intents string mechanism** (`LocalizedStringResource` values and an `AppShortcuts.xcstrings` catalog in the target that defines the shortcuts), *not* through UI `Localizable.xcstrings` keys. This is the documented App Intents localization path and keeps "adding a language is a pure translation task" true — the translation task just spans one additional catalog. English values: title/label/shortTitle **"Scan Receipt"**; phrases per D3.

### D6 — Considered and rejected

- **`LockedCameraCapture` extension** (iOS 18+): genuinely captures while locked, but requires a *separate capture UI extension* with its own camera implementation and constrained storage handoff (content is handed to the app for processing after unlock), duplicating the capture flow the app already has in VisionKit — and the receipt pipeline (SwiftData, Apple Intelligence, review UI) needs the unlocked app anyway. Cost/benefit fails for v1: the control gets the user from Lock Screen to scanner in one tap + Face ID glance. Revisit only if real usage shows the unlock step losing receipts.
- **Legacy `openAppWhenRun`**: superseded by `supportedModes` on an iOS 26-only target (§2); using both is contradictory.
- **`SetValueIntent`/toggle control**: controls docs reserve toggles for stateful features; scanning is a fire-once action → button.
- **Widget (timeline) showing trip total with a scan button**: display feature, PRD dashboard-adjacent; out of scope here.
- **NotificationCenter/shared-defaults signaling instead of the deep link**: breaks for the extension-process invocation path; the URL route is the one uniform channel and is already load-bearing for the share extension.

## 5. Edge cases

- **Intent fired while the app is already showing the scanner**: the request-ID trigger re-presents idempotently — no stacked scanners, no dismissal of an in-progress scan (a scan in progress wins; the request is ignored).
- **Intent fired mid-review (unsaved receipt on screen)**: the review flow's existing save/discard protection applies; the capture request must not discard user work — it is dropped with the review sheet left intact.
- **Onboarding/gate states**: D1 ladder; a blocked-gate state (device ineligible) shows the existing gate screen — the intent never bypasses it.
- **Control placed, app later deleted from Lock Screen context**: system behavior (control grays out/removes); nothing to build.
- **Locked device, control tapped**: system prompts unlock, then the app opens to the scanner — acceptable and standard; explicitly the D6 trade-off.
- **UI-test/`-SkipOnboarding` lanes**: deep-link `capture` host is exercisable directly (open URL in test), no intent invocation needed in tests.

## 6. Accessibility & localization

- Strings: D5 — App Intents catalog entries (title, phrases, short title); no new `Localizable.xcstrings` keys. Control label and Spotlight tile inherit these.
- The control button and shortcut tile are system-rendered — VoiceOver, Dynamic Type, and increase-contrast handling come from the system; the app's obligation is a meaningful label ("Scan Receipt") and a legible symbol, both specified.
- New accessibility identifier: none in-app (no new in-app UI); the scanner presentation reuses existing capture-flow identifiers.

## 7. Test impact

- **Unit tests**: URL routing — `capture` host triggers the capture request ID exactly once per open, unknown hosts ignored, scheme split per lane (extend the existing shared-inbox routing tests if present; add them if not).
- **UI tests**: launching with the `capture` deep link lands on the capture tab with the scanner presentation triggered (assert via the camera-permission-denied fallback in simulator, which is deterministic); deep link during review does not discard the review sheet; deep link before onboarding completion shows welcome.
- **Manual (device)**: place the control in Control Center and a Lock Screen slot, bind to Action button; verify one-tap-to-scanner from all three cold and warm; Spotlight "scan" under the app name shows the shortcut; Siri phrase works; sandbox lane variant opens the sandbox app. Verify the widget-extension target does not break `make install-device`.
- **Build**: `xcodegen generate` after `project.yml` changes; both schemes build; extension embeds correctly in both lanes.

## 8. Acceptance criteria

1. From a locked iPhone with the control in a Lock Screen slot: one tap + unlock lands in the document scanner. Same single-tap behavior from Control Center and the Action button — all served by one `ControlWidget`.
2. Typing "scan" or the app name into Spotlight surfaces the Scan Receipt shortcut; the Siri phrase containing the app name runs it — with zero prior user setup in the Shortcuts app.
3. The intent never bypasses onboarding or permission gates, never blocks on Apple Intelligence availability, and never discards an in-progress scan or unsaved review.
4. Both lanes ship the feature with correctly nested extension bundle IDs and per-lane URL schemes; the sandbox control opens the sandbox app only.
5. The intent uses `supportedModes` (iOS 26 API), conforms to `OpenIntent`, and contains no capture/pipeline logic — verified by the routing being the same deep-link path the share extension established.
6. All intent/control/shortcut strings are localized via the App Intents string-catalog mechanism; no hardcoded user-visible strings; no new colors or in-app UI.
7. PRD §5, `design/ui-spec.html`, and the DESIGN.md iconography note are amended per the header in the same change; `xcodegen generate` + both build lanes + all tests pass.
