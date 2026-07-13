# SPEC — App Store metadata, keywords, and screenshot program

**Status:** proposed
**Owner files:** `fastlane/metadata/en-US/` (new — name, subtitle, keywords, promotional text, description, release notes as checked-in text files), `fastlane/screenshots/en-US/` (new — final marketing screenshots), `fastlane/Deliverfile` + ASC API-key wiring (new), `docs/appstore/` (new — screenshot shot-list and caption source of truth); no app code changes
**Docs this spec amends:** none (PRD §7 export/privacy claims are the source of truth this metadata must not contradict)
**Related specs:** SPEC-mac-app.md (Mac App Store listing shares this metadata), sandbox lane in CLAUDE.md (`make sandbox-profile` / `make install-device-sandbox` — the screenshot-capture environment)

All numeric limits and indexing behavior below were verified against Apple documentation and current ASO sources as of 2026-07; re-verify limits at submission time.

---

## 1. Problem

The app is approaching App Store submission with zero marketing metadata. App Store search ranking is driven almost entirely by a few small indexed fields (name 30 chars, subtitle 30, hidden keyword field 100, and — since ~2025 — OCR-indexed screenshot caption text), while the 4,000-char description is **not indexed on iOS** and matters only for conversion. Getting keywords wrong at launch wastes the strongest ranking window a new app gets; getting claims wrong (Guideline 2.3.1, accurate metadata) risks rejection — particularly for a finance-adjacent app using on-device AI. Screenshots carry the pitch: search results show only the first ~3 portrait iPhone screenshots.

## 2. Goals

- A complete, submission-ready metadata set for iOS and Mac App Store: name, subtitle, keyword field, promotional text, description, category, privacy label answers, age rating inputs.
- A screenshot program: shot list, caption copy, exact required sizes, and the capture pipeline using the existing sandbox seed lane.
- Metadata lives in the repo (diffable, reviewable) and uploads via automation, not hand-typing into App Store Connect.
- Copy that is 2.3.1-safe: privacy claims we can prove, AI claims scoped to "on-device, user-confirmed", no compliance/tax promises.

## 3. Non-goals

- No App Preview videos at launch — highest-effort asset; deferred to a post-launch conversion pass once real screenshots exist to build on.
- No in-app purchases, subscriptions, or in-app events — nothing to name or index there.
- No localized metadata at launch (English-only UI per PRD §3.2). The per-locale keyword-slot expansion (each added locale contributes its own indexed name/subtitle/keywords — e.g. es-MX is indexed on the US storefront) is documented as the designated first ASO follow-up, since it needs no app translation.
- No paid ASO tooling, keyword-volume subscriptions, or A/B testing infrastructure in this pass.
- No marketing website, press kit, or social assets — App Store product page only.

## 4. Design decisions

### D1 — Indexed fields carry keywords; the description carries conversion

Budget every indexed character; never spend indexed space on words Apple already has from another field (Apple combines name + subtitle + keyword field per locale; duplicates are pure waste). The description is written purely for humans.

**Name (30 max):** `Intelli-Expense` (15 chars). The brand alone — clean, and it already contains the high-value stem "expense". Rejected: `Intelli-Expense: Trip Receipts` (exactly 30) — it double-spends "trip" and "receipts", which the subtitle and captions cover, and long names truncate in many placements.

**Subtitle (30 max):** `Scan receipts, export trips` (27 chars). Benefit-led and adds four indexed stems (scan, receipts, export, trips) not present in the name.

**Keyword field (100 max, comma-separated, no spaces after commas, no words from name/subtitle, singular-or-plural not both, never the category name or "app"):**
`travel,business,work,tracker,report,csv,reimbursement,ocr,invoice,offline,private,organizer,log`
(95 chars.) Rationale: the algorithm composes multi-word phrases from components, so this field plus name/subtitle yields "expense tracker", "travel expense report", "business receipts", "work trip expenses", "receipt scanner ocr", "expense log", etc. "Reimbursement" is the highest-intent single word for the target user (personal card on a work trip). Rejected inclusions: "scanner" (stem covered by subtitle's "scan"), "finance" (category name), "tax" (invites 2.3.1 scrutiny for compliance implications we must avoid, D4).

**Promotional text (170 max, not indexed, editable without review):**
`Every receipt stays on your device. On-device AI reads it, you confirm every field, and each trip exports as a finance-ready zip. No accounts, no servers, no tracking.` (166 chars.) This field is the "update without a build" slot — reserve it for messaging tweaks post-launch.

### D2 — Description structure (≤4,000 chars, conversion-only)

Checked-in as `fastlane/metadata/en-US/description.txt`, structured for the skim reader:

1. One-line promise: turn a pocket of paper receipts into an organized, exportable expense record — privately, on your device.
2. How it works (mirrors the real pipeline): scan or import → on-device intelligence reads vendor, date, amount, currency → you confirm on a review screen → export a date-named zip of images plus `summary.csv` per trip.
3. Privacy block: no accounts, no servers, no analytics; the only network traffic is iCloud sync inside your own private iCloud database; "Data Not Collected" per the App Store privacy label.
4. Feature bullets grounded in shipped features only (multi-currency amounts kept separate, trip folders and archiving, Mac drag-and-drop import, quick-capture widget, share-sheet import).
5. Requirements block, stated plainly: requires iOS 26/macOS 26 and Apple Intelligence; extraction runs on device and every extracted field is confirmed by you before it's saved.
6. Support/contact line and privacy-policy URL (privacy policy URL is a mandatory ASC field — a static page stating the above; its authoring is part of this spec's acceptance).

Tone per DESIGN.md's product voice: calm, concrete, zero hype adjectives; every claim traceable to a PRD acceptance criterion.

### D3 — Category, age rating, and privacy label

- **Primary category: Finance; secondary: Business.** Finance is where expense trackers live and rank; Business captures the work-trip audience. Rejected: Productivity (weaker intent match, fiercest generic competition).
- **Age rating:** questionnaire answers all "None" → 4+.
- **Privacy nutrition label: "Data Not Collected."** Apple's definition of "collect" is transmission off-device that the developer or partners can access. This app qualifies: processing is on-device, there is no analytics or crash SDK, no ads, no server, and CloudKit **private-database** data is accessible only to the user's iCloud account, not to us. Every ASC data-type question is answered No. This label is a marketable differentiator and is echoed in the promo text, description, and one screenshot caption. **Standing constraint recorded here: adding any analytics/crash-reporting SDK later forfeits the label and must reopen this spec.**

### D4 — Review-safety rules for copy (Guideline 2.3.1 and the 2026 AI climate)

Binding rules for every metadata field, caption, and future What's New note:

- Never claim tax, audit, IRS, HMRC, or expense-policy **compliance**; describe the export factually ("date-named image folders plus a summary.csv"). "Finance-ready" is acceptable shorthand for format, not a compliance claim.
- Never state or imply extraction accuracy percentages; the honest frame — used everywhere — is "AI reads, you confirm."
- State the Apple Intelligence requirement in the description and What's New (there is no device-capability key that gates listing visibility for Foundation Models, so metadata plus the in-app PRD §6.4 gates are the whole story; reviewers do exercise degraded states).
- No competitor names, no "best/#1", no price/promo claims in screenshots.
- Camera/photo permission purpose strings already state receipt capture — screenshots must not show any other camera use.

### D5 — Screenshot program

**Sizes (Apple screenshot specifications, current):** iPhone masters at **1320×2868** (6.9" portrait; the single required iPhone set — smaller classes scale down). Mac masters at **2880×1800** (16:10 Retina). PNG, 1–10 per device class.

**Order and captions** — the first three carry the entire pitch (that's all search results show), one message per shot, headline set large enough to read at thumbnail size. Captions are OCR-indexed since ~2025, so they deliberately carry keyword phrases the 100-char field couldn't fit:

| # | Screen content (sandbox seed data) | Caption |
|---|---|---|
| 1 | Scanner mid-capture on a receipt | `Scan any paper receipt in seconds` |
| 2 | Review & Confirm with fields filled | `On-device AI reads it — you confirm` |
| 3 | Export sheet / zip with csv visible | `Export a finance-ready zip per trip` |
| 4 | Trips home with organized trips | `Every work trip, organized` |
| 5 | Trip detail with per-currency totals | `Multi-currency totals, never muddled` |
| 6 | Settings/empty network state motif | `Private by design. Data Not Collected.` |

Mac set (4 shots): drag-and-drop import, three-column review, export, and the folder editor — caption style identical, first caption `Review and export on your Mac`.

**Capture pipeline:** the sandbox lane exists for exactly this (`make sandbox-profile`, `make install-device-sandbox` — generic screenshot-safe seed trips/receipts, CLAUDE.md). Shots are taken from the sandbox build at required resolutions (device or simulator for iPhone; the Mac app windowed at 2880×1800 equivalent). Raw captures and final framed/captioned PNGs both live under `docs/appstore/` with the shot list; finals are copied into `fastlane/screenshots/en-US/`. Caption text lives in the shot-list doc as the single source of truth (captions are marketing assets, **not** app UI — they do not enter `Localizable.xcstrings`).

### D6 — Automation: checked-in metadata tree + fastlane deliver

Metadata and screenshots are repo artifacts uploaded by `fastlane deliver` authenticated with an App Store Connect API key: `fastlane/metadata/en-US/*.txt` (name, subtitle, keywords, promotional_text, description, release_notes) and `fastlane/screenshots/en-US/` (deliver maps files to display families automatically, iPhone 6.9" and Mac). `deliver download_metadata` seeds/reconciles the tree from ASC. A `Deliverfile` pins app identifier and disables anything not managed here (pricing). Manual-in-ASC remainder, documented as a submission checklist in `docs/appstore/`: privacy-label questionnaire answers (not writable via the public API), category selection, age-rating questionnaire, and pricing. Rejected: raw ASC API scripting (deliver already wraps the same endpoints and matches the repo's existing ASC-CLI bootstrap habits) and hand-entering metadata in the ASC UI (undiffable, unreviewable).

## 5. Edge cases

- **Name collision at reservation:** if "Intelli-Expense" is taken in a storefront, fallback is `Intelli-Expense — Receipts` (26); the keyword budget in D1 is then re-audited for the new duplicate ("receipts" leaves the subtitle... it does not — the subtitle keeps "receipts"; instead the fallback forfeits nothing in the keyword field). Any name change re-runs the no-duplicate audit across all three indexed fields.
- **Keyword field over 100 after edits:** the file is the source of truth; a pre-upload length check in the deliver lane fails the run rather than letting ASC silently truncate.
- **Mac and iOS metadata drift:** one shared en-US tree; Mac-specific screenshot set is the only divergent asset. What's New is written once per release and must be true on both platforms.
- **Screenshot content shows real-looking data:** only sandbox seed data (generic vendors, no real names/amounts from anyone's actual trips) may appear — this is why capture is pinned to the sandbox lane, never the durable app.
- **Promotional text drift:** promo text is editable without review — but it remains bound by D4's rules; the checked-in file stays authoritative and ASC-side hotfixes must be back-ported to the repo.
- **Apple changes limits/sizes:** the spec records values verified 2026-07; the submission checklist's first item is re-verifying the four numbers that move (name/subtitle/keyword limits, screenshot dimensions).

## 6. Accessibility & localization

No new app UI and no new `Localizable.xcstrings` keys — metadata, captions, and the privacy-policy page are store/marketing artifacts maintained in `fastlane/metadata/` and `docs/appstore/`. Locale-expansion (adding indexed metadata locales without translating the UI) is the designated follow-up spec and must not be improvised piecemeal. Screenshot finals use high-contrast caption text over solid backgrounds (thumbnail legibility); no information is conveyed by color alone in captions.

## 7. Test impact

No app-code tests. Verification is lane-based:

- A metadata lint step in the deliver lane: field lengths (30/30/100/170/4000), keyword-field character-class check (no spaces after commas), no-duplicate check between name/subtitle/keyword stems, and presence of every required file.
- Screenshot dimension check (1320×2868 / 2880×1800, PNG) before upload.
- `deliver` dry-run (`--verify_only` behavior / precheck) against a TestFlight-stage app record before first real submission.
- Manual: proofread pass of description and captions against D4's rules, privacy-label questionnaire walk-through recorded in the submission checklist.

## 8. Acceptance criteria

1. `fastlane/metadata/en-US/` exists with name (≤30), subtitle (≤30), keyword field (≤100, D1 mechanics respected, zero stems duplicated from name/subtitle), promotional text (≤170), description per D2, and a live privacy-policy URL.
2. `fastlane/screenshots/en-US/` contains the D5 iPhone set (1320×2868) and Mac set (2880×1800), captured exclusively from the sandbox lane, with captions matching the shot-list doc; the first three iPhone shots deliver scan → confirm → export.
3. `docs/appstore/` contains the shot list (caption source of truth) and the manual submission checklist (privacy label = all No → "Data Not Collected", category Finance/Business, age rating 4+, limit re-verification step).
4. `fastlane deliver` with an ASC API key uploads the full metadata + screenshot set to the app record without manual field entry; the lint and dimension checks run before upload and fail the lane on violation.
5. Every sentence of copy passes D4: no compliance/accuracy claims, AI framed as on-device and user-confirmed, Apple Intelligence requirement stated.
6. The privacy label qualifies as "Data Not Collected" given the shipped binary (no analytics/crash/ads SDKs present — verified against the dependency list at submission), and the forfeiture constraint is recorded in this spec.
