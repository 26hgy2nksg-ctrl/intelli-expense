# Spec: Full-resolution receipt image viewing (review + detail)

**Status:** ready for implementation
**Problem owner:** user report — "receipts during upload or after upload cannot be viewed in their full actual resolution"
**Scope:** `IntelliExpense/UI/ReviewViews.swift`, `IntelliExpense/UI/ReceiptsViews.swift`, `IntelliExpense/Review/ReceiptReviewForm.swift`, `IntelliExpense/Capture/ReceiptCapturePageBuilder.swift`, one new view file, String Catalog, tests. No `ExpenseCore` changes.

---

## 1. Problem — verified root causes

The user cannot ever see a receipt at its stored resolution, let alone its captured resolution. Three independent causes, in order of impact:

### 1.1 The review screen ("during upload") shows the 320 px thumbnail

- `ReceiptReviewForm.previewImageData` (Review/ReceiptReviewForm.swift:52–55) **prefers `thumbnailData` over `imageData`**. `thumbnailData` is generated at max 320 px on the long side (Capture/ReceiptCapturePageBuilder.swift:16).
- `ReceiptReviewImageHeader` (UI/ReviewViews.swift:162–193) renders that data `scaledToFit` capped at `maxHeight: 260` with **no tap-to-zoom and no full-screen presentation**.
- PRD.md:248 requires the review screen to show the "Receipt image on top (collapsible, **tap to zoom**)". Neither exists. The image the user is supposed to verify fields against is a blurry 320 px thumbnail.

### 1.2 Receipt detail ("after upload") has no zoomable full-screen viewer

- `ReceiptDetailView` (UI/ReceiptsViews.swift:304–317) shows full `imageData` but inside a `TabView` form row at `minHeight: 260`, `scaledToFit`. No pinch zoom, no full-screen, no way to read small print (tax lines, itemized totals) on a tall receipt squeezed into ~260 pt.
- PRD.md:228 requires: "Receipt detail: **full-screen-zoomable image pages**". Direct violation.

### 1.3 Stored "full" image is capped at 1800 px

- `ReceiptCapturePageBuilder` (Capture/ReceiptCapturePageBuilder.swift:14–22) re-encodes every captured page at max 1800 px long side, JPEG q=0.82, flattened opaque. A 12 MP photo import (4032 px) is permanently reduced to ~20 % of its pixel count before OCR and before storage.
- PRD.md §4.3 (line 156) says `imageData` stores a "processed (perspective-corrected, **reasonably compressed) full-resolution** image"; PRD.md:280 tempers this with "compress sensibly (receipts don't need 12MP HEIC)". 1800 px is defensible for screen viewing but leaves OCR accuracy and export/archival quality on the table for dense receipts.
- Note: OCR runs on the already-downscaled JPEG (`ReceiptProcessingPipeline.swift:186–190` feeds `page.imageData`), so the cap also bounds recognition quality.

Non-causes (verified, leave alone): the processing overlay preview (ContentView.swift:293, 528–575) intentionally uses the thumbnail for a 180×250 decorative animation — fine. List rows use thumbnails — correct.

---

## 2. Requirements

### R1 — New `ReceiptImageViewer` (full-screen, zoomable, paged)

New file `IntelliExpense/UI/ReceiptImageViewer.swift`:

- Presented with `.fullScreenCover`. Input: `pages: [Data]` (full-resolution `imageData`, ordered by `pageIndex`) and `initialPage: Int`.
- Horizontal paging between pages (`TabView` `.page` style or equivalent), page indicator "N of M" (localized `viewer.page.indicator`, `%1$d`/`%2$d` args) shown for multi-page receipts.
- Per-page zoom: pinch 1×–6×, double-tap toggles 1× ↔ ~3× centered on the tap point, pan while zoomed, zoom resets when swiping to another page. Rendering must display the image data at native resolution when zoomed (no pre-scaled snapshot).
  - Implementation guidance: a `UIScrollView`-backed `UIViewRepresentable` (scrollview + `UIImageView`, `viewForZooming`, `minimumZoomScale` fit-to-screen) gives correct pan/zoom/rubber-band feel with the least code. A pure-SwiftUI `MagnifyGesture` solution is acceptable only if pan+zoom+paging don't fight each other. Verify the chosen approach against current Apple docs per the repo rule (use `apple-platform-think` if available).
- Chrome: black backdrop (`Color.black` is permitted here as photographic surround, not a token violation), top-trailing **Done** button (`common.done` or reuse existing key if present; otherwise add `viewer.done`), tap once toggles chrome visibility. No red, no destructive actions in the viewer.
- Accessibility: viewer is announced with `receipt.image.accessibility`; Done button labeled; page changes announced (`.accessibilityScrollAction` or posted announcements); identifier `receipt.image.viewer` on the container, `receipt.image.viewer.done` on Done.
- Memory: decode pages lazily (only current ± neighbor pages) — a 10-page scan at ~2.4k px each must not decode all pages up front. Use `UIImage(data:)` per visible page; do not retain decoded images for offscreen pages.

### R2 — Review screen: full image + tap to open viewer

In `ReceiptReviewImageHeader` (UI/ReviewViews.swift:162–193) and `ReceiptReviewForm`:

- Add `fullImageData(at index: Int) -> Data?` and `var pageImageDatas: [Data]` to `ReceiptReviewForm`, sourced from `draft.pages` sorted by `pageIndex`, **using `imageData` (never `thumbnailData`)**.
- The header renders the first page from `imageData` (the header can stay ≤260 pt tall — SwiftUI downsamples for display; the point is the source data is full-res so it is sharp, and the viewer gets true pixels).
- Tapping the header (or a small `arrow.up.left.and.arrow.down.right` overlay button, per taste) presents `ReceiptImageViewer` with all pages. Accessibility identifier `review.image.open`.
- Keep the page-count capsule (ReviewViews.swift:181–189).
- `previewImageData` may remain for any caller that genuinely wants a thumbnail, but the review header must stop using it.

### R3 — Receipt detail: tap any page → viewer at that page

In `ReceiptDetailView` (UI/ReceiptsViews.swift:304–317):

- Keep the inline paged strip (it's a good affordance) but make each page tappable → `ReceiptImageViewer(pages:initialPage:)` opening at the tapped index.
- Add a subtle zoom affordance so discoverability doesn't depend on guessing (e.g. `.overlay(alignment: .bottomTrailing)` magnifying-glass glyph in `.secondary`), with accessibility identifier `receipt.image.open`.
- The attachments must be sorted by `pageIndex` once and shared between strip and viewer (today the sort is done inline at line 307).

### R4 — Raise the stored-image cap

In `ReceiptCapturePageBuilder` (Capture/ReceiptCapturePageBuilder.swift:15):

- `maxImageDimension`: **1800 → 2600**. Rationale: ~2600 px long side keeps a tall receipt legible at 4–6× zoom on device, measurably helps Vision OCR on dense receipts, and keeps a typical page at ~600 KB–1.2 MB JPEG — acceptable for CloudKit private-DB assets (`@Attribute(.externalStorage)` mirrors as `CKAsset`, PRD.md:64). Keep `compressionQuality` 0.82 and `thumbnailDimension` 320.
- One constant change; the PDF rasterizer inherits it via its injected `pageBuilder` (Capture/PDFReceiptPageRasterizer.swift:12). Existing already-stored 1800 px attachments are untouched (no migration/re-encode — out of scope).
- Update any tests pinning 1800 (check `IntelliExpenseTests/CaptureInputTests.swift`).

### R5 — Out of scope (do not build)

- Re-encoding existing attachments to the new cap.
- Sharing/saving the image from the viewer (export flow already covers getting images out).
- Running OCR on pre-downscale originals (separate optimization; R4 already lifts OCR input quality).
- Perspective re-cropping UI, filters, rotation.

---

## 3. Localization (String Catalog only)

| Key | English |
|---|---|
| `viewer.done` | "Done" (skip if a `common.done` key already exists — reuse it) |
| `viewer.page.indicator` | "%1$d of %2$d" |
| `review.image.open.accessibility` | "View receipt full screen" |

No hardcoded strings in views; all existing keys reused where noted.

## 4. Tests (TDD — write first)

Unit (`IntelliExpenseTests`):
1. `ReceiptCapturePageBuilder` with a 4000×3000 input → stored image long side == 2600; thumbnail long side == 320; smaller-than-cap input is not upscaled.
2. `ReceiptReviewForm.pageImageDatas` returns full `imageData` (not thumbnail) ordered by `pageIndex`, for a 3-page draft with shuffled insert order.

UI (`IntelliExpenseUITests`, `-UITestFakeServices`):
3. Capture fixture → review sheet → tap `review.image.open` → `receipt.image.viewer` exists → tap `receipt.image.viewer.done` → back on review.
4. Saved receipt → detail → tap `receipt.image.open` → viewer appears.

## 5. Acceptance criteria

- [ ] On the review screen the header image is sharp (full `imageData`), and tapping it opens a full-screen viewer where pinch/double-tap zoom reveals genuinely more detail (small print readable on a real scanned receipt).
- [ ] On receipt detail, tapping a page opens the viewer at that page; swiping pages works; zoom resets between pages; Done returns.
- [ ] Newly captured/imported receipts store images at up to 2600 px long side; a 12 MP photo import is visibly sharper when zoomed than a pre-change capture.
- [ ] VoiceOver can open the viewer, hears the page position, and can dismiss it.
- [ ] No red anywhere; only semantic colors/tokens; Dynamic Type unaffected (viewer chrome uses semantic fonts).
- [ ] `cd ExpenseCore && swift test` unchanged-green; app build + tests green:
  `xcodebuild -project IntelliExpense.xcodeproj -scheme IntelliExpense -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' test`
