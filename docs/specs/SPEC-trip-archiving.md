# SPEC — Trip archiving (swipe = Archive; Delete moves behind it)

**Status:** proposed
**Owner screens:** Trips home (`IntelliExpense/UI/GroupsViews.swift`, `GroupsTabView`), trip editor sheet (`GroupEditorSheet`), new Archived Trips screen, trip detail (`GroupDetailView`, minor)
**Docs this spec amends:** `design/ui-spec.html` §2 (Trips home — swipe affordance + Archived entry row) and a new Archived Trips screen section; DESIGN.md §5 (archive semantics + where destructive delete may appear)

---

## 1. Problem

Swiping a trip on the Trips home today immediately offers **Delete** — a destructive, unrecoverable action (hard delete of the `ExpenseGroup`, with a dialog choosing whether receipts are kept unfiled or deleted too). But the dominant lifecycle of a trip in this app is: scan receipts → confirm → export → *done with it, don't want to see it, don't want to lose it*. The natural post-export action is "put this away", not "destroy this". Receipts already have exactly this concept (`Receipt.isArchived` / `archivedAt`, swipe-to-archive in trip detail, archived browsing mode per SPEC-tab-accessory-collapse-and-archive) — trips don't, so the only way to tidy the home screen is data loss.

Precedent: Apple Mail's default swipe is Archive, with Delete available but not the reflex gesture; the reflex gesture should be the safe one.

## 2. Goals

- Swiping a trip (featured card or compact row) offers **Archive**, not Delete. Full swipe archives. No confirmation dialog — archiving is safe and reversible.
- Archiving a trip puts the **whole trip** away: the trip disappears from the Trips home feed (featured selection, compact rows, capture-destination pickers, trip filters) and its receipts disappear from the active Receipts tab — but everything remains intact: receipts stay attached, detail remains viewable, export still works.
- A discoverable **Archived Trips** surface lists archived trips with one-gesture **Restore**.
- **Delete still definitely exists**, in two deliberate (non-reflex) places, and keeps the existing keep-receipts / delete-receipts confirmation dialog unchanged.
- CloudKit-safe model change (new attributes with defaults/optionality only, per CLAUDE.md schema rules).

## Non-goals

- No change to *receipt* archiving — the existing `Receipt.isArchived` flow, its swipe actions, and its archived browsing mode are untouched. Archiving a trip never **writes** to per-receipt archive flags (see D3 — visibility is derived, flags are not cascaded).
- No auto-archive rules (e.g., "archive after export") — manual gesture only in this pass.
- No changes to export format, CSV, or the share extension.
- No undo toast / snackbar system — Restore in the Archived Trips list is the undo.

## 3. Design decisions

### D1 — Model: mirror the Receipt archive shape on `ExpenseGroup`

`ExpenseGroup` gains an archived flag (default false) and an archived-at timestamp (optional), exactly mirroring the names and semantics already on `Receipt`. Store-level operations mirror the existing receipt ones in `ReceiptStore`: an archive operation (set flag, stamp date, save) and a restore operation (clear both, save). CloudKit rules hold: both new attributes have a default or are optional, no uniqueness, no migration step needed — existing synced trips materialize as not-archived.

All queries/sorts that feed active UI (`sortedByMostRecentActivity`, featured selection, compact rows, capture accessory destination list, receipt-review trip picker, Receipts-tab trip filter) exclude archived trips. The Unfiled section is unaffected.

### D2 — Swipe: Archive replaces Delete on the Trips home

The Trips home currently uses list `onDelete` on both the featured and compact sections. That is replaced by an explicit trailing swipe action on each trip row/card:

- **Archive** — archivebox symbol, tinted with the same treatment the receipt archive swipe uses (brand accent, never red), full-swipe enabled, no dialog. The row animates out with the default list animation.
- Archiving the **featured trip** promotes the next most-recent active trip into the featured slot (same behavior the delete path has today); archiving the last trip lands on the existing create-row / empty-state fallbacks.

No leading-edge action is added on the home screen in this pass.

### D3 — Archive semantics: archiving a trip archives its receipts *by derivation*, not by flag writes

Archiving a trip means the whole trip — container and contents — is put away. The mechanism matters: the trip's archive state **implies** its receipts' archive state; per-receipt `isArchived` flags are never written by the trip operation. Define one rule used by every active-content query: *a receipt is effectively archived when it is individually archived **or** its trip is archived.* Consequences, stated explicitly so implementation doesn't guess:

- Trips home: archived trips vanish from featured/compact sections.
- Receipts tab: receipts belonging to an archived trip disappear from the active month sections along with the trip — archiving the trip cleans up everywhere at once. They do **not** appear in the archived-*receipts* browsing mode either (that mode remains "receipts you archived individually"); they are reached through Archived Trips → trip detail, which keeps restore actions unambiguous (restore the trip there, not receipt-by-receipt).
- Restore: restoring the trip brings back the trip and all its receipts *except* any the user had individually archived before (or after) — their own flags were never touched, so this falls out for free with no bookkeeping.
- Sync: archiving a trip of any size is a single record write, not N receipt writes — cheaper and conflict-free under CloudKit.
- Capture: an archived trip can never be the capture destination; if it was the most-recent destination, capture falls back the same way it does after a delete today.
- Trip detail of an archived trip (reached from the Archived Trips screen): fully functional — receipts list, filters, and **Export** all work (the whole point of archiving is keeping the finance record reachable). Edit is allowed too; editing does not un-archive.

**Considered and rejected — cascading `isArchived` writes onto every receipt when the trip is archived:** restore becomes ambiguous (which receipts were archived *by the trip* vs. individually by the user before that?), requiring per-receipt bookkeeping and N synced writes. The derived-visibility rule above delivers identical user-facing behavior without either cost.

### D4 — Archived Trips surface

A new **Archived** entry appears on the Trips home *below the Unfiled section*, only when at least one archived trip exists (zero archived trips = zero new chrome). It is a compact navigation row (archivebox icon + "Archived" + count), deliberately quiet — same visual weight as the Unfiled row.

It pushes an **Archived Trips** list: plain compact rows (reuse the existing trip row component; no featured card here), sorted by `archivedAt` descending. Each row:

- navigates to the normal trip detail;
- **leading swipe: Restore** (full-swipe enabled) — clears the archive state; the trip re-enters the home feed and re-sorts by its own recency;
- **trailing swipe: Delete** — destructive role, routes through the **existing** keep-receipts / delete-all-receipts confirmation dialog verbatim (same string keys, same `ReceiptStore` delete policies).

Empty state after restoring/deleting the last archived trip: pop back to Trips home (or show the standard empty-state view if the screen stays).

### D5 — Where Delete lives now (two deliberate places)

1. **Archived Trips list** (D4) — the primary home for deletion: the natural flow is archive first, purge later.
2. **Trip editor sheet** (`GroupEditorSheet`, edit mode only, not create mode) — a destructive "Delete Trip…" button in its own section at the bottom of the form, for the user who wants to delete an active trip without archiving first. It triggers the same confirmation dialog; on confirmed delete the sheet dismisses and (if invoked from trip detail) the detail screen pops.

Both paths funnel into the one existing delete implementation (`ReceiptStore.delete(group:receiptPolicy:in:)`); no second deletion code path. Destructive styling uses the system destructive role in dialogs/menus only — no red introduced into the app palette (DESIGN.md rule).

### D6 — Documentation amendments (same commit as the implementation)

- **DESIGN.md §5** gains the archive law: *"Archiving is the reflex gesture for putting content away and is always safe (accent-tinted, full-swipe, no dialog); a receipt is effectively archived when it or its trip is archived; destructive delete never rides a reflex swipe on active content — it lives only behind archived surfaces or explicit editor actions, styled with the system destructive role, never app-palette red."*
- **design/ui-spec.html §2 (Trips home)**: swipe mock changes from Delete to Archive; add the quiet Archived row below Unfiled (shown in a ≥1-archived-trip state).
- **design/ui-spec.html new section (Archived Trips)**: compact-rows list mock with leading Restore / trailing Delete swipe annotations and the empty state.

No DESIGN.md rule conflicts: the feature reuses the receipt-archive swipe treatment, standard inset-grouped rows, existing tokens, Dynamic Type roles, and adds no color, glass, or fixed sizes.

## 4. Edge cases

- **Archiving while pending capture/drafts reference the trip**: drafts keep their group link; on confirm-save, the receipt files into the archived trip normally (the trip just isn't offered as a *new* destination). Acceptable: the user chose that trip before archiving it.
- **CloudKit merge**: archive state is last-writer-wins like any attribute; a trip archived on one device and edited on another converges without conflict handling beyond SwiftData defaults.
- **Sandbox seed data**: seeded trips remain non-archived; optionally one seeded archived trip may be added so screenshots can show the surface (sandbox lane only).
- **Trip archived while its detail screen is open** (other device via sync): screen stays functional; the home feed updates on return.
- **Delete of an archived trip with "keep receipts"**: receipts become unfiled and thus *reappear* in the Unfiled section — this is existing delete behavior, unchanged, but worth a line in the dialog QA pass.

## 5. Accessibility & localization

New string-catalog keys (English values; all UI strings in `Localizable.xcstrings` per CLAUDE.md):

| Key | Value |
|---|---|
| `trip.archive` | Archive |
| `trip.restore` | Restore |
| `trips.archived.title` | Archived |
| `trips.archived.row` | Archived (with count, plural-variant aware) |
| `trips.archived.empty.title` / `.message` | No archived trips / When you archive a trip it moves here. |
| `group.editor.delete` | Delete Trip… |

Reuse unchanged: `group.delete.title`, `group.delete.keep`, `group.delete.deleteAll`.

New accessibility identifiers: `trips.archived.link`, `trips.archived.list`, `trip.action.archive`, `trip.action.restore`, `group.editor.delete`. Swipe actions get accessibility custom actions automatically via standard swipe-action buttons; verify VoiceOver exposes Archive/Restore/Delete on rows.

## 6. Test impact

- **ExpenseCore/app unit tests**: archive/restore store operations (flag + timestamp set/cleared, persisted, no per-receipt flag writes); the effective-archival rule (individually archived OR trip archived) drives every active-content filter — recency sort, featured selection, Receipts-tab active sections; round-trip: archive trip → restore trip leaves a previously individually-archived receipt archived; delete policies unchanged.
- **UI tests**: (1) swipe a trip → Archive → it leaves the home list, its receipts leave the active Receipts tab, and the Archived row appears with count; (2) Archived list → leading swipe Restore → trip and receipts return to their active surfaces; (3) Archived list → trailing swipe Delete → existing confirmation dialog appears, both policies behave as today; (4) editor sheet shows Delete Trip… in edit mode only, and the button drives the same dialog; (5) featured-card archive promotes the next trip.
- **Manual**: light/dark, AX5 type sizes, VoiceOver on both swipes, CloudKit two-device archive/restore sanity check, sandbox lane screenshots.

## 7. Acceptance criteria

1. Swiping any trip on the Trips home shows **Archive** (accent, archivebox) and never Delete; full swipe archives with no dialog.
2. An archived trip and all of its receipts appear nowhere in active UI (featured, compact rows, capture destinations, trip filters/pickers, active Receipts-tab sections); the trip's detail + export work from the Archived Trips screen. Archiving the trip writes no per-receipt archive flags.
3. Restore returns the trip and its receipts to their active surfaces in correct recency order — except receipts the user archived individually, which stay archived; archive state round-trips through CloudKit.
4. Delete remains available in exactly two places (Archived Trips swipe; editor-sheet destructive button), both showing the unchanged keep/delete-receipts dialog and both funneling to the single existing delete implementation.
5. New `ExpenseGroup` attributes follow CloudKit rules (defaults/optionality, no unique); existing installs upgrade with all trips active and no data loss.
6. Zero archived trips ⇒ the Trips home renders byte-for-byte as today except the swipe label; no new chrome.
7. All new user-facing strings live in the String Catalog; no red in the app palette; Dynamic Type only; all existing + new tests pass.
8. DESIGN.md §5 and `design/ui-spec.html` are amended per D6 in the same change — the shipped UI and the canonical mockups never diverge.
