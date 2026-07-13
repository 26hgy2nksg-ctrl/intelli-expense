# SPEC-fm-tools-workspace — Standalone Foundation Models prompt-evaluation workspace

**Status**: Draft — ready for execution
**Owner screens**: none (no app UI surface). Owner artifacts: `/Volumes/External-2TB/Projects/fm-tools/` (new, outside this repository), and read-only references into this repository: `IntelliExpense/Capture/FoundationModelReceiptService.swift` (schema + prompt factory), `Makefile` (toolchain-scoping pattern), `docs/verification/testing-strategy.md` (verification ladder).
**Docs this spec amends**: none in this repository. This spec creates external tooling only; `DESIGN.md`, `design/ui-spec.html`, and `Localizable.xcstrings` are untouched because no user-facing app surface changes.

## 1. Problem

Iterating on the receipt-extraction prompt, instructions, and schema currently requires building and running the app on device, scanning or importing a receipt, and reading the review screen. That loop is minutes long, non-deterministic, and produces no persisted record of which prompt wording performed better on which receipts. Three upstream open-source projects (Rudrank Riyam's `afm` CLI, his Foundation Lab workbench app, and the `FoundationModelsKit` package) provide a headless and an interactive harness for the same on-device `SystemLanguageModel`. They must be set up durably, outside this repository, so prompt experiments never contaminate the app codebase, its git history, or its planned open-source publication (see `docs/specs/SPEC-oss-publication.md`).

## 2. Goals

- G1: A durable sibling workspace at `/Volumes/External-2TB/Projects/fm-tools/` containing shallow-history-free (full) clones of the three upstream repositories, treated as read-only mirrors.
- G2: A built, runnable `afm` release binary usable from any shell without modifying machine-wide toolchain state.
- G3: An `intelli-expense-eval/` sub-workspace (its own local git repository, no remote) holding a `receipt.yaml` schema document, an `instructions.md` system-instructions file, and a `prompt-template.md` — each derived faithfully from the app's current extraction code — plus `fixtures/` and `runs/` directories with documented conventions.
- G4: A verified end-to-end run: one synthetic OCR fixture pushed through `afm schema run custom` returning structured JSON that decodes into the six expected receipt fields.
- G5: A `README.md` in `fm-tools/` recording layout, update procedure, boundary rules, and the exact upstream commit SHAs cloned, so a future agent can refresh or rebuild the workspace without this conversation.

## 3. Non-goals

- No dependency edge from Intelli-Expense to any of the three repositories. `project.yml`, `ExpenseCore/Package.swift`, and the Xcode project remain untouched. `FoundationModelsKit` is explicitly rejected as an app dependency (chat/PCC-centric scope, `branch: main` versioning, bundled network-calling tools conflicting with the app's no-network rule).
- No committing of real receipt OCR text anywhere. Real fixtures are personal data and stay only in `intelli-expense-eval/fixtures/real/`, which is git-ignored even inside the eval repo's own git history.
- No changes to app behavior, prompts, or schema in this spec. When an experiment converges, the result flows back as a separate normal spec + implementation change in this repository.
- No patching of the upstream clones. Ideas worth keeping (e.g. `FoundationModelsKit`'s `RuntimeCompatibleGenerable` compatibility shim or its token-estimation constants) get reimplemented in `ExpenseCore` under a future spec, never vendored.
- No building of Foundation Lab's iOS/visionOS variants and no Private Cloud Compute / bridge setup; on-device macOS execution only.
- No hosted CI for any of this. GitHub-hosted macOS runners have no Apple Intelligence; all live model runs are local-Mac-only, consistent with `docs/verification/github-macos-runner-usage.md`.

## 4. Design decisions

- **D1 — Location: sibling directory `/Volumes/External-2TB/Projects/fm-tools/`, never inside this repository.** Rule satisfied: the repository's anti-drift and OSS-publication posture requires that non-app tooling, third-party clones, and personal receipt data never enter the app tree or its git history. A sibling under the same `Projects/` root keeps everything on the external volume the owner already uses for all projects. Rejected alternative: a `tools/` subdirectory inside intelli-expense (pollutes the OSS-bound tree, risks accidental staging); rejected alternative: `~/Documents` (splits project storage across volumes).

- **D2 — Layout.**
  ```
  /Volumes/External-2TB/Projects/fm-tools/
  ├── README.md                           # layout, boundary rules, pinned SHAs, update procedure
  ├── Foundation-Models-Framework-Lab/    # clone, read-only mirror
  ├── Foundation-Models-Framework-CLI/    # clone, read-only mirror; afm built here
  ├── FoundationModelsKit/                # clone, read-only mirror, reference reading only
  └── intelli-expense-eval/               # local git repo (git init, no remote)
      ├── README.md                       # run conventions, how to regenerate schema from app code
      ├── .gitignore                      # ignores fixtures/real/ and runs/
      ├── .afm/schemas/receipt.yaml       # schema document mirroring FoundationModelReceiptSchema
      ├── instructions.md                 # system instructions mirroring the prompt factory
      ├── prompt-template.md              # task + field-checklist prompt body for manual composition
      ├── fixtures/
      │   ├── synthetic/                  # committed, invented receipts (safe)
      │   │   └── cafe-simple.txt         # first fixture, created by this spec
      │   └── real/                       # git-ignored, personal OCR dumps
      └── runs/                           # git-ignored dated JSON outputs
  ```
  Rejected alternative: keeping eval assets inside the CLI clone's own `.afm/` directory (updates via `git pull` would then risk conflicts, and eval assets would live in a directory this workspace treats as read-only).

- **D3 — Toolchain scoping follows the repository's existing pattern: `DEVELOPER_DIR` per-invocation, never `xcode-select`.** The `afm` package requires swift-tools 6.2 (README nominally asks for Xcode 26.6 or 27). The build must first try the machine's default toolchain; if the tools-version check fails, retry with `DEVELOPER_DIR=/Volumes/External-2TB/Applications/Xcode-27-beta.app/Contents/Developer`, exactly mirroring the scoping used by `make build-device` in this repository's Makefile. Machine-wide `xcode-select` state must not change. If the beta path is used, run the repository's documented readiness check first (`make check-xcode-beta` from the intelli-expense directory); if it exits 69, stop and report per the CLAUDE.md beta-readiness rule rather than running `-runFirstLaunch` without need.

- **D4 — Binary exposure: symlink, not PATH edits.** After `swift build -c release --product afm`, symlink the built binary to `~/bin/afm` if `~/bin` exists and is already on the owner's PATH; otherwise create `fm-tools/bin/afm` as the symlink target and record in `fm-tools/README.md` that invocations use the absolute path. Do not edit shell profiles — modifying the owner's shell configuration is out of scope and needs an explicit owner decision.

- **D5 — Clones are full (not shallow) and pinned by record, not by lock.** Full clones allow `git log` archaeology on upstream changes. The exact `HEAD` SHA of each clone at setup time is recorded in `fm-tools/README.md`. Update procedure is documented as: `git pull` per clone, rebuild `afm`, re-run the acceptance fixture, update the recorded SHAs. Rejected alternative: submodules under a parent repo (adds ceremony with no consumer; nothing depends on these clones programmatically).

- **D6 — `receipt.yaml` mirrors `FoundationModelReceiptSchema` field-for-field.** The app's `@Generable` schema (in `IntelliExpense/Capture/FoundationModelReceiptService.swift`) has exactly 18 string properties: six receipt fields (`vendor`, `date`, `totalAmount`, `currencyCode`, `paymentMethod`, `expenseType`), each accompanied by an `…Alternate` and an `…AlternateReason` property. The schema document must reproduce: every property name verbatim; every `@Guide` description verbatim; `enum` constraints of `["card","cash","unknown"]` for both payment-method properties and `["food","hotel","flight","taxi","other","unknown"]` for both expense-type properties; all 18 properties required with `type: string` (the app schema has no optionals — absence is expressed by the literal string `unknown`, and empty string for absent reasons). Property ordering must follow the Swift declaration order via the schema document's ordering mechanism, since guided generation emits fields in schema order and the app's alternate-after-primary ordering is deliberate. Known fidelity limit (documented in the eval README, accepted): the CLI compiles this document to a `DynamicGenerationSchema`, so token counts and generation behavior approximate but do not byte-match the compiled `@Generable` schema; the harness validates prompt and schema design, while the app's unit tests against `ExtractionModelServicing` fakes remain the source of truth.

- **D7 — `instructions.md` and `prompt-template.md` are transcriptions, not inventions.** `instructions.md` reproduces the exact five-line output of the prompt factory's instructions builder for locale `en_US` (extraction persona, English-schema note, output-language instruction, structured-values-only rule; the locale line is omitted for `en_US` exactly as the factory omits it). `prompt-template.md` reproduces the prompt body: the extraction task paragraph ("Extract one receipt from the supplied evidence…"), the six-item field checklist, the Amount rule, and the Vendor rule verbatim, followed by a marked slot where fixture OCR text is appended. Each file carries a header comment naming the source file and stating that the app code is authoritative and these files must be re-transcribed when the factory changes. Rejected alternative: paraphrasing or "improving" the wording during transcription — that would make every eval run test a prompt the app does not ship.

- **D8 — Deterministic generation settings are the harness default.** All scripted runs use greedy sampling with a fixed seed and JSON output (`--sampling greedy`, `--seed`, `--output json --pretty`), matching the app's own `GenerationOptions(sampling: .greedy, …)`. Run outputs are written to `runs/YYYY-MM-DD-<slug>.json` so before/after prompt comparisons are plain file diffs.

- **D9 — Foundation Lab is built once as proof, not installed.** Build the macOS app with the README-documented signing-disabled invocation (`xcodebuild -project FoundationLab.xcodeproj -scheme 'Foundation Lab' -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO build`) to prove the interactive workbench is one command away, and record the invocation in `fm-tools/README.md`. Do not copy it to `/Applications`, do not launch it during setup (it is a GUI app on the owner's desktop). Its value to this project is the Playground for interactive prompt iteration, the invoice-extraction lab (`Foundation Lab/Views/Examples/DynamicSchemas/InvoiceProcessingSchemaView.swift`) as the closest published analog to the receipt pipeline, and the availability-state examples paralleling PRD §6.4.

- **D10 — `FoundationModelsKit` is cloned for reading only.** No build step, no product consumption (it arrives transitively as an `afm` dependency anyway). `fm-tools/README.md` lists the two study targets for possible future reimplementation in `ExpenseCore` — the OS-26/Xcode-27 `RuntimeCompatibleGenerable` compatibility shim and the calibrated token-estimation constants — plus the bundled `skills/foundation-models-app-builder` playbook as reference reading, and repeats the do-not-depend rationale from §3.

- **D11 — First fixture is synthetic.** Create `fixtures/synthetic/cafe-simple.txt`: an invented, obviously fake café receipt OCR dump (fake merchant name, plausible line noise, a subtotal, a tax line, and a final total, dated in the past, USD). It exists to prove the pipeline and to serve as the regression smoke fixture. Real receipt dumps are added later by the owner into the git-ignored `fixtures/real/`.

## 5. Edge cases

- E1: Default toolchain rejects swift-tools 6.2 → retry the `afm` build with the scoped beta `DEVELOPER_DIR` per D3. If both fail, stop and report the two build errors; do not attempt toolchain installs.
- E2: `make check-xcode-beta` exits 69 → stop and report per CLAUDE.md (one-time component setup is an owner-visible action already documented there).
- E3: Apple Intelligence unavailable on this Mac at run time → `afm available --output json` reports it; complete every non-live step (clone, build, schema files, `--dry-run` validation) and report the live-run acceptance criterion as blocked with the reported unavailability reason. Do not toggle system settings.
- E4: `afm`'s schema-document dialect rejects a construct (e.g. an ordering or enum spelling) → adapt the YAML to the dialect the CLI's schema loader actually supports while keeping property names, descriptions, and enum values verbatim; record any deviation in the eval README. If a required construct is genuinely unsupported, record it as a known fidelity limit under D6 rather than altering the app-facing wording.
- E5: `~/bin` absent or not on PATH → fall back to `fm-tools/bin/afm` per D4; never edit shell profiles.
- E6: `fm-tools/` already exists from a prior partial attempt → inspect before touching; reuse clean clones, re-run only missing steps, and never delete existing directories without reporting first.
- E7: Upstream `main` moves between analysis and execution → proceed with current `HEAD`, record actual SHAs; if the `afm` command surface differs from this spec's expectations (subcommand names, flag spellings), follow the clone's own README/`--help` as authoritative for invocation syntax while preserving this spec's intent, and note the differences in `fm-tools/README.md`.
- E8: Live run returns structurally valid JSON but wrong field values (e.g. subtotal chosen as total) → this is a prompt-quality observation, not a setup failure; the acceptance criterion is a well-formed structured response, not extraction accuracy. Record the output in `runs/` as the baseline.

## 6. Accessibility & localization

Not applicable — no app UI, no user-facing strings in the app, no `Localizable.xcstrings` changes. The transcribed instruction files intentionally reproduce the app's English prompt text, which lives in code (model-facing, not user-facing) per the existing implementation.

## 7. Test impact

- No app targets, `ExpenseCore`, or test bundles change; no app test lanes need to run. `git status` in the intelli-expense repository must remain clean apart from this spec file itself.
- The eval workspace's own verification is the acceptance run in §8 plus `afm schema run custom --dry-run` as the model-free structural check (usable even where the model is unavailable).
- Future test impact (out of scope here, noted for the record): when a converged experiment flows back into the app, the corresponding spec cites the `runs/` evidence in its verification receipt.

## 8. Acceptance criteria

1. `/Volumes/External-2TB/Projects/fm-tools/` contains the three clones, `README.md` with pinned SHAs, boundary rules, update procedure, and the Foundation Lab build invocation.
2. The `afm` binary is built in release configuration; `afm --help` and `afm available --output json` both succeed from a fresh shell via the symlinked or absolute path, without any machine-wide toolchain change (`xcode-select -p` output identical before and after).
3. Foundation Lab's macOS build completes with signing disabled (build succeeds; app not installed or launched).
4. `intelli-expense-eval/` is an initialized git repository with the layout of D2; `fixtures/real/` and `runs/` are git-ignored; the initial commit contains `README.md`, `.gitignore`, `receipt.yaml`, `instructions.md`, `prompt-template.md`, and `fixtures/synthetic/cafe-simple.txt`.
5. `receipt.yaml` contains all 18 properties with names, `@Guide` descriptions, and enum constraints matching `FoundationModelReceiptSchema` verbatim, in declaration order; `instructions.md` and `prompt-template.md` match the prompt factory's `en_US` output verbatim per D7.
6. A dry-run schema validation succeeds, and — if Apple Intelligence is available (E3) — one live run over `cafe-simple.txt` with greedy sampling and a fixed seed produces JSON containing all six primary fields, saved as the first file in `runs/`; the JSON `totalAmount` for the fixture is a plain decimal string, demonstrating the unknown-sentinel/decimal-string contract survives the harness.
7. The intelli-expense working tree shows no modifications other than `docs/specs/SPEC-fm-tools-workspace.md`, and no new dependencies appear in `project.yml` or any `Package.swift`.
8. A short closing report states: pinned SHAs, toolchain used for the `afm` build, availability status at run time, and the path of the baseline run output (or the E3 blocker).
