# Spec: Fix ReceiptDraft storage leak + locale-aware amount input parsing

**Status:** ready for implementation
**Scope:** two confirmed bugs from the 2026-07-05 Scan Receipt audit, independent of each other:

- **Part A** — every scan permanently leaks a `ReceiptDraft` (with full-resolution image data) that syncs to CloudKit forever. Touches `IntelliExpense/Review/ReceiptReviewForm.swift`, `IntelliExpense/UI/ReviewViews.swift`, app launch bootstrap, unit tests. No pipeline behavior changes.
- **Part B** — the review amount field silently corrupts money on comma-decimal-separator regions (`"12,50"` → saves **12**, not 12.50). Touches `ExpenseCore/Sources/ExpenseCore/Parsing/`, `IntelliExpense/Review/ReceiptReviewForm.swift`, `IntelliExpense/UI/ReviewViews.swift`, unit tests.

Neither part changes the String Catalog, design tokens, or any user-facing layout.

---

# Part A — ReceiptDraft is never deleted (storage + CloudKit leak)

## A1. Problem (verified in code)

`ReceiptProcessingPipeline.persistDraftPages` ([ReceiptProcessingPipeline.swift:161](IntelliExpense/Capture/ReceiptProcessingPipeline.swift), :224–241) saves a `ReceiptDraft` + `ReceiptDraftPage` rows — full-resolution `imageData` and `thumbnailData` via `@Attribute(.externalStorage)` — *before* OCR runs, by design (never lose a capture). But **no code path ever deletes a draft**; `context.delete` is called only for groups/receipts:

1. **Save path:** `ReceiptReviewForm.save` (ReceiptReviewForm.swift:202–256) copies every draft page's bytes into new `ReceiptAttachment` rows (:224–234) and saves — the draft and its duplicate image data remain forever.
2. **Discard path:** the Discard button just calls `dismiss()` (ReviewViews.swift:134); swipe-dismissing the review sheet (`.sheet(item: $reviewForm)`, ContentView.swift:201–209) does the same. Draft remains.
3. **Attach path:** `Receipt.applyAttachedCapture` (ReceiptReviewForm.swift:311–341) copies `result.draft.pages` into attachments and saves — `result.draft` remains.
4. **Error path:** the draft is persisted at pipeline line 161; if OCR throws at :163 the error propagates and the draft is orphaned with no UI referencing it.

Because the whole schema is CloudKit-mirrored (PersistenceStack.swift), every scan roughly **doubles its image footprint permanently** and syncs the garbage to the private database and every device.

## A2. Requirements

### A-R1 — Save deletes the draft in the same transaction

In `ReceiptReviewForm.save(in:group:)`, after building `attachments` and `extraction` (data is copied by value into `ReceiptAttachment`, so this is safe) and before `try context.save()`:

```swift
if let draft { context.delete(draft) }
```

Cascade removes the pages (`ReceiptDraft.pages` has `deleteRule: .cascade`, PersistenceModels.swift:19). Record success on the form: add `private(set) var didSave = false`, set `true` after the save succeeds.

### A-R2 — Discard (button *and* swipe-dismiss) deletes the draft, idempotently

Add to `ReceiptReviewForm`:

```swift
func discardIfUnsaved(in context: ModelContext)
```

Behavior: if `didSave == false` and `draft` exists and has not already been deleted (`draft.modelContext != nil` guard, or an internal `didCleanUp` flag), delete it and `try? context.save()`. Must be a no-op on second call and after a successful save.

Wire-up in `ReceiptReviewView` (ReviewViews.swift):

- Discard button (:134): `form.discardIfUnsaved(in: modelContext); dismiss()`.
- Add `.onDisappear { form.discardIfUnsaved(in: modelContext) }` on the view — this catches the sheet's interactive swipe-dismiss, which never touches the button. Idempotency (above) is what makes the double-fire from the button path and the post-save fire harmless.

`ReceiptReviewForm.manual()` has `draft == nil` — every path must tolerate that (guards already imply it).

### A-R3 — Attach flow deletes the incoming draft

In `Receipt.applyAttachedCapture(_:in:)` (ReceiptReviewForm.swift:311–341), after the pages are copied into `ReceiptAttachment`s and the extraction record is upserted, add `context.delete(result.draft)` before the existing `try context.save()` (:339). The offset-indexing and diff behavior stay identical.

### A-R4 — Launch sweep for legacy + error-path orphans

A-R1–A-R3 stop new leaks but existing installs already carry orphans, and the OCR-failure path (A1 item 4) still strands a fresh draft. Add a best-effort janitor, run once per launch (e.g. from the app's startup `.task`, alongside the availability refresh in ContentView):

- Fetch all `ReceiptDraft` where `max(createdAt, lastUpdatedAt) < now − 48h` and delete them; `try? context.save()`.
- **48 hours, not "all drafts":** drafts sync via CloudKit, so a device launching while *another* device has a review sheet open must not delete the in-flight draft. Review sessions live seconds-to-minutes; 48h is comfortably safe and still drains legacy garbage within two days.
- Failures are ignored (retried next launch). No UI.

### A-R5 — Out of scope

- Not persisting drafts until after OCR (would violate the never-lose-a-capture intent).
- Populating `modelOutputJSON` (separate audit finding, separate change).
- Any change to `ReceiptProcessingPipeline` behavior or its tests.

## A3. Tests (TDD — write first; in-memory `ModelContainer`, follow `PersistenceTests.swift` style)

1. **Save cleans up:** build a form with a 2-page draft, `save(in:group:)` → fetch counts: `ReceiptDraft == 0`, `ReceiptDraftPage == 0`; the saved receipt has 2 attachments whose `imageData` equals the original page bytes.
2. **Discard cleans up, idempotently:** `discardIfUnsaved` → draft + pages gone; calling it a second time does not throw or crash.
3. **No double-delete after save:** `save` then `discardIfUnsaved` → still exactly 1 receipt, 0 drafts, no crash.
4. **Manual form:** `ReceiptReviewForm.manual()` — `save` and `discardIfUnsaved` both work with no draft present.
5. **Attach cleans up:** `applyAttachedCapture` on a receipt with 1 existing attachment and a 1-page draft → receipt has 2 attachments with correct `pageIndex` offset, and 0 drafts remain.
6. **Sweep threshold:** two drafts, one stamped 3 days old, one fresh → janitor deletes only the old one.

## A4. Acceptance criteria

- [ ] Scan → Save: no `ReceiptDraft`/`ReceiptDraftPage` rows remain (assert in tests; on device, repeated scans no longer grow storage in Settings ▸ General ▸ iPhone Storage).
- [ ] Scan → Discard button, and scan → swipe the sheet down: draft rows are gone in both cases.
- [ ] Attach a scan to an existing receipt: attachments appear, no draft remains.
- [ ] Fresh launch on an install with pre-existing orphaned drafts older than 48h: they are removed; a draft younger than 48h survives.
- [ ] Existing `CapturePipelineTests` and `PersistenceTests` pass unchanged.

---

# Part B — Locale-naive amount parsing silently corrupts money

## B1. Problem (verified in code)

The review amount field uses `.keyboardType(.decimalPad)` (ReviewViews.swift:62), which offers the **locale's** decimal separator — a comma in de_DE, fr_FR, es_ES, pt_BR, and many more regions (English-only UI does not prevent this; the keyboard follows device region). Parsing, however, is locale-naive `Decimal(string:)` in two places:

- `ReceiptReviewForm.parsedAmount` (ReceiptReviewForm.swift:258–260) — feeds `canSave`, `save`, chip-selection predicates, and autofill conflict detection.
- `DuplicateNotice.isDuplicate` (ReviewViews.swift:225).

`Decimal(string: "12,50")` stops at the comma and returns **12** — non-nil, so `canSave` passes and `save()` persists a wrong total with no error. This violates the repo's core rule: *Money is `Decimal` end-to-end; locale-aware `FormatStyle` formatting* (CLAUDE.md).

A second inconsistency compounds it: prefill/chip text is formatted with a hardcoded `en_US_POSIX` dot (`formatAmount`, ReceiptReviewForm.swift:280–288), so on a comma-region device the prefilled text shows `.` while the keyboard offers `,` — mixed separators in one field.

Note: `en_US_POSIX` parsing of **model output** (FoundationModelReceiptService.swift:263) is correct and stays untouched; this spec is about *user-typed* text only.

## B2. Design

`ExpenseCore` already contains the right disambiguation logic — `ReceiptAmountParser.decimal(from:)` (ReceiptAmountParser.swift:75–109) resolves dot/comma per token — but it is `private` and, being built for OCR, **strips** unexpected characters instead of rejecting them (`"12a50"` → `1250`), which is exactly the wrong behavior for user input. So: add a small strict, pure, locale-parameterized parser to `ExpenseCore` next to it (sharing internals where practical), and route all user-input parsing through it.

## B3. Requirements

### B-R1 — `AmountInputParser` in ExpenseCore (pure, strict, testable)

```swift
public enum AmountInputParser {
    /// Strictly parses user-typed amount text. Returns nil rather than guessing.
    public static func parse(_ text: String, locale: Locale) -> Decimal?
}
```

Rules (deterministic, in order):

1. Trim whitespace. Empty → `nil`.
2. **Strict charset:** any character other than digits, `.`, `,` → `nil`. Never strip-and-continue (that is the OCR parser's job, not the input parser's). Negative amounts → `nil`.
3. Both `.` and `,` present → the **last-occurring** separator is the decimal separator, the other is grouping (handles `1,234.56` and `1.234,56` regardless of locale).
4. One separator character occurring **multiple times** → grouping; require every group after the first to be exactly 3 digits, else `nil` (`1.234.567` → 1234567; `1.2.3` → `nil`).
5. One separator, single occurrence:
   - equals `locale.decimalSeparator` → decimal separator (`"12,50"` in de_DE → 12.50; `"12,345"` in de_DE → 12.345);
   - otherwise, exactly 3 digits follow → grouping (`"12,345"` in en_US → 12345);
   - otherwise, 1–2 digits follow → decimal separator (lenient cross-separator typing: `"12.50"` on a de_DE device → 12.50);
   - otherwise → `nil`.
6. Normalize to a dot-decimal plain string and finish with `Decimal(string:locale: en_US_POSIX)`.

Locale is always an explicit parameter — no hidden `Locale.current` inside `ExpenseCore` (keeps the package pure and the tests deterministic).

### B-R2 — Form parses and formats with the same locale

In `ReceiptReviewForm`:

- Add `private let locale: Locale` set from a new init parameter `locale: Locale = .current` (both initializers / `manual()`), so tests can inject de_DE etc.
- `parsedAmount` (:258–260) → `AmountInputParser.parse(amountText, locale: locale)`. Change its access from `private` to internal (`var parsedAmount: Decimal?`) so the view layer can reuse it (B-R3).
- `formatAmount` (:280–288) → format with the form's `locale` (2 fraction digits, no grouping — keep `usesGroupingSeparator = false`), so prefill (:77), `chooseTotalAmount` (:127), and autofill (:164) all produce text whose separator matches the user's keyboard. The B-R1 round-trip guarantee below makes this safe.

Everything downstream — `canSave`, `save`, `isTotalAmountChoiceSelected`, autofill conflict checks — flows through `parsedAmount` and needs no further changes.

### B-R3 — Duplicate detection uses the form's parser

`DuplicateNotice.isDuplicate` (ReviewViews.swift:225): replace `Decimal(string: form.amountText)` with `form.parsedAmount`. One parser, one truth.

### B-R4 — Round-trip invariant

For every `Decimal` with ≤ 2 fraction digits and every supported locale: `AmountInputParser.parse(formatAmount(d), locale:) == d`. Assert in tests across at least `en_US`, `de_DE`, `fr_FR`, `en_IN`, `ja_JP` (fr_FR matters: its decimal separator is `,` and its grouping separator is a narrow no-break space, which the strict charset must not receive because `formatAmount` disables grouping).

### B-R5 — Out of scope

- `ReceiptAmountParser` OCR behavior, `FoundationModelReceiptService` parsing/formatting (`en_US_POSIX` is correct there), and the deterministic parser's language tables — all unchanged.
- Currency-aware fraction-digit limits (JPY has 0, BHD has 3) — do not reject based on currency; the user is the authority on the review screen.
- Any keyboard or field UI change.

## B4. Tests (TDD — write first)

`ExpenseCore` (`swift test`, new `AmountInputParserTests`, table-driven):

| Input | Locale | Expected |
|---|---|---|
| `"12.50"` | en_US | 12.50 |
| `"12,50"` | de_DE | 12.50 |
| `"12.50"` | de_DE | 12.50 (rule 5, 2 digits follow) |
| `"1,234.56"` | en_US | 1234.56 |
| `"1.234,56"` | de_DE | 1234.56 |
| `"1.234.567"` | de_DE | 1234567 |
| `"12,345"` | en_US | 12345 |
| `"12,345"` | de_DE | 12.345 |
| `"1.2.3"` | any | nil |
| `"12,50abc"` | any | nil |
| `"-5"` | any | nil |
| `""`, `"  "` | any | nil |
| `",5"` | de_DE | 0.5 |

Plus the B-R4 round-trip property over the five locales.

App target (`IntelliExpenseTests/ReceiptReviewFormTests.swift`, existing builder style):

1. Form with `locale: Locale(identifier: "de_DE")`, `amountText = "12,50"` → `canSave == true`; `save` persists `totalAmount == Decimal(string: "12.5")`.
2. Same form, `amountText = "1.2.3"` → `canSave == false`; `save` throws `.invalidAmount`.
3. Prefill: merged receipt with primary total 1234.5 on de_DE form → `amountText == "1234,50"`; `parsedAmount == 1234.5`; the matching chip predicate (`isTotalAmountChoiceSelected`) is true — chips stay consistent with `SPEC-choice-chip-selection.md` R1.
4. `chooseTotalAmount` on de_DE form emits comma text and the chip remains selected.

## B5. Acceptance criteria

- [ ] Device region Germany (or any comma-decimal region): typing `12,50` on the decimal pad enables Save and persists exactly 12.50; the receipt row and CSV export show the right amount.
- [ ] Prefilled amounts on that device render with a comma, matching the keyboard.
- [ ] Pasting `1,234.56` on a US-region device parses as 1234.56; pasting `1.234,56` on a German-region device parses the same.
- [ ] Garbage (`1.2.3`, `12,50abc`) disables Save instead of silently truncating; nothing crashes.
- [ ] Duplicate detection fires for a comma-typed amount equal to an existing receipt's total.
- [ ] Existing `ReceiptParserTests`, `ExtractionMergePolicyTests`, and `ReceiptServiceWrapperTests` pass unchanged.

---

# Verification commands (both parts)

```bash
# ExpenseCore: new AmountInputParserTests + existing suites
cd ExpenseCore && swift test

# App unit tests: draft-cleanup tests + review-form locale tests
xcodebuild -project IntelliExpense.xcodeproj -scheme IntelliExpense \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' test

# Build only
xcodebuild -project IntelliExpense.xcodeproj -scheme IntelliExpense \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' build
```

Manual pass for Part B: set the simulator region to Germany (Settings ▸ General ▸ Language & Region), scan or create a manual receipt, type `12,50`, save, and verify the stored amount and export CSV. For Part A: scan and discard several receipts, then confirm no `ReceiptDraft` rows via a debug fetch (or re-run the unit suite).
