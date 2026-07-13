# GitHub-hosted macOS runner usage

GitHub-hosted Mac runners are reserved exclusively for Intelli-Expense native Mac UI automation. Every non-UI check runs locally on the owner's Mac.

## Accounting rule

- Record every hosted Mac job, including setup failures, retries, and cancelled jobs.
- Measure from GitHub job `started_at` to `completed_at` and round up to a whole minute.
- Count concurrent jobs separately.
- GitHub's billing page is authoritative for the remaining allowance; this ledger is the repository receipt.
- Before dispatch, verify native Mac UI interaction is necessary and prefer one exact method.

## Usage ledger

| Date (UTC) | Run | Reason/filter | Result | Actual duration | Conservative minutes |
|---|---:|---|---|---:|---:|
| 2026-07-11 | [29153870386](https://github.com/dctmfoo/intelli-expense/actions/runs/29153870386) | Hosted activation proof: `testEmptyDetailStateRendersWhenNothingIsSelected` | Passed 1/1 | 2m 39s | 3 |
| 2026-07-11 | [29153984852](https://github.com/dctmfoo/intelli-expense/actions/runs/29153984852) | First full-class closeout receipt | 5/17 passed; exposed scene-restoration and modal-search isolation defects | 5m 51s | 6 |
| 2026-07-11 | [29154262018](https://github.com/dctmfoo/intelli-expense/actions/runs/29154262018) | Focused seeded delete/undo confirmation | Seed data was present; exact-label query could not see composite Mac row value | 3m 07s | 4 |
| 2026-07-11 | [29154423811](https://github.com/dctmfoo/intelli-expense/actions/runs/29154423811) | Focused composite-row retry | Row lookup and Delete passed; Command-Z exposed missing window undo-manager wiring | 1m 40s | 2 |
| 2026-07-11 | [29154589721](https://github.com/dctmfoo/intelli-expense/actions/runs/29154589721) | Focused Command-Z wiring confirmation | Delete passed; command availability remained stale after the undo group closed | 1m 39s | 2 |
| 2026-07-11 | [29154774745](https://github.com/dctmfoo/intelli-expense/actions/runs/29154774745) | Focused command-availability retry | Delete passed; local manager was not the SwiftUI window responder-chain manager | 2m 33s | 3 |
| 2026-07-11 | [29154936527](https://github.com/dctmfoo/intelli-expense/actions/runs/29154936527) | Final focused Command-Z confirmation for this pass | Archive and headless undo remain green; rendered Command-Z restoration remains pending | 1m 42s | 2 |
| 2026-07-11 | [29155025480](https://github.com/dctmfoo/intelli-expense/actions/runs/29155025480) | Repeated folder-selection proof | Passed 1/1; two Berlin Filing to Unfiled cycles | 1m 47s | 2 |
| 2026-07-11 | [29155091730](https://github.com/dctmfoo/intelli-expense/actions/runs/29155091730) | Whole-window content zoom proof | Command fired; `dynamicTypeSize` left explicit semantic-font frame unchanged | 1m 46s | 2 |
| 2026-07-11 | [29155301054](https://github.com/dctmfoo/intelli-expense/actions/runs/29155301054) | App-wide semantic content zoom confirmation | Passed 1/1; zoom steps, persistence, reset, and endpoints | 1m 29s | 2 |
| 2026-07-11 | [29155380634](https://github.com/dctmfoo/intelli-expense/actions/runs/29155380634) | Category-sheet search isolation confirmation | Correct search field found; nested Mac sheet did not transfer keyboard focus | 2m 17s | 3 |
| 2026-07-11 | [29155506707](https://github.com/dctmfoo/intelli-expense/actions/runs/29155506707) | Category search keyboard-focus confirmation | Passed 1/1; empty results, stable viewport, reset, and dismissal | 2m 08s | 3 |
| 2026-07-12 | [29176520522](https://github.com/dctmfoo/intelli-expense/actions/runs/29176520522) | Sidebar bottom-bar creation, selected-folder disclosure, and badge proof | Creation, selection, and badge passed; system Folders disclosure triangle had no XCUI label | 3m 04s | 4 |
| 2026-07-12 | [29176624602](https://github.com/dctmfoo/intelli-expense/actions/runs/29176624602) | Disclosure-selector retry after first hosted hierarchy signal | Confirmed zero `DisclosureTriangle` descendants; artifact exposed Folders as a clickable outline-header `StaticText` | 1m 42s | 2 |
| 2026-07-12 | [29176748941](https://github.com/dctmfoo/intelli-expense/actions/runs/29176748941) | Artifact-grounded Folders header retry | Header label existed but did not toggle; hierarchy geometry located the native disclosure eight points before the text | 1m 54s | 2 |
| 2026-07-12 | [29176829909](https://github.com/dctmfoo/intelli-expense/actions/runs/29176829909) | Native disclosure geometry retry | Coordinate click was delivered eight points before the Folders label, but the selected folder remained visible; hosted XCUI still could not toggle the system disclosure | 2m 04s | 3 |
| 2026-07-12 | [29208704932](https://github.com/dctmfoo/intelli-expense/actions/runs/29208704932) | Receipt-selection Amount regression proof | Seeded rows loaded, but the test queried the Amount field before explicitly selecting the first receipt; production assertion was not reached | 2m 30s | 3 |
| 2026-07-12 | [29208859306](https://github.com/dctmfoo/intelli-expense/actions/runs/29208859306) | Receipt-selection Amount regression confirmation | Passed 1/1; editable Amount followed explicit selection across 84.50, 20.00, and 10.00 receipts | 2m 26s | 3 |

Tracked actual job time: **42m 18s**. Conservative rounded usage: **51 Mac runner-minutes**.

## Dispatch checklist

1. Local project generation, compilation, and relevant non-UI tests are green.
2. Existing evidence does not already cover the question.
3. The dispatch reason explains why rendered native Mac UI interaction is required.
4. One exact method is selected unless this is an intentional full-class closeout.
5. No run is already queued or active.
6. A rerun follows a relevant change, except for one fresh-runner initialization retry.
7. The result and GitHub job duration are appended here.
