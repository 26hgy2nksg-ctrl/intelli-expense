# Spec: Auto-collapsing capture accessory + Receipt archive/restore

**Status:** ready for implementation
**Scope:** two independent features, implementable in either order:

- **Part A** — adopt the native iOS 26 tab accessory (`tabViewBottomAccessory` + `tabBarMinimizeBehavior`) so the Scan Receipt bar collapses with the tab bar while scrolling. Touches `IntelliExpense/ContentView.swift` only (plus UI tests).
- **Part B** — non-destructive Archive/Restore for receipts alongside the existing hard delete. Touches `IntelliExpense/Persistence/PersistenceModels.swift`, `Persistence/ReceiptStore.swift`, `UI/ReceiptsViews.swift`, `UI/GroupsViews.swift`, String Catalog, unit tests. No changes to `ExpenseCore` (its `TotalsCalculator` stays pure; filtering happens before mapping).

---

# Part A — Auto-collapsing tab bottom accessory

## A1. Problem

The "Scan Receipt" bar is a custom button injected with `.safeAreaInset(edge: .bottom)` and a hardcoded `.padding(.bottom, 62)` to visually hover above the tab bar (ContentView.swift:100–109, 418–447). It never reacts to scrolling: it sits fixed on top of every list, permanently covering the last rows and looking bolted-on ("always sitting on top"). The 62pt magic number also breaks the moment tab bar metrics change.

This is a known deviation from the design system:

- `DESIGN.md:187–189` — "**Capture accessory:** `tabViewBottomAccessory` glass bar — camera circle in Ledger Green, 'Scan Receipt' label, context subtitle naming the destination group, ⋯ menu for Photo / File / Manual. Hidden on Settings."
- `DESIGN.md:213` — "scroll-edge effects instead of opaque headers, **tab bar minimizes on scroll**."
- `design/ui-spec.html` `.tabzone`/`.accessory` mockups (lines ~141–155) show the accessory docked with the tab bar, not floating over content.

## A2. Verified API availability (offline Apple docset, version 24703; app targets iOS 26.0)

- `View.tabViewBottomAccessory(content:)` — `/documentation/swiftui/view/tabviewbottomaccessory(content:)` — iOS 26.0+. Docs: "On iPhone, the placement of the bottom accessory depends on the tab bar size: when the tab bar is normal size, the accessory appears above it; when the tab bar is collapsed, the accessory displays inline."
- `View.tabBarMinimizeBehavior(_:)` — `/documentation/swiftui/view/tabbarminimizebehavior(_:)` — iOS 26.0+. Behaviors: `TabBarMinimizeBehavior.automatic / .never / .onScrollDown / .onScrollUp` (`/documentation/swiftui/tabbarminimizebehavior`). Apple's own example applies `.onScrollDown` to a TabView whose tabs contain plain `ScrollView`s — our `List`-in-`NavigationStack` tabs are the standard case.
- `EnvironmentValues.tabViewBottomAccessoryPlacement` → `TabViewBottomAccessoryPlacement` enum, cases `.expanded` / `.inline` (`/documentation/swiftui/tabviewbottomaccessoryplacement`) — read inside the accessory content to render a compact variant when the tab bar is minimized.

No custom scroll tracking (`onScrollGeometryChange`, offset preferences, etc.) may be written — the system owns this behavior.

## A3. Requirements

### A-R1 — Replace the safeAreaInset hack with the native accessory

In `MainTabView` (ContentView.swift):

- Delete the entire `.safeAreaInset(edge: .bottom) { … }` block (lines 100–109), including `.padding(.bottom, 62)`.
- Attach to the `TabView`:

```swift
.tabViewBottomAccessory {
    if selectedTab != 2 {
        CaptureAccessoryView { showAddDialog(defaultGroup: nil) }
            .allowsHitTesting(processing == false)
    }
}
.tabBarMinimizeBehavior(.onScrollDown)
```

- `.onScrollDown` is the required behavior (content-first while reading a list; bar returns on scroll up). `.automatic` is not acceptable — pin the behavior explicitly so it can't drift between OS releases.

### A-R2 — Migrate tabs to the `Tab` builder

Replace the three `.tabItem { Label(...) }` blocks with the modern API the accessory documentation is built around:

```swift
TabView(selection: $selectedTab) {
    Tab("tab.groups", systemImage: "folder", value: 0) { GroupsTabView(...) }
    Tab("tab.receipts", systemImage: "receipt", value: 1) { ReceiptsTabView(...) }
    Tab("tab.settings", systemImage: "gearshape", value: 2) { SettingsView() }
}
```

Same localized keys; `selectedTab` stays an `Int` (`value:` gives typed selection without renaming state).

### A-R3 — Accessory adapts to placement

Rework `CaptureAccessoryButton` → `CaptureAccessoryView` reading the placement environment:

```swift
@Environment(\.tabViewBottomAccessoryPlacement) private var placement
```

- **`.expanded`** (tab bar full size, accessory above it): current layout — Ledger Green camera circle, `capture.accessory.title` + `capture.accessory.subtitle`, trailing `ellipsis.circle`.
- **`.inline`** (tab bar minimized, accessory beside it): compact single line — camera glyph + `capture.accessory.title` only. Drop the subtitle and the ellipsis; keep everything on one line so it fits the inline capsule.
- **Remove the custom `.regularMaterial` capsule background** (line 442): the system draws the accessory's Liquid Glass container. Verify on simulator that no double-glass ring appears; if the system container turns out not to provide a background in some placement, restore material for that placement only. Net effect: the app drops from two custom glass elements to one (only the Save bar remains custom — an improvement against `DESIGN.md:214`).
- Fonts stay semantic (`.subheadline`, `.caption`); colors stay `Color("LedgerGreen")` + semantic styles. No `colorScheme` branches.

### A-R4 — Hidden on Settings

Keep the `selectedTab != 2` condition, now inside the accessory ViewBuilder (A-R1). **Verify on simulator** that an empty builder removes the accessory entirely (no empty capsule) and that the transition when switching to/from Settings doesn't glitch. If an empty builder leaves artifacts, fall back to switching between the accessory view and `EmptyView` explicitly, or gate with `.opacity`/`transition` — but the requirement stands: no accessory is visible on Settings (`DESIGN.md:189`).

### A-R5 — Processing state unchanged

The accessory must remain non-interactive while `processing == true` (today's `.allowsHitTesting(processing == false)` contract, line 107). `ProcessingOverlay` stays as-is; note the overlay does not cover the accessory (same as today), which is why the hit-testing guard is load-bearing — keep it.

### A-R6 — Accessibility & identifiers

- Keep `capture.accessory.accessibility` as the accessibility label in **both** placements.
- Add `.accessibilityIdentifier("capture.accessory")` so UI tests can assert presence/absence per tab (there is no identifier today).
- The inline variant must remain a single tappable button (system guarantees the hit target; do not shrink content below one `.subheadline` line).

### A-R7 — Out of scope (do not build)

- The ⋯ button as a separate `Menu` (DESIGN.md wants a distinct Photo/File/Manual menu; today the whole bar opens one confirmation dialog with all four options). Keep today's single-dialog behavior — separate spec if ever needed.
- The "context subtitle naming the destination group" (`DESIGN.md:188`) — subtitle stays the static `capture.accessory.subtitle` for now.
- Any custom scroll-offset tracking or tab bar restyling.

## A4. Tests & acceptance criteria

UI test (existing UITest target style, `-UITestFakeServices`):

- Accessory with identifier `capture.accessory` exists on Groups and Receipts tabs, does not exist on Settings.
- Tapping it presents the add dialog (`capture.add.title`).

Manual acceptance (simulator + device, light/dark, XL Dynamic Type):

- [ ] On Receipts with enough rows to scroll: scrolling down minimizes the tab bar and the accessory docks inline (compact variant); scrolling up restores the full tab bar and expanded accessory.
- [ ] Last list row is reachable and readable — the accessory no longer permanently overlaps content.
- [ ] No double glass background on the accessory; camera circle stays Ledger Green in both placements.
- [ ] Switching to Settings hides the accessory without visual glitches; back to Groups/Receipts restores it.
- [ ] During processing the accessory cannot be tapped.
- [ ] VoiceOver reads the accessory label in both placements.

---

# Part B — Archive / Restore for receipts

## B1. Problem

The only way to remove a receipt from lists, totals, and exports is a hard `modelContext.delete(receipt)` (ReceiptsViews.swift:302–307), which cascades to attachments and the extraction record — the scanned image is gone forever, on every synced device. There is no reversible middle ground for "done with this / claimed / not relevant" records. No model has any `isArchived`/`archivedAt` flag today, and every query/total/export consumes all receipts unfiltered:

- Lists: `@Query(sort: \Receipt.date, order: .reverse)` + in-memory filters (ReceiptsViews.swift:63, 125–145); group detail lists via `group.receipts` (GroupsViews.swift).
- Totals: `ExpenseGroupSummary.make(for:)` maps `group.receipts ?? []` (ReceiptStore.swift:31–42).
- Export: `exportGroup()` maps `group.receipts ?? []` (GroupsViews.swift:209–220) via `ReceiptExportMapper.exportReceipts(from:)`.

PRD only mandates "Delete with confirmation" (PRD.md:229); archive is additive scope and must not weaken the delete flow.

## B2. Data model (CloudKit-safe)

Add to `Receipt` (`PersistenceModels.swift`):

```swift
var isArchived: Bool = false
var archivedAt: Date?
```

- Both have defaults/optionality → satisfies the repo's CloudKit schema rules; purely additive, lightweight migration is automatic, and the private-DB schema gains two fields on first run of the new build.
- Rollout note: an older app version syncing the same iCloud account ignores these fields and will still show archived receipts as active. Acceptable for a single-user private-DB app; do not attempt to gate on schema version.
- `archivedAt` records when it was archived (shown in UI, and available as a future auto-purge hook — the purge itself is out of scope).

Mutations live in `ReceiptStore` next to the existing group-delete policy:

```swift
@MainActor
static func archive(_ receipt: Receipt, in context: ModelContext)   // isArchived = true,  archivedAt = .now, save
@MainActor
static func restore(_ receipt: Receipt, in context: ModelContext)   // isArchived = false, archivedAt = nil,  save
```

Archiving is reversible → **no confirmation dialog** (HIG: confirm only destructive actions). Deleting keeps its existing confirmation.

## B3. Requirements

### B-R1 — One source of truth for "active"

Add a single helper used everywhere instead of scattering `!$0.isArchived`:

```swift
extension ExpenseGroup {
    var activeReceipts: [Receipt] { (receipts ?? []).filter { $0.isArchived == false } }
}
```

and for arrays: `receipts.filter { $0.isArchived == false }` inline where no group is involved (Receipts tab query results). Grep-level acceptance: `group.receipts` must no longer be consumed raw by summaries, exports, or list UIs — only by deletion policy code.

### B-R2 — Every aggregate and export excludes archived

- `ExpenseGroupSummary.make(for:)` (ReceiptStore.swift:36) → map `group.activeReceipts`.
- `exportGroup()` (GroupsViews.swift:211) → `ReceiptExportMapper.exportReceipts(from: group.activeReceipts)`. Archived receipts appear in **neither** `summary.csv` nor the image folders.
- `GroupRow` receipt counts / totals and `GroupDetailView` lists + type/payment filters → active only.
- Receipts-tab month buckets and search (ReceiptsViews.swift:125–145) → active only in the default view.

### B-R3 — Receipts tab: Archived filter

- The existing toolbar filter menu gains an **"Archived"** toggle (`receipts.filter.archived`). Off (default): only active receipts. On: only archived receipts (not mixed — the list becomes the archive browser).
- Archived rows show a small `archivebox` + `receipt.archived.badge` caption in `.secondary` (never red; no new colors — semantic styles only).
- Empty archive state reuses `AppEmptyStateView` with `receipts.archived.empty.title` / `.message`.

### B-R4 — Swipe actions

- Active receipt row (Receipts tab **and** GroupDetailView list): trailing `swipeActions` with an **Archive** button — `Label("receipt.archive", systemImage: "archivebox")`, `.tint(Color("LedgerGreen"))`. No `role: .destructive` (that renders red and implies data loss).
- Archived receipt row (archived filter on): trailing **Restore** — `Label("receipt.restore", systemImage: "arrow.uturn.backward")`, same tint.
- `allowsFullSwipe: true` is fine for both (reversible).

### B-R5 — Receipt detail

In `ReceiptDetailView` (ReceiptsViews.swift, around the existing delete section, lines ~295–307):

- Active receipt: an **Archive** row (plain button, Ledger Green tint, `archivebox` icon) placed **above** the existing Delete section. Tapping archives immediately and pops/dismisses back to the list.
- Archived receipt: replace it with **Restore**, plus a footnote line "Archived <date>" using `archivedAt` formatted with locale-aware `FormatStyle` (`receipt.archived.on` with a `%@` date argument).
- The Delete button + confirmation dialog stay exactly as they are — archive does not replace delete.

### B-R6 — Interaction with group deletion

`ReceiptStore.delete(group:receiptPolicy:in:)` (ReceiptStore.swift:12–28) operates on **all** receipts of the group, archived included:

- `.keepReceiptsUnfiled` → archived receipts are also unfiled (stay archived, group becomes nil).
- `.deleteReceipts` → archived receipts of that group are hard-deleted too.

This is intentional (a group delete that skipped archived children would leak orphaned data); assert it in tests rather than changing behavior.

### B-R7 — Localization (String Catalog only)

New keys in `Localizable.xcstrings`, English values:

| Key | Value |
|---|---|
| `receipt.archive` | "Archive" |
| `receipt.restore` | "Restore" |
| `receipt.archived.badge` | "Archived" |
| `receipt.archived.on` | "Archived %@" |
| `receipts.filter.archived` | "Archived" |
| `receipts.archived.empty.title` | "No Archived Receipts" |
| `receipts.archived.empty.message` | "Receipts you archive appear here." |

No literals in views; no red; Dynamic Type only.

### B-R8 — Accessibility

- Swipe action labels come from the keys above (VoiceOver rotor actions get them for free).
- Archived badge: part of the row's accessibility label ("…, Archived").
- Accessibility identifiers for UI tests: `receipt.action.archive`, `receipt.action.restore`, `receipts.filter.archived`.

### B-R9 — Out of scope (do not build)

- Archiving `ExpenseGroup`s (receipts only).
- Auto-purge of old archived receipts ("delete after 30 days") — `archivedAt` merely enables it later.
- Undo toasts/snackbars (no such infrastructure exists; restore via the archived filter is the undo).
- A dedicated Archived screen — the Receipts-tab filter is the archive browser.
- Any change to the merge policy, capture pipeline, or `ExpenseCore` public API.

## B4. Tests (TDD — write first)

App target (`IntelliExpenseTests`, in-memory `ModelContainer`, follow `PersistenceTests.swift` style):

1. **Archive sets state:** `ReceiptStore.archive` → `isArchived == true`, `archivedAt != nil`; restore clears both.
2. **Summary excludes archived:** group with one active (10 USD) + one archived (5 USD) → `ExpenseGroupSummary.make` totals == 10 USD; breakdown counts exclude archived.
3. **Export excludes archived:** same group → `ReceiptExportMapper.exportReceipts(from: group.activeReceipts)` yields 1 receipt; archived vendor absent.
4. **Group delete policies include archived:** `.deleteReceipts` removes archived children from the store; `.keepReceiptsUnfiled` leaves them archived with `group == nil` (extend the two existing tests at PersistenceTests.swift:79–111).
5. **activeReceipts helper:** returns only non-archived, order-independent.

UI test: archive a receipt via detail button (fake-services fixture), assert it disappears from the default list, appears under the Archived filter, restore returns it.

## B5. Acceptance criteria

- [ ] Swiping an active receipt reveals a green Archive action (no red anywhere); archiving removes it from the list, group totals, and month buckets immediately, with no confirmation dialog.
- [ ] The Archived filter shows only archived receipts with an "Archived" badge; Restore (swipe or detail button) returns them to normal everywhere.
- [ ] Receipt detail shows Archive (active) or Restore + "Archived <date>" (archived); Delete with confirmation still works unchanged.
- [ ] Exporting a group containing archived receipts produces a zip whose `summary.csv` and image folders contain only active receipts.
- [ ] Archived state syncs across devices via CloudKit (archive on device A → hidden on device B).
- [ ] All new strings resolve from the String Catalog; light/dark via existing tokens; large Dynamic Type renders correctly.

---

# Verification commands (both parts)

```bash
# ExpenseCore stays untouched — must still pass unchanged
cd ExpenseCore && swift test

# App unit + UI tests (new archive tests + accessory UI tests)
xcodebuild -project IntelliExpense.xcodeproj -scheme IntelliExpense \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' test

# Build only
xcodebuild -project IntelliExpense.xcodeproj -scheme IntelliExpense \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' build
```

Manual pass: walk both acceptance-criteria lists on simulator, then on device (scroll-minimize feel and haptics can't be judged in the simulator alone).
