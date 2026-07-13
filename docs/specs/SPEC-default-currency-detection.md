# SPEC — Default currency: detect at first launch, pick (never type) everywhere

**Status:** proposed
**Owner screens:** Onboarding welcome (`IntelliExpense/UI/OnboardingViews.swift`), Settings (`IntelliExpense/UI/SettingsView.swift`), no change to receipt review behavior beyond what it already reads
**Docs this spec amends:** `design/ui-spec.html` (onboarding welcome mock — currency row; new currency-picker sheet section; settings mock — currency row becomes a picker entry), DESIGN.md §4 (new shared component: searchable currency picker), PRD §5 (settings row description; first-launch currency seeding note)

---

## 1. Problem

Two related failures for a globally shipped app:

1. **The default currency is a free-text field.** Settings today exposes `defaultCurrencyCode` as a plain `TextField` with autocapitalization — the user can type `INR`, but also `RS`, `₹`, `rupees`, or nothing. There is no validation, no localized currency names, no discoverability of valid codes. Every downstream consumer (capture pipeline, review form prefill) trusts this string.
2. **A user in India (or anywhere non-US) must find Settings and manually fix the default.** The seed value is `Locale.current.currency?.identifier ?? "USD"`, which is actually correct for a device set to the India region — but the user never *sees* that a default was chosen, so they can't trust it; and for the mismatch cases (device region ≠ working currency, e.g. an en_US-configured phone used in India) the wrong default silently flows into every scanned receipt until the user notices bad data on the review screen.

The robust shape: **detect confidently, show the detection at first launch, make correcting it one tap, and make the correction surface a real picker.**

## 2. Goals

- On first launch the app derives the default currency from the device locale and **shows it to the user during onboarding** with a one-tap change affordance — no extra onboarding screen, no forced choice.
- Currency is **always chosen from a picker** (localized currency names + ISO code + symbol, searchable), never typed. Same picker component in onboarding and Settings.
- The stored value is always a valid ISO 4217 code; detection logic and its fallback order are deterministic and testable.
- Zero network use (app ground rule); zero location-services use (privacy, and physical location is the wrong signal anyway — see D4).

## Non-goals

- No currency *conversion*, no multi-currency totals (PRD §2 non-goals — unchanged).
- No per-trip default currency (a trip inherits nothing; the app default prefills the review form exactly as today).
- No re-prompting when the user travels or changes device region after first launch — the default is seeded once and thereafter owned by the user (Settings). Per-receipt currency remains editable at review, which is where travel is actually handled.
- No change to how extraction-detected currency wins over the default in the merge (existing behavior: extracted currency, else default).

## 3. Design decisions

### D1 — Detection: device locale currency, seeded once

Source of truth for detection is Foundation's locale currency (`Locale.current.currency` — the currency of the user's chosen region, honoring any per-locale currency override the user set at the OS level; iOS 16+, verified against the docset). Fallback order, applied at first launch only:

1. Device locale currency identifier, if present and ISO-valid.
2. Otherwise `USD`, and the onboarding row visibly shows it as a *suggestion* needing confirmation (same UI either way; nothing special to build).

Seeding happens **once**, guarded by a persisted "currency seeded" flag alongside the existing `defaultCurrencyCode` app-storage value — not by re-evaluating the locale on every launch. Rationale: `Locale.current` is a launch-time snapshot of the device region setting; re-deriving on later launches would silently overwrite a deliberate user choice when the device region changes. After seeding, the value is user-owned.

Existing installs (value already present in app storage): the seeded flag is set retroactively without touching the stored value — upgrade is a no-op for current users, including the owner's own INR setting.

### D2 — Onboarding: confirm-in-place, not an extra screen

The existing welcome screen (`OnboardingWelcomeView`) gains one compact row in the footer cluster, between the privacy label and the Continue button (slot defined in SPEC-onboarding-welcome-redesign D5, which governs that screen's layout): a currency chip/row showing the detected currency — symbol, localized display name, and code (e.g. "₹ · Indian Rupee · INR") — with a "Change" affordance that opens the currency picker (D3) in a sheet. Continue accepts whatever is shown.

Why this shape and not a dedicated "choose your currency" onboarding step: detection from the device region is correct for the overwhelming majority of users, so a mandatory picker screen is pure friction that mostly asks people to confirm the obvious. Showing the detection makes it *trusted* (fixes problem 2's silent-default issue) while keeping onboarding at its current length. The mismatch minority gets a one-tap correction at the exact moment the app introduces itself.

Apple Intelligence gating (PRD §5.0/§6.4) is untouched — the currency row lives on the welcome screen, before/independent of the availability gates.

### D3 — The currency picker (shared component, replaces the Settings text field)

One picker component used by both the onboarding sheet and Settings:

- **Data**: the full ISO currency set from Foundation (`Locale.Currency.isoCurrencies`, filtered to real ISO currencies), each rendered as localized display name (via the locale's localized currency-name lookup) + ISO code + symbol. Names come from Foundation, **not** the String Catalog — they are data, not UI chrome; only the picker's own labels (title, search prompt, section headers) are catalog strings. This keeps the "adding a language is a pure translation task" rule intact, since Foundation localizes currency names for free.
- **Structure**: a searchable list (search matches name, code, and symbol), with a small **Suggested** section pinned on top containing the device-locale currency and the currently selected value, then the full alphabetical list. No "popular currencies" editorializing beyond that.
- **Selection**: single tap selects and dismisses (sheet context) or updates the checkmark row (Settings push context — implementer's choice of presentation, behavior identical).
- **Settings**: the `settings.defaultCurrency` row becomes a navigation/label row showing the current selection ("Indian Rupee · INR") that opens this picker. The free-text `TextField` is deleted. If a legacy stored value is not a known ISO code (possible with the old text field), the row shows the raw code and the picker opens with nothing checked — first selection repairs it.

### D4 — Signals considered and rejected

- **StoreKit storefront** (App Store account region): tied to the user's *payment* region, not their expense currency; requires StoreKit and account state; wrong for a receipts app and adds a dependency for a worse signal.
- **Location services / geo-IP**: physical location is the wrong signal (a traveler in Vienna on a work trip still reports expenses in their home-currency ledger — or the trip currency, which is per-receipt anyway); location permission is a privacy cost the PRD's no-network, on-device ethos shouldn't pay; geo-IP requires network calls, which are banned outside CloudKit.
- **Re-deriving from locale on every launch**: overwrites deliberate user choice; rejected in D1.

Device region is the one signal that is user-chosen, stable, offline, permission-free, and already currency-bearing.

### D5 — Documentation amendments (same commit as the implementation)

- **DESIGN.md §4** gains the component rule for the shared picker: *"Currency picker: searchable inset-grouped list, Suggested section pinned on top, rows show localized name + ISO code + symbol (Foundation-localized, never hardcoded), single-accent checkmark selection, Dynamic Type only. Currency is always picked, never typed."*
- **design/ui-spec.html**: onboarding welcome mock gains the currency row (detected value + Change); a new currency-picker sheet section (search field, Suggested section, alphabetical list); the Settings mock's currency text field becomes a picker entry row showing the current selection.
- **PRD §5**: settings row description updated to "picker" and one sentence added on first-launch seeding from the device locale.

No DESIGN.md rule conflicts: the row and picker use standard inset-grouped list treatments, existing tokens, the single brand accent for selection state, and no new colors, glass, or fixed sizes. Constraining rules honored and cited in D2/D3: single brand accent, Dynamic Type only, locale-formatted data never hardcoded, all UI chrome strings in the String Catalog.

## 4. Edge cases

- **Locale with a currency override** (custom locale components / `@currency=` identifiers): Foundation's locale currency already reflects the override; detection honors it automatically.
- **Locale with no currency** (rare region-less configurations): fallback to `USD` per D1; the onboarding row still renders and invites change.
- **Non-ISO legacy stored value** (from the old text field): handled in D3 — displayed raw, repaired on first picker selection. No migration pass rewrites data behind the user's back.
- **RTL and long currency names**: the row shows name with standard truncation; the picker list rows wrap normally under Dynamic Type. Symbols render via the locale, never hardcoded (CLAUDE.md money rules).
- **Onboarding skipped** (`-SkipOnboarding` launch flag / UI-test lanes): seeding still runs at first launch regardless of whether the welcome screen was shown — detection must not depend on the onboarding UI being visited. Sandbox lane seeds its own deterministic value so screenshots are stable.

## 5. Accessibility & localization

New string-catalog keys (labels only — currency names/symbols come from Foundation):

| Key | Value |
|---|---|
| `onboarding.currency.label` | Default currency |
| `onboarding.currency.change` | Change |
| `currencyPicker.title` | Currency |
| `currencyPicker.search` | Search currencies |
| `currencyPicker.suggested` | Suggested |

`settings.defaultCurrency` key reused; its row becomes a picker entry (value display, not input).

Accessibility: the onboarding row is one VoiceOver element reading label + selected currency + "Change" action; picker rows read "name, code, selected/not selected". Identifiers: `onboarding.currency.row`, `currencyPicker.list`, `currencyPicker.search`, `settings.currency.row`. Dynamic Type only; no fixed sizes.

## 6. Test impact

- **Unit tests** (ExpenseCore or app target, behind a protocol/fake for the locale so no real device dependency, per CLAUDE.md testability rule): detection fallback order (locale currency → USD); seed-once semantics (second launch does not overwrite a changed value; region change after seeding does not overwrite); retroactive flag for existing installs preserves the stored value; legacy non-ISO value handling.
- **UI tests**: onboarding shows the currency row and Continue persists it; Change opens the picker, search finds "rupee"/"INR", selection updates the row; Settings row opens the same picker and the old text field is gone; a scanned/manual receipt's review form prefills the chosen default when extraction found no currency (existing behavior, now asserted).
- **Manual**: device set to India region (expect INR), US region (USD), a currency-override locale, light/dark, AX5.

## 7. Acceptance criteria

1. Fresh install on an India-region device: the welcome screen shows Indian Rupee as the default with no user action; Continue lands the user with `INR` prefilled on their first scanned receipt.
2. Fresh install with device region ≠ desired currency: the user can change the default in ≤ 2 taps from the welcome screen without visiting Settings.
3. Currency can no longer be typed anywhere; every entry point is the shared searchable picker; the stored default is always a valid ISO 4217 code after any picker interaction.
4. Upgrading an existing install never changes the user's stored currency.
5. Changing device region after first launch never silently changes the app default.
6. No network calls, no location permission, no StoreKit dependency introduced; all new UI strings are in the String Catalog; currency names/symbols are Foundation-localized, never hardcoded.
7. All new unit and UI tests pass; existing review-form merge behavior (extracted currency wins over default) is unchanged and covered.
8. DESIGN.md §4, `design/ui-spec.html`, and PRD §5 are amended per D5 in the same change — the shipped UI and the canonical docs never diverge.
