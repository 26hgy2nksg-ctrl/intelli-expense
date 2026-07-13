# SPEC — GitHub-hosted macOS UI automation

**Status:** Implemented; first hosted proof pending
**Owner surfaces:** `.github/workflows/macos-ui.yml`, `Makefile`, `CLAUDE.md`, `AGENTS.md`, `docs/verification/testing-strategy.md`
**Branch:** `codex/github-macos-ui-automation`

## 1. Problem

Intelli-Expense's native Mac UI suite can occupy the owner's desktop and currently fails to activate its test app from a non-foreground local session. GitHub-hosted Mac capacity is limited and charged in minutes, so generic CI and automatic triggers would waste the allowance.

## 2. Goals

- Run only irreducible AppKit/XCUI interaction on an ephemeral GitHub-hosted Mac.
- Keep every build, package test, unit test, project check, and other non-UI verification local.
- Make hosted use manual, focused, auditable, and conservative.
- Preserve logs and `.xcresult` evidence without adding Apple credentials or repository secrets.

## 3. Non-goals

- No push or pull-request workflow trigger.
- No iOS simulator, core, app unit, or Mac unit tests on a GitHub-hosted Mac.
- No self-hosted runner and no persistent GitHub credentials on the owner's Mac.
- No repeated full-suite diagnostic loop.

## 4. Decisions

- The workflow uses GitHub's `macos-26` image and `/Applications/Xcode_26.5.app`.
- Every dispatch requires a reason and an exact `IntelliExpenseMacUITests/IntelliExpenseMacUITests` class or method filter. The prefilled value is the smallest existing smoke test.
- Only a deliberate closeout receipt may select the whole class; diagnosis selects one method.
- XcodeGen 2.43 or newer regenerates the project, and committed-project drift fails the run.
- CI disables signing at the command line. Product signing, entitlements, and CloudKit configuration remain unchanged.
- The workflow has `contents: read`, a 20-minute timeout, no write-capable token, no secrets, queued concurrency, and no cancellation of already-running billed work.
- Every run uploads the raw log, `.xcresult`, summary JSON, and a step-observed usage estimate for 14 days.
- `IntelliExpenseMacTests` stays local through `make test-mac-unit`. Local Mac UI commands are owner-explicit fallbacks only.

## 5. Failure protocol

1. Fix project drift or compilation locally before another hosted dispatch.
2. Move assertion logic into local core/app/Mac unit coverage whenever it can be proven without rendered UI.
3. If UI interaction is irreducible, change the relevant code or configuration, then dispatch only the failed method.
4. A pre-assertion automation initialization failure may be retried once on a fresh runner. Two matching failures are recorded as a GitHub-hosted-runner blocker.
5. Run the complete Mac UI class once only when focused failures are cleared and a closeout receipt is needed.

## 6. Acceptance criteria

1. The workflow can be invoked only manually and runs only the native Mac UI target.
2. Invalid target/class filters fail before `xcodebuild` starts.
3. The project regenerates without drift and the selected UI test builds unsigned.
4. Every hosted job is recorded in the usage ledger using GitHub job timestamps and conservative rounding.
5. Agent guides state that non-UI checks are local and hosted Mac minutes are not a general CI resource.
6. The pending Mac verification note links hosted evidence and retains genuinely manual acceptance items.
