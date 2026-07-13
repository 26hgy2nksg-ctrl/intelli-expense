# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this app is

**Intelli-Expense** — a private, on-device iOS 26 + native macOS 26 app that turns paper receipts into an organized, exportable expense record per trip. The user pays for work-trip expenses with a personal card/cash, scans receipts or imports them on Mac, on-device AI extracts the fields, the user confirms on a review screen, and later exports a finance-ready zip (date-named image folders + `summary.csv`) per group/trip. No server, no accounts — zero network calls except CloudKit private-database sync.

Pipeline at the heart of the app: **SwiftUI → VisionKit document scan → Vision document OCR (`RecognizeDocumentsRequest`) → deterministic parser → Foundation Models guided generation → merge → Review & Confirm UI**.

## Repository state

Implementation is underway. The repo contains iPhone and native Mac targets generated from `project.yml`, plus a local `ExpenseCore` Swift package for shared pure logic.

## Spec and planning artifacts

Agent-authored implementation specs, user-supplied spec drafts, and follow-up feature briefs belong in `docs/specs/`. Do not create `SPEC-*.md` files in the repository root; if a spec is provided at the root, move it into `docs/specs/` before committing and update any references to the new path.

Spec detail level: specs must be detailed enough that another agent can implement them faithfully without asking questions — name the owner screens/files, spell out design decisions with rationale (including considered-and-rejected alternatives), enumerate edge cases, new string-catalog keys, accessibility identifiers, test impact, and acceptance criteria. But keep them above code level: no Swift snippets, no function signatures, no line-by-line instructions — behavior and component references, not implementation.

Spec house format (follow the existing `SPEC-*.md` files): header with **Status**, **Owner screens** (file paths), and **Docs this spec amends**; numbered sections for Problem, Goals, Non-goals, Design decisions (D1, D2, …), Edge cases, Accessibility & localization, Test impact, Acceptance criteria.

## Keeping design, localization, and docs in sync (anti-drift rules)

The UI is consistent because three artifacts stay authoritative: `DESIGN.md` (tokens + rules), `design/ui-spec.html` (canonical screen mockups), and `Localizable.xcstrings` (every user-facing string). Any spec or implementation that touches UI must actively keep them that way:

- **Ground specs in the design system before inventing anything.** When a spec has a design surface, re-read the relevant `DESIGN.md` sections and `ui-spec.html` screens first, and *quote the specific rules that constrain the decision* in the spec's design-decisions section (e.g., "one hero number per screen", the two-element glass budget, single brand accent / no red, Dynamic Type only, base-4/8 grid, nine asset-catalog token pairs, no `colorScheme` branches). A design decision that doesn't cite the rule it satisfies is a drift risk; a decision that can't cite one is probably inventing a pattern that needs D-review below. Prefer reusing an existing component (name it and its file) over describing a new one that looks similar.
- **New UI patterns amend the canonical docs in the same change.** If a feature introduces a component, layout, or interaction not yet in `DESIGN.md`/`ui-spec.html`, the spec's "Docs this spec amends" header must list them and the implementation commit must update them — the mockups and rules never lag the shipped app. If a feature genuinely conflicts with a `DESIGN.md` rule, do not silently deviate: either change the design to fit the rule, or amend `DESIGN.md` explicitly (with rationale) in the spec so the rule stays true.
- **Localization is enumerated, never implied.** Every spec that adds or changes user-facing text must include the key/value table: new string-catalog keys with English values, changed *values* on stable keys (keys never renamed for copy changes), and plural variants where counts appear. Locale-dependent data (dates, currency names/symbols, number formatting) comes from Foundation formatters/locale APIs, never from the catalog and never hardcoded. A spec whose strings aren't in the table will produce hardcoded strings — reject it.
- **Accessibility identifiers and Dynamic Type are spec content**, not implementation afterthoughts: list new identifiers, state the VoiceOver grouping for composite elements, and note any AX-size behavior (wrapping, horizontal scrolling) the layout depends on.
- **Use the design skills when building or reviewing UI** (`swiftui-design-principles`, and `apple-platform-think` for API grounding), and verify against `ui-spec.html` (the `design-spec` preview server) before calling UI work done.

## Commit discipline

Spec implementation must happen on a branch named for that spec, never directly on `main`. Use `codex/<spec-slug>` by default (for example, `codex/per-category-distinct-colors`) so the branch, commit, and spec file can be matched during review and later archaeology.

Commits must be **frequent and focused**. Commit whenever a complete logical unit is green instead of accumulating a large dirty tree until the end. A small spec may fit in one coherent commit; a larger spec should use multiple focused commits at natural checkpoints. Never mix multiple specs or unrelated work in the same commit. Stage only files that belong to the current logical unit, and preserve and call out any unrelated dirty work that was already present.

For non-spec changes, follow the same frequent, focused discipline and commit at natural checkpoints after the relevant verification passes. The only normal reasons to hand off verified implementation without a commit are: the owner explicitly asked not to commit, verification is blocked, or the change is intentionally an exploratory tryout.

## Required reading (in this order, before writing code)

1. [PRD.md](PRD.md) — the complete product spec: goals/non-goals, data model (4 entities), screens, extraction pipeline, export format, acceptance criteria. **Read it fully before writing any code.** Its §0 ground rules are binding.
2. [DESIGN.md](DESIGN.md) — design system: machine-readable tokens in the YAML frontmatter + rules in the body. PRD defines *what*; DESIGN defines *how it looks and feels*.
3. [design/ui-spec.html](design/ui-spec.html) — canonical screen-by-screen mockups. On layout, this file wins; on tokens/rules, DESIGN.md wins.
4. Re-read the production lessons in `PRD.md` §0 and §6 before changing the receipt pipeline. The original private proof of concept established feasibility on a real iPhone, but is intentionally not part of this repository; its relevant warnings are captured in the PRD and current protocol-backed implementation. Treat the POC as evidence, never as an architecture to reconstruct.
5. [PLAN.md](PLAN.md) — the checkpointed implementation plan (TDD, milestone order, verification commands).

## Platform & stack (fixed decisions — see PRD §3)

- iPhone (iOS 26.0+) and native Mac (macOS 26.0+), Swift 6 strict concurrency, SwiftUI with `@Observable` main-actor view models. Product behavior stays shared; layout, density, presentation sizing, focus, and command placement adapt to each platform.
- SwiftData + CloudKit mirroring (private DB). CloudKit schema rules from day 1: all relationships optional with inverses, no `.unique`, defaults/optionality on every attribute.
- OCR: Vision `RecognizeDocumentsRequest`. AI: FoundationModels `SystemLanguageModel` + `@Generable` guided generation. Verify all Apple APIs against current docs before locking choices; use the `apple-platform-think` and `swiftui-design-principles` skills when available.

## Non-negotiable constraints (recurring traps)

- **Money is `Decimal` end-to-end** — never Float/Double; locale-aware `FormatStyle` formatting; never sum across currencies; never hardcode currency symbols.
- **Every user-facing string lives in the String Catalog** (`Localizable.xcstrings`) from the first commit; English-only UI at launch but adding a language must be a pure translation task (PRD §3.2).
- All language-specific parser knowledge (total-label keywords, date formats, digit grouping) lives in **one per-language data table**, never inline in parser logic.
- OCR, Foundation Models, and the availability check go **behind protocols with deterministic fakes** — every availability/degradation state (PRD §5.0/§6.4) must be testable without real hardware.
- Deterministic parser results are baseline truth; the model refines and fills gaps, it never silently overrides (merge policy, PRD §6.3).
- Apple Intelligence is a requirement (blocking gates for ineligible/disabled) but transient unavailability degrades gracefully — capture must never be blocked at a cash register (PRD §6.4).
- Respect PRD §2 non-goals: no line items, no currency conversion, no dashboards, no reimbursement tracking, no third-party services. When in doubt, cut scope, not quality.
- Design: single brand accent (Ledger Green), no red anywhere, Dynamic Type only (no fixed point sizes), semantic colors + nine named asset-catalog token pairs, no `colorScheme` branches in feature code.

## Commands

- Preview the design spec: `python3 -m http.server 8734 --directory .` then open `http://localhost:8734/design/ui-spec.html` (configured as the `design-spec` server in `.claude/launch.json`).
- Generate the Xcode project after editing `project.yml`: `xcodegen generate`
- ExpenseCore package tests: `cd ExpenseCore && swift test`
- App simulator build: `xcodebuild -project IntelliExpense.xcodeproj -scheme IntelliExpense -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' build`
- App unit + UI tests: `xcodebuild -project IntelliExpense.xcodeproj -scheme IntelliExpense -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' test`
- Native Mac signed build: `make build-mac`
- Native Mac behavior/unit tests: `make test-mac-unit` (local; no UI automation)
- Native Mac UI automation: use the manual GitHub-hosted workflow with one exact method filter. `make test-focus-mac TEST=<target/class[/method]>` and `make test-mac` are owner-explicit local fallbacks only.
- Shared UI changes must run every affected platform lane before handoff: normally `make test-app` locally, relevant `make test-mac-unit` coverage locally, and one focused hosted Mac UI method when rendered Mac interaction is affected. Run the complete hosted Mac UI class only once for an intentional closeout receipt. If one platform is genuinely unaffected, state why in the spec and verification receipt; a successful cross-platform compile is not a substitute for exercising the changed screen.
- Default phone build/install after normal app work: `make build-device` or `make install-device`. These canonical durable-app targets scope `DEVELOPER_DIR` to `/Volumes/External-2TB/Applications/Xcode-27-beta.app`, enable `XCODE_27_FOUNDATION_MODELS`, and install `com.nags.intelliexpense` on the paired iPhone without uninstalling or resetting existing app data. Override the beta location with `XCODE_BETA_DIR=/path/to/Xcode-27-beta.app`; never change machine-wide `xcode-select`. The explicit `make build-device-beta` / `make install-device-beta` names remain compatibility aliases for the same default lane. `DEVICE_ID` must be the physical Xcode destination UDID, not the CoreDevice UUID; `make devices` prints both inventories and labels the Xcode destinations.
- Beta readiness: `make check-xcode-beta` must pass before the default phone lane. If it exits 69 after a new beta install, complete the beta's one-time component setup with `DEVELOPER_DIR=/Volumes/External-2TB/Applications/Xcode-27-beta.app/Contents/Developer xcodebuild -runFirstLaunch`, then rerun the check. This setup remains scoped to the beta app and does not change `xcode-select`.
- Stable-Xcode phone fallback: `make build-device-stable` or `make install-device-stable`. Use these only when the owner explicitly needs a text-only build from the machine's stable Xcode; they preserve the same durable bundle and app data. If the required beta toolchain, paired phone, or signing path is unavailable for the default handoff, stop and report the blocker instead of silently substituting the stable lane.
- Xcode 27 beta simulator/test lane: `make build-sim-beta` or `make test-app-beta`. These use the same scoped beta toolchain and image-input compilation condition as the default phone lane without changing `xcode-select`.
- Sandbox side-by-side lane: run `make sandbox-profile` first, then `make install-device-sandbox`. This builds `IntelliExpenseSandbox` (`com.nags.intelliexpense.sandbox`) with local-only SwiftData, CloudKit/App Group off, generic screenshot-safe seed trips/receipts, and a reset-by-default install. Use this lane whenever the owner asks for "sandbox", "seeded sandbox", side-by-side testing, or App Store screenshot data. Do not install or uninstall the durable app in that lane unless the owner explicitly asks.

### GitHub-hosted Mac UI automation

- GitHub-hosted Mac runners are reserved exclusively for native Mac UI automation that would occupy the owner's desktop. Project generation, builds, package tests, app tests, Mac unit tests, source scans, and every other non-UI check run locally.
- `.github/workflows/macos-ui.yml` is manual-only. Push and pull-request triggers are forbidden because hosted Mac minutes are limited. Each dispatch requires a reason and one exact `IntelliExpenseMacUITests/IntelliExpenseMacUITests` class or method filter.
- Prefer one exact method. Select the whole class only for a deliberate closeout receipt, never to diagnose one failure. A second run requires a relevant change or the single permitted fresh-runner retry for a pre-assertion initialization failure.
- Before dispatch, read [docs/verification/github-macos-runner-usage.md](docs/verification/github-macos-runner-usage.md), confirm no existing receipt answers the question, and confirm no Mac job is already queued or running. After every job, append GitHub's job duration and conservatively rounded minutes to the ledger.
- The workflow pins `macos-26` and Xcode 26.5, regenerates and drift-checks the project, disables signing only for CI, uploads logs and `.xcresult` evidence for 14 days, and has read-only repository permission. It needs no Apple signing, CloudKit, or repository secrets.
- CI is a closing receipt, not a diagnostic loop. Diagnose locally with `make test-core`, `make test-app`, or `make test-mac-unit` wherever possible. Two matching pre-assertion initialization failures are a hosted-runner blocker; do not configure a self-hosted runner without a new owner decision.
- Follow [docs/verification/testing-strategy.md](docs/verification/testing-strategy.md) for the verification ladder, dispatch command, failure classification, and artifact handling.
