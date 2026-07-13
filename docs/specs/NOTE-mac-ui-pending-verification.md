# Mac UI Pending Verification

**Recorded:** 2026-07-11
**Implementation branch:** `codex/mac-desktop-behaviors`
**Verified implementation:** `4b1abdf`
**Installed app:** `/Applications/IntelliExpense.app` (`com.nags.intelliexpense`)

## Current status

- The signed native Mac target builds successfully.
- The installed app passes strict code-signature verification and launches from `/Applications`.
- Seven Mac-compiled behavior tests pass, including SwiftData relationship undo/redo, batch undo, delete undo, Dock badge derivation, search, zoom bounds, and multi-page drag materialization.
- The complete Mac UI test target compiles.

## Pending hosted Mac UI run

Local `xcodebuild` fails before the first UI assertion because XCTest cannot activate the test app and reports it as `Running Background`. This also reproduces with the pre-existing empty-detail smoke test, so it is a test-host activation blocker rather than a failure in a new desktop-behavior assertion.

Use the manual `.github/workflows/macos-ui.yml` lane so automation does not occupy the owner's desktop. First run the single empty-detail smoke method to prove hosted activation. If it passes, run the full `IntelliExpenseMacUITests/IntelliExpenseMacUITests` class once as the intentional closeout receipt. Do not use repeated full-class runs to diagnose an individual failure; follow [the testing strategy](../verification/testing-strategy.md) and record every job in [the runner usage ledger](../verification/github-macos-runner-usage.md).

Hosted activation is now proven: [run 29153870386](https://github.com/dctmfoo/intelli-expense/actions/runs/29153870386) passed `testEmptyDetailStateRendersWhenNothingIsSelected` (1/1). The first full-class receipt, [run 29153984852](https://github.com/dctmfoo/intelli-expense/actions/runs/29153984852), passed 5/17 and exposed two shared harness defects: scene restoration overwrote seeded test destinations, and category-sheet tests selected the underlying receipt search field. Both defects are fixed locally; focused hosted confirmation and a final closeout receipt remain pending.

[Run 29155380634](https://github.com/dctmfoo/intelli-expense/actions/runs/29155380634) confirmed that the category query now selects the correct `Search categories` field, but the nested Mac sheet did not transfer keyboard focus to that field. The browse catalog now requests search focus when it appears. [Run 29155506707](https://github.com/dctmfoo/intelli-expense/actions/runs/29155506707) passed the complete empty-results, stable-viewport, reset, and dismissal path.

Owner testing also exposed two native Mac defects during this pass: the row's double-click rename gesture competed with single-click folder selection, and content zoom used an inherited parent font that could not scale explicit semantic fonts. Folder rows now leave selection to the native `List` and use a non-delaying AppKit double-click recognizer only for rename; the earlier explicit single-click workaround did not remove the gesture delay. [Run 29155025480](https://github.com/dctmfoo/intelli-expense/actions/runs/29155025480) passed two complete repeated folder-switch cycles before that remaining latency was reported. Hosted evidence then showed `dynamicTypeSize` does not resize those explicit fonts on macOS, so the app now routes every semantic font through one environment-aware macOS 26 `Font.scaled(by:)` modifier. [Run 29155301054](https://github.com/dctmfoo/intelli-expense/actions/runs/29155301054) passed zoom stepping, persistence across relaunch, reset, and disabled endpoint behavior.

Delete-to-archive succeeds and the headless undo contract remains green, but hosted Command-Z still does not restore the row after focused responder-chain changes. After [run 29154936527](https://github.com/dctmfoo/intelli-expense/actions/runs/29154936527), further hosted retries were stopped to protect the minute budget. This one rendered keyboard path remains pending local AppKit diagnosis; it must not trigger another hosted run without a new implementation change and local proof.

The sidebar-refinement pass (`codex/mac-sidebar-refinement`, spec `SPEC-mac-sidebar-refinement.md`) has one open hosted item. Four hosted runs on 2026-07-12 ([29176520522](https://github.com/dctmfoo/intelli-expense/actions/runs/29176520522) through [29176829909](https://github.com/dctmfoo/intelli-expense/actions/runs/29176829909)) proved sidebar bottom-bar creation, folder selection, and badge behavior, but XCUI could not toggle the system `Section` disclosure: the triangle exposed no label, no `DisclosureTriangle` descendants existed, and geometry clicks eight points before the "Folders" header did not collapse the section. Commit `9af4b91` then changed the implementation to expose a native disclosure control, and **no hosted run has executed after that commit** — the fix is merged unproven on the hosted lane. The next agent may dispatch exactly one focused disclosure method against a commit containing `9af4b91`; if that fifth attempt still cannot toggle the disclosure, treat rendered disclosure toggling as a hosted-XCUI limitation, cover the collapse behavior with a headless state assertion instead, and stop spending runner minutes on it.

The pending UI coverage includes:

- Search focus/filter/empty state and Escape behavior.
- Multi-selection summary and separate per-currency totals.
- Delete-to-archive followed by Undo.
- Inline folder rename, including whitespace rejection.
- Quick Look collection presentation.
- Receipt drag-to-folder filing.
- Export sheet Show in Finder affordance.
- Content zoom stepping, persistence, reset, and disabled ladder endpoints.
- Receipt-viewer magnification command routing.
- Existing Mac folder-editor and nested category-sheet regression flows.
- Sidebar Folders-section disclosure collapse/expand via the native control exposed in `9af4b91`.

## Pending manual Mac acceptance

- Spot-check Undo/Redo after a CloudKit sync round trip.
- Exercise Continuity Camera Import from iPhone, including cancellation and multi-page scan intake.
- Confirm the Dock badge changes correctly across agent-entry confirm and discard.
- Run VoiceOver through the multi-selection summary and inline rename.
- Complete an import-to-folder workflow using only the keyboard.
- Verify largest content zoom in normal and Full Screen window layouts.
- Verify window frame, sidebar selection, and zoom restoration across a normal quit and relaunch.

## Exit condition

Close this note after the hosted full-class receipt is green, its logs and `.xcresult` are recorded, and each manual item above has been checked on the installed app. `make test-focus-mac` and `make test-mac` remain owner-explicit local fallbacks only.
