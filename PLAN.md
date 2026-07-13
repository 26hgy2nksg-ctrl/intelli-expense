# PLAN.md — Intelli-Expense implementation plan

**Who reads this:** the agent executing the build goal. [PRD.md](PRD.md) says *what* to build, [DESIGN.md](DESIGN.md) + [design/ui-spec.html](design/ui-spec.html) say *how it looks*, this file says *in what order, with what process, and what proves progress*. Read [CLAUDE.md](CLAUDE.md) first if you haven't.

## Objective

Build Intelli-Expense v1 end-to-end per PRD.md, test-driven, until the stopping condition below is met.

## Stopping condition (what "done" means)

1. All milestones M0–M8 below are complete.
2. `swift test` (ExpenseCore package) and `xcodebuild test` (app unit + UI test plans) pass with zero failures on an iOS 26 simulator.
3. Every PRD §10 acceptance criterion is walked and recorded in `PROGRESS.md`: simulator-verifiable ones **pass**; device-only ones (real camera scan, real Foundation Models behavior, CloudKit two-device sync, App Store gating) are explicitly listed for manual verification with exact steps — never silently skipped.
4. No PRD §2 non-goal was built.

## Process rules (binding)

- **Red-green-refactor.** For every piece of logic: write the failing test first, make it pass, refactor. Never write parser/merge/CSV/totals code before its test exists.
- **The suite is never red at a checkpoint.** Do not start a new milestone with failing tests. Commit at every green checkpoint with a descriptive message.
- **Keep a progress log** in `PROGRESS.md` (create it at M0): one dated entry per checkpoint — what was completed, which command verified it, what remains, whether blocked. Compact, honest, no fluff.
- **Verify Apple APIs against current documentation before locking each choice** (PRD §0.2). Record any deviation from the PRD's named API (and why) in PROGRESS.md.
- **Simulator constraints:** the document camera (`VNDocumentCameraViewController`) does not run on simulator — UI tests exercise capture via photo/file import with bundled fixture images. Foundation Models availability on simulator is environment-dependent — all automated tests use the fake services (M2); never let a test depend on the real model.
- When in doubt, cut scope, not quality (PRD §0.3). Ask before building anything in PRD §11.

## Architecture for testability (decided here, follow it)

- **`ExpenseCore` — a local Swift package** holding all pure logic: money/`Decimal` math, per-currency totals, expense enums, the per-language keyword table, the deterministic parser, the merge policy, extraction DTOs, CSV/zip export logic, filename sanitization. No SwiftUI, no SwiftData, no Vision/FoundationModels imports. Tests run in seconds on macOS via `swift test` — this is the TDD inner loop.
- **App target** consumes ExpenseCore and adds: SwiftData models, real OCR/model services (conforming to ExpenseCore protocols), capture, and all UI. Its unit tests (in-memory `ModelContainer`, fake services) and UI tests run via `xcodebuild test`.
- Boundary protocols (defined in ExpenseCore, per PRD §9): `OCRServicing`, `ExtractionModelServicing`, `ModelAvailabilityProviding` — each with a deterministic fake so every §5.0/§6.4 state is testable without hardware.

## Milestones

### M0 — Scaffold
Xcode project (app + unit-test + UI-test targets, iOS 26.0 min, Swift 6 strict concurrency, `UIRequiredDeviceCapabilities` = `[arm64, iphone-performance-gaming-tier]`), local `ExpenseCore` package wired in, `Localizable.xcstrings` created, asset catalog with the nine DESIGN.md color-token pairs, `PROGRESS.md` started.
**Verify:** `swift test` (one placeholder test) and `xcodebuild build` both succeed. Record the exact commands (with scheme/destination) in CLAUDE.md's Commands section.

### M1 — Core domain, TDD (ExpenseCore)
Expense type + payment enums (string raw values), per-currency totals math, per-language keyword/format table, then the deterministic parser (PRD §6.2): dates (multi-format, sanity-checked), amounts (symbols/codes, Indian + Western grouping, decimal commas), total identification (label preference, subtotal+tax≈total), vendor heuristics, payment hints, currency detection — all with per-field confidence. Fixture transcripts required by PRD §9: Indian GST, EU VAT, US, crumpled/partial, plus ≥2 non-English (e.g. German + French or Japanese) exercising the keyword table.
**Verify:** `swift test` — every parser behavior fixture-backed.

### M2 — Extraction contracts + merge policy, TDD (ExpenseCore)
Boundary protocols + fakes; extraction DTOs mirroring the `@Generable` schema shape (per-field primary + optional single alternate with reason + explicit unknown, PRD §6.3); merge policy tests: deterministic high-confidence wins, model fills gaps and classifies, conflict → deterministic primary + model as second chip, ≤2 options per field, fallback to empty fields when extraction is too ambiguous.
**Verify:** `swift test`.

### M3 — Persistence (app target)
SwiftData models per PRD §4 (`ExpenseGroup`, `Receipt`, `ReceiptAttachment`, `ExtractionRecord`) obeying every CloudKit constraint (optional relationships + inverses, no `.unique`, defaults everywhere); external-storage image data; CloudKit private-DB mirroring configured.
**Verify:** app unit tests against an in-memory `ModelContainer` (CRUD, group/unfiled behavior, delete-group keep-vs-delete receipts, computed totals through ExpenseCore).

### M4 — Export, TDD (ExpenseCore + thin app shim)
`summary.csv` (fixed English headers, RFC-4180, UTF-8 BOM, localized comment row, documented totals decision), date-folder zip layout, filename sanitization + collision suffixes, `.txt` stubs for photo-less receipts, `Decimal` round-trip precision through CSV.
**Verify:** `swift test`; a generated zip's CSV opens cleanly (assert byte-level BOM/quoting in tests).

### M5 — Capture + pipeline integration (app target)
VisionKit document scan (multi-page → ordered attachments, all pages' text concatenated — not the POC's first-page shortcut), PhotosPicker, file import with PDF rasterization, perspective-corrected compressed images + thumbnails; real `OCRServicing` (Vision `RecognizeDocumentsRequest`, auto language detection) and real `ExtractionModelServicing` (FoundationModels guided generation, English prompts + locale-steering phrase, ~4k-token truncation, ~10s timeout → deterministic fallback, `unsupportedLanguageOrLocale` → non-blocking degradation); crash-safety: persist attachment + raw OCR as soon as available.
**Verify:** app unit tests with fakes for orchestration/fallback/timeout paths; manual simulator run for the real-service happy path.

### M6 — UI (app target)
Per DESIGN.md tokens and ui-spec.html layouts: onboarding welcome + Apple Intelligence gate states (§5.0), three tabs + capture accessory, Groups home + group detail (per-currency hero totals, type breakdown, filters, Unfiled), Receipts tab (search, composable filters, month grouping) + receipt detail (zoomable pages, provenance disclosure, add-photo-later with non-overwriting diff confirm), Review & Confirm (ambiguity choice chips, attention edges, required type/payment, duplicate notice, Save bar), manual entry, Settings. Every string in the String Catalog; every list has an empty state; every failure state designed.
**Verify:** `xcodebuild build` clean; manual simulator pass of each screen in light + dark.

### M7 — UI tests, accessibility, degradation (app target)
UI tests: photo-import capture→review→save happy path (fixture image + fake services injected via launch arguments), manual-entry path, each availability gate/degradation state. Accessibility sweep: VoiceOver labels on every control, Dynamic Type at large sizes, dark mode on every screen, pseudolocalization + RTL smoke pass, no-string-literals audit.
**Verify:** `xcodebuild test` full suite green.

### M8 — Acceptance sweep
Walk all 11 PRD §10 criteria; record each in `PROGRESS.md` as **pass (automated)**, **pass (manual simulator)**, or **needs device** with exact manual steps. Fix anything that fails. Final full-suite run.
**Verify:** stopping condition fully satisfied.

### M9 - App Store Connect and internal TestFlight handoff
Start this milestone only after M8 is complete, the full suite is green, and
the final acceptance sweep is recorded. Store-specific identifiers, signing
certificates, provisioning profiles, and App Store Connect operations belong in
the maintainer's private runbook and ignored `Makefile.local`, not in this public
plan.

Release-plumbing requirements:

- Align the app bundle ID with ASC: `com.nags.intelliexpense`.
- Supply the maintainer's Apple Developer team through local build configuration.
- Align CloudKit entitlements with `iCloud.com.nags.intelliexpense`.
- Keep the app iPhone-only and keep `UIRequiredDeviceCapabilities` as `[arm64,
  iphone-performance-gaming-tier]`.
- Create or refresh the App Store provisioning profile and verify it contains the
  CloudKit entitlement.
- Run a signed build to initialize the CloudKit Development schema, then deploy
  the schema to Production before using TestFlight for CloudKit sync proof.

ASC/TestFlight steps:

1. Confirm the configured App Store Connect record still reports
   `Intelli-Expense` and bundle ID `com.nags.intelliexpense`.
2. Create the internal TestFlight group if it still does not exist, then record
   its ID in the private release log.
3. Archive/export an App Store Connect IPA signed with the verified profile.
4. Upload the verified archive to the configured internal TestFlight group.
5. Read back the build with `asc builds list` / `asc validate testflight` and
   record the build number, build ID, processing state, and group ID in the
   private release log.

Do not submit for App Store review in this milestone unless the owner explicitly
asks for review submission. App Privacy and account agreement prompts remain
owner-confirmed because the public App Store Connect API cannot fully verify
them.
