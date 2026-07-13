# SPEC — Agent import bridge (folder protocol + Claude/Codex plugin)

**Status:** proposed — **depends on SPEC-mac-app.md shipping first**
**Owner surfaces:** Mac app (agent-inbox watcher + trips manifest + provenance/badging), new `plugin/` directory in-repo (Claude Code plugin: skill + docs; Codex skill variant)
**Docs this spec amends:** PRD (new §: agent entry surface — scope, two modes, and the **review-first amendment**: human confirmation may occur in the agent conversation for structured entries, with attested provenance), `design/ui-spec.html` (agent-entered provenance line + raw-mode pending-review state on Mac), DESIGN.md (provenance presentation rule)
**Related:** SPEC-share-extension-import.md (the inbox-ingestion precedent this generalizes), GitHub issue #1 (App Intents entities — the future richer bridge)

---

## 1. Problem / user story

The user has a folder of receipt images (downloads, email attachments, phone photos synced to the Mac) and says to Claude Code or Codex: *"add these to Intelli-Expense."* The agent examines the receipts with its own vision, **does the data entry itself** — merchant, date, amount, currency, type, payment method, trip assignment — confirms the full result with the user in chat, and files finished records. The user never opens the app to type anything; the receipts simply appear in the Mac app, and on the iPhone via existing CloudKit sync.

Today there is no way for anything outside the app to add receipts except the iOS share extension — and no way at all to add *completed* receipt data.

**Repo grounding for the "skip the pipeline" premise:** the app already creates fully valid receipts with no OCR text, no draft, and no model output — the manual-entry path (`ReceiptReviewForm.manual()`). A receipt built directly from structured data plus an image attachment is therefore a shape the data model already supports; agent entry is the manual path with a different author and an attached image, not a new persistence concept.

## 2. Feasibility grounding — why the bridge must go *through* the app

**The one hard constraint (architectural law):** an external process must never write the SwiftData store directly. CloudKit mirroring exports changes observed by the app's own container; rows inserted into the SQLite file by another process are unsupported, fragile against schema evolution, and above all **do not reliably sync** — which breaks the exact "appears on the iPhone" promise of the user story. Every sanctioned design therefore hands *files* to the app and lets the app ingest them through its own pipeline and its own `ModelContext`, so persistence, validation, extraction, and CloudKit export all remain single-pathed.

Evidence base:

- **Repo:** the share extension already proves the pattern — files land in an inbox the app owns, the app ingests via the normal pipeline (`intelliexpense://shared-inbox` handling in `ContentView`). This spec generalizes that inbox to a Mac folder an agent can write.
- **Apple docs (offline docset):** the full extraction pipeline is macOS-native (see SPEC-mac-app.md §2 — FoundationModels, `RecognizeDocumentsRequest` on macOS 26). `shortcuts run` exists as a macOS CLI (Apple Support: "Run shortcuts from the command line") but runs user-authored *shortcuts*, not App Intents directly — a setup burden rejected for v1 (D6).
- **Web (plugin surface):** Claude Code plugins bundle skills/agents/hooks/MCP servers and distribute via marketplaces (code.claude.com/docs — plugins, skills, plugin-marketplaces); a skill is a `SKILL.md` with instructions + optional scripts. Codex has the equivalent Agent Skills mechanism (developers.openai.com/codex/skills). MCP (modelcontextprotocol.io) suits a long-running tool server; for "read a manifest, copy files," a skill driving plain file operations is simpler and works in *both* ecosystems.

**Verdict: feasible**, cleanly, with a file-drop protocol — no store surgery, no private-API risk, sync for free.

## 3. Goals

- A documented, versioned **agent-inbox folder protocol** with two drop modes:
  - **Structured mode (primary — the point of this feature)**: receipt file + a *complete* JSON record; the app validates and ingests it directly as a finished receipt — no OCR, no parser, no Foundation Models run. The agent did the data entry; the app is the endpoint.
  - **Raw mode (fallback)**: receipt file with routing info only; the app runs its normal extraction pipeline and the receipt lands pending review.
- A read-only **trips manifest** the app maintains, so agents can ground trip assignment in current data without a query channel.
- **Review-first, amended honestly and gated by a setting**: by default, structured entries land *pending review with all fields prefilled* (one-glance in-app confirm). An explicit **auto mode** setting lets attested chat confirmation count as the confirmation, landing entries confirmed. Provenance is recorded either way; every field stays editable later.
- A **Claude Code plugin** (skill) shipped from this repo, with a Codex skill variant — the agent-side counterpart that reads receipts, extracts the fields itself, proposes trip mapping, confirms everything with the user, and writes the drops.
- Everything local: no network beyond existing CloudKit, no third-party services, receipts never leave the machine except into the user's own agent context.

## Non-goals

- No direct store writes, ever (§2).
- No MCP server in v1 — the protocol is deliberately file-shaped so a skill suffices in both Claude and Codex; an MCP wrapper is a thin future addition if a client needs it.
- No App Intents command bridge in v1 (D6; issue #1's entities are the future path).
- No iOS-side inbox folder (iPhone users get this via the Mac app + sync; the iOS share extension remains the phone's bulk path).
- No auto-creation of trips by the agent in v1 — unknown suggestions go to Unfiled (D5).
- No unconfirmed structured entry: a structured drop whose sidecar does not attest user confirmation always lands pending review (D3) — the plugin cannot skip the human, in either setting state.
- No batch "confirm all" action for pending agent entries in v1 — per-receipt review keeps the manual mode meaningful; revisit if real batches make it tedious.

## 4. Design decisions

### D1 — The agent-inbox folder

A fixed, documented directory inside the Mac app's container (path published in the manifest, D2, so tools never hardcode it). The app watches it while running and sweeps it on launch — drops made while the app is closed are ingested next launch. Each drop is a pair:

- `<uuid>.<ext>` — the receipt file (same type allowlist as Mac import: images + PDF)
- `<uuid>.json` — sidecar. Common envelope: protocol version, mode (`structured` | `raw`), suggested trip (manifest ID and/or exact name), optional note, source label (e.g. "claude-code"), and — structured mode only — the complete receipt record plus a `userConfirmed` attestation.

**Structured-mode record schema** (the data-entry payload; formats chosen so the app's type laws survive JSON):

| Field | Format | Rule |
|---|---|---|
| `merchant` | string, non-empty | trimmed; length-capped |
| `date` | ISO 8601 date string | must parse; sanity-bounded (not future beyond tomorrow, not older than a documented horizon) |
| `total` | **string** decimal, e.g. `"1234.56"` | parsed to `Decimal` with `.`-separator canonical form — **never a JSON number**, which would round-trip through floating point and violate the Decimal-end-to-end law |
| `currency` | ISO 4217 code string | must be a known ISO currency (same validation set as the currency picker) |
| `expenseType` | enum string from a documented list | must match a known case exactly |
| `paymentMethod` | enum string from a documented list | must match a known case exactly |
| `notes` | optional string | length-capped |
| `userConfirmed` | boolean | must be `true` for structured ingestion (D3) |

Sidecar-less files are ingested raw to Unfiled (a bare drop is still better than a lost receipt). Files are consumed atomically: ingested → moved to a `processed/` subfolder (or `failed/` with a machine-readable reason file), so the agent can verify outcome by listing the folder — that *is* the result channel, no IPC needed.

### D2 — The trips manifest

The app maintains `manifest.json` beside the inbox: protocol version, inbox path, and per-trip `id` (stable model identifier), name, start/end dates, receipt count, currencies present, archived flag. Refreshed on relevant data changes and on launch. Read-only for agents; the app never reads it back (one-way, no trust in external edits). This answers "how does the agent see current app data" without any query API: file read.

### D3 — Ingestion: structured mode skips the pipeline; validation replaces extraction

**Structured mode (primary).** The app performs *no extraction*: it validates the record against the D1 schema, then materializes it directly — a `Receipt` with the given fields, `ReceiptAttachment`(s) from the dropped file (thumbnail generated as on any import), and an `ExtractionRecord` whose provenance says agent-entry and whose stored payload is the **verbatim sidecar** (full auditability: what the agent claimed is permanently inspectable). This is the repo's existing manual-entry shape (§1) with an attachment and a recorded author — no OCR text, no draft, no Foundation Models session, no merge. The receipt lands **confirmed**, in the resolved trip (manifest ID match, else exact-name match, else Unfiled), immediately visible on the Mac and on the iPhone via existing CloudKit sync.

Validation is strict and total — every field per the D1 table, with any failure sending the pair to `failed/` with a per-field reason. Validation replaces extraction; it does not soften because the agent "already did the work."

**Raw mode (fallback).** File with routing-only sidecar (or none): the existing import path runs — OCR → deterministic parser → guided generation → merge — and the receipt lands **pending review** exactly like any other capture. This keeps the bridge useful when the agent shouldn't or can't read the receipts itself.

**The confirmation rule that holds it together (setting-gated; PRD amendment).** A new Mac setting — **"Agent entries require in-app review"**, default **ON** — is the trust dial:

- **Manual (default)**: structured entries land **pending review with all fields prefilled**. Grounding note on the mechanism: in this app "pending review" is the *draft* state — a `Receipt` only exists after confirmation, and the share-extension inbox already occupies exactly this shape. So a manual-mode structured entry materializes as a draft whose prefilled field values come from the sidecar (recorded at the confirmed-source tier, not as model output), entering the existing review flow; confirming is a glance and a tap, never re-typing, and produces the `Receipt` + attachment + provenance exactly as auto mode would have. No new "needs review" flag on `Receipt` is introduced.
- **Auto (explicit opt-in)**: structured entries whose sidecar attests `userConfirmed: true` — meaning the plugin showed the user the complete record (all fields, not just trip routing) and the user approved it in chat — land **confirmed**. The PRD amendment is correspondingly scoped: *confirmation is a human act; with this setting enabled, its venue may be the agent conversation.*
- **Regardless of the setting**: a structured drop without the attestation lands **structured-pending** (the agent's data is kept and prefilled — never re-extracted, per D6 — but a human must confirm in-app). There is no sidecar shape, in any setting state, that yields a confirmed receipt without a human confirmation somewhere.

The app cannot verify the chat happened (the trust boundary is the user's own machine and their own agent session); what it enforces is that skipping confirmation is not expressible in the protocol, and what it records is who claimed what, verbatim, on the extraction record. The setting is read at ingestion time; flipping it later does not retroactively confirm pending entries.

Provenance surfaces as a quiet "Entered by agent" line in receipt detail (not a nagging badge); every field remains editable in-app like any receipt. The skill reads no setting — it always behaves identically; the app decides the landing state.

### D3a — Cross-device review: confirm from the iPhone, not just the Mac

Grounded fact: `ReceiptDraft`/`ReceiptDraftPage` are already in the CloudKit schema (`PersistenceStack.schema`) — drafts sync today. Pending agent entries therefore appear on **both** devices with zero new sync code, and the walk-away story completes anywhere: ask the agent on the Mac, leave, confirm from the iPhone on the couch. The review setting (D3) syncs as a preference or is per-device — decision: **per-device is wrong** (the landing state is decided once, at ingestion on the Mac); the setting lives where ingestion happens and needs no sync. Confirmation of a pending entry from either device wins by normal last-writer semantics.

### D3b — The confirmation card: confirm at a glance, edit only by choice

Agent entries arrive *complete* — every field filled, trip assigned, provenance known. Forcing the full Review & Confirm screen (built for uncertain OCR fields with choice chips) onto data that is already right would punish the happy path with a screen-per-receipt tax. Pending agent entries get their own presentation, mocked upfront in `design/ui-spec.html` §agent-entries (authored with this spec, not left to implementation):

- **Placement**: a "Needs confirmation" section pinned above the featured card on the Trips home (iOS) and at the top of the content column (Mac), present only when pending agent entries exist — zero chrome otherwise, same law as the Archived row.
- **Card anatomy** (one card per entry): receipt thumbnail + merchant name + amount right-aligned in tabular numerals at `.headline` weight (never hero weight — the featured card keeps the screen's one hero number); a meta line (date · type · payment); the assigned trip line; a quiet provenance footnote ("Entered by agent"); then two actions — **Confirm** (accent-filled capsule, the card's primary act) and **Review details…** (plain text button) which opens the *existing* full Review & Confirm screen prefilled, for the entry the user wants to change.
- **Interactions**: Confirm animates the card out and materializes the receipt (D3); confirming the last card removes the section. Tapping the card body = Review details (never silent-confirm on a body tap). No swipe-to-confirm — confirmation stays a deliberate button on both platforms.
- **Batch reality**: cards stack newest-first; the section header carries the count. No "confirm all" (non-goal) — but each confirm is one tap, so a five-receipt batch is five taps with full sight of every record.
- The card reuses existing component vocabulary (thumbnail, row typography, chips) and introduces no new colors or fixed sizes; VoiceOver reads each card as one element with Confirm and Review Details as actions.

This card is also the answer to "review from iOS": the same section, same card, both platforms — one design (SPEC-mac-app D4 sync doctrine).

### D4 — The plugin (agent side)

A `plugin/` directory in this repo containing a Claude Code plugin with one skill (`intelli-expense-import`), plus a Codex-skill variant of the same instructions.

**Authoring shape** (grounded in the Claude Code plugin/skill docs and the Codex Agent Skills docs cited in §2):

- Claude Code: standard plugin layout — a plugin manifest plus `skills/intelli-expense-import/SKILL.md`. The skill's frontmatter `description` carries the trigger vocabulary ("add receipts to Intelli-Expense", "import these receipts", "file my receipts") so it fires on natural phrasing; the body contains the D1 schema verbatim (field table, string-decimal money rule, enum lists), the manifest location/staleness check, the mandatory-confirmation step, the drop procedure, and the outcome-reporting format. Reference fixtures (sample manifest, valid/invalid sidecars) live beside it for authoring-time testing.
- Codex: the same instruction body as an Agent Skill in Codex's skill format — one source of truth for the instructions, two thin packagings; the protocol knowledge must not fork.
- Versioning: the skill states which protocol version it writes; the sidecar carries it; the app rejects newer-than-known (D5). Skill and app versions are decoupled by the protocol, coupled to it.
- The skill is instructions + schema only — no bundled executables; file operations use the agent's normal tools, which keeps it portable across both ecosystems and trivially auditable.

The skill's flow:

1. Locate the manifest (documented default path; error with guidance if the Mac app isn't installed/has never run).
2. Read the user's receipt directory; identify receipt-like files (allowlist).
3. **Do the data entry**: read each receipt image/PDF with the agent's own vision and produce the complete D1 record — merchant, ISO date, string-decimal total, ISO currency, expense type, payment method — plus a trip assignment grounded in the manifest (dates/merchant vs. trip ranges and names; "no good match → Unfiled"). The skill spells out the exact schema, the string-decimal money rule, and the enum lists.
4. **Present the complete records — every field, per receipt — to the user and get explicit approval before writing anything** (in Claude Code: AskUserQuestion; mandatory instruction, not a suggestion). Only approved records may carry `userConfirmed: true`; the user may correct fields in chat, and corrections go into the sidecar. Receipts the agent can't read confidently are offered as raw-mode drops instead.
5. Write sidecars + copy files into the inbox; poll `processed/`/`failed/` briefly; report per-file outcomes, including validation failures verbatim.

The skill documents that originals are copied, never moved or deleted. Distribution: in-repo for personal use; marketplace packaging is a later decision.

### D5 — Trust and safety boundaries

- App side validates everything: sidecar schema version, file type/size limits, path traversal (names are regenerated, never trusted), malformed JSON → `failed/` with reason. The inbox is data-only; nothing is executed.
- Unknown/ambiguous trip suggestion → Unfiled, never a wrong trip and never auto-created trips (an agent typo would otherwise mint junk trips that sync everywhere).
- Duplicate defense: same content hash already ingested (tracked per recent imports) → `failed/duplicate`, keeping agent retries idempotent.
- Privacy note in the plugin README: the agent reads receipt images into its own model context — that is the user's explicit choice when invoking the skill and stays within their agent session; the app itself remains no-network-but-CloudKit.

### D6 — Considered and rejected

- **Direct SQLite/SwiftData writes from the CLI**: §2 — unsupported, schema-fragile, and breaks CloudKit export. This is the failure mode the whole design exists to avoid.
- **`shortcuts run` App Intents bridge**: needs per-user Shortcuts setup, brittle structured output; superseded later by issue #1 entities if a live query/command channel is ever needed.
- **CloudKit web services from the plugin**: talking to the private database from a CLI requires user CloudKit auth tokens and re-implements the schema outside the app — violates the no-third-party/no-server ethos and duplicates truth.
- **MCP server in v1**: adds a process and a protocol for what two file reads and a copy achieve; revisit only for clients where skills can't run shell/file operations.
- **Re-running the app pipeline over structured entries "to double-check"**: the OCR/parser/model pass would produce a second opinion the merge policy was never designed to reconcile with human-confirmed data, doubles ingestion cost, and second-guesses a confirmation the user already gave. The extraction record retains the sidecar; auditability, not re-extraction, is the check.
- **Pipeline re-extraction as the downgrade for unattested structured drops**: an earlier draft sent them through OCR/parser/model; rejected once structured-pending existed as a state — the agent's data is strictly richer than a re-extraction, and the review screen prefilled from it is the cheaper, saner human check.
- **Auto mode as the default**: rejected — confirmation authority should be granted by the user after the agent earns trust, not assumed on install; default-manual also keeps the PRD amendment opt-in rather than ambient.

## 5. Edge cases

- **Mac app not running during drop**: files wait; launch sweep ingests (D1). The plugin tells the user to open the app if `processed/` stays empty.
- **Two agents / re-run of the skill**: UUID filenames + content-hash duplicate defense make drops idempotent.
- **Manifest stale (app closed for days)**: manifest carries a generated-at timestamp; the skill warns the user and suggests opening the app to refresh before mapping.
- **Apple Intelligence unavailable during ingestion**: irrelevant to structured mode (no model run — structured ingestion works on a gated Mac, a genuine benefit); raw mode degrades exactly as the existing capture path does (deterministic parser only, extraction retry pending).
- **Mixed batch (some records valid, some not)**: per-file outcomes — valid pairs ingest, invalid pairs fail individually with per-field reasons; never all-or-nothing.
- **Currency differs from the trip's dominant currency**: allowed (the app is multi-currency per receipt by design); the skill flags it to the user during confirmation as a likely extraction error rather than silently proceeding.
- **Archived trip suggested** (per SPEC-trip-archiving): treated as no-match → Unfiled; manifest includes the archived flag so well-behaved agents don't suggest them.
- **Protocol evolution**: sidecar/manifest both carry a version; app rejects newer-than-known versions to `failed/version` with a clear reason rather than guessing.

## 6. Accessibility & localization

New app-side strings (String Catalog): provenance line `receipt.provenance.agentEntry` ("Entered by agent"); setting `settings.agentEntries.requireReview` ("Agent entries require in-app review") with a footnote string explaining both modes; failure-reason strings are file-side English identifiers (machine-readable protocol, not UI — documented as such). The provenance line is a standard label in receipt detail, read by VoiceOver in place. Plugin-side text is English-only documentation (not app UI; outside the String Catalog rule's scope, noted explicitly).

## 7. Test impact

- **Unit tests (Mac app)**: structured-record validation table-driven per D1 field (string-decimal parse to exact `Decimal`, JSON-number total rejected, bad currency/enum/date each yielding its named `failed/` reason); the full D3 landing-state matrix (attested × setting → confirmed/pending; unattested → pending in both setting states); setting read at ingestion time (flip does not retro-confirm); bare file → raw to Unfiled; version/type/duplicate/path-hostile → correct reasons; manifest correctness incl. archived flag and regeneration on data change.
- **Integration tests**: (a) structured batch → N *confirmed* receipts in the right trips, correct `Decimal` totals, attachments + thumbnails present, verbatim sidecar on the extraction record, zero OCR/model invocations (asserted via the pipeline protocol fakes); (b) raw batch → pending-review receipts through the normal pipeline — both asserted through the store, not the UI.
- **Plugin**: skill instructions tested manually against fixture folders (happy path, no-manifest, ambiguous mapping, app-closed); the mandatory-confirmation step verified in both Claude Code and Codex.
- **Manual end-to-end**: the user story verbatim — folder of mixed receipts → chat mapping → confirm → visible in Mac app as pending review → visible on iPhone via sync → in-app review clears badges.

## 8. Acceptance criteria

1. The user story runs end-to-end: point the agent at a folder → agent presents complete per-receipt records (all fields + trip) grounded in the live manifest → user approves in chat → with the review setting in **auto**, receipts appear **confirmed** in the Mac app and on the iPhone via existing CloudKit sync with no in-app pass; with the **default (manual)** setting, they appear pending review with every field prefilled, and confirming each is a single in-app action with no re-typing.
2. Structured ingestion runs zero extraction (no OCR, no parser, no model session — provable via the pipeline fakes), validates every field per the D1 schema, stores totals as exact `Decimal` from string-decimal JSON, and retains the verbatim sidecar as provenance; raw-mode drops go through the unmodified pipeline into pending review.
3. No component ever writes the SwiftData store from outside the app; removing the plugin leaves the app fully functional; disabling the inbox (folder absent) is a no-op.
4. Malformed, oversized, wrong-type, duplicate, path-hostile, future-versioned, or invalid-field drops land in `failed/` with machine-readable per-field reasons; nothing from the inbox is ever executed; trips are never auto-created; archived trips never receive agent entries.
5. Human confirmation is structurally unskippable across the whole matrix: a confirmed receipt requires both `userConfirmed: true` *and* the auto setting; every other combination lands pending review; the setting defaults to manual and never retro-confirms; the PRD review-first amendment (confirmation venue may be the agent conversation, when the user enables it) ships in the same change.
6. The protocol (folder layout, sidecar schema, manifest schema, versioning) is documented in the plugin README well enough for a third-party tool to implement drops without reading app source.
7. PRD/DESIGN/ui-spec amendments per the header ship in the same change; all new tests pass; the iOS app is unaffected.
