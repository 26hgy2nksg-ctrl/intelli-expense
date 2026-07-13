---
name: intelli-expense-import
description: Use when the user asks to add, import, file, or organize receipt images/PDFs into Intelli-Expense from a local folder. The skill reads the Intelli-Expense manifest, extracts complete receipt records itself, asks the user to confirm every field, and writes app-owned folder drops only.
---

# Intelli-Expense Import

Use the app-owned folder protocol. Never write the SwiftData store, SQLite files, CloudKit data, or app container database directly.

Read `reference/README.md`, `reference/schema/sidecar.schema.json`, and `reference/schema/manifest.schema.json` (relative to this skill's directory) before writing drops. Use `reference/fixtures/` for shape checks.

## Workflow

1. Locate the manifest:
   `~/Library/Containers/com.nags.intelliexpense/Data/Library/Application Support/AgentImportBridge/manifest.json`
2. If the manifest is missing, ask the user to open the Mac app once and stop.
3. Read the manifest. Use `inboxPath`, `processedPath`, and `failedPath` from the file, not hardcoded paths.
4. Inspect the user-provided receipt folder. Consider only `jpg`, `jpeg`, `png`, `heic`, `heif`, `tif`, `tiff`, `gif`, and `pdf`.
5. For each readable receipt, do the data entry yourself from the image/PDF:
   merchant, ISO date, total, ISO currency, expense type, payment method, optional notes, and trip suggestion.
6. Present every field for every receipt to the user and wait for explicit approval before writing any sidecar.
   In Claude Code, use AskUserQuestion when available. If unavailable, ask in chat and wait.
7. Only approved structured records may set `userConfirmed: true`. If the user does not confirm every field, either keep `userConfirmed: false` or use raw mode.
8. Copy originals into the inbox. Never move, delete, or modify the originals.
9. Write `<uuid>.<ext>` and `<uuid>.json` into the inbox. Use unique UUID-style basenames.
10. Poll `processed/` and `failed/` briefly, then report per-file results. Include machine-readable failure reasons verbatim.

## Structured Record

Use structured mode when you can confidently read every field and the user has reviewed the full record.

Fields:

- `merchant`: non-empty string, <= 160 characters
- `date`: `yyyy-MM-dd`
- `total`: string decimal using `.`, for example `"84.50"`; never a JSON number
- `currency`: uppercase ISO 4217 code
- `expenseType`: `food`, `hotel`, `flight`, `taxi`, or `other`
- `paymentMethod`: `card` or `cash`
- `notes`: optional string
- `userConfirmed`: boolean; set true only after explicit user approval

Trip assignment:

- Prefer active manifest `id`
- Else exact active trip `name`
- Else omit or use no match so the app files to Unfiled
- Never target archived trips
- Never create trips

## Raw Mode

Use raw mode when the receipt is unreadable, ambiguous, or the user wants the app pipeline to extract it. Raw mode can include `suggestedTrip`, `note`, and `sourceLabel`, but no complete receipt record is required.

## Report Format

After writing and polling, summarize:

- Receipt filename
- Mode: structured or raw
- Trip target or Unfiled
- Outcome: processed, failed, or waiting for the Mac app
- Failure reason from `reason.json`, if any

Privacy reminder: this skill reads receipt images into the user's agent session because the user asked it to. The app itself still makes no network calls except the user's private CloudKit sync.
