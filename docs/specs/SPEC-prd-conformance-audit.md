# Spec: PRD conformance fixes (audit remediation)

**Status:** ready for implementation
**Source:** full audit of `IntelliExpense/` + `ExpenseCore/Sources/` against PRD.md (2026-07-05). Every finding verified in code at the cited lines. PLAN.md milestones M0–M8 are complete; M9 items are excluded.
**Scope:** `ExpenseCore` (export + parsing), app UI/plumbing, String Catalog, PRD.md amendments.
**Related specs (do not duplicate):** full-screen zoom → `SPEC-full-resolution-receipt-viewing.md`; red/destructive styling, duplicate banner + peek, save haptic, group-row date subtitles → `SPEC-design-conformance-audit.md`; share import → `SPEC-share-extension-import.md`.

Verified conforming (no action): Decimal end-to-end, no cross-currency sums, no hardcoded symbols; CloudKit schema rules; protocols + deterministic fakes for OCR/FM/availability with launch-arg injection; merge policy (deterministic first, model as chips); multilingual pipeline rules (English prompts, locale steering, truncation, all-pages OCR); §2 non-goals; zero network calls.

---

## Part A — Export contract (PRD §8, §3.2-A5) — HIGH

### A-R1 — `summary.csv` columns must match the PRD exactly

`ExpenseCore/Sources/ExpenseCore/Export/SummaryCSVExporter.swift:13` emits `receipt_id,date,vendor,total_amount,currency_code,expense_type,payment_method,group,notes,attachment_count`. PRD §8 fixes the contract: **`date, vendor, expense_type, payment_method, currency, amount, group, notes, has_image`** — fixed English identifiers, machine contract.

- Rename/reorder to the PRD list. `has_image` = `true`/`false` (attachment_count > 0). Drop `receipt_id` and `attachment_count` (if wanted later, that's a PRD amendment first, not silent divergence).
- Update `ExportModels.swift` DTO + `ReceiptExportMapper` accordingly; update `ExpenseCore/Tests/ExpenseCoreTests/ExportTests.swift` golden expectations.

### A-R2 — Rows sorted by date

`SummaryCSVExporter` preserves input order and the caller passes an unsorted relationship array (`UI/GroupsViews.swift:220`). Sort by `date` ascending (tie-break: vendor) inside `ExportArchiveBuilder`/exporter so **every** caller gets sorted output. Test with shuffled input.

### A-R3 — Header comment must tell the truth about totals

PRD §8: pick totals-in-file or totals-left-to-user and document it in the header comment. Current comment (`export.csv.comment`) claims "Totals are shown per currency" but no totals rows exist. **Decision: keep totals out of the file** (simplest, Excel-friendly). Reword the key to state amounts are per-receipt in original currency and totals are left to the reader.

### A-R4 — Export for Unfiled

PRD §8: export exists "per group (and for 'Unfiled')". `UnfiledReceiptsView` (GroupsViews.swift:293–317) has none. Add the same share-icon `ToolbarItem` (see design spec D-R2) exporting active unfiled receipts; archive name from a localized `export.unfiled.filename` slug.

### A-R5 — Sanitize the zip filename

`GroupsViews.swift:222` builds `"\(group.name.replacingOccurrences(of: " ", with: "-")).zip"` — `Berlin/June` or emoji breaks the path. Reuse the `ExportFilenameBuilder` slug logic (ASCII-safe, locale-independent, PRD §3.2-A5) for archive names; empty slug falls back to `export.unfiled.filename`-style default. Unit-test slash/emoji/unicode names.

### A-R6 — Localize the manual-entry `.txt` stub

`ExportFilenameBuilder.swift:101–109` hardcodes English user-facing stub text inside ExpenseCore (violates §3.2-A1: every user-facing string in the String Catalog; ExpenseCore stays localization-free by injection). Inject stub template strings the same way `csvCommentRow` is injected into `ExportArchiveBuilder`; app supplies them from the String Catalog.

### A-R7 — `_pN` suffix only for multi-page

`ExportFilenameBuilder.swift:61` appends `_p1` to single-page receipts; PRD §8 example shows page suffixes only for page ≥ 2. Suffix only when `pageCount > 1`. Update tests.

### A-R8 — Export off the main actor, with progress

`GroupsViews.swift:218–229` builds the whole zip synchronously on `@MainActor` with every attachment's `imageData` in one `Data`. PRD §8: progress for large groups, 200+ receipts without blocking UI. Move assembly to a background task (`Task.detached` or actor), report determinate progress (receipts processed / total) driving a progress card (design: ui-spec.html §export — honest counts, cancellable), write to a temp file streamed per entry if the zip API allows, clean the temp file in `defer`/on dismiss. Cancel abandons cleanly.

## Part B — Data-safety & money bugs — HIGH

### B-R1 — Cancelling processing must not destroy the captured image

PRD §5.4: cancel → "review screen with whatever is available, even just empty fields + image"; §9: never lose a captured image silently. Today `ReceiptProcessingPipeline.swift:254–259` deletes the draft (with page images) on `CancellationError` and `ContentView.swift:304–305` swallows it — the photo taken at the register is gone.

Fix: on cancellation, **keep** the persisted draft and open the review sheet with `ReceiptReviewForm(draft:mergedReceipt: MergedReceipt(rawText: draft.rawOCRText, requiresManualEntryFallback: true))` (plus whatever parse results already exist if OCR finished). The existing `discardIfUnsaved` path then governs cleanup. Unit test: cancel mid-OCR → draft still present, review form carries its pages.

### B-R2 — Receipt-detail amount editing must use the locale-aware parser

`UI/ReceiptsViews.swift:328–336` uses `Decimal(string:)`: German-style `84,50` silently saves **84**; invalid text silently keeps the old amount. Replace with `AmountInputParser.parse(_:locale:)` (already used by the review form, ReceiptReviewForm.swift:280–282); when parse fails, keep the stored value but mark the field invalid (secondary-label hint, no red) and don't write. Unit test `84,50` in `de_DE` → 84.50.

## Part C — Missing UX contract — HIGH/MEDIUM

### C-R1 — Settings defaults must actually apply (PRD §5.3/§5.4)

`SettingsView.swift:5–6` writes `defaultCurrencyCode`/`defaultPaymentMethod` to `@AppStorage`, nothing reads them (manual entry uses `Locale.current`, ContentView.swift:149; payment default unused). Plumb both into `ReceiptReviewForm.manual(...)` and capture-review defaulting (used only when extraction produced no value — never override extracted/merged values). Unit tests for both.

### C-R2 — Group delete confirmation with keep-vs-delete; group rename/edit (PRD §5.1)

- `GroupsViews.swift:80–85`: swipe-delete immediately unfiles receipts. Add a confirmation dialog: "Keep receipts (move to Unfiled)" (default) / "Delete N receipts too" / Cancel — wiring the existing unreachable `.deleteReceipts` policy (ReceiptStore.swift:5–8). No red (design rule); destructive safety comes from the dialog.
- `GroupEditorSheet` (GroupsViews.swift:319) is create-only. Reuse it for editing (pre-populated name/dates/notes), reachable from group detail (e.g. toolbar title menu or an Edit row). Keys: `group.editor.edit.title`, `group.delete.title`, `group.delete.keep`, `group.delete.deleteAll`.

### C-R3 — Group filter on the Receipts tab (PRD §5.2, §7)

Filter menu (ReceiptsViews.swift:107–158) lacks a group filter; PRD requires composable group AND type AND payment. Add a group submenu (All / Unfiled / each group) composed with existing filters. (Design spec D-R18 later restyles filters as chips — build the capability here, the chip restyle picks it up.)

### C-R4 — `.modelNotReady` onboarding notice (PRD §5.0)

`ContentView.swift:22` branches only on `blocksCapture`; `.modelNotReady` users get no explanation until after first scan. Add the PRD's non-blocking notice screen/banner after onboarding when status is `.modelNotReady`: "Apple Intelligence is still downloading — capture works now, smart extraction joins when ready" + Get Started. Testable via existing `-FakeModelNotReady` launch arg.

### C-R5 — Camera-permission-denied designed state (PRD §6.4)

Real denial currently lands in the generic `capture.error.title` alert (ContentView.swift:188) with no recourse. Detect the denial (check `AVCaptureDevice.authorizationStatus(for: .video)` before presenting, and/or map the VisionKit error), show a designed state: why + "Open Settings" button (`UIApplication.openSettingsURLString`) + explicit note that Photo/File import still works. Keys `capture.camera.denied.title/.message/.settings`.

### C-R6 — Record `userCorrectedFields` on the main save path (PRD §4.4)

`ReceiptReviewForm.save()` (ReceiptReviewForm.swift:245–250) always writes nil. Diff final saved values against the merged primaries captured at init (vendor/date/amount/currency/type/payment); store changed field names. Unit test: change vendor + amount → `["vendor", "totalAmount"]`.

## Part D — Localization architecture (PRD §3.2 — cheap now, expensive later) — MEDIUM

### D-R1 — Move inline language knowledge into `ReceiptLanguageProfiles`

PRD §3.2-C1: adding a language = table entries + fixtures, zero parser-code changes. Violations:
- `ReceiptParser.swift:92` — vendor heuristic hardcodes `"date"/"datum"/"bill"/"receipt"/"ticket"/"gstin"`.
- `ReceiptParser.swift:231–262` — `isMetadataLine` hardcodes a 20+ English/Indian keyword list (`fssai`, `gstin`, `cashier`, …).
- `ReceiptAmountParser.swift:16` — regex hardcodes `(USD|EUR|INR|GBP|JPY|CHF|CAD|AUD)`.

Fix: add `vendorSkipKeywords` and `metadataKeywords` to `ReceiptLanguageProfile`; build the currency alternation from the profiles' currency-code set. Parser behavior identical for existing fixtures (all parser tests stay green — that's the regression gate).

### D-R2 — Per-language date-format precedence

`ReceiptLanguageProfiles.allDateFormats` (ReceiptLanguageProfiles.swift:130–132) flattens all languages' formats **alphabetically**, so `MM/dd/yyyy` always beats `dd/MM/yyyy` — `06/07/2026` on a German receipt parses as June 7 (US) systematically. Fix: preserve per-profile order and try profiles in a deterministic language-relevance order (detected/receipt language first when known, else locale-preferred first); ambiguous numeric dates should surface **both** candidate dates as choices (the chips UI already supports multiple date options). Add fixture tests for `06/07/2026` under `de` and `en_US` profiles.

### D-R3 — Parameterize the model's output-language instruction (PRD §3.2-B4)

`FoundationModelReceiptService.swift:50` says alternate reasons "must be in the app UI language" without naming it. Interpolate the UI language display name (`Locale.current.localizedString(forLanguageCode:)` of the app's UI language) into one explicit instruction line ("You MUST write reasons in English", etc.).

### D-R4 — `supportsLocale()` preflight (PRD §3.2-B5)

`FoundationModelAvailabilityProvider` never calls `SystemLanguageModel`'s locale-support check; only the request-time `unsupportedLanguageOrLocale` catch exists (FoundationModelReceiptService.swift:167–168). Add the preflight to the availability/pipeline path so unsupported-locale is known **before** a generation attempt (verify the exact current API name against Apple docs — repo rule). Degradation behavior unchanged; it just gets decided earlier and becomes testable via the fake.

## Part E — Smaller conformance items — LOW

- **E-R1** Groups list ordering: sort by most-recent activity (max of `createdAt` / newest receipt date) instead of `createdAt` (GroupsViews.swift:7); PRD §5.1.
- **E-R2** Review group default: pre-select the most-recently-used group when capture didn't start from a group (PRD §5.4 should-have); keep Unfiled as fallback. (`defaultCaptureGroup`, ContentView.swift:71.)
- **E-R3** Migrate money/amount formatting from `NumberFormatter` to `Decimal.FormatStyle` (`ExpenseFormatters.swift:5–14`, `ReceiptReviewForm.swift:302–310`) — PRD §3.2-A3 names `FormatStyle`. Output must remain byte-identical for existing tests or tests updated deliberately.
- **E-R4** Settings iCloud row (`SettingsView.swift:21`) is a static label; reflect real `CKContainer.accountStatus()` (signed-in/available vs unavailable) as a minimal honest status. Full sync telemetry stays deferred (design spec).

## Part F — PRD amendments (docs, not code)

Update PRD.md in the same PR (mark with a changelog note):
1. §6.3 timeout: record the deliberate 30 s production timeout (AppServices.swift:44, PROGRESS.md "Smart Extraction Timeout — 2026-07-05") or revert to ~10 s once device telemetry justifies — pick one, don't leave PRD and code disagreeing.
2. §4 data model: document the two shipped additions — `ReceiptDraft`/`ReceiptDraftPage` (crash-safety, §9) and `Receipt.isArchived`/`archivedAt` (archive feature). Note that drafts (with full-res images) currently live in the CloudKit-mirrored store — accepted for now.
3. §8: record the totals-out-of-file decision (A-R3).

## Tests & acceptance

- ExpenseCore: updated export golden tests (columns, sort, stub injection, `_pN`, slug), new parser-profile tests (D-R1 keeps all fixtures green; D-R2 date-precedence fixtures), `cd ExpenseCore && swift test`.
- App unit: cancel-keeps-draft (B-R1), locale amount edit (B-R2), settings defaults (C-R1), userCorrectedFields diff (C-R6), group-delete both policies reachable (C-R2).
- UI: `-FakeModelNotReady` shows the notice (C-R4); group filter composes with type filter (C-R3); Unfiled export produces a share sheet (A-R4).
- Full suite: `xcodebuild -project IntelliExpense.xcodeproj -scheme IntelliExpense -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' test`.
- Manual: export a 2-currency group → CSV opens in Numbers with PRD columns, date-sorted rows, truthful header; cancel a capture mid-processing → review sheet with image; German locale device edits an amount to `84,50` → stores 84.50.
