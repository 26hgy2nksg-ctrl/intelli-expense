# Spec: Processing overlay per DESIGN §7 + extraction audit trail (model JSON, OCR confidence)

**Status:** ready for implementation
**Scope:** three findings from the 2026-07-05 Scan Receipt audit:

- **Part A** — the processing overlay violates DESIGN.md §7: no Cancel, generic paper graphic instead of the actual captured receipt, no staged hints (and its scan-line animation never runs). Touches `IntelliExpense/ContentView.swift`, `IntelliExpense/Capture/ReceiptProcessingPipeline.swift`, String Catalog, tests.
- **Part B** — `modelOutputJSON` exists on both `ReceiptDraft` and `ExtractionRecord` but is never populated; raw model output is thrown away. Touches `ExpenseCore` (new pure encoder), pipeline, `ReceiptReviewForm.swift`.
- **Part C** — OCR confidence is discarded (`confidence: nil`). Touches `IntelliExpense/Capture/VisionDocumentOCRService.swift`, pipeline timing, persistence models.

Parts B and C are small and share the pipeline; implement them together. Part A is independent but its cancellation work assumes the draft-cleanup rules of `SPEC-draft-cleanup-and-amount-parsing.md` Part A (implement that first or alongside).

---

# Part A — Processing overlay: Cancel, real receipt, truthful stages

## A1. Problem (verified in code)

DESIGN.md §7 (lines 221–224) is explicit: *"Processing is the signature moment: a scan-line sweeps over the **actual captured receipt** (never a spinner) with truthful stage hints ('Reading text…' → 'Understanding receipt…') and an **always-present Cancel**. Respect `accessibilityReduceMotion` — static shimmer, text carries the story."*

The current overlay (ContentView.swift:449–499, shown at :96–98 while `processing == true`) violates every clause:

1. **No Cancel.** The overlay blocks the whole screen; the user is trapped at a cash register for up to OCR-time + the 30s model timeout. Nothing cancels the in-flight `Task` (`process`, ContentView.swift:256–272).
2. **Generic drawing, not the receipt.** `ReceiptPaperPreview` (:469–499) renders gray capsules on a white rounded rect — the captured image (already in memory as `CapturedReceiptPage.thumbnailData`) is never shown.
3. **No stage hints.** Static `processing.title` / `processing.subtitle`; the pipeline reports nothing while it moves through OCR → parse → model.
4. **Bonus bug — the sweep never animates.** The gradient's offset animates with `.animation(…repeatForever…, value: reduceMotion)` (:494–495): the animation only triggers when `reduceMotion` *changes*, which never happens mid-overlay, so the "scan line" just sits at a fixed offset. `onAppear {}` (:497) is empty.

## A2. Requirements

### A-R1 — Pipeline reports stages

Add to the capture layer (app target, next to the pipeline):

```swift
enum ReceiptProcessingStage: Equatable {
    case readingText          // OCR running
    case understandingReceipt // Foundation Models running
}
```

`ReceiptProcessingPipeline` gains an optional callback, injected via `process`:

```swift
func process(
    capturedPages: [CapturedReceiptPage],
    onStage: (@MainActor (ReceiptProcessingStage) -> Void)? = nil
) async throws -> ReceiptProcessingResult
```

- Invoke `.readingText` immediately before the OCR call (ReceiptProcessingPipeline.swift:163).
- Invoke `.understandingReceipt` immediately before the model call (:199) — **only** on the path where the model actually runs. Truthful means: deterministic-only runs (model not ready, :187–195) and empty-OCR bails (:174–181) never show "Understanding receipt…".
- The pipeline is `@MainActor`; the callback is a plain closure — no concurrency gymnastics. Existing callers/tests compile unchanged thanks to the default `nil`.

### A-R2 — Cancellable capture task

In `MainTabView` (ContentView.swift):

- Replace the scattered `Task { await process { … } }` spawns (camera sheet :160, photos `.onChange` :180, fileImporter :193, UITest fixtures :240/:249) with two helpers that create **and store** the task:

```swift
@State private var captureTask: Task<Void, Never>?

private func startCapture(_ buildPages: …)            // wraps process(…)
private func startAttachmentCapture(for: Receipt, _:)  // wraps processAttachment(…)
```

- The overlay's Cancel button calls `captureTask?.cancel()`.
- The pipeline must stop at stage boundaries: add `try Task.checkCancellation()` before OCR, before the model call, and after each (Vision's and FoundationModels' async calls also observe cancellation, but the explicit checkpoints make the behavior deterministic and testable).
- **On cancellation the pipeline deletes the draft it created** (persisted at :161 before OCR): catch `CancellationError` around the post-draft stages, `context.delete(draft)`, `try? context.save()`, rethrow. (The 48h sweep from the draft-cleanup spec remains the backstop, not the mechanism.)
- In `process`/`processAttachment` (ContentView), catch `CancellationError` **before** the generic `catch`: reset state, show **no** error alert — user-initiated cancel is not an error (DESIGN §8: never the word "error"). The generic `catch` currently swallows cancellation into `capture.error.generic` — that must not survive.

### A-R3 — Overlay shows the actual receipt with a working sweep

Replace `ReceiptPaperPreview` usage in `ProcessingOverlay` (:449–467):

- New state on `MainTabView`: the overlay is driven by a single value, e.g. `@State private var processingState: ProcessingOverlayState?` — replaces the `processing: Bool` (`ProcessingOverlayState` holds `stage: ReceiptProcessingStage?` and `previewImageData: Data?`). Set `previewImageData` from the first built page (`pages.first?.thumbnailData ?? pages.first?.imageData`) right after `buildPages()` returns, before the pipeline starts; update `stage` from the A-R1 callback. All existing `processing == true` checks (:96, :107) key off `processingState != nil`.
- Overlay layout: the captured image (`UIImage(data:)`, `scaledToFit`, same ~180×250 frame budget, rounded corners) with the Ledger Green scan-line gradient sweeping over it in a loop. Manual-entry never shows the overlay (no pipeline run); if `previewImageData` is nil for any other reason, fall back to the existing paper drawing rather than a blank.
- **Fix the animation:** drive the sweep with a `@State` toggle flipped in `.onAppear` inside `withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: false))` (or `TimelineView`) — not `.animation(value:)` keyed to a constant. Under `accessibilityReduceMotion`: no sweep, static soft shimmer (current gradient at fixed offset is acceptable) — the stage text carries the story.
- Stage line: replaces the static `processing.subtitle` — shows `processing.stage.reading` while `.readingText`, `processing.stage.understanding` while `.understandingReceipt`, animating the text change with a gentle transition. Keep `processing.title` as-is above it.
- **Cancel:** a plain, always-visible button under the stage text — `common.cancel` (key already exists in the String Catalog), white/secondary styling on the dark scrim, generous tap target. No red (destructive styling is wrong for a safe action, and the design bans red anyway). No haptic — DESIGN §7: "Nothing else vibrates."

### A-R4 — Accessibility

- The overlay stays one combined accessibility element for the visual block (existing `.accessibilityElement(children: .combine)`), but **Cancel must be its own focusable element**.
- Announce stage changes to VoiceOver (`AccessibilityNotification.Announcement` posting the stage string) so non-visual users get the same truthful hints.
- Respect `accessibilityReduceMotion` per A-R3.

### A-R5 — Localization

New String Catalog keys (English), following the existing `processing.*` style:

| Key | Value |
|---|---|
| `processing.stage.reading` | "Reading text…" |
| `processing.stage.understanding` | "Understanding receipt…" |

`common.cancel`, `processing.title`, `processing.accessibility` already exist. `processing.subtitle` becomes unused — remove its usage; delete the key only if nothing else references it.

### A-R6 — Out of scope

- Progress percentages, determinate bars, or per-page progress.
- Cancelling *after* the review sheet is presented (Discard already covers that).
- Any change to the 30s model timeout or the notice banners.

## A3. Tests (TDD — write first)

`IntelliExpenseTests` (extend `CapturePipelineTests` patterns — fakes for OCR/model/availability already exist):

1. **Stages are truthful:** full pipeline run with available model → recorded stage sequence is exactly `[.readingText, .understandingReceipt]`. Model-not-ready run → `[.readingText]`. Empty-OCR run → `[.readingText]` (no understanding stage).
2. **Cancellation cleans up:** a fake OCR service that suspends until cancelled; cancel the task mid-OCR → `process` throws `CancellationError`, and the store contains **zero** `ReceiptDraft`/`ReceiptDraftPage` rows.
3. **Cancellation before model:** fake model service that suspends; cancel during it → same guarantees, and no `ReceiptProcessingResult` is produced.

UI test (fake services): start a fixture capture, assert the overlay exposes a Cancel button (accessibility identifier `processing.cancel`); tap it; assert the overlay dismisses and no error alert appears.

## A4. Acceptance criteria

- [ ] During a real scan, the overlay shows the actual captured receipt with a moving Ledger Green scan-line, "Reading text…" then (only when the model runs) "Understanding receipt…", and a Cancel button — matching DESIGN.md §7 word for word.
- [ ] Tapping Cancel at any point returns to the app instantly: no error alert, no review sheet, no leftover draft rows.
- [ ] With Reduce Motion on: no sweep animation; stage text still updates; VoiceOver announces stage changes.
- [ ] Deterministic-only runs never claim "Understanding receipt…".
- [ ] Existing pipeline tests pass unchanged (the `onStage` parameter defaults to nil).

---

# Part B — Persist the model's raw output (`modelOutputJSON`)

## B1. Problem (verified in code)

`ReceiptDraft.modelOutputJSON` (PersistenceModels.swift:11–33) and `ExtractionRecord.modelOutputJSON` (:210–235) exist — and `ExtractionRecord`'s init already accepts the parameter (:220–226) — but **nothing ever writes them**: the pipeline discards `modelReceipt` after merging (ReceiptProcessingPipeline.swift:199–211), `ReceiptReviewForm.save` constructs `ExtractionRecord(rawOCRText:receipt:)` without it (ReceiptReviewForm.swift:236–239), and `upsertExtractionRecord` in the attach flow ignores it too (:383+). The PRD's audit-trail intent (extraction provenance per receipt) is silently unmet: once merged, there is no record of what the model actually said versus what the parser said versus what the user corrected.

## B2. Requirements

### B-R1 — Stable JSON encoding in ExpenseCore (pure, versioned)

Do **not** retrofit `Codable` onto the generic `ModelField`/`ModelExtractedReceipt` types — `JSONEncoder` encodes `Decimal` lossily (via `Double`), and synthesized output would make the storage format an accident of type layout. Add an explicit encoder to `ExpenseCore/Sources/ExpenseCore/Extraction/`:

```swift
public enum ModelOutputAuditEncoder {
    /// Stable, versioned JSON for audit storage. Returns nil only on encoder failure.
    public static func json(for receipt: ModelExtractedReceipt) -> String?
}
```

Format rules: top-level `{"version": 1, "vendor": {...}, "date": {...}, ...}`; each field object carries `primary`/`alternate` (each `{value, reason}`) and `isUnknown`; **amounts as strings** (`"\(decimal)"` — exact), **dates as ISO 8601 strings**, enums as their raw values; keys sorted (`.sortedKeys`) so output is deterministic and diff-able. This is an internal audit format, not an API — but version it anyway (`pipelineVersion` on the models stays what it is; the JSON's own `version` guards format evolution).

### B-R2 — Pipeline writes it to the draft

In `ReceiptProcessingPipeline.process`, on the successful model path (after :206, before returning):

```swift
draft.modelOutputJSON = ModelOutputAuditEncoder.json(for: modelReceipt)
draft.lastUpdatedAt = Date()
try context.save()
```

Failure/fallback paths leave it nil — nil means "the model never produced output", which is itself audit information.

### B-R3 — Save and attach flows carry it to the receipt

- `ReceiptReviewForm.save` (:236–239): `ExtractionRecord(rawOCRText: …, modelOutputJSON: draft?.modelOutputJSON, receipt: receipt)` — the init parameter already exists.
- `Receipt.applyAttachedCapture` → `upsertExtractionRecord` (:383+): extend the signature with `modelOutputJSON: String?` from `result.draft.modelOutputJSON`; set it on the created/updated record when non-nil (do not overwrite an existing record's JSON with nil from a deterministic-only attach).

Ordering note vs. the draft-cleanup spec: both flows copy the value off the draft **before** the draft is deleted in the same transaction — no conflict.

### B-R4 — Out of scope

Any UI reading this JSON (a future "extraction details" debug screen), re-parsing it at runtime, or including it in exports. Write-only audit trail for now.

## B3. Tests

- `ExpenseCore` (`ModelOutputAuditEncoderTests`): known `ModelExtractedReceipt` (primary+alternate amount with reason, unknown payment) → exact expected JSON string (deterministic thanks to sorted keys); Decimal `1234.56` survives as the string `"1234.56"`; date round-trips through ISO 8601.
- `CapturePipelineTests`: successful model run → `draft.modelOutputJSON != nil` and decodes with `version == 1`; model-timeout run → stays nil.
- `IntelliExpenseTests`: form save → the receipt's `extraction?.modelOutputJSON` equals the draft's; attach flow → upserted record carries it; deterministic-only attach onto a receipt with existing JSON does not blank it.

## B4. Acceptance criteria

- [ ] After a scan where smart extraction ran, the saved receipt's `ExtractionRecord.modelOutputJSON` contains versioned JSON with every field's primary/alternate/reason.
- [ ] Deterministic-only and manual receipts have `modelOutputJSON == nil`.
- [ ] Amounts in the JSON are exact decimal strings, never floats.

---

# Part C — Capture OCR confidence

## C1. Problem (verified in code + docset)

`OCRTextPage.confidence: Double?` exists in the contract (ExtractionContracts.swift:15–25) but `VisionDocumentOCRService` hardcodes `confidence: nil` (VisionDocumentOCRService.swift:27). Vision provides the signal: `DocumentObservation.confidence` — `let confidence: Float`, normalized 0–1, iOS 26.0+ (offline docset, `/documentation/vision/documentobservation/confidence`). Today a barely-legible receipt and a crisp one produce indistinguishable metadata; the quality signal is lost before anyone could use it.

## C2. Requirements

### C-R1 — Populate per-page confidence

In `VisionDocumentOCRService.recognizeText` (:14–32): compute the mean of `observations.map(\.confidence)` (a page usually yields one observation; average is correct if there are several) and pass it as `Double`. Empty observations → `nil` (unknown, not zero — zero would be a claim).

### C-R2 — Persist an aggregate

- Add `var ocrConfidence: Double?` to **both** `ReceiptDraft` and `ExtractionRecord` (PersistenceModels.swift) — optional, CloudKit-safe, additive migration, mirroring how `rawOCRText` flows.
- Aggregate rule: the **minimum** across pages that have a value (conservative — one unreadable page taints the document); all-nil → nil. Implement as a computed helper on `OCRResult` in ExpenseCore (`public var aggregateConfidence: Double?`) so it's pure and tested.
- Pipeline: set `draft.ocrConfidence` alongside `draft.rawOCRText` (:170–172). Save/attach flows: carry it into `ExtractionRecord` exactly like `modelOutputJSON` in Part B (same touch points, same nil-preservation rule).

### C-R3 — Log it

Add `var ocrConfidence: Double?` (default nil) to `ReceiptProcessingTiming` (ReceiptProcessingPipeline.swift:47–70) and include it in `LoggingReceiptProcessingTimingRecorder`'s line (:82–104) — the field has a default, so existing test constructions compile unchanged.

### C-R4 — Out of scope

- Weighting parser confidence by OCR confidence (a merge-policy change — needs its own design; this spec only stops discarding the data).
- Any UI (badges, warnings) driven by confidence.
- Word/line-granular confidence.

## C3. Tests

- `FakeOCRService`-based pipeline test: pages with confidences `[0.9, 0.4]` → `draft.ocrConfidence == 0.4`; all-nil → nil.
- `ExpenseCore` test for `OCRResult.aggregateConfidence` (min semantics, nil handling).
- `ReceiptServiceWrapperTests`: extend the request-configuration test area with a mapping test if the observation→page mapping is factored into a testable pure function (recommended: `static func pageConfidence(from observations:)`).
- Form save / attach tests: `ocrConfidence` reaches `ExtractionRecord`.

## C4. Acceptance criteria

- [ ] A real scan stores a non-nil `ocrConfidence` on the draft and, after save, on the receipt's `ExtractionRecord`; the OSLog timing line includes it.
- [ ] Multi-page documents report the worst page's confidence.
- [ ] No behavior change anywhere else — parser, merge, and UI outputs are byte-identical for the same input.

---

# Verification commands (all parts)

```bash
# ExpenseCore: ModelOutputAuditEncoderTests + OCRResult.aggregateConfidence + existing suites
cd ExpenseCore && swift test

# App unit + UI tests: stage/cancellation tests, audit-trail tests, overlay UI test
xcodebuild -project IntelliExpense.xcodeproj -scheme IntelliExpense \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' test

# Build only
xcodebuild -project IntelliExpense.xcodeproj -scheme IntelliExpense \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' build
```

Manual pass (device — the overlay is about feel): scan a real receipt and watch the sweep run over the actual image with truthful stage text; cancel mid-scan at both stages; repeat with Reduce Motion on; then inspect a saved receipt's `ExtractionRecord` in tests/debugger for `modelOutputJSON` + `ocrConfidence`.
