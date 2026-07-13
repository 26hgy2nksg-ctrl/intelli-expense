# SPEC - Foundation Models amount and vendor evidence prompt

**Status:** proposed
**Owner files:**
- `IntelliExpense/Capture/FoundationModelReceiptService.swift` - prompt factory, Foundation Models schema, guided generation call
- `IntelliExpense/Capture/ReceiptProcessingPipeline.swift` - handoff from OCR/parser into the model request
- `ExpenseCore/Sources/ExpenseCore/Parsing/ReceiptParser.swift` - deterministic amount/vendor baseline and field evidence
- `ExpenseCore/Sources/ExpenseCore/Parsing/ReceiptLanguageProfiles.swift` - total/subtotal/tax/payment/vendor-skip vocabulary used for evidence extraction
- `ExpenseCore/Sources/ExpenseCore/Extraction/ExtractionContracts.swift` - `ExtractionModelRequest` gains the compact evidence packet that the pipeline hands to the model service
- `ExpenseCore/Sources/ExpenseCore/Extraction/ReceiptPromptEvidenceBuilder.swift` (new) - pure evidence-packet builder (D1-D3)
- `ExpenseCore/Sources/ExpenseCore/Extraction/ModelOutputEvidenceValidator.swift` (new) - pure post-generation amount/vendor support validation (D6)
- `ExpenseCore/Sources/ExpenseCore/Extraction/ReceiptMergePolicy.swift` - model/deterministic merge behavior and ambiguity limits
- `ExpenseCore/Sources/ExpenseCore/Extraction/ModelOutputAuditEncoder.swift` - persisted model-output audit trail for before/after debugging
- `IntelliExpenseTests/ReceiptServiceWrapperTests.swift`, `IntelliExpenseTests/CapturePipelineTests.swift`, `ExpenseCore/Tests/ExpenseCoreTests/ReceiptParserTests.swift`, `ExpenseCore/Tests/ExpenseCoreTests/ExtractionMergePolicyTests.swift` - prompt, pipeline, parser, and merge coverage

**Docs this spec amends:**
- `PRD.md` section 6.2 - clarify that deterministic parser output feeds a compact evidence prompt, not just a raw baseline
- `PRD.md` section 6.3 - clarify that the Foundation Models layer receives compact receipt evidence and that amount/vendor model outputs are accepted only when supported by OCR evidence

---

## 1. Problem

The current Foundation Models prompt sends a broad OCR transcript plus a short deterministic baseline:

- session instructions: factual receipt fields, English schema, structured values only, do not invent data
- prompt body: locale line, alternate-reason language line, one general extraction sentence, optional `Deterministic baseline: ...`, and `OCR text: ...`
- OCR cap: `16,000` characters, using head/tail truncation

This is too much undifferentiated text for the two fields where mistakes are most expensive: **total amount** and **vendor**.

Amount errors are especially risky because receipts contain many plausible numbers: invoice IDs, GST/VAT IDs, order numbers, line items, tax, subtotal, rounding lines, card masks, and totals. The existing parser already tries to classify these, but the model currently sees the raw OCR and must rediscover that logic inside a small on-device context window. In the synthetic `synthetic_airport_food_stall_ocr` fixture, for example, the text contains a huge invoice number, repeated `142.86`, `7.14`, and a bare `Total:` label near a noisy `150.0...` line. That is exactly the kind of input where an on-device model can pick a plausible but wrong number.

Vendor errors are similarly easy. OCR often starts with brand, concession operator, legal entity, tax registration, address, or receipt metadata. The app wants the user-facing merchant/store name, not GSTIN/FSSAI lines, tax IDs, addresses, payment processors, cashier metadata, or a legal entity when a clearer store name appears above it. The deterministic parser already skips several metadata classes, but the model prompt does not expose that reasoning clearly.

Apple's on-device Foundation Models prompting guidance, checked in the local Apple docset on 2026-07-09 (`/documentation/foundationmodels/prompting-an-on-device-foundation-model`, docset v24703), points directly at the fix:

- keep prompts concise and specific because on-device models are smaller and have a smaller context window
- reduce the amount of thinking the model needs to do
- move conditional logic into code instead of putting long if/else logic in the prompt
- use guided generation constraints for structured output when possible
- use examples sparingly and keep them simple if they are needed

The current prompt is directionally correct but asks the model to do too much field selection from raw OCR. For amount and vendor, the app should do the cheap deterministic filtering in code, then ask the model to choose from compact evidence.

## 2. Goals

- Improve amount and vendor extraction accuracy without sending images or data off-device.
- Keep the full raw OCR transcript stored for provenance, but send the model a shorter, field-aware evidence block.
- Preserve the current privacy/product architecture: Vision OCR, deterministic parser, Foundation Models guided generation, merge, review.
- Preserve the PRD rule that deterministic parser results are baseline truth and the model refines/fills gaps; the model must not silently override high-confidence deterministic amount/vendor values.
- Make amount and vendor model outputs evidence-gated: unsupported model values are ignored or downgraded before merge.
- Keep `Decimal` exactness end-to-end; do not introduce `Double`/`Float` for money.
- Keep localization behavior: prompts/schema stay in English, locale steering stays, and user-visible alternate reasons stay in the app UI language.
- Add testable, pure extraction/prompt behavior so the improvement can be validated without depending on nondeterministic live model output in CI.

## 3. Non-goals

- No line-item extraction.
- No image-to-model input. The model still receives text only.
- No third-party model, server API, analytics, or network call.
- No new UI, no new review fields, and no string-catalog changes.
- No change to receipt persistence, CloudKit schema, export CSV format, or attachment storage.
- No change to manual-entry behavior.
- No permanent "dumb mode"; existing availability/degradation behavior remains.
- No broad merge-policy rewrite. This spec only tightens model input and validates amount/vendor model support before existing merge rules run.
- No generic prompt-optimization framework. This is a receipt-specific change focused on amount and vendor.

## 4. Design Decisions

### D1 - Build compact receipt evidence in code before prompting

Add a pure evidence-building step before `FoundationModelReceiptPromptFactory` assembles the prompt. It takes the full OCR text plus the deterministic parse result and emits a compact, field-aware evidence packet.

The evidence packet should include:

- **Header/vendor candidates:** the first merchant-like lines after removing blank lines, pure amounts, date-only lines, known total/subtotal/tax labels, payment hints, and known metadata/tax-registration lines.
- **Amount candidates:** lines containing parsed monetary values, grouped by role: labeled total/amount-due/grand-total lines, subtotal lines, tax lines, fallback amount lines, and obvious non-total identifiers.
- **Parser candidates:** deterministic vendor, amount, currency, date, and payment values with their confidence and evidence lines. Low-confidence amount candidates may appear as "parser is unsure" evidence, but not as a trusted baseline.
- **Receipt tail context:** a short tail window because many receipts print the final payable total at the bottom.

Placement and bounds:

- The evidence builder is a new pure type in `ExpenseCore` (`Extraction/ReceiptPromptEvidenceBuilder.swift`) so every behavior in D1-D3 is testable with `swift test` and deterministic fakes, without the app target or a device.
- The packet reaches the prompt factory through `ExtractionModelRequest` (`ExtractionContracts.swift`): the pipeline builds the packet once from the OCR text plus the deterministic parse it already has, and passes it alongside the raw text it already persists. The app-target prompt factory only formats; it does not re-derive evidence.
- The packet is bounded by a configurable character budget, default 4,000 characters — well under the current 16,000 raw cap — covering the header/vendor, amount-candidate, parser, and tail sections together. When the budget overflows, drop lowest-priority candidates first; the top merchant-like header line and the strongest final-total candidate must always survive.

The model prompt should say "OCR evidence" or equivalent, not "OCR text", because the model is no longer receiving the whole transcript as its primary input. The full OCR remains stored in `ReceiptDraft.rawOCRText` and `ExtractionRecord.rawOCRText` exactly as today.

Rationale: Apple recommends concise, specific prompts for the on-device model. Filtering in code uses deterministic logic we can test, reduces token load, and leaves less room for the model to choose an invoice number or legal entity.

### D2 - Amount evidence has an explicit priority order

The amount evidence packet must make final payable totals easier to identify than other numbers.

Priority order:

1. Labeled final totals: total, grand total, amount due, balance due, summe, total ttc, and equivalents from `ReceiptLanguageProfiles`.
2. Parser high-confidence total where the evidence line is a labeled final-total line.
3. Parser medium-confidence total with clear final-total evidence.
4. Low-confidence fallback amounts only when no final-total line exists.
5. Subtotal, tax, service charge, round-off, invoice/order/GST/VAT identifiers, card masks, and dates are never final-total candidates.

The prompt should instruct the model to choose `unknown` for `totalAmount` when the evidence does not contain a final payable total. It should not ask the model to infer a total from subtotal plus tax unless the evidence packet already marks the reconciliation as valid.

Rationale: amount mistakes are the most damaging extraction failure. The model should not perform fresh arithmetic or guess from a wall of numbers; it should pick from the evidence prepared by the app.

### D3 - Vendor evidence prefers the consumer-facing merchant

The vendor evidence packet must separate likely merchant lines from metadata and legal/tax lines.

Rules:

- Prefer the first merchant-like header line when it contains letters and is not a known metadata, amount, date, total, tax, payment, address, or registration line.
- Prefer a shorter brand/store line over a later legal entity when both appear near the top and the shorter line is not metadata.
- Do not use GSTIN, FSSAI, VAT, tax ID, receipt number, invoice number, cashier, terminal, card network, address-only, or payment processor lines as vendor.
- If only a legal entity appears and no better merchant-like line exists, it may be a vendor candidate.

The prompt should ask for the user-facing merchant/store name printed on the receipt, not the operator, tax registration, address, or payment entity.

Rationale: the user searches and reviews by merchant. A synthetic storefront name such as "BLR SKY BITES - T1" is useful; a tax ID or service-company legal name often is not.

### D4 - Replace the generic prose prompt with a short field checklist

Keep the session instructions short. Replace the current one-sentence extraction prompt with an ordered field checklist that tells the model exactly what to return:

- vendor: user-facing merchant/store name from vendor evidence
- date: receipt issue/purchase date in `yyyy-MM-dd`
- totalAmount: final payable total as a plain decimal string
- currencyCode: ISO 4217 code
- paymentMethod: card, cash, or unknown
- expenseType: food, hotel, flight, taxi, other, or unknown

Keep the existing rules:

- use OCR evidence only
- prefer `unknown` over guessing
- return alternates only when genuinely torn between two supported readings
- write user-visible alternate reasons in the app UI language

Avoid long conditional paragraphs. Conditional work belongs in the evidence builder and post-model validator.

Rationale: this follows Apple's guidance to use direct, simple language and reduce on-device reasoning burden.

### D5 - Use guided generation constraints for closed vocab fields

Apply guided-generation value constraints for fields whose legal values are closed sets:

- payment method primary/alternate: `card`, `cash`, `unknown`
- expense type primary/alternate: `food`, `hotel`, `flight`, `taxi`, `other`, `unknown`

Do not try to constrain vendor, amount, date, or currency with hand-built finite lists in the schema. Those fields need parsing/validation after generation instead.

Apple's local docset for `/documentation/foundationmodels/generationguide/anyof(_:)` (docset v24703) says the guide enforces that a string be one of the provided values on iOS 26.0+. This matches the app's deployment target and current Foundation Models usage.

Rationale: prose instructions are weaker than guided constraints for enum-like output. This removes avoidable invalid model text from fields that already have fixed app domains.

### D6 - Evidence-gate model amount and vendor before merge

Before `ReceiptMergePolicy` receives the model result, validate model amount and vendor values against the evidence packet. The validation lives in a new pure `ExpenseCore` type (`Extraction/ModelOutputEvidenceValidator.swift`), and the pipeline invokes it between the model response and the existing merge call — merge policy rules themselves do not change (per the non-goals):

- A model amount is supported only when its normalized decimal value matches a final-total amount candidate or a parser-supported amount candidate in the evidence packet. Formatting differences such as `150.0` vs `150.00` are equivalent; unrelated numbers are not.
- A model amount that matches only subtotal, tax, invoice, order, GST/VAT, date, or card-mask evidence is unsupported.
- A model vendor is supported only when its normalized text matches or cleanly derives from a vendor candidate. Case, punctuation, and OCR whitespace differences are acceptable; unrelated legal/tax/payment/address lines are not.
- Unsupported model primary values become `unknown` for that field. Unsupported alternates are dropped.
- If deterministic amount/vendor is high-confidence, existing merge behavior still keeps deterministic primary. If the model has a supported conflicting value, it may remain the second option under the existing ambiguity rules.

Rationale: prompt improvements reduce bad outputs, but the app still needs a deterministic guardrail. The model should not be able to introduce a number or merchant name that the OCR evidence builder did not surface.

### D7 - Keep raw model output audit useful

`modelOutputJSON` should continue storing what the model actually returned. The evidence-gated value used for merge should also be debuggable in tests/logs, but do not overwrite the raw audit trail with post-validated output.

Implementation may either:

- store only the raw model output as today and test the post-validation separately, or
- version the audit JSON to include both raw and accepted/rejected status for amount/vendor.

If the audit JSON format changes, keep it deterministic, versioned, sorted, and Decimal-safe as required by `SPEC-processing-overlay-and-extraction-audit.md`.

Rationale: if amount/vendor remain wrong on device, the raw-vs-accepted distinction is the evidence we need to debug the prompt instead of guessing.

### D8 - Do not add few-shot examples in the first pass

Do not add broad few-shot examples to the initial implementation. The compact evidence block and field checklist should be tested first.

If evaluation still shows recurring amount/vendor failures, a follow-up may add at most two tiny examples, both fixture-backed and receipt-specific:

- one example where an invoice/order number is not the amount
- one example where the first merchant-like header line beats a later legal/tax entity

Rationale: Apple allows few-shot prompting but warns that on-device examples should be simple and not too long. Examples are a second lever, not the first fix.

## 5. Edge Cases

- **Airport/vendor operator receipts:** prefer the consumer-facing merchant line over a concession operator/legal entity when both are present.
- **Receipts with tax identifiers near the top:** GSTIN, FSSAI, VAT, tax ID, terminal, receipt number, and invoice lines never become vendor candidates.
- **Total label separated from amount:** if `Total:` appears on one line and the amount is nearby below it, the evidence builder may group them as one candidate only when the distance is small and no stronger final-total candidate exists.
- **Crumpled/partial OCR:** if the only apparent amount contains OCR letter noise such as `9.9O`, keep amount unknown rather than coercing it.
- **Repeated line-item amounts:** repeated product/tax amounts are not totals unless the evidence labels them as final payable totals.
- **Subtotal + tax:** use reconciliation only when deterministic parser already validates it. Do not ask the model to perform arithmetic from scratch.
- **Decimal comma receipts:** preserve comma evidence in the prompt, but model output still uses plain dot-decimal strings so downstream `Decimal` parsing stays exact.
- **Multi-page receipts:** evidence builder considers all pages in OCR order but still produces a bounded prompt; page order must remain stable.
- **No raw OCR text:** model is not called today for empty OCR. This remains unchanged.
- **Unsupported receipt language:** existing deterministic fallback and notice behavior remain unchanged.
- **Very long receipts:** evidence packet remains bounded and includes only the useful header, candidate, and tail sections; full raw OCR remains in persistence for review/provenance.

## 6. Accessibility and Localization

- No user-facing UI strings are added or changed.
- No accessibility identifiers are added or changed.
- Prompt/session text remains English, including schema property names and guide descriptions, matching PRD section 3.2-B.
- Preserve the exact locale steering helper behavior: omit the locale line for `en_US`; otherwise include `The person's locale is <locale identifier>.`
- Preserve the alternate-reason language instruction so any user-visible reason strings are written in the app UI language.
- Do not put language-specific total/vendor knowledge inline in the prompt factory. Total labels, tax labels, payment hints, vendor skip keywords, decimal conventions, and date formats stay in `ReceiptLanguageProfiles` or adjacent parser data.

## 7. Test Impact

### ExpenseCore unit tests

Add pure tests for the evidence builder:

1. `indian_gst`: amount evidence marks `GRAND TOTAL ₹1,240.00` as final-total evidence and excludes `Bill No`, `GSTIN`, `CGST`, and `SGST` as final-total candidates. Vendor evidence is `ANAND RESTAURANT`.
2. `german_rewe`: amount evidence marks `SUMME €84,50` as final-total evidence and vendor evidence is `REWE CITY`.
3. `french_bakery`: amount evidence marks `TOTAL TTC 11,00 EUR` as final-total evidence and vendor evidence is `BOULANGERIE LUMIERE`.
4. `synthetic_airport_food_stall_ocr`: amount evidence supports `150.0` as the payable total and rejects `420001000900123456`, `142.86`, `7.14`, `996331`, `GST55`, and tax/metadata lines as final totals. Vendor evidence prefers `BLR SKY BITES - T1` over `AIRPORT FOOD SERVICES PRIVATE LIMITED`, GST/FSSAI lines, and product lines.
5. `crumpled_partial`: amount evidence does not surface `9.9O` as a supported amount; vendor evidence remains `CITY KIOSK`.
6. Long synthetic OCR: evidence output stays under the configured prompt-evidence budget while retaining the top merchant line and bottom final-total line.

Add model-output validation tests:

1. Unsupported amount primary matching an invoice number is dropped before merge.
2. Unsupported amount alternate matching a tax line is dropped.
3. Supported amount with equivalent formatting (`150.0` vs `150.00`) survives.
4. Unsupported vendor primary matching a tax-registration or payment line is dropped.
5. Supported vendor with punctuation/case/spacing normalization survives.
6. High-confidence deterministic amount remains primary even when a supported model conflict exists.

### App target tests

Update `ReceiptServiceWrapperTests`:

1. Prompt contains a compact `OCR evidence` section rather than raw full transcript language.
2. Prompt contains the amount priority/checklist language for final payable total and excludes known non-total identifiers from trusted candidate sections.
3. Prompt contains vendor guidance that asks for user-facing merchant/store name and rejects tax IDs/legal/payment/address metadata.
4. Locale steering and alternate-reason language tests continue to pass.
5. Long OCR test changes from head/tail raw truncation to evidence retention: top vendor line and bottom final-total line must survive, middle noise must not.

Update `CapturePipelineTests`:

1. Pipeline still sends raw OCR to persistence and audit fields unchanged.
2. Pipeline sends compact evidence prompt into the model request path.
3. Model timeout/unavailable/unsupported-language fallback behavior is unchanged.

### Evaluation pass

Because live Foundation Models output is not deterministic enough for CI, add a repeatable manual/device evaluation checklist for this spec:

- Run the model on the six existing receipt fixtures (`indian_gst`, `german_rewe`, `french_bakery`, `us_market`, `synthetic_airport_food_stall_ocr`, `crumpled_partial`) plus one owner-observed amount/vendor failure fixture if the raw OCR can be safely redacted and committed.
- Save the raw prompt, model output JSON, accepted post-validation fields, and merged review fields as a local evidence artifact under `docs/specs/evidence/`.
- Pass condition: amount and vendor are correct or unknown for every fixture; no unsupported wrong amount/vendor reaches review as the primary field.

## 8. Acceptance Criteria

1. The Foundation Models prompt no longer sends up to 16,000 raw OCR characters as the primary context. It sends a bounded, compact evidence packet plus a short field checklist.
2. Full raw OCR is still persisted unchanged on drafts and saved extraction records.
3. Amount evidence prioritizes final payable totals and excludes invoice/order IDs, GST/VAT/tax IDs, subtotals, tax lines, dates, card masks, and metadata as final-total candidates.
4. Vendor evidence prioritizes the user-facing merchant/store name and excludes tax IDs, legal/registration metadata, addresses, payment processors, receipt IDs, and product lines.
5. Model-generated amount values that are unsupported by amount evidence are dropped before merge.
6. Model-generated vendor values that are unsupported by vendor evidence are dropped before merge.
7. Deterministic high-confidence amount/vendor values remain primary under the existing merge policy.
8. Closed-vocabulary fields use guided constraints where supported by Foundation Models on iOS 26: payment method and expense type cannot produce arbitrary strings.
9. Existing locale behavior remains: English prompt/schema, exact locale steering line, and localized alternate reasons.
10. Existing availability and degradation behavior remains: model not ready, unsupported locale, timeout, and empty OCR still reach review with deterministic/manual fallback as today.
11. Tests prove the known amount/vendor trouble shapes: Indian GST, German decimal comma, French total TTC, airport receipt with invoice/tax noise, and crumpled partial amount.
12. No new user-facing strings, UI surfaces, CloudKit schema fields, export columns, or network calls are introduced.

## 9. Verification Commands

Implementation must run the normal app validation lane:

```bash
make test-core
make test-app
make install-device
```

If the paired iPhone/signing path is unavailable, stop and report the blocker. This is normal app behavior, so the durable app install lane is required before handoff.
