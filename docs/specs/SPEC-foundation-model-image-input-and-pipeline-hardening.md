# SPEC - Foundation Models image input (iOS 27) and extraction pipeline hardening

**Status:** implemented (device evaluation evidence pending physical degraded-receipt captures)
**Owner files:**
- `IntelliExpense/Capture/FoundationModelReceiptService.swift` - availability provider, prompt factory, guided-generation call, timeout/retry, image attachment on the iOS 27 path
- `IntelliExpense/Capture/ReceiptProcessingPipeline.swift` - orchestration, stage notices, degradation ladder, retry invocation
- `IntelliExpense/Capture/VisionDocumentOCRService.swift` - per-page OCR error isolation
- `IntelliExpense/Capture/ReceiptCapturePageBuilder.swift` - source of the prompt-attachment image variant (downscaled)
- `ExpenseCore/Sources/ExpenseCore/Extraction/ExtractionContracts.swift` - `ModelAvailabilityProviding` gains an image-input capability signal; `ExtractionModelRequest` gains optional image payloads; fakes updated
- `ExpenseCore/Sources/ExpenseCore/Extraction/ReceiptPromptEvidenceBuilder.swift` - token-aware budgeting hooks
- `ExpenseCore/Sources/ExpenseCore/Extraction/ModelOutputEvidenceValidator.swift` - image-grounded acceptance tier; date/currency plausibility validation
- `ExpenseCore/Sources/ExpenseCore/Extraction/ReceiptMergePolicy.swift` - confidence tiers for model options (evidence-supported vs image-grounded)
- `ExpenseCore/Sources/ExpenseCore/Extraction/ModelOutputAuditEncoder.swift` - audit records whether the image path ran and which values were accepted per tier
- `Makefile`, `project.yml` - default repo-scoped Xcode 27 beta device lane with an explicit stable-Xcode fallback
- `IntelliExpenseTests/ReceiptServiceWrapperTests.swift`, `IntelliExpenseTests/CapturePipelineTests.swift`, `ExpenseCore/Tests/ExpenseCoreTests/*` - coverage listed in §7

**Docs this spec amends:**
- `PRD.md` §6.2 - OCR remains the deterministic baseline input; on image-capable devices the model prompt additionally carries the receipt image
- `PRD.md` §6.3 - merge policy gains a third acceptance tier for image-grounded model values (secondary options only; deterministic baseline still wins)
- `PRD.md` §6.4 - degradation matrix gains one row: image input unavailable → text-only model path, silently
- `CLAUDE.md`, `AGENTS.md`, `ASC.md` - document the default Xcode 27 beta device-install lane and stable fallback

---

## 1. Problem

Three compounding problems, confirmed by an end-to-end review of the pipeline on 2026-07-11:

**The model never sees the receipt.** The Foundation Models step receives only a pre-digested OCR evidence packet (`ReceiptPromptEvidenceBuilder`), and `ModelOutputEvidenceValidator` discards any vendor or total the model returns that is not already present in that packet. This is the correct guardrail for a text-only model — but it means any OCR miss (glare, thermal-paper fade, crumple, stylized logos as vendor names) is unrecoverable: the parser can't see it, the evidence can't carry it, and the validator would reject it even if the model somehow inferred it. The model's additive value for the two most expensive fields is hard-capped at "pick among parser candidates."

iOS 27's Foundation Models framework (verified against the WWDC26 "What's new in the Foundation Models framework" session and third-party coverage on 2026-07-11) removes exactly this cap: prompts can now carry an image attachment alongside text, guided generation works unchanged, and the third-generation on-device model (AFM 3 Core Advanced, on iPhone 15 Pro-class devices and above) is natively multimodal with a larger context window (~8K tokens on-device, with new `contextSize` / `tokenCount` introspection APIs from 26.4). The owner's device — iPhone 16 Pro Max on iOS 27.0 — is in the supported class.

**Reliability gaps that lose model enrichment silently.** A single transient model failure (30s timeout, `generationFailed`) drops all model output with no retry; the timeout races a sleep task but the underlying generation may not honor cancellation; availability is checked twice per run; multi-page OCR aborts entirely when one page fails to recognize.

**Prompt and validation asymmetries.** Only vendor and total are evidence-validated — a hallucinated date, currency, or payment method passes to the review UI unchecked. All model options are flattened to medium confidence regardless of corroboration. The 18-field schema (primary + alternate + alternate-reason × 6) competes with a 700-token output cap, risking truncation in verbose locales. The prompt budget is a raw 4,000-character count with no awareness of the model's actual token window. The output-language instruction appears in both the prompt and the instructions in slightly different forms.

Apple's on-device prompting guidance (local docset, `/documentation/foundationmodels/prompting-an-on-device-foundation-model`) remains the constraint frame: concise specific prompts, conditionals in code not prose, guided constraints over instructions, reasoning burden minimized.

## 2. Goals

- On devices where Foundation Models supports image input, attach the receipt image to the extraction prompt so the model can recover fields OCR missed — while the deterministic parser remains baseline truth and the text-only path remains byte-for-byte intact everywhere else.
- Keep one app binary: iOS 26 devices, simulators, ineligible hardware, and transient unavailability all continue on the existing text-only or deterministic-only paths with no new blocking states.
- Make the repo-scoped Xcode 27 beta lane the default durable iPhone build/install path, while leaving the machine default (`xcode-select` → Xcode 26.x) untouched and retaining an explicit stable-Xcode fallback.
- Recover from transient model failures with one bounded retry instead of silently degrading.
- Close the validation asymmetry: every model field gets at least a plausibility gate before merge.
- Make model-option confidence reflect corroboration instead of a flat medium.
- Budget the prompt by tokens (using the 26.4 `contextSize`/`tokenCount` APIs where available) instead of raw characters.
- Isolate per-page OCR failures so one bad page no longer aborts a multi-page receipt.
- No tools: extraction stays single-shot guided generation (D5).
- Preserve all standing constraints: `Decimal` end-to-end, no network calls, English prompt/schema with locale steering, no red, no new UI patterns.

## 3. Non-goals

- No line-item extraction, currency conversion, or third-party model/service (PRD §2).
- No Tool-protocol adoption — neither the iOS 27 built-in `OCRTool`/`BarcodeReaderTool` nor custom tools (rationale in D5).
- No Private Cloud Compute. Extraction stays fully on-device.
- No removal of Vision OCR or the deterministic parser on any path. "Skip OCR" was considered and rejected: the PRD's merge policy makes the parser baseline truth, raw OCR text is the persisted provenance/audit artifact, and OCR+parser is the degradation path that keeps capture unblocked when the model is unavailable (PRD §6.4).
- No new review-screen UI, fields, layouts, or interaction patterns. Existing choice chips, attention edges, and provenance disclosure carry the new behavior unchanged.
- No CloudKit schema, export format, or attachment-storage changes.
- No raising the app's deployment target: it stays iOS 26.0.
- No App Store submission from the beta lane (Apple requires release Xcode for submission); the beta lane exists for the owner's device install only.
- No prompt-versioning framework beyond the single availability-gated fork this spec introduces.

## 4. Design Decisions

### D1 - One binary, compile-gated iOS 27 code, default beta phone lane

The iOS 27 image-attachment code paths are isolated behind a compile-time gate plus a runtime `#available`-style check, such that:

- Building with Xcode 26.x (machine default) still compiles the full app with the text-only model path — existing `make test-core`, `make test-app`, `build-sim`, and simulator lanes are unchanged and keep passing on the current toolchain.
- Building with Xcode 27 beta additionally compiles the image-attachment path, which then activates only when the runtime capability check (D3) passes.

The gate mechanism is an implementation choice between a versioned-module `canImport` condition and a custom Swift active-compilation condition set by a dedicated xcodegen build setting; whichever is chosen must fail closed (absent gate → text-only path) and must not fork the source tree.

The Makefile scopes `DEVELOPER_DIR` to the Xcode 27 beta location for device invocations only (default `/Volumes/External-2TB/Applications/Xcode-27-beta.app`, overridable through `XCODE_BETA_DIR`). `make build-device` and `make install-device` are the canonical beta-backed durable-app targets, so normal phone handoffs compile the image-input path. The explicit `-beta` target names remain compatibility aliases. `make build-device-stable` and `make install-device-stable` preserve a deliberate Xcode 26.5/text-only fallback without silently changing what the default handoff exercises. `CLAUDE.md`, `AGENTS.md`, and `ASC.md` document the contract.

Owner setup (one-time, requires Apple ID): download Xcode 27 beta from the Apple Developer downloads page, install it at `/Volumes/External-2TB/Applications/Xcode-27-beta.app` (or override `XCODE_BETA_DIR`), and leave `xcode-select` pointing at Xcode 26.x. No other machine-level change.

Rationale: the owner's other repos must keep building with Xcode 26.x; `DEVELOPER_DIR` scoping is the standard side-by-side mechanism and keeps the beta dependency out of every lane that doesn't need it.

### D2 - Hybrid prompt: evidence packet plus image attachment

On the image-capable path, the extraction prompt carries, in order: the existing locale/output-language steering, the existing field checklist and amount/vendor rules, the structured OCR evidence packet, and the receipt image as a prompt attachment. Nothing about the text-only prompt changes when the image path is off.

- **Which image:** a downscaled prompt variant of the receipt page, produced by `ReceiptCapturePageBuilder` alongside the existing full JPEG and thumbnail. Apple's guidance is that arbitrary sizes are accepted but larger images cost tokens and latency; the prompt variant targets legibility of receipt text at minimum token cost. The exact long-edge target is tuned during implementation against the token budget (D8) and recorded in the audit trail; the full-resolution JPEG persisted for provenance/export is untouched.
- **Multi-page receipts:** attach at most two pages — the first page (vendor header) and the last page (final total) — chosen deterministically. Middle pages are represented by the evidence packet only. Single-page receipts attach that page once.
- **Evidence stays in the prompt.** The image does not replace the evidence packet: evidence gives the model the parser's candidates and the cross-check anchor that the validator (D4) and merge policy rely on. The instructions are amended so the model may use both the evidence and the image, prefers agreement between them, and still prefers `unknown` over guessing.

Rationale: this satisfies the PRD §6.3 merge rule (deterministic baseline, model refines and fills gaps) while finally letting the model fill gaps that OCR created rather than only gaps the parser flagged. "Image-only prompt" was considered and rejected: it discards the parser's candidate anchoring, weakens the validator to plausibility-only for all fields, and spends its token savings on re-deriving what the evidence already states.

### D3 - Runtime image-capability check behind the existing availability protocol

`ModelAvailabilityProviding` gains an image-input capability signal alongside the existing availability status. The live provider derives it from the iOS 27 Foundation Models availability/capability API surface (exact API verified during implementation against the installed SDK — third-party docs agree image input exists only on AFM 3 Core Advanced-class devices, and only a runtime check is definitive). The fakes gain the same signal so every combination is testable: capability present, absent, and present-but-model-unavailable.

Degradation is silent: image capability absent (older device, iOS 26 runtime, base-model hardware, compile gate off) → the text-only prompt runs exactly as today, with no notice, no new blocking state, and no UI difference. `blocksCapture` semantics are unchanged. The audit record (D7) notes which path ran so failures are diagnosable.

Rationale: PRD §6.4 — capture must never be blocked at a cash register, and a missing enhancement is not a degradation the user needs to hear about.

### D4 - Three-tier model-output acceptance replaces the binary validator

`ModelOutputEvidenceValidator` currently keeps or discards vendor/total binarily. It becomes a three-tier classifier applied to every model value:

1. **Evidence-supported** — the value matches an evidence candidate under the existing normalization rules. Merged exactly as today.
2. **Image-grounded** (image path only) — the value is not in the evidence but passes field plausibility (below) and does not collide with a known non-total/non-vendor evidence line (invoice numbers, tax IDs, subtotals, card masks — the existing rejection classes). Accepted as a **secondary option only**: it may never displace a deterministic primary of any confidence, and it may become primary only where the merge policy already promotes model values (deterministic field empty or low-confidence total).
3. **Rejected** — everything else, dropped as today. On the text-only path, tier 2 does not exist and behavior is byte-identical to current.

Plausibility gates close the current asymmetry for all fields, on both paths:

- **date** — must parse as a real calendar date in the schema format and fall within a sane capture window (not in the future beyond a one-day timezone allowance; not implausibly old). Out-of-window dates are rejected, not clamped.
- **currencyCode** — must be a valid ISO 4217 code per Foundation's locale data, never a hardcoded list.
- **totalAmount** — must parse as an exact `Decimal`; image-grounded totals must additionally be positive and structurally price-like.
- **vendor** — image-grounded vendors must not match any evidence line already classified as metadata/tax/payment/address.
- **paymentMethod / expenseType** — already closed sets via guided constraints; no change.

Rationale: the validator was the right guardrail against text hallucination but is the wrong shape once the model has legitimate independent perception. Tier 2 admits that perception without ever letting it silently override the deterministic baseline — the PRD §6.3 invariant survives intact.

### D5 - No tools

The session is created with no Tool implementations, and the iOS 27 per-request tool-calling controls are not adopted. Considered and rejected:

- **Built-in `OCRTool`:** duplicates the app's own Vision OCR with less control (no page normalization, no language profiles, no confidence capture), adds a model-directed round-trip inside a latency-sensitive capture flow, and makes output nondeterministic in a step the test suite currently fakes cleanly.
- **Custom evidence-lookup tool** (model requests more raw OCR lines on demand): solved a context-scarcity problem that the iOS 27 window growth and token budgeting (D8) solve more simply.

One-shot guided generation remains the correct shape for a fixed-schema extraction task. This decision is recorded so future agents don't re-litigate it without new evidence.

### D6 - One bounded retry on transient model failure

The pipeline retries the model step exactly once when the failure is transient — timeout or generation failure — using a fresh session. It does not retry unavailability, unsupported-locale, or context-window-exceeded errors (the last should instead shrink the evidence packet, D8). The combined budget for both attempts is bounded so the processing overlay never hangs: the second attempt gets a shorter timeout than the first, and both attempts together stay within the current worst-case wait plus a small constant. On the image path, the retry drops the image attachment and retries text-only — the cheaper, more reliable request — so a multimodal-specific failure still yields model enrichment. Timing records (`ReceiptProcessingTiming`) capture attempt count and per-attempt duration.

The redundant second availability check inside the service is removed in favor of the pipeline's single check; the service treats a runtime unavailability error from the framework as the signal it currently derives from pre-checking.

Rationale: today one transient blip silently costs all model enrichment and the user sees an unexplained deterministic-only review. One retry is the cheapest reliability win in the pipeline; unbounded retries would violate the capture-speed principle.

### D7 - Audit trail distinguishes path and acceptance tier

The persisted model-output audit (`modelOutputJSON` via `ModelOutputAuditEncoder`) is versioned to additionally record: whether the image path ran, attachment count, attempt count, and — per field — the acceptance tier from D4 (supported / image-grounded / rejected). Raw model output remains stored unmodified, per the standing rule in `SPEC-processing-overlay-and-extraction-audit.md` (deterministic, versioned, sorted, Decimal-safe). The review screen's provenance disclosure renders the same JSON blob it renders today; no UI change.

Rationale: when an image-grounded value is wrong on-device, the raw-vs-tier distinction is the only way to tell a perception failure from a validator bug.

### D8 - Token-aware prompt budgeting

`ReceiptPromptEvidenceBuilder`'s 4,000-character budget becomes token-aware: where the 26.4+ introspection APIs (`contextSize`, `tokenCount`) are available, the pipeline computes the evidence budget from the actual window minus instructions, expected output reservation, and (on the image path) the measured attachment cost; the character budget remains the fallback. The output-token cap is raised from the current fixed 700 to a value derived from the same computation, ending the tension between 18 output fields and verbose-locale alternate reasons. The alternate-reason guide descriptions gain an explicit brevity bound (one short phrase), and the output-language instruction is stated exactly once, in the session instructions, removing the duplicated near-identical line from the prompt body. Section priority and survivor rules (top vendor line, strongest total candidate always survive) are unchanged.

Rationale: Apple's context-window technote makes overflow a hard error, and the image attachment introduces the first genuinely variable-cost prompt component — guessing with characters is no longer safe.

### D9 - Per-page OCR isolation and honest aggregate confidence

`VisionDocumentOCRService` isolates per-page failures: a page whose recognition throws is skipped, recorded, and excluded from confidence aggregation; remaining pages proceed. All pages failing yields the existing no-text error and manual-entry fallback. Aggregate confidence continues to use the minimum across **succeeded** pages, and the result notes skipped pages so the audit trail reflects partial OCR. Page order remains stable.

### D10 - Corroboration-based confidence for model options

`ReceiptMergePolicy` stops hardcoding model options to medium confidence: evidence-supported model values stay medium; image-grounded values enter at low. Because the review screen's existing attention-edge rule highlights unconfirmed multi-option fields, image-grounded suggestions naturally draw review attention through the existing mechanism — satisfying the design system without any new UI pattern (per `DESIGN.md`'s reuse rule: prefer an existing component over a new one that looks similar; no new indicators, no new colors, and in particular no red). The two-option cap per merged field is retained; when a deterministic option, an evidence-supported model option, and an image-grounded option all exist, the image-grounded one is dropped first.

## 5. Edge Cases

- **Image-capable device, transiently unavailable model:** existing `.modelNotReady` handling wins — deterministic-only with notice; image capability is irrelevant when the model can't run.
- **Capability check passes, attachment request fails at runtime** (first OS beta, capability drift): treated as a transient generation failure → D6 retry runs text-only. Never a user-facing error.
- **iOS 26 runtime on a binary built with the beta lane:** compile gate present but runtime check fails → text-only path; behavior identical to a Xcode 26 build.
- **Glare/faded receipt where OCR got nothing:** empty OCR still short-circuits to manual entry before the model step, unchanged — the image path does not create a new "model-only extraction from a blank OCR" flow (PRD merge policy needs a deterministic baseline to exist).
- **Model reads a *different* number off the image than the printed total (perception error):** enters as a low-confidence secondary option at most; deterministic primary unaffected; attention edge prompts the user. This is the accepted residual risk of tier 2 and the reason it can never be primary over a deterministic value.
- **Image-grounded date in the future or wrong century** (common OCR-adjacent perception slip): rejected by the date plausibility window, not clamped.
- **Multi-page receipt where the total is on a middle page:** attached pages are first and last only; the middle-page total still reaches the model through the evidence packet; if OCR also missed it, the field stays unknown — acceptable, rare, and reviewable manually.
- **Very large context consumption** (long receipt + image): D8 budgeting shrinks evidence sections by existing priority; if the framework still reports window overflow, the retry drops the attachment.
- **Timeout on first attempt, success on retry:** merged result carries no user-visible difference; timing/audit records show two attempts.
- **Both attempts fail:** existing deterministic-only degradation and notice, exactly as today.
- **Locale unsupported by the model:** unchanged — deterministic-only with the existing notice; the image path never runs.
- **Sandbox lane** (`IntelliExpenseSandbox`): inherits the same code paths; seeded fake services gain the capability flag so sandbox screenshots exercise both paths deterministically.

## 6. Accessibility and Localization

- **No new user-facing strings.** No new notices, labels, or banner variants; the string-catalog key/value table for this spec is intentionally empty. Degradation from the image path is silent (D3), and all new provenance detail lives in the existing audit JSON disclosure.
- **No new accessibility identifiers.** Review-screen structure, VoiceOver grouping, and Dynamic Type behavior are untouched.
- Prompt and schema remain English with the existing locale-steering line; user-visible alternate reasons remain in the app UI language, now instructed exactly once (D8).
- Currency validation (D4) uses Foundation locale data, never a hardcoded code list; date plausibility uses calendar APIs, never string comparison.
- No `colorScheme` branches, no new colors, no red: image-grounded options render through existing chip styling and the existing attention edge only.

## 7. Test Impact

### ExpenseCore unit tests (`make test-core`)

1. Validator tiers: evidence-supported value merges as today; image-grounded plausible vendor/total accepted as secondary only; image-grounded value colliding with a non-total identifier rejected; tier 2 unreachable on the text-only path.
2. Plausibility gates: future date rejected; malformed/valid ISO 4217 currency rejected/accepted via locale data; non-Decimal and negative image-grounded totals rejected.
3. Merge confidence: image-grounded options enter at low confidence; drop-order test for the two-option cap (deterministic > evidence-supported > image-grounded).
4. Budgeting: token-budget path and character-fallback path both preserve survivor rules; shrink-on-overflow drops sections in priority order.
5. Audit encoder: versioned output is deterministic, sorted, Decimal-safe, and records path/tier/attempt fields; raw model output preserved unmodified.

### App target tests (`make test-app`, runs on the Xcode 26 lane)

1. Pipeline retry: transient failure then success yields model-enriched merge with two attempts recorded; two failures yield today's deterministic-only notice; unavailability and unsupported-locale do not retry.
2. Retry drops the image: fake capability-enabled service asserts attempt one carries attachments, attempt two does not.
3. Capability fakes: capability off → prompt request carries no attachments and text behavior is byte-identical to current expectations; capability on → request carries at most two attachments, first and last pages, prompt-variant sized.
4. OCR isolation: multi-page fixture with one failing page still yields text from remaining pages, confidence excludes the failed page, skipped pages recorded; all pages failing yields the existing no-text fallback.
5. Existing locale steering, checklist wording, and degradation-ladder tests continue to pass unmodified on the text-only path.

### Device evaluation (manual, owner's iPhone 16 Pro Max, iOS 27)

Extend the evaluation checklist from `SPEC-foundation-model-amount-vendor-evidence-prompt.md`: run the existing fixtures plus at least three physically degraded receipts (glare, faded thermal print, stylized logo vendor) through capture on-device; save prompt, raw model output, tier classification, and merged review fields under `docs/specs/evidence/`. Pass condition: image path recovers at least one field OCR missed on the degraded set, no image-grounded wrong value ever appears as a primary field, and every fixture that passed before still passes.

## 8. Acceptance Criteria

1. Built with Xcode 26.x, the app compiles and behaves byte-identically to today on all paths; all existing tests pass on the current toolchain.
2. Built with the beta lane and run on the owner's iPhone 16 Pro Max (iOS 27), the extraction prompt carries the receipt image, and the review screen can surface image-grounded values as secondary options.
3. On any device or runtime without image capability, the text-only path runs with no notice, no new UI, and no behavioral change.
4. Deterministic parser output remains baseline truth: no image-grounded value ever displaces a deterministic primary; promotion happens only where merge policy already allows it.
5. Every model field passes a validation gate before merge: vendor/total per tier rules, date/currency per plausibility, payment/expense-type per guided constraints.
6. A transient model failure retries exactly once (text-only), within a bounded combined time budget; attempt counts appear in timing and audit records.
7. One failed OCR page no longer aborts a multi-page receipt; confidence aggregates over succeeded pages only.
8. Prompt budgeting is token-aware where the introspection APIs exist, with the character budget as fallback; the fixed 700-token output cap is replaced by a derived value.
9. The audit JSON is versioned and records path (image/text), attachments, attempts, and per-field acceptance tier, without altering the raw model output record.
10. No tools are registered on the session; no Private Cloud Compute; no network calls; no new strings, accessibility identifiers, UI patterns, CloudKit fields, or export changes.
11. `Makefile` makes the scoped Xcode 27 beta lane the default for `make build-device` and `make install-device`, retains compatibility `-beta` aliases plus explicit `-stable` fallbacks, and documents the contract in `CLAUDE.md`, `AGENTS.md`, and `ASC.md` without changing machine-wide `xcode-select`.
12. `PRD.md` §6.2/§6.3/§6.4 are amended in the implementation change as listed in the header.

## 9. Verification Commands

```bash
make test-core        # Xcode 26 default toolchain — must stay green
make test-app         # Xcode 26 default toolchain — must stay green
make install-device   # canonical durable install, scoped Xcode 27 beta lane
make install-device-beta   # compatibility alias for the same beta lane
make install-device-stable # explicit Xcode 26.5/text-only fallback
```

Prerequisite (owner, one-time): install Xcode 27 beta at `/Volumes/External-2TB/Applications/Xcode-27-beta.app` (Apple Developer downloads; requires Apple ID sign-in), or set `XCODE_BETA_DIR` to its location. `make check-xcode-beta` must pass; if a new beta returns first-launch status 69, run `DEVELOPER_DIR=/Volumes/External-2TB/Applications/Xcode-27-beta.app/Contents/Developer xcodebuild -runFirstLaunch` once and retry. Do not change `xcode-select`. If the beta is unavailable or the paired iPhone/signing path is blocked, stop and report the default handoff blocker rather than silently substituting the stable lane or claiming the image path is verified.
