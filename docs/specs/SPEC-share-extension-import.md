# Spec: Share receipts into Intelli-Expense from Photos (Share Extension)

**Status:** ready for implementation
**Manual Developer Portal prerequisite:** complete for the shipping app. App Group `group.com.nags.intelliexpense` is registered to the maintainer's Apple Developer team; both App IDs (`com.nags.intelliexpense` and `com.nags.intelliexpense.share`) are configured with that App Group. Contributors use their own team and provisioning profiles.
**Feature:** from the Photos app (or any app offering images in the share sheet), share a photo to Intelli-Expense; the receipt then goes through the normal pipeline — OCR → parser → Foundation Models → merge — and the usual **Review & Confirm** sheet appears in the app. An alternative entry point to the in-app "Choose photo" flow (ContentView.swift:138–144), not a replacement.
**Scope:** new share-extension target + `project.yml`, App Group entitlement on both targets, a small shared inbox store in the app target, `ContentView.swift` wiring, String Catalog, tests.

---

## 1. Architecture decision — inbox handoff, not in-extension processing

The extension does **not** run OCR/Foundation Models and does **not** open the SwiftData store. It writes the shared images to an App Group "inbox" and finishes. The main app drains the inbox on next activation and runs the **existing** capture pipeline (`MainTabView.process(_:)`, ContentView.swift:284–309), so the user gets the exact same processing overlay → review sheet they get today.

Why (binding rationale — do not "improve" this into in-extension processing):
- Share extensions have tight memory limits; `SystemLanguageModel` + Vision in-extension is exactly the kind of thing the POC guide warns against copying blindly.
- The Review & Confirm UI, group assignment, duplicate detection, and draft persistence all live in the app; duplicating them in an extension violates PRD §2 (cut scope, not quality).
- Share extensions cannot reliably launch their containing app (`openURL` is unavailable/rejectable from share extensions) — so "hand off + review on next open" is the honest UX, and matches the user's ask ("shows me for confirmation — the usual process").
- Extension never touches SwiftData/CloudKit → zero schema/mirroring risk.

Semantics: **one share action = one receipt**; multiple images shared at once become ordered pages of that receipt — identical to multi-select in the in-app PhotosPicker (ContentView.swift:339–345).

## 2. App Group + shared inbox

### 2.1 Entitlements / project.yml

- App Group id: `group.com.nags.intelliexpense`. Add `com.apple.security.application-groups` to `IntelliExpense/IntelliExpense.entitlements` **and** the new extension's entitlements.
- Manual Apple Developer step: **DONE 2026-07-05**. Evidence from decoded installed profiles:
  - Main Development profile: `<your-team-id>.com.nags.intelliexpense`, `get-task-allow = true`, App Group `group.com.nags.intelliexpense`, CloudKit `iCloud.com.nags.intelliexpense`.
  - Share Development profile: `<your-team-id>.com.nags.intelliexpense.share`, `get-task-allow = true`, App Group `group.com.nags.intelliexpense`, no CloudKit.
  - Main App Store profile: `<your-team-id>.com.nags.intelliexpense`, `get-task-allow = false`, App Group `group.com.nags.intelliexpense`, CloudKit `iCloud.com.nags.intelliexpense`.
  - Share App Store profile: `<your-team-id>.com.nags.intelliexpense.share`, `get-task-allow = false`, App Group `group.com.nags.intelliexpense`, no CloudKit.
  - Ignore older stale download `IntelliExpense_share_extn.mobileprovision`; it was created before App Groups were configured and has no App Group entitlement.
- New target in `project.yml` (then `xcodegen generate`):

```yaml
  IntelliExpenseShare:
    type: app-extension
    platform: iOS
    deploymentTarget: "26.0"
    sources: [IntelliExpenseShare]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.nags.intelliexpense.share
        INFOPLIST_FILE: IntelliExpenseShare/Info.plist
        GENERATE_INFOPLIST_FILE: "NO"
        CODE_SIGN_ENTITLEMENTS: IntelliExpenseShare/IntelliExpenseShare.entitlements
        DEVELOPMENT_TEAM: $(INTELLI_TEAM_ID)
```
  plus `- target: IntelliExpenseShare` as a dependency (embed) of the app target. Verify exact xcodegen keys for extension embedding against xcodegen docs.
- Extension Info.plist: `NSExtensionPointIdentifier = com.apple.share-services`; activation rule images only, `NSExtensionActivationRule` dict with `NSExtensionActivationSupportsImageWithMaxCount = 10`. Display name "Intelli-Expense". PDFs/other types are **out of scope** v1 (in-app file import already covers them).

### 2.2 `SharedReceiptInbox` (app target, new file `IntelliExpense/Capture/SharedReceiptInbox.swift`)

A small value-type store over `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`:

- Layout: `<container>/SharedInbox/<UUID>/manifest.json` + `page-0.jpg`, `page-1.jpg`, …
- `manifest.json`: `{ "version": 1, "createdAt": ISO8601, "pageFilenames": ["page-0.jpg", ...] }`.
- API: `write(images: [Data]) throws -> URL` (used by the extension — compile the file into **both** targets), `pendingItems() -> [SharedInboxItem]` (sorted by `createdAt`), `remove(_ item:)`, and `sweep(olderThan:)` for corrupt/abandoned entries (missing manifest or pages → delete).
- Pure Foundation, injectable container URL for tests (default: real App Group; tests: temp dir).
- Write must be atomic-ish: write pages first, manifest **last** — the app treats a folder without manifest as incomplete and ignores it (sweeps it after 24 h).

## 3. The extension target (`IntelliExpenseShare/`)

- Minimal UI (SwiftUI hosted in the extension's root view controller): thumbnail(s) of the incoming image(s), title `share.title` ("Add to Intelli-Expense"), body `share.body` ("Saved for review — open Intelli-Expense to confirm the details."), **Add** (`share.confirm`) and **Cancel** buttons. Ledger Green accent via a copy of the token colors in the extension's asset catalog (or share the asset catalog via project.yml resources — preferred if xcodegen allows). No red; Dynamic Type; extension gets its own `Localizable.xcstrings` (extensions don't read the app bundle's catalog).
- On Add: load each `NSItemProvider` conforming to `UTType.image` via `loadDataRepresentation` (fall back to `loadFileRepresentation` + read), preserve the share order, `SharedReceiptInbox.write(images:)`, then `extensionContext.completeRequest(...)`. On any failure: show `share.error` and complete with error — never write a partial manifest.
- No network, no SwiftData, no Vision/FoundationModels imports. Keep the extension under a handful of files.

## 4. Main app: drain the inbox through the usual flow

In `MainTabView` (ContentView.swift):

- Trigger points: `.task` on appear and `scenePhase == .active` (the app already observes scenePhase in `ContentView`:36–39; add the hook in `MainTabView` or thread it down).
- Guard: only start when `processingState == nil && reviewForm == nil && attachmentTargetReceipt == nil` — never interrupt an in-flight capture or an open review sheet. After the review sheet closes (`onSaved` / dismiss), re-check the inbox and process the next item (drain sequentially, oldest first).
- Per item: read page datas → `services.receiptCapturePageBuilder.makePages(fromImageData:sourceType: .photoImport)` → existing `startCapture`/`process` path so the processing overlay, stage announcements, cancellation, and notices all behave exactly as an in-app photo import.
- **Deletion contract (never lose an image, PRD.md:360):** remove the inbox folder only after `ReceiptProcessingPipeline.process` has persisted the `ReceiptDraft` (i.e. after `process(capturedPages:)` returns a result — the draft with pages is saved before OCR even starts, ReceiptProcessingPipeline.swift:180–181). On `blockedByModelAvailability`, cancellation, or any thrown error before a draft exists, **keep** the inbox item and retry on next activation. If the user cancels the processing overlay for an inbox item, delete the item (explicit user intent, matching in-app cancel semantics).
- Gates: if onboarding hasn't been completed or `availability.blocksCapture` shows the gate view, `MainTabView` isn't on screen and the inbox simply stays pending — correct behavior, no extra code.
- Review sheet uses `defaultCaptureGroup = nil` (Unfiled by default; user picks the group in review, same as today).

## 5. Localization (String Catalog)

App catalog: `inbox.processing.announcement` only if a distinct VoiceOver announcement is wanted (optional). Extension catalog: `share.title`, `share.body`, `share.confirm`, `common.cancel` equivalent (`share.cancel`), `share.error`.

## 6. Tests (TDD — write first)

Unit (`IntelliExpenseTests`, temp-dir container):
1. `write(images:)` creates folder with pages + manifest; `pendingItems()` returns it with correct page order and count.
2. Folder without manifest is ignored by `pendingItems()` and removed by `sweep`.
3. `remove(_:)` deletes the folder; `pendingItems()` sorted oldest-first across multiple items.
4. Drain integration (fake services, in-memory ModelContainer): seed inbox with 2 items → drain → first produces a `ReceiptDraft` and review form; inbox item deleted after pipeline result; second remains until first review completes.

UI (`IntelliExpenseUITests`): launch argument `-UITestSeedSharedInbox` makes `AppServices`/launch config seed one fixture inbox item (reuse `makeReceiptFixtureImage()`, AppServices.swift:136–159) into a temp container → app launches → processing overlay appears → review sheet (`review.title`) shows prefilled fields → Save → receipt exists. (The extension UI itself is not UI-testable in simulator CI; cover it by keeping its logic inside `SharedReceiptInbox` + manual acceptance.)

## 7. Acceptance criteria

- [ ] In Photos, select 1 receipt photo → Share → Intelli-Expense → Add → confirmation copy shown, sheet dismisses.
- [ ] Opening Intelli-Expense next: processing overlay runs, then the standard Review & Confirm sheet with extracted vendor/date/amount; Save files it (Unfiled unless changed) with the image attached at full stored resolution.
- [ ] Sharing 3 photos at once yields **one** receipt with 3 ordered pages.
- [ ] Sharing while the app is later opened mid-capture: inbox item waits; it processes after the current review closes.
- [ ] Force-quit between share and open: item survives (inbox is on disk).
- [ ] Airplane mode / Apple Intelligence transiently unavailable: receipt still lands in review with deterministic-parser values + notice (existing degradation path), image never lost.
- [ ] No new network calls; extension sandbox contains no SwiftData store.
- [ ] All strings from String Catalogs (app + extension); no red; Dynamic Type.
- [ ] `xcodegen generate` then build + tests green:
  `xcodebuild -project IntelliExpense.xcodeproj -scheme IntelliExpense -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' test`

## 8. Out of scope

- PDFs / arbitrary file types in the share sheet (file importer covers them in-app).
- Launching the app directly from the extension; push/local-notification nudges.
- Treating multiple shared images as multiple receipts (revisit only with real user demand).
- Processing inside the extension; App Intents / Shortcuts entry points (possible later spec).
