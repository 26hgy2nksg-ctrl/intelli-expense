# Intelli-Expense Agent Import Protocol

Protocol version: `1`

This plugin is instructions and schema only. It never writes the SwiftData store and ships no executables. Agents copy receipt files plus JSON sidecars into the Mac app's inbox; the Intelli-Expense app validates, persists, and syncs through its own CloudKit-backed container.

## Locate The Manifest

Open the Mac app once, then read:

```text
~/Library/Containers/com.nags.intelliexpense/Data/Library/Application Support/AgentImportBridge/manifest.json
```

The manifest is read-only for agents. Treat its `inboxPath`, `processedPath`, and `failedPath` as authoritative if present.

## Folder Layout

```text
AgentImportBridge/
  manifest.json
  inbox/
    <uuid>.<ext>
    <uuid>.json
  processed/
  failed/
```

Receipt extensions: `jpg`, `jpeg`, `png`, `heic`, `heif`, `tif`, `tiff`, `gif`, `pdf`.

## Manifest

`manifest.json` contains:

- `protocolVersion`: integer, currently `1`
- `generatedAt`: ISO timestamp
- `inboxPath`, `processedPath`, `failedPath`: absolute paths
- `trips`: objects with `id`, `name`, optional `startDate`/`endDate`, `receiptCount`, `currenciesPresent`, and `archived`

Archived trips are never valid agent targets.

## Sidecar Envelope

Each drop is a receipt file plus optional `<uuid>.json` sidecar. No sidecar means raw mode to Unfiled.

```json
{
  "protocolVersion": 1,
  "mode": "structured",
  "suggestedTrip": { "id": "manifest-trip-id", "name": "Berlin Trip" },
  "note": "Optional agent note",
  "sourceLabel": "codex",
  "receipt": {
    "merchant": "REWE CITY",
    "date": "2026-06-14",
    "total": "84.50",
    "currency": "EUR",
    "expenseType": "food",
    "paymentMethod": "card",
    "notes": "Optional receipt note",
    "userConfirmed": true
  }
}
```

Structured totals must be string decimals with a dot separator. Never write a JSON number for money.

Enums:

- `expenseType`: `food`, `hotel`, `flight`, `taxi`, `other`
- `paymentMethod`: `card`, `cash`

Trip resolution order: manifest `id`, exact active trip `name`, else Unfiled. Unknown or archived suggestions do not create trips.

## Landing States

Structured mode runs zero OCR, parser, or model calls.

| Sidecar | Mac setting | App result |
|---|---|---|
| `userConfirmed: true` | Agent entries require in-app review = ON | Prefilled draft with confirmation card |
| `userConfirmed: true` | Agent entries require in-app review = OFF | Confirmed receipt |
| `userConfirmed: false` | Either setting | Prefilled draft with confirmation card |

Raw mode (`"mode": "raw"`) and sidecar-less files use the normal app pipeline and land pending review on the Mac.

## Outcomes

After app ingestion:

- Success: the app moves the pair into `processed/<drop-id>-<uuid>/`
- Failure: the app moves the pair into `failed/<drop-id>-<uuid>/reason.json`

Failure reasons are machine-readable English identifiers such as `record.total.invalid`, `file.duplicate`, `file.unsupportedType`, and `version.unsupported`.

The app records the verbatim structured sidecar as provenance on confirmed receipts. Receipt detail shows the quiet line: `Entered by agent`.
