# SPEC - Manual entry review starts at Fields

**Status:** proposed
**Owner screens/files:**
- `IntelliExpense/UI/ReviewViews.swift` - `ReceiptReviewView` and `ReceiptReviewImageHeader`
- `IntelliExpense/Review/ReceiptReviewForm.swift` - existing page/image state only; no form validation changes
- `IntelliExpense/Resources/Localizable.xcstrings` - `review.manual.header` audit (key is retained; see section 7)

Out-of-scope surface (named so the audit is unambiguous): `IntelliExpense/Mac/MacContentView.swift` - the Mac review pane's `MacReceiptImageColumn` placeholder also uses `review.manual.header`; it is intentionally unchanged by this spec (see Non-goals).

**Docs this spec amends:**
- `DESIGN.md` section 4 Components and section 9 Do's and Don'ts - clarify that the review image header appears only when there is an actual receipt image
- `design/ui-spec.html` `#review` and `#manual` - clarify that photo-less manual entry begins at the form, while image-backed review keeps the paper anchor

---

## 1. Problem

The manual-entry review sheet currently spends the scan/photo preview slot on a large placeholder card that says "Manual entry". In the owner's reference screenshot, that placeholder occupies the same first-screen space that image-backed review uses for the receipt photo. For manual entry there is no receipt image yet, so the card does not add trust, context, or an action. It pushes the useful work, the `Fields` section, lower on the screen and makes the first impression feel wasteful.

This happens because `ReceiptReviewView` always renders the image-header section before the fields section. `ReceiptReviewImageHeader` then falls back to `review.manual.header` with the `square.and.pencil` symbol when the form has no page images. `ReceiptReviewForm.manual()` creates exactly that no-page shape, so the placeholder is a generic shared-view fallback, not a product requirement.

The product docs point the other way:

- PRD section 5.4 says the review screen has the receipt image on top for captured documents, but the manual-entry screen is "the same form, no image."
- PRD section 4.2 says manual entries have empty attachments until a photo is added later.
- `design/ui-spec.html` `#manual` says "Manual entry is the review form minus the image."
- `DESIGN.md` section 1 calls the paper receipt the trust anchor; without paper, there is no trust anchor to reserve.

## 2. Evidence and Platform Grounding

Codebase grounding:

- `ReceiptReviewView` renders `Section { ReceiptReviewImageHeader(form: form) }` before notices, duplicates, and `Section("review.section.fields")`.
- `ReceiptReviewImageHeader` displays the actual image when `form.fullImageData(at: 0)` decodes. Otherwise it displays `Label("review.manual.header", systemImage: "square.and.pencil")` inside a `minHeight: 160` rounded rectangle.
- `ReceiptReviewForm.manual()` is built from an empty `MergedReceipt(rawText: "")`, with no draft pages and no page images. The fallback therefore always appears for pure manual entry.

Apple docs grounding, checked through the local Apple docset/cache on 2026-07-09:

- SwiftUI `Form` (`/documentation/swiftui/form`, docset v24703) says iOS forms render as grouped lists with platform-appropriate styling for controls. The manual path should lean on that grouped form/list structure instead of replacing missing content with a custom empty image card.
- SwiftUI `Section` (`/documentation/swiftui/section`, docset v24703) is the API for organizing content in `List`, `Picker`, and `Form`, with per-instance content, headers, and footers. The `Fields` section is the real first content group for manual entry.
- SwiftUI `ViewBuilder` (`/documentation/swiftui/viewbuilder`, docset v24703) explicitly supports conditionally building child content with `buildIf` / `buildEither`. Conditionally omitting the image section when no image exists is a first-class SwiftUI shape, not a workaround.
- Apple's "Adopting Liquid Glass" guidance in the local Apple cache says lists, tables, and forms have updated row height, padding, and section radius, and recommends grouped SwiftUI forms to inherit platform layout metrics. Removing the fake header lets the system grouped-list metrics carry the form.

## 3. Goals

- Pure manual entry opens with the navigation title and then the `Fields` section as the first meaningful content.
- Image-backed review from scan, photo import, file import, share extension, raw agent drops, and "no receipt text found" fallback keeps the receipt image header unchanged.
- The implementation stays scoped to presentation logic: same `ReceiptReviewForm`, same field order, same save/discard behavior, same validation, same `Decimal` money handling.
- The screen remains native SwiftUI: grouped list/form sections, Dynamic Type, semantic colors, no new decorative card, no new custom glass.
- The spec is implementable without changing persistence or the capture pipeline.

## 4. Non-goals

- No full manual-entry redesign in this change. The amount-hero sheet shown in `design/ui-spec.html` `#manual` is a larger future pass because it changes field hierarchy, focus behavior, optional-field grouping, and tests.
- No field-order change. The existing review order remains Vendor, Date, Amount, Currency, Category, Payment, Folder, Notes.
- No new "manual mode" data model flag. Header visibility comes from whether real page image data exists.
- No new Add Photo action on the review sheet. Photo attachment remains the post-save receipt-detail flow described in PRD section 5.2.
- No change to the duplicate banner, processing notice, or save bar placement.
- No change to extraction/provenance persistence in this spec.
- No change to the Mac review pane. `MacContentView`'s review layout is a fixed side-by-side image column plus form, not a stacked scroll; hiding its column for photo-less entries would reflow the whole pane and is a separate design question. Its `ContentUnavailableView("review.manual.header", ...)` placeholder stays as is.

## 5. Design Decisions

### D1 - The image header is content, not chrome

Render the review image-header section only when the form has actual page image data. For image-backed forms, the header remains exactly where it is today: first section, tap-to-zoom, page count, same image viewer, same `review.image.open` identifier.

For forms with no page images, omit the entire image-header section. Do not replace it with a smaller "Manual entry" row, glyph tile, banner, or helper copy. The navigation title already frames the modal, and the `Fields` header tells the user what to do.

Rationale: the preview slot exists to show evidence. If there is no evidence image, a placeholder is pure layout tax.

### D2 - Manual entry starts at the form

On a fresh pure manual entry, the first scrollable section is `Section("review.section.fields")`. The user should see the `Fields` heading and the first field rows immediately after the sheet title, without needing to scroll past a fake preview.

Existing conditional content keeps its role:

- Processing notices remain above `Fields` when present.
- Duplicate notice remains above `Fields` when the form has enough values to detect a possible duplicate.
- Neither notice should appear on a fresh blank manual form, so the normal starting state is simply `Fields`.

### D3 - Keep image-backed fallback behavior separate from manual behavior

Do not infer "manual" from empty OCR text. A captured image with no OCR text is still image-backed review, and PRD section 6.4 explicitly says that flow opens with the image attached and empty fields. That case must keep the receipt image header because the image is the user's proof.

The condition is therefore image presence, not extraction quality, source type, or raw text.

### D4 - Do not introduce a manual-specific visual language

Manual entry should not get a unique top card, accent color, instructional banner, or badge. This app's rule is "reuse the review form for post-save editing - one component, one muscle memory" (`DESIGN.md` section 9). This update preserves the shared form and removes only the content that is not actually available.

### D5 - Documentation amendment

The implementation change that follows this spec must update the canonical docs in the same change:

- `DESIGN.md`: clarify that the review image header is required only for image-backed review, and photo-less manual entry begins directly at the form.
- `design/ui-spec.html`: update the `#review` / `#manual` notes so the shipped component's conditional header is explicit. Keep the amount-hero manual mockup labeled as a fuller future manual-entry redesign unless that redesign is implemented in the same change.

## 6. Edge Cases

- Fresh manual entry: no page images, no processing notice, no duplicate notice. The first visible content after the title is `Fields`.
- Manual entry launched from a folder/trip: still starts at `Fields`; the folder row inside the form carries the destination.
- Manual entry with default currency/payment from Settings: still starts at `Fields`; prefilled values do not create an image header.
- Scan/photo/file with valid image but empty extraction: keep the image header and any no-text notice.
- Multi-page capture: keep the image header, page count, and full-screen viewer unchanged.
- Agent structured draft with image pages: keep the image header because an image exists.
- Future photo-less agent or imported structured draft: omit the image header and start at its confirmation/form content, unless that flow has its own dedicated card by another spec.
- Largest Dynamic Type sizes: omitting the header must not introduce a fixed spacer. The grouped list should naturally place the `Fields` section under the title.
- Dark mode and Increased Contrast: no new colors or surfaces are introduced, so existing semantic/system rendering carries this change.

## 7. Accessibility and Localization

- VoiceOver order for pure manual entry: navigation title, close button, then the `Fields` section and its field controls. VoiceOver must not announce "Receipt image" or "Manual entry" when no image exists.
- `review.image.open` remains present and tappable only for image-backed forms. It must be absent from pure manual entry.
- No new accessibility identifiers are required. Existing identifiers on field controls, category chips, payment controls, group row, and Save stay stable.
- No new strings are required. `review.section.fields`, field labels, `common.save`, and existing validation copy are reused.
- `review.manual.header` loses its iOS review-sheet caller but **remains in use** by the Mac review pane (`MacContentView.swift`, `MacReceiptImageColumn` placeholder). The key must be retained in the catalog; do not remove it and do not add replacement copy. If a later spec reworks the Mac review pane's photo-less state, that spec owns the key's retirement.
- Dynamic Type remains system-driven; no fixed point sizes or custom spacers are introduced to compensate for the removed header.

## 8. Test Impact

- Add or update an iOS UI test for manual entry:
  - Open the manual path from the Add Receipt sheet or capture accessory.
  - Assert the review sheet appears.
  - Assert no `review.image.open` element exists.
  - Assert the localized "Manual entry" placeholder text is absent.
  - Assert `Fields` and the first field controls are visible without scrolling.
- Keep or add an image-backed review UI test:
  - Open a fixture scan/photo review.
  - Assert `review.image.open` exists.
  - Tap it and verify the receipt image viewer still opens.
- Unit tests in `ReceiptReviewFormTests` do not need logic changes, but they can keep asserting that `ReceiptReviewForm.manual()` has empty page image data.
- Snapshot/manual QA: verify light mode, dark mode, largest Dynamic Type, and manual entry launched from both Unfiled and a specific folder/trip.
- Localization audit: after removing the iOS fallback, search for `review.manual.header` and confirm the only remaining caller is the Mac review pane (`MacContentView.swift`); the key stays in the catalog.

## 9. Acceptance Criteria

1. Fresh manual entry no longer shows the large "Manual entry" placeholder card.
2. Fresh manual entry begins with the `Fields` section as the first meaningful content under the navigation title.
3. Scan, photo, file, share-extension, and image-backed fallback review still show the receipt image header, page count, zoom affordance, and full-screen image viewer exactly as before.
4. No new colors, custom glass, fixed type sizes, or decorative manual-entry surfaces are added.
5. No field order, validation, save/discard, `Decimal`, currency, category, payment, or persistence behavior changes.
6. VoiceOver on a photo-less manual entry does not announce image-related content; VoiceOver on image-backed review keeps the existing image-opening control.
7. `review.manual.header` is retained in the string catalog, its only remaining caller is the Mac review pane, and the Mac review pane's layout and placeholder behavior are unchanged.
8. `DESIGN.md` and `design/ui-spec.html` are amended in the implementation change so the canonical docs match the conditional header behavior.
9. Manual-entry and image-backed review UI tests pass, along with the normal app test lane for the implementation change.
