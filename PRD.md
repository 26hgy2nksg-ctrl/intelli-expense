# Intelli-Expense — Product Requirements Document

**Version:** 1.3 (adds native Mac app and agent import bridge requirements)
**Date:** 2026-07-05
**Status:** Approved for implementation
**Audience:** The implementation agent building this app. Read this document fully before writing any code.

---

**Changelog note — 2026-07-06:** recorded the native Mac companion and local agent import bridge: app-owned folder drops, review-first structured entries, and provenance-preserving sidecars.

**Changelog note — 2026-07-05:** recorded shipped conformance decisions for the 30-second Foundation Models timeout, crash-safe receipt drafts/archive metadata, and totals-left-to-user CSV export contract.

## 0. Required reading & ground rules for the implementation agent

1. **Start from the production lessons, not the original prototype:**
   A private proof of concept, built and run on a real iPhone, established the feasibility of the pipeline this app productizes: SwiftUI → VisionKit document scan → Vision document OCR (`RecognizeDocumentsRequest`) → deterministic parser → Foundation Models guided generation. The prototype itself is intentionally not part of this repository. Treat its result as evidence only: do not collapse the app into one file, do not keep workflow state in view-local `@State`, do not process only the first page, do not make heuristic parsing or model output authoritative, and do not omit persistence, error states, or deterministic tests.
2. **Survey current Apple documentation before locking API choices** (VisionKit, Vision, Foundation Models, SwiftData, CloudKit, PhotosUI). Every Apple API named in this PRD was validated in the POC era; verify it is still the best current option and prefer newer/better APIs where justified. If local skills such as `apple-platform-think` or `swiftui-design-principles` are available in the session, use them.
3. **Product philosophy:** This is a deliberately simple, single-purpose app. It does one thing — capture and organize personally-paid work-trip expenses for later reimbursement — and must do it excellently. When in doubt, cut scope, not quality. UX polish on the core loop beats breadth of features.

---

## 1. Problem statement

When the user travels for work, they pay with a **personal card or cash** and must keep track of every expense so they can claim reimbursement after the trip. Today this means a pocket full of paper receipts, photos scattered in the camera roll, and manual spreadsheet work. The app replaces that with: capture a receipt in seconds, let on-device AI extract the details, confirm with one glance, and export a finance-ready zip per folder.

**One-line product definition:** A private, on-device iOS app that turns paper receipts into organized, exportable expense folders.

---

## 2. Goals and non-goals

### Goals (must ship)

- G1. Capture receipts via camera document scan, photo-library import, or file import (PDF/image).
- G2. Extract receipt fields on-device using a mature pipeline: Vision document OCR → deterministic parsing → Foundation Models guided generation — **before** the user sees the review screen.
- G3. A world-class review-and-confirm experience: every extracted field visible, editable, and — where the model was unsure — presented as a two-option choice. Nothing is saved without user confirmation. For structured agent entries, the confirmation venue may be the agent conversation only when the user has explicitly disabled in-app review on the Mac; otherwise agent entries land as prefilled drafts.
- G4. Organize receipts into user-created **Folders** in the UI (backed by the generic `ExpenseGroup` model). Browse receipts and totals per folder and per expense type.
- G5. Manual entry of a receipt with minimal fields when no document exists, with the ability to attach a photo/scan later.
- G6. All data stored on-device via SwiftData with CloudKit private-database sync (user's own iCloud); receipt images stored alongside with an explicit relationship between the original document and the extracted record.
- G7. Export a folder's receipts as a zip: date-named folders of receipt images plus a `summary.csv` at the root.
- G8. Per-receipt currency; folder totals displayed per currency (no conversion).
- G9. **Localization-ready from day 1:** the UI ships English-only, but adding a UI language later must be a pure translation task (no code changes), and receipts written in any Apple Intelligence-supported language must extract correctly in v1 — see §3.2.
- G10. Native macOS companion app for file-first receipt import, review, folder browsing, export, and private CloudKit sync with the iPhone app.
- G11. Agent import bridge for trusted local agents: the Mac app publishes a read-only folder manifest using the existing trips protocol fields and ingests receipt file drops through an app-owned folder protocol. Structured drops validate complete user-confirmed records and skip OCR/model extraction; raw drops use the normal pipeline and land pending review.

### Non-goals (explicitly out of scope — do not build)

- Reimbursement/submission status tracking (user decision: track elsewhere).
- Line-item extraction (individual items on a receipt). Only totals-level fields.
- Currency conversion or exchange rates.
- Budgets, spending limits, analytics dashboards, charts beyond simple totals.
- Multi-user, sharing, collaboration, or any server backend beyond the user's private iCloud.
- Accounts, sign-in, or any third-party service. **The app must make zero network calls except CloudKit sync.**
- Android, web, watchOS. (Code should not preclude a future iPad target, but do not build for it.)
- Mileage, per-diem, or non-receipt expense types.
- Shipping translated UI languages beyond English in v1. (The architecture must make adding them trivial — §3.2 — but producing and QA-ing translations is deferred, §11.)
- Direct writes to the SwiftData store by agents, CLIs, plugins, or scripts. External tools may copy files into the bridge inbox only; the app remains the sole persistence and CloudKit-sync writer.

---

## 3. Platform & technical foundation

| Decision | Value | Rationale |
|---|---|---|
| Platform | iPhone and native macOS, iOS/macOS 26.0+ | Foundation Models requires Apple Intelligence; POC targeted iOS 26; Mac is a native SwiftUI companion, never Catalyst |
| Language | Swift 6, strict concurrency | POC-validated |
| UI | SwiftUI, `@Observable` view models on the main actor | Per POC production-shape recommendation |
| Persistence | SwiftData with CloudKit mirroring (private database) | Satisfies "stored locally using CloudKit": data lives on-device and syncs to the user's private iCloud |
| Images | Stored as external-storage binary data on a dedicated attachment model (mirrored to CloudKit as assets) | Keeps the main store lean; explicit relationship to extracted record |
| OCR | Vision `RecognizeDocumentsRequest` (verify against current docs) | POC-proven for receipts; exposes text + table structure |
| AI extraction | FoundationModels `SystemLanguageModel` + guided generation (`@Generable`) | POC-proven; on-device, private |
| Capture | `VNDocumentCameraViewController` (evaluate current alternatives), PhotosPicker, file importer | POC-proven + import goals |
| Distribution gating | Minimum deployment iOS 26.0 **plus** `UIRequiredDeviceCapabilities = [arm64, iphone-performance-gaming-tier]` | Closest available App Store gate to Apple Intelligence hardware — see §3.1 |
| Localization | String Catalog (`Localizable.xcstrings`), Foundation `FormatStyle` formatters, Foundation Models locale APIs (`supportsLocale(_:)`, locale instructions) | Day-1 internationalization readiness — see §3.2 |

**CloudKit constraints the data model must respect** (verify against current SwiftData/CloudKit docs): all relationships effectively optional, no `.unique` constraints, all attributes need defaults or optionality, inverse relationships required. Design the schema for these from day one — retrofitting is painful.

### 3.1 App Store availability gating (product decision: this app requires Apple Intelligence)

Smart extraction is the product. The app should, as far as Apple's tooling allows, **not be offered to devices that can never run Foundation Models**, and should treat Apple Intelligence as a requirement, not an enhancement (see §5.0 and §6.4).

What Apple's tooling actually allows (verified against Apple docs, July 2026 — re-verify at submission time):

1. **There is no `UIRequiredDeviceCapabilities` key for Apple Intelligence.** Apple's capability list (`developer.apple.com/support/required-device-capabilities/`) contains no Apple Intelligence / Neural Engine key, and developers have an open Feedback (FB19366221) requesting one. You cannot gate the App Store on "Apple Intelligence capable" directly.
2. **The closest legitimate gate is `iphone-performance-gaming-tier`** (iOS 17+): Apple defines it as performance "equivalent to the iPhone 15 Pro and iPhone 15 Pro Max" — the same A17 Pro hardware floor as Apple Intelligence on iPhone. Combined with the iOS 26 minimum deployment target, this hides the app from, and prevents installs on, all older iPhones.
3. **Known residual risk:** the gaming tier is a *graphics/sustained-performance* tier, not a Neural Engine tier. Apple Intelligence-capable budget models (e.g. iPhone 16e with a binned 4-core GPU) may or may not be inside it, and the two sets could diverge in future hardware. **At submission time, check the device list for `iphone-performance-gaming-tier` on Apple's Required Device Capabilities page against Apple's current Apple Intelligence device list.** If an Apple Intelligence-capable model is excluded by the key, decide then: keep the key (lose those buyers) or drop it (rely on the in-app gate). Default: keep the key — a smaller honest audience beats one-star "app doesn't work" reviews.
4. **This choice is a one-way door:** App Store rules allow updates to *maintain or relax* capability requirements, never to add new ones. Shipping v1 **with** the key is therefore the safe order; the reverse is impossible.
5. Even with the key, the store gate is **necessary but not sufficient**: the device may be capable while Apple Intelligence is switched off, the model is still downloading, or (edge case) an ineligible device slipped through. Runtime checking via `SystemLanguageModel.default.availability` remains mandatory (§5.0, §6.4).

**Foundation Models availability is not guaranteed at runtime** even on eligible hardware (feature disabled, model download pending). The app gates on it at onboarding (§5.0) and handles transient unavailability gracefully (§6.4).

### 3.2 Internationalization: adding a language must be trivial (day-1 architecture requirement)

v1 ships with an **English UI only**, but two things must be true from the first commit: (a) adding a UI language later is a translation task, never an engineering task; and (b) the extraction pipeline handles **receipts in any Apple Intelligence-supported language in v1** — this is a travel app; a Berlin trip means German receipts regardless of the UI language. Grounded in Apple's article *Supporting languages and locales with Foundation Models* (`/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models`); re-verify at implementation time.

**A. UI localization readiness (English at launch; translation-only to extend):**

1. Every user-facing string lives in a String Catalog (`Localizable.xcstrings`) from day 1 — including accessibility/VoiceOver labels, empty states, error and gate screens (§5.0/§6.4), processing-stage hints, notification/haptic-adjacent toasts, and the `summary.csv` header comment row. No user-facing string literals in view code.
2. Never assemble sentences by concatenating fragments; use format strings with placeholders so word order can change per language. Use the platform's plural/inflection support for count-bearing strings ("3 receipts").
3. All dates, numbers, and money formatted via Foundation `FormatStyle` from `Locale.current` (already required by §7) — never hand-rolled or hardcoded symbols. `Locale.current` also honors the **per-app language** a user can set in Settings; the app must key everything off it and must **not** build an in-app language picker.
4. Layout is RTL-safe by construction: leading/trailing (never left/right), SF Symbols, standard SwiftUI stacks, Dynamic Type (§5.5).
5. **CSV stays a stable machine contract:** `summary.csv` column headers (§8) remain fixed English identifiers in every locale; only the optional comment row is localized. Zip/file naming (§8) stays ASCII-safe and locale-independent.

**B. Multilingual extraction pipeline (must work in v1):**

1. The on-device system language model is **multilingual** — one model understands and generates every Apple Intelligence-supported language; prompts, instructions, and OCR-derived input may be in different languages. Language coverage grows with OS/model versions, so **never hardcode a supported-language list**; query `SystemLanguageModel.supportedLanguages` / `supportsLocale(_:)` if a check is needed.
2. Keep all app-authored prompts, `Instructions`, and the `@Generable` schema — **type names, property names, and `@Guide` descriptions** — in English. Apple treats these as model inputs that must be in a supported language; English is the canonical choice and never changes when UI languages are added.
3. **Locale steering (per Apple's exact-phrase guidance):** when `Locale.current` is not U.S. English, prepend the exact instruction phrase `"The person's locale is \(locale.identifier)."` — this phrase comes from the model's training and reduces multilingual hallucination. Implement it as the single documented `localeInstructions(for:)` helper from the article.
4. Any free-text the model generates that users see (the alternate-value "reason" strings, §6.3) must be requested in the app's current UI language via one explicit, parameterized instruction line (e.g. "You MUST respond in …"); structured fields (dates, `Decimal`, ISO 4217 codes, enum classifications) are language-neutral and need no output-language handling.
5. **Preflight + error handling:** check `SystemLanguageModel.default.supportsLocale()` (defaults to `Locale.current`, including the per-app setting) as part of the availability layer; and at request time catch `LanguageModelSession.GenerationError.unsupportedLanguageOrLocale(_:)` — a receipt can be in a language the model doesn't support even when the UI locale is fine. This error is a **non-blocking degradation** (§6.4): the deterministic results still populate the review screen. Never crash or gate on it.
6. Note from Apple's docs: model guardrails only cover supported languages — unsupported-language content may bypass them. Low risk for receipt text, but do not build any feature that assumes guardrails on arbitrary OCR input.

**C. Deterministic parser localization (§6.2):**

1. All language-specific knowledge — total-label keywords ("TOTAL", "SUMME", "TOTAAL", "合計"…), payment hints, date-format patterns, digit-grouping/decimal conventions — lives in **one extensible per-language data table**, not scattered through parser logic. Adding a receipt language = adding table entries + fixtures, zero parser-code changes.
2. Vision OCR runs with automatic language detection; do not pin recognition languages.

---

## 4. Data model

Keep the confirmed receipt model small. v1 also includes operational draft entities for crash safety and archive metadata on receipts; these support §9 reliability and browsing without expanding the user-facing domain model.

### 4.1 `ExpenseGroup`

The single grouping concept. A "trip" is just a group the user names. (User decision: generic groups, not a dedicated Trip type, to stay expandable.)

| Field | Type | Notes |
|---|---|---|
| `name` | String | Required in UX (validated in UI, optional in schema for CloudKit). e.g. "Berlin — June 2026" |
| `startDate` | Date? | Optional. Lets trip-like groups show a date range and pre-select the active group during capture |
| `endDate` | Date? | Optional |
| `notes` | String? | Optional |
| `createdAt` | Date | |
| `profileIDRawValue` | String | Folder profile ID, default `workTrip`. Existing folders migrate to Work Trip with no user action (§4.7) |
| `categorySnapshotJSON` | String | CloudKit-safe JSON of the folder's ordered visible-category snapshot; empty for pre-profile folders, which resolve to their profile default on read (§4.7) |
| `receipts` | [Receipt] | To-many, inverse of `Receipt.group` |

Derived (computed, not stored): total per currency, count, breakdown by category ID.

The user-facing container is a **Folder** (Folders tab, "New Folder…") — see [SPEC-expense-profiles-and-visible-categories](docs/specs/SPEC-expense-profiles-and-visible-categories.md) §D1.

### 4.2 `Receipt`

| Field | Type | Notes |
|---|---|---|
| `vendor` | String | Shop/merchant name |
| `date` | Date | Date the receipt was issued (not the scan date) |
| `totalAmount` | Decimal | Use `Decimal`, never floating point, for money |
| `currencyCode` | String | ISO 4217 (e.g. "INR", "EUR"). Default: user's locale currency |
| `expenseType` | Enum | `food`, `hotel`, `flight`, `taxi`, `other` — see §4.6 |
| `paymentMethod` | Enum | `card`, `cash` |
| `notes` | String? | |
| `createdAt` | Date | |
| `isArchived` | Bool | Soft archive flag for receipts hidden from active browsing without deleting reimbursement evidence |
| `archivedAt` | Date? | Set when archived; nil when active |
| `group` | ExpenseGroup? | Optional — a receipt may be unfiled ("No folder"); UI surfaces unfiled receipts so they don't get lost |
| `attachments` | [ReceiptAttachment] | To-many. Empty for manual entries until a photo is added later |
| `extraction` | ExtractionRecord? | Nil for pure manual entries |

### 4.3 `ReceiptAttachment`

The original document/photo, related to but separate from the extracted output (explicit user requirement).

| Field | Type | Notes |
|---|---|---|
| `imageData` | Data | `@Attribute(.externalStorage)`; store a processed (perspective-corrected, reasonably compressed) full-resolution image |
| `thumbnailData` | Data? | Small JPEG for lists; generate on save |
| `pageIndex` | Int | Multi-page scans → multiple attachments, ordered |
| `capturedAt` | Date | |
| `sourceType` | Enum | `cameraScan`, `photoImport`, `fileImport` |
| `receipt` | Receipt? | Inverse of `Receipt.attachments` |

### 4.4 `ReceiptDraft` and `ReceiptDraftPage`

Temporary persisted capture state used to make the pipeline crash-safe and cancellation-safe. Drafts store the OCR transcript plus full-resolution page images before the user confirms a receipt. They currently live in the same CloudKit-mirrored SwiftData store as confirmed receipts, including full-resolution image data; that is accepted for v1 so captured images are never silently lost, with future draft-resume polish deferred.

| Field | Type | Notes |
|---|---|---|
| `rawOCRText` | String | Best transcript available so far; may be empty while OCR is still running |
| `createdAt` | Date | Used for stale-draft cleanup |
| `pages` | [ReceiptDraftPage] | To-many, inverse of `ReceiptDraftPage.draft` |
| `imageData` | Data | Full-resolution page image on `ReceiptDraftPage` |
| `thumbnailData` | Data? | Optional preview data on `ReceiptDraftPage` |
| `pageIndex` | Int | Multi-page ordering |
| `sourceType` | Enum | `cameraScan`, `photoImport`, `fileImport` |
| `draft` | ReceiptDraft? | Inverse |

### 4.5 `ExtractionRecord`

Provenance: what the pipeline saw and produced, so the app never silently invents values and debugging/re-extraction stays possible.

| Field | Type | Notes |
|---|---|---|
| `rawOCRText` | String | Full Vision transcript |
| `modelOutputJSON` | String? | Serialized guided-generation result, including per-field alternatives |
| `pipelineVersion` | String | Prompt/schema/parser version stamp for future migrations |
| `extractedAt` | Date | |
| `userCorrectedFields` | [String]? | Field names the user edited before confirming (useful signal; keep cheap) |
| `receipt` | Receipt? | Inverse |

### 4.6 Category (formerly Expense type)

The user-visible concept is **Category**, backed by stable ASCII IDs stored in `Receipt.expenseTypeRawValue` (field name kept for migration safety). The five legacy IDs — `food`, `hotel`, `flight`, `taxi`, `other` — stay canonical and unmigrated. Categories are drawn from a built-in catalog (id, localized display-name key, validated SF Symbol + fallback, and a restrained color role), plus folder-local custom categories. The AI pipeline still classifies into the five legacy types; the review layer maps that onto the chosen folder's visible category set. See §4.7.

### 4.7 Folder profiles & visible categories

Each folder carries a **profile** (a preset, not a rigid type) that seeds an ordered, editable snapshot of visible categories; the folder then owns that list. Profiles (Work Trip, Conference, Client Visit, Home Project, Medical Claim, Vehicle Costs, Business Purchases, Moving, Event, Warranty, Custom) start with 5–8 categories including `Other`, which is always present and pinned last. Users edit visible categories per folder — remove unused defaults, add profile suggestions, browse the full built-in catalog, add folder-local custom categories, and reorder — capped at nine including `Other`, with a reassignment guardrail before removing a category receipts already use. Every screen shows only relevant categories: review selectors show the folder's set, breakdowns show only used categories, filters prioritize visible/used. Full behavior, catalog, and rationale: [SPEC-expense-profiles-and-visible-categories](docs/specs/SPEC-expense-profiles-and-visible-categories.md).

---

## 5. Navigation & screens

**Three tabs + one global capture action.** (User requirement: appropriate number of screens — not too many, not too few.)

```
TabView
├── Tab 1: Folders  (home — the folder-centric view)
├── Tab 2: Receipts (flat list of everything, searchable/filterable)
└── Tab 3: Settings
+ Prominent "Add" affordance available from Tabs 1 & 2
  (evaluate the current iOS tab-bar accessory/center-action patterns;
   fallback: toolbar "+" on both tabs)
```

The bottom accessory remains camera-first: tapping **Scan Receipt** opens the scanner immediately. The accessory **More** trigger and the toolbar **+** on browsing tabs open the **Add receipt** sheet with **Scan document** · **Choose photo** · **Import file** · **Enter manually**, including the current destination before the user chooses a capture path.

The same camera-first action is also exposed as **Scan Receipt** across system surfaces: one App Intent (`OpenIntent`) powers a Control Center / Lock Screen / Action button control, and one App Shortcut powers Spotlight, Siri, Shortcuts, and Action button shortcut assignment. These entry points are only doorways into the existing in-app capture flow via `intelliexpense://capture` (sandbox: `intelliexpense-sandbox://capture`); they do not duplicate scanner, permission, extraction, or save logic. Onboarding and blocking Apple Intelligence gates still win, while the transient model-downloading state remains non-blocking and capture proceeds as usual.

A fourth system surface, the **Quick Capture** Home Screen widget, puts all four capture actions — **Scan · Photo · File · Manual** — one tap from the Home Screen (medium as a row of four, small as a 2×2 grid). Each tile is a `Link` into the same route with a `kind` (`intelliexpense://capture?kind=<scan|photo|file|manual>`; bare `capture` still means scan), opening the app straight into that flow. Like the other surfaces it is a doorway, not a duplicate pipeline, and it shows no data (a launcher, not a dashboard — see §2 non-goals); every gate above applies unchanged. See `docs/specs/SPEC-quick-capture-widget.md`.

### 5.0 First-run onboarding (simple and effective — two screens, one conditional)

Onboarding exists to do exactly two things: tell the user what the app does, and get Apple Intelligence turned on. Nothing else. No feature tour, no account, no permission pre-prompts (camera permission is requested just-in-time at the first scan, per platform convention).

**Screen 1 — Welcome (always shown, once).** App icon, one line of value ("Scan a receipt. Confirm the details. Export the folder."), three short illustrated bullets mapping to the core loop (Capture → Confirm → Export), and a privacy footnote ("Everything happens on your device. Data syncs only to your private iCloud."). It also shows the default currency seeded once from the device locale, with a one-tap **Change** picker. Single button: **Continue**.

**Screen 2 — Apple Intelligence gate (conditional).** On Continue, check `SystemLanguageModel.default.availability` and branch:

| Availability | Behavior |
|---|---|
| `.available` | Skip this screen entirely — user lands in the app. Most users (store gate + AI on by default) never see it. |
| `.unavailable(.appleIntelligenceNotEnabled)` | Friendly full-screen explainer: this app uses Apple Intelligence to read receipts on-device; show the exact path **Settings → Apple Intelligence & Siri → turn on Apple Intelligence**, with an **Open Settings** button. Re-check availability every time the app returns to foreground; the moment it's `.available`, dismiss automatically and continue. **Constraint:** there is no public deep link to the Apple Intelligence settings pane — the button may only use public API (open the Settings app; verify current guidance at implementation time). Do **not** use private `App-prefs:` URLs (App Review rejection risk). |
| `.unavailable(.modelNotReady)` | Non-blocking notice: "Apple Intelligence is getting ready (downloading the on-device model). You can start scanning now — smart extraction switches on automatically when it's ready." Button: **Get started**. User enters the app; pipeline runs in deterministic mode (§6.4) until the model is ready. |
| `.unavailable(.deviceNotEligible)` or unknown | Should be nearly impossible past the store gate (§3.1). Honest full-screen state: "Intelli-Expense needs Apple Intelligence, which this device doesn't support." No dead-end mystery, no crippled mode pretending otherwise. |

The Apple Intelligence gate is not onboarding-only: the same check runs on every launch/foreground, and the same screens are reused if the user later disables Apple Intelligence (§6.4). Onboarding state ("welcome seen") is stored locally (e.g. `@AppStorage`), not in CloudKit.

After onboarding, land on Tab 1 with its empty state inviting the first folder/scan — the empty states (§5.5) carry the rest of the teaching load.

### 5.1 Tab 1 — Folders (home)

UI label for `ExpenseGroup` is "Folder" (tab: Folders); the model stays the generic Group per §4.1.

- List of `ExpenseGroup`s, most recently active first. The UI labels them as folders; the most recently active folder is featured, remaining folders use compact rows with name, date range (if set), receipt count, **total per currency** (e.g. "€420 · ₹3,200"), and tiny expense-type breakdown glyphs.
- Create folder (name + optional dates + notes), rename, edit, delete (delete asks whether receipts should be deleted too or become unfiled — default: unfiled).
- An **"Unfiled"** pseudo-section appears when receipts exist with no group.
- **Folder detail screen:** header with totals per currency and a per-expense-type breakdown (amount + count per type); receipt list below, filterable by expense type and payment method, sorted by receipt date; **Export** button in the toolbar (§8); empty state invites the first scan.

### 5.2 Tab 2 — Receipts

- All receipts, newest first, grouped by month. Row: thumbnail (or expense-type symbol for photo-less manual entries), vendor, date, amount + currency, expense-type badge, folder name.
- Search (vendor, notes) and filters (folder, expense type, payment method, has-photo).
- Tap → **Receipt detail:** full-screen-zoomable image pages, all fields, folder assignment, extraction provenance tucked behind a disclosure ("View original scan text"). Everything editable at any time (user requirement). Manual entries show a prominent **"Add photo"** action (scan/photo/file) that runs the extraction pipeline and offers to fill still-empty fields (never silently overwriting user-entered values — show a diff-style confirm if extracted values conflict).
- Delete with confirmation.

### 5.3 Tab 3 — Settings

Minimal: default currency picker, default payment method, CSV delimiter/decimal style if needed for locale, storage/iCloud status indicator, privacy statement ("All processing happens on your device. Data syncs only to your private iCloud."), app version. On Mac, Settings also includes **Agent entries require in-app review**, default ON; turning it off allows structured agent drops with `userConfirmed: true` to materialize as confirmed receipts at ingestion time. The default currency is seeded once from the device locale at first launch and then user-owned in Settings. No account, no sign-in.

### 5.3a Agent-entered receipts

The Mac app owns the local agent bridge. It writes a read-only manifest beside an app-owned inbox with folder IDs, names, date ranges, receipt counts, currencies, and archived state. The manifest keeps the historical `trips` field names for protocol compatibility. Agents read the manifest, copy originals into the inbox, and write a sidecar; they never edit the app database.

Structured agent entries are complete records: merchant, ISO date, string-decimal total parsed to `Decimal`, ISO currency, expense type, payment method, optional notes, proposed folder, and `userConfirmed`. They run zero OCR, parser, or model calls. If the Mac setting is ON, or if `userConfirmed` is false, the entry becomes a `ReceiptDraft` with every field prefilled and a shared "Needs confirmation" card on both iPhone and Mac. If the setting is OFF and `userConfirmed` is true, the app creates the confirmed `Receipt` directly. In both cases, the extraction record provenance is "Entered by agent" and stores the verbatim sidecar.

Raw drops and sidecar-less files are fallback captures. They go through the normal extraction pipeline and remain pending review; they do not get the structured confirmation card.

### 5.4 Capture & review flow (the heart of the app — invest UX here)

```
Add → capture (scan / photo / file)
    → Processing (OCR → parse → Foundation Models)   [animated, cancellable]
    → Review & Confirm screen
    → Save → lands in folder; success feedback (haptic + subtle confirmation)
```

**Processing screen:** show the captured receipt image immediately with a tasteful progress treatment (e.g. shimmer/scan-line over the image) and stage hints ("Reading text… Understanding receipt…"). Target < 5s p50 on device; must be cancellable (cancel → review screen with whatever is available, even just empty fields + image).

**Review & Confirm screen (world-class, user's explicit priority):**

- Receipt image on top (collapsible, tap to zoom); extracted fields below as a clean form.
- Fields, in order: **Vendor · Date · Total amount · Currency · Expense type · Payment method (card/cash) · Folder · Notes.** Expense type and payment method are explicitly required before saving (user requirement) — expense type via a horizontal chip/segmented selector with symbols; payment method via a two-option toggle.
- **Ambiguity UX (user requirement):** when the model returns two candidates for a field (e.g. two plausible totals or two date interpretations), render that field as **two tappable choice chips** ("₹1,240" / "₹1,420") with a small "which is correct?" affordance; picking one fills the field; an "edit" option allows a third value. At most 2 options per field, at most a few fields in this state — if extraction is worse than that, fall back to empty editable fields rather than a wall of choices.
- Confidence styling: low-confidence or unfilled fields get a subtle attention treatment (never alarming red walls).
- Folder defaults to the currently-open folder (if capture started from a folder detail) or the most recently used / date-matching folder; changeable inline.
- Primary action: single, prominent **Save**. Secondary: **Discard** (confirmation if fields were edited).
- **Duplicate warning (should-have):** if an existing receipt matches vendor + date + amount, show a non-blocking "Possible duplicate" notice with a peek at the existing one.

**Manual entry screen:** the same form, no image, minimal required fields: **amount, date, expense type, payment method** (vendor optional, defaults empty; currency defaults from settings; folder optional). Photo attachable later from receipt detail (§5.2).

### 5.5 UX quality bar (applies everywhere)

- Native-feeling SwiftUI: standard navigation, Dynamic Type, dark mode, VoiceOver labels on every control, haptics on save/confirm, sensible keyboard types (decimal pad for amounts, date pickers for dates).
- Empty states for every list (first-run folder list, empty folder, no search results) with a helpful next action.
- Every failure has a designed state (§6.4) — no dead spinners, no raw error strings.
- Follow the `swiftui-design-principles` skill if available; no AI-slop layouts, no gratuitous gradients or emoji.

---

## 6. Extraction pipeline (functional requirements)

Layered pipeline; each layer improves on the last and none is a single point of failure:

```
Capture → Preprocess → Vision document OCR → Deterministic parser
        → Foundation Models guided generation → Merge & confidence → Review UI
```

### 6.1 Capture & preprocess

- Camera scanning via VisionKit document camera (multi-page supported: every page becomes a `ReceiptAttachment`; extraction runs on all pages' text, concatenated in order — do **not** copy the POC's first-page-only shortcut).
- Photo import (PhotosPicker) and file import (images + PDF; rasterize PDF pages).
- Orientation-correct, perspective-corrected images; compress sensibly (receipts don't need 12MP HEIC).

### 6.2 OCR + deterministic parse

- Vision `RecognizeDocumentsRequest` with language detection and correction (verify current API). Keep the full transcript and document structure (tables) in the intermediate representation.
- OCR remains the deterministic baseline input. When the runtime and model expose image input, the model prompt additionally carries downscaled receipt images (first and last pages at most); stored full-resolution attachments remain unchanged.
- Deterministic parser (evolve the POC's, properly tested): dates (multiple formats, sanity-check not-in-future/not-ancient), amounts (currency symbols/codes, Indian and Western digit grouping, decimal commas), total identification (prefer "TOTAL/GRAND TOTAL/AMOUNT DUE" labels; validate subtotal + tax ≈ total when present), vendor (top-of-receipt heuristics), payment hints ("CASH", "VISA", card masks → payment method suggestion), currency detection (symbol/code, default to locale). The deterministic parse also feeds a compact amount/vendor evidence packet for the model prompt; full raw OCR remains persisted for provenance. All language-specific keywords and format patterns come from the per-language data table required by §3.2-C — never inline in parser logic.
- Deterministic results carry per-field confidence and are the **baseline truth**; the model refines, it does not override silently.

### 6.3 Foundation Models layer

- Check `SystemLanguageModel` availability before every use.
- Single-turn session, short versioned instructions, guided generation with a `@Generable` schema; greedy/stable sampling for factual extraction (per POC learnings; verify current API).
- Prompts, instructions, and the `@Generable` schema stay in English; instructions include the locale-steering phrase and (for user-visible free text) the output-language line, both per §3.2-B. The model receives compact OCR evidence (vendor candidates, amount candidates, parser fields, and tail context) rather than the raw transcript as its primary prompt input. Catch `GenerationError.unsupportedLanguageOrLocale` → deterministic fallback (§6.4).
- **Schema must support ambiguity (user requirement):** for each field, the schema allows a primary value plus an optional single alternate (with a short reason), and an explicit "unknown" — the prompt must instruct the model to (a) never invent values not supported by the OCR text, (b) return an alternate only when genuinely torn between two readings, (c) prefer "unknown" over guessing. Also have the model classify `expenseType` (food/hotel/flight/taxi/other) and suggest `paymentMethod` and `currencyCode`.
- Keep very long transcripts within the roughly 4,000-token context window by truncating or summarizing them; the totals region and header matter most.
- Budget prompts from the model's measured context size and token counts when those APIs are available, reserving space for the guided schema and response; retain the prioritized character-budget fallback for older runtimes.
- Timeout or transient generation failure retries exactly once within a bounded ~32-second combined budget; an image attempt retries text-only. If both attempts fail, proceed with deterministic results only.
- Merge policy has three acceptance tiers: evidence-supported model values, image-grounded plausible values, and rejected values. Deterministic values remain baseline truth; image-grounded values enter at low confidence and never displace a deterministic primary. Text-only vendor/amount values still require compact OCR evidence support, and all dates/currencies pass plausibility validation before merge.

### 6.4 Availability gate + transient degradation (must-have)

**Product stance (user decision):** Apple Intelligence is a requirement, not an enhancement. The app does not offer a permanent "dumb mode" for devices/users that will never have Foundation Models — that is handled by the store gate (§3.1) and the blocking gate screens (§5.0).

**But do not confuse *permanent* ineligibility with *transient* unavailability.** On a fully eligible device with Apple Intelligence on, the model will still be briefly unavailable in real life: right after an OS update while the model re-downloads, under storage pressure, or a single request timing out mid-scan. Hard-blocking capture in those windows would lose the user's receipt at the exact moment they're standing at a cash register — worse than a degraded extraction they'll review anyway on the confirm screen. So:

**Blocking states (gate screens from §5.0, shown at launch/foreground, capture disabled):**

| Condition | Behavior |
|---|---|
| `.deviceNotEligible` | Full-screen "requires Apple Intelligence" state (§5.0). Should be nearly unreachable past the store gate |
| `.appleIntelligenceNotEnabled` | Full-screen enable prompt with Open Settings (§5.0); auto-clears on foreground once enabled |

**Non-blocking transient states (capture and the rest of the app stay fully usable):**

| Condition | Behavior |
|---|---|
| `.modelNotReady` (downloading etc.) | OCR + deterministic parse still run; review screen opens prefilled with deterministic values; subtle one-line note "Smart extraction is getting ready" |
| Image input unavailable | Run the existing text-only model path silently; no notice or gate |
| Model available but request fails/times out (~30s, §6.3) | Same deterministic fallback for that scan; no gate screen, no nagging |
| Receipt text in a language the model doesn't support (`GenerationError.unsupportedLanguageOrLocale`, §3.2-B) | Same deterministic fallback for that scan; subtle one-line note that smart extraction doesn't support this receipt's language yet; review screen opens normally |
| OCR finds no/garbage text ("no receipt detected") | Review screen opens with image attached and empty fields — effectively manual entry with photo; clear message |
| Camera permission denied | Designed state explaining why + button to Settings; photo/file import still offered |
| iCloud unavailable | App fully functional locally; quiet status in Settings; sync resumes automatically |

The deterministic parser (§6.2) is therefore still a required, tested component — it is the safety net for transient windows and the baseline the model refines, even though it is no longer a permanent operating mode.

Every stage is unit-testable behind protocols with real-receipt fixtures (see §9).

---

## 7. Totals & browsing requirements

- Folder totals: sum of `totalAmount` **per currency** — never sum across currencies (user decision: no conversion). Display multi-currency totals as separate amounts.
- Per-expense-type breakdown within a folder: amount + count per type, same per-currency rule.
- Tab 2 filters must compose (e.g. folder = "Berlin" AND type = taxi AND cash).
- Formatting: always locale-aware currency formatting from `currencyCode`; never hardcode symbols.

## 8. Export (functional requirements)

Per folder (and for "Unfiled"), from folder detail → Export:

```
Berlin-June-2026.zip
├── summary.csv
├── 2026-06-14/
│   ├── 2026-06-14_Lufthansa_EUR-420.00.jpg
│   └── 2026-06-14_Hotel-Adlon_EUR-180.00_p2.jpg   ← page 2 of multi-page
├── 2026-06-15/
│   └── 2026-06-15_Manual-Entry_EUR-12.50.txt      ← photo-less receipt: stub with its details
└── ...
```

- **Folders named by receipt-issue date** (`YYYY-MM-DD`, user requirement).
- Image filenames: `date_vendor_currency-amount[_pN].jpg` — sanitize vendor for filesystem safety; disambiguate collisions with a numeric suffix.
- **`summary.csv`** columns: `date, vendor, expense_type, payment_method, currency, amount, group, notes, has_image`. One row per receipt, sorted by date. UTF-8 with BOM (Excel-friendly), RFC-4180 quoting. Totals are deliberately left out of the file so the CSV remains one row per receipt; the localized header comment row states that amounts are original-currency per-receipt values and totals are left to the reader.
- Photo-less manual receipts still appear in the CSV and get a small `.txt` stub in their date folder so the zip is a complete record.
- Deliver via the system share sheet (AirDrop, Mail, Files…). Generate in a temp directory, clean up after. Show progress for large folders; must handle 200+ receipts without blocking the UI.

## 9. Non-functional requirements

- **Privacy:** all OCR and model inference on-device; images and data only in the user's private iCloud via CloudKit; zero third-party/analytics network calls. State this in Settings.
- **Performance:** capture-to-review p50 < 5s, p95 < 12s on a supported device; list scrolling smooth with 1,000+ receipts (thumbnails, lazy loading); export of a 50-receipt folder < 10s.
- **Reliability:** no data loss on crash mid-pipeline — persist the attachment + raw OCR as soon as available; a crash before confirm should leave a resumable "draft" the user can finish or discard on next launch (nice-to-have: full draft resume; must-have: never lose a captured image silently).
- **Money correctness:** `Decimal` end-to-end; currency-aware formatting; amounts round-trip through CSV without precision loss.
- **Internationalization hygiene (enforced, §3.2):** no user-facing string literals outside the String Catalog (audit with Xcode's string-catalog compiler checks / a lint rule); verify layout and strings with pseudolocalization and an RTL smoke pass before release, even though v1 ships English-only.
- **Testing:** unit tests for parser (fixture transcripts from real receipts: Indian GST, EU VAT, US, crumpled/partial, **plus at least two non-English fixtures — e.g. a German and a French or Japanese receipt — exercising the per-language keyword table**), merge policy, CSV/zip generation, totals math; UI tests for the capture→review→save happy path and manual-entry path. Foundation Models calls behind a protocol with a deterministic fake for tests; the availability check behind the same protocol so every §5.0/§6.4 state (available / not enabled / not ready / not eligible / unsupported receipt language) is testable without real hardware states.
- **Code shape:** feature-folder structure per the POC guide's "Recommended Production Shape" (adapted as needed), services behind protocols, `@Observable` view models, no singletons for testable logic.

## 10. Acceptance criteria (definition of done)

1. Scan a real paper receipt → within seconds see a review screen prefilled with vendor, date, total, currency, suggested expense type and payment method → adjust nothing or anything → Save → receipt appears in the chosen folder with image attached.
2. A field the model was unsure about shows exactly two tappable candidate values; picking one fills the field; manual override is always possible.
3. Create "Berlin June 2026" folder; add 5 receipts (mixed EUR cash/card); folder header shows correct per-currency, per-type totals.
4. Enter a taxi expense manually with only amount/date/type/payment; later attach a photo from the camera roll; extraction offers values without overwriting the manual ones.
5. Export the folder → zip contains date-named folders, correctly named images, a stub for the photo-less receipt, and a `summary.csv` that opens cleanly in Excel/Numbers with correct amounts.
6. First launch shows the welcome screen once; with Apple Intelligence available, no other onboarding friction appears. With Apple Intelligence switched off on an eligible device, the app shows the enable gate, and turning it on in Settings and returning to the app dismisses the gate without a relaunch. While the model is still downloading (`.modelNotReady`), scanning works end-to-end with deterministic extraction and a subtle notice (no crash, no dead end).
7. Airplane mode: everything works; data syncs to iCloud when connectivity returns; second device signed into the same iCloud sees the data.
8. Every field of every receipt is editable after saving; edits persist and update folder totals.
9. Delete a folder and choose "keep receipts" → receipts appear under Unfiled.
10. VoiceOver can complete the capture→review→save flow; app is fully usable in dark mode and at large Dynamic Type sizes.
11. A receipt in a non-English Apple Intelligence-supported language (e.g. German) extracts vendor, date, and total correctly; a receipt in an unsupported language still reaches the review screen prefilled with deterministic values and a subtle notice (no crash, no gate screen). The codebase contains no user-facing strings outside the String Catalog, and the app renders correctly under pseudolocalization.

## 11. Open items intentionally deferred (do not build without asking)

- Reimbursement status tracking (explicitly rejected for v1 — revisit only if the user asks).
- A global category-management screen, per-category color pickers, or reusing custom categories across folders (folder profiles and folder-local visible categories shipped per §4.7; these remaining affordances stay deferred).
- PDF expense-report export (CSV chosen for v1).
- Currency conversion.
- iPad layouts.
- Shipping translated UI languages beyond English. Because of §3.2 this must cost only: add translations to the String Catalog, add that language's entries + fixtures to the parser keyword table, and run the localized QA pass. If it costs more than that, §3.2 was violated — fix the architecture, not the estimate.
