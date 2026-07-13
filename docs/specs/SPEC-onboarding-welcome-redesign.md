# SPEC — Onboarding welcome screen: real icon, sharper story, tighter composition

**Status:** proposed
**Owner screens:** Onboarding welcome (`IntelliExpense/UI/OnboardingViews.swift`, `OnboardingWelcomeView`); icon still asset in `IntelliExpense/Resources/Assets.xcassets` (new imageset exported from `AppIcon.icon`)
**Docs this spec amends:** `design/ui-spec.html` (onboarding welcome mock — full redesign of the section), DESIGN.md §6 (one-time onboarding reveal motion rule)
**Related specs:** SPEC-default-currency-detection.md D2 places the currency row on this screen; this spec defines its slot (D5).

---

## 1. Problem

Field evidence: device screenshot of the current welcome screen (dark mode). Five distinct problems, in severity order:

1. **The screen shows a counterfeit app icon.** The hero image is a flat `LedgerGreen` rounded rectangle with the `receipt` SF Symbol — a hand-drawn approximation of the icon. The shipped icon (`AppIcon.icon`, Icon Composer layered format) is materially different: a deep-green *gradient* field, a receipt sheet with specular lighting and translucency, ledger marks, and a scan frame. The user launches the app by tapping the real icon and is greeted one second later by a lookalike that is visibly not it. Apple's own welcome screens (Mail, Notes, TestFlight, Journal) always show the true icon — it's the continuity handshake between Home Screen and first run.
2. **The story skips the magic.** The pipeline is scan → **on-device AI extraction** → confirm → export, and the app *requires Apple Intelligence* (the very next onboarding screen may gate on it). Yet the three feature rows — Capture / Confirm / Export — never mention intelligence at all. "Check each extracted field" assumes the user already knows extraction happens. The differentiator (AI that never leaves the device) is the one thing this screen doesn't say, and the gate screen that may follow lands without setup.
3. **Title and subtitle are redundant with the rows.** The subtitle ("Scan a receipt. Confirm the details. Export the trip.") is a compressed duplicate of the three row titles directly beneath it. Apple's welcome pattern is title + rows, no subtitle — the rows *are* the summary. The duplication also causes the awkward two-line wrap with the "the trip." orphan.
4. **Dead composition zone.** A single `Spacer` between the rows and the privacy footnote leaves ~25% of the screen empty on tall devices; the content reads top-heavy with a hole at two-thirds height.
5. **No AX-size fallback.** The screen is a fixed `VStack` with spacers; at large accessibility type sizes the content will compress/clip rather than scroll.

## 2. Goals

- The hero is the **actual app icon** — pixel-faithful to the Home Screen artwork, correct in light and dark.
- The screen tells the true story in three beats: capture → on-device intelligence + user confirmation → export, so the Apple Intelligence gate (if it follows) is expected rather than surprising.
- Composition has no dead zone at any supported height and scrolls at accessibility sizes.
- A restrained one-time reveal animation that respects Reduce Motion — polish, not spectacle.
- The screen keeps its slot for the default-currency row (SPEC-default-currency-detection D2) with a defined position.
- Constraining DESIGN.md rules, cited and honored throughout: single brand accent, no red, Dynamic Type only (all sizes via text styles / `@ScaledMetric`), base-4/8 spacing grid, semantic + token colors with no `colorScheme` branches in feature code, two-element glass budget untouched (this screen uses none).

## Non-goals

- No multi-page onboarding, no page dots, no video/lottie. One screen, one Continue.
- No change to the Apple Intelligence gate/preparing screens or camera-permission screen (same file, out of scope).
- No change to onboarding *flow* (welcome → gates → app) or to `hasSeenWelcome` semantics and launch flags.
- No marketing-speak rewrite of the privacy footnote — its current sentence is exactly right.

## 3. Design decisions

### D1 — Real icon via an exported still (the `.icon` file can't be rendered live)

Icon Composer `.icon` files are composed by the system at build/run time for the Home Screen; they are not loadable as in-app images. So the same Icon Composer project exports a flattened 1024pt still into a new imageset (light + dark appearance variants, matching the icon's own light/dark fill specializations). The welcome screen renders it at ~96–104pt (`@ScaledMetric`, relative to `.largeTitle`), masked with the standard continuous-corner squircle approximation (corner radius ≈ 22.5% of side), with a soft ambient shadow (black at low opacity, small y-offset) so it sits *on* the screen like a physical object rather than floating flat.

Maintenance rule (this is the anti-drift clause): the imageset is regenerated **in the same commit** whenever `AppIcon.icon` artwork changes — the acceptance criteria make a stale still a review failure. Sandbox target shares the same resources, so the sandbox lane inherits it automatically.

Considered and rejected: reading the composed icon out of the bundle at runtime (fragile against the `.icon` pipeline, yields Home-Screen-masked bitmaps at icon sizes, wrong for a 100pt+ hero); keeping the SF Symbol tile (the problem being fixed).

### D2 — Copy: title becomes a welcome, subtitle is removed, the middle row gains the intelligence beat

String-catalog changes (values on stable keys, per the localization anti-drift rule; one key retired):

| Key | Current value | New value |
|---|---|---|
| `onboarding.welcome.title` | Intelli-Expense | **Welcome to Intelli-Expense** |
| `onboarding.welcome.subtitle` | Scan a receipt. Confirm the details. Export the trip. | **(removed — key deleted; rows carry the summary)** |
| `onboarding.bullet.capture.title` | Capture | *(unchanged — matches the app's own tab vocabulary)* |
| `onboarding.bullet.capture.subtitle` | Use the document scanner, photo library, or a receipt file. | **Scan with the camera, or bring in photos and files.** |
| `onboarding.bullet.confirm.title` | Confirm | *(unchanged)* |
| `onboarding.bullet.confirm.subtitle` | Check each extracted field before anything is saved. | **On-device intelligence fills in the merchant, date, and total — you check every field before it's saved.** |
| `onboarding.bullet.export.title` | Export | *(unchanged)* |
| `onboarding.bullet.export.subtitle` | Create a finance-ready zip when the trip is done. | *(unchanged — already the strongest line on the screen)* |
| `onboarding.privacy` | Everything happens on your device. Data syncs only to your private iCloud. | *(unchanged)* |

Rationale for the Confirm line: it introduces the AI (so a following "enable Apple Intelligence" gate has context), reasserts user control ("you check every field" — the PRD's review-first principle), and quietly reinforces the privacy claim ("on-device") that the footnote then completes. "Intelligence" deliberately echoes Apple Intelligence without naming the feature — the gate screens do the naming.

Row symbols unchanged (`camera.viewfinder`, `checkmark.seal`, `square.and.arrow.up`); considered `sparkles` for the Confirm row and rejected — the seal is the review-and-approve metaphor, and sparkles would make the row read as "AI does it for you," the opposite of the confirm-first message.

### D3 — Composition: three anchored bands, no dead zone

The screen becomes three vertical bands inside the existing 24pt padding:

1. **Identity band** (top third, centered): icon still → `Welcome to Intelli-Expense` in `.largeTitle.bold()` (up from `.title` — this is the app's one welcome moment; Apple's welcome screens use large title), wrapping to two lines naturally ("Welcome to" / "Intelli-Expense" at default sizes). The app name may carry the brand accent color only if it occupies its own line; otherwise the whole title stays primary-label color — never a mid-line color switch.
2. **Story band** (middle, vertically centered in the space between identity and footer): the three rows, current `OnboardingBullet` layout unchanged (soft-green icon tile, semibold subheadline title, footnote subtitle). Centering the *band* — rather than stacking it under the title and leaving a bottom hole — is what removes the dead zone across device heights.
3. **Footer cluster** (pinned bottom): privacy `Label` → currency row (D5, when that spec ships) → Continue button, with 16pt internal spacing. The button keeps `.borderedProminent` + `.controlSize(.large)` + brand tint; considered the iOS 26 glass-prominent treatment and rejected — DESIGN.md's glass budget is reserved and this screen earns nothing by spending it.

The whole screen gains a scroll fallback: content scrolls only when it doesn't fit (accessibility sizes, shortest devices), with the footer cluster joining the scroll content rather than overlapping it. At standard sizes nothing scrolls and the bands hold their anchors.

### D4 — Motion: one staggered reveal, once, and only if motion is welcome

On first appearance only: the icon settles in with a gentle scale-and-fade (from ~0.9, no bounce past 1.0), then the title, the three rows (in order, ~80ms apart), and the footer cluster fade-and-rise a few points. Total sequence under a second; nothing loops; nothing moves after settling. With Reduce Motion enabled, the sequence is replaced by a plain simultaneous fade (opacity only — no scaling or translation). The reveal never plays again (not on re-appearance within the session, not for `-SkipOnboarding`/UI-test lanes, which render the settled state immediately so tests never wait on animation).

This adds a motion pattern the design system doesn't document yet, so DESIGN.md §6 gains the rule: *"One-time reveals (onboarding): staggered fade-and-rise, ≤1s total, settle and stop; Reduce Motion replaces all movement with opacity-only fades; never used on recurring screens."*

### D5 — Slot for the default-currency row

When SPEC-default-currency-detection ships, its currency row sits in the footer cluster **between the privacy label and the Continue button** — it is a decision the user confirms on the way out, not part of the app's story, so it belongs with the footer furniture, not the feature rows. Until that spec ships, the footer cluster is privacy label + button only; this spec must not block on it.

## 4. Edge cases

- **Icon artwork changes later** (rebrand, seasonal variant): D1's same-commit regeneration rule; acceptance criterion 6 is the enforcement.
- **Shortest supported device / landscape**: bands compress via their flexible spacing before any scrolling starts; the icon's `@ScaledMetric` never shrinks below its base — if it doesn't fit, the screen scrolls (D3), it never clips.
- **AX5 text sizes**: title wraps to three+ lines, rows grow, screen scrolls; the Continue button remains full-width at the end of the scroll content — verified in the manual pass.
- **Tinted/clear Home Screen icon modes**: the in-app still always shows the full-color light/dark artwork — the welcome hero is the brand, not the user's Home Screen theming; no tinted variant is exported.
- **VoiceOver order**: icon hidden (decorative) → title (header trait) → each row as one combined element (title + subtitle) → privacy → currency row (when present) → Continue.

## 5. Accessibility & localization

- String changes: exactly the D2 table — values on stable keys, one key (`onboarding.welcome.subtitle`) deleted from the catalog and the view. No other keys touched; no new keys.
- Accessibility identifiers: `onboarding.continue` unchanged (UI tests depend on it). No new identifiers required; the icon still is decorative.
- Dynamic Type only: title/rows/footnote keep text styles; icon and row tiles stay on `@ScaledMetric`. No fixed point sizes anywhere.
- Colors: existing tokens only (`LedgerGreen`, `LedgerGreenSoft`, semantic labels); the icon still carries its own light/dark variants via the asset catalog — no `colorScheme` branches in the view.

## 6. Test impact

- **UI tests**: existing flow tests keep passing (`onboarding.continue` unchanged; reveal is disabled in test lanes per D4). Update any test asserting the old title text to "Welcome to Intelli-Expense". Add: welcome screen shows the icon still (image existence by identifier if needed for the assertion) and all three row titles.
- **Unit tests**: none — no logic changes.
- **Manual pass**: light/dark (icon still must match the Home Screen icon side-by-side on device — this is the point of the feature), default and AX5 sizes, Reduce Motion on/off, shortest simulator device, VoiceOver order per §4, sandbox lane screenshot.

## 7. Acceptance criteria

1. The welcome hero is visually identical to the Home Screen icon artwork in both light and dark appearance (side-by-side device check), masked with the standard continuous-corner treatment — the SF-Symbol lookalike tile is gone.
2. The screen reads: Welcome to Intelli-Expense → Capture / Confirm (with the on-device-intelligence line) / Export → privacy footnote → Continue. No subtitle; the word "intelligence" appears exactly once, in the Confirm row.
3. No dead zone: on a current-size device at default type, the vertical gap between the story band and the footer cluster is visually balanced with the gap above the story band (bands are anchored per D3).
4. At AX5 the screen scrolls with nothing clipped; with Reduce Motion the reveal is opacity-only; in UI-test/skip lanes no animation plays.
5. All copy changes live in the String Catalog per the D2 table; `onboarding.welcome.subtitle` is fully removed (view and catalog); no new colors, no glass, no fixed sizes, single accent preserved.
6. The icon-still imageset is generated from the current `AppIcon.icon` artwork, and DESIGN.md §6 + `design/ui-spec.html` are amended per D4/this spec in the same change — shipped UI and canonical docs never diverge. Any future `AppIcon.icon` change that ships without regenerating the still fails review against this criterion.
7. Existing UI tests pass with the title assertion updated; the manual pass checklist in §6 is completed on device.
