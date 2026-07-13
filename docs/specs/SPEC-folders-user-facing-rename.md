# SPEC - Complete user-facing Trip -> Folder rename

**Status:** implemented
**Owner screens:** Folders home and archived folders (`IntelliExpense/UI/GroupsViews.swift`), folder editor/category composer (`IntelliExpense/UI/GroupsViews.swift`, `IntelliExpense/UI/CategoryComposer.swift`), receipt filters and assignment rows (`IntelliExpense/UI/ReceiptsViews.swift`, `IntelliExpense/UI/ReviewViews.swift`), onboarding welcome (`IntelliExpense/ContentView.swift`), Mac sidebar/commands/detail (`IntelliExpense/Mac/MacContentView.swift`, `IntelliExpense/Mac/MacCommands.swift`, `IntelliExpense/Mac/MacReceiptDetailPane.swift`), string catalog (`IntelliExpense/Resources/Localizable.xcstrings`)
**Docs this spec amends:** `PRD.md` §1/§2/§4.1/§5.0/§5.1/§5.2/§5.3a/§5.4/§7/§8/§10, `DESIGN.md` §3/§4/§5 and Mac companion notes, `design/ui-spec.html` app structure/Folders home, Archived, folder detail, review/detail assignment rows, export, agent entries, Mac companion

---

## 1. Problem

The profile/category work has already moved the product direction from a trip-only container to a broader **Folder** concept. The app is partly renamed: the tab says **Folders**, the create/edit sheet title says **New/Edit Folder**, and the review assignment label says **Folder**.

The remaining visible copy still leaks the older noun. Field evidence from the 2026-07-09 device screenshot: the sheet title says **Edit Folder**, while the destructive action at the bottom still says **Delete Trip…**. That split language makes the app feel unfinished and makes destructive actions less trustworthy.

This is a frontend/content consistency change. The model can remain `ExpenseGroup`, existing Swift files can remain named `GroupsViews.swift`, and existing string keys/accessibility identifiers can remain `group.*`, `groups.*`, `trip.*`, and `trips.*` when renaming them would be internal churn.

## 2. Goals

- Every generic container label the user sees says **Folder/Folders**, not Trip/Trips.
- Existing user data is untouched. A folder whose user-entered name contains "Trip" stays exactly as entered.
- Existing code identifiers, persisted schema, CloudKit record shapes, accessibility identifiers, CSV column names, app group identifiers, and agent protocol fields remain stable unless they visibly render as app chrome.
- The canonical docs stop describing the main surface as Trips home. Future agents should read Folders home, featured folder card, archived folders, and folder detail.
- The implementation is mostly string-catalog value changes plus doc/test expectation updates; no model migration is required.

## 3. Non-goals

- No rename of `ExpenseGroup`, `Receipt.group`, `GroupDetailView`, `GroupsTabView`, `GroupRow`, `FeaturedTripCard`, `AgentImportManifest.Trip`, or file names. Internal names are implementation history.
- No rename of string-catalog keys or accessibility identifiers such as `groups.featured.card`, `trips.archived.link`, `trip.action.archive`, or `group.editor.delete`.
- No change to the export CSV contract, including the stable `group` column header. That file is a compatibility artifact, not app navigation chrome.
- No profile rename. **Work Trip** remains a valid folder profile name because it identifies a specific folder type, not the generic container noun.
- No attempt to rewrite all old spec history. This spec supersedes the generic-container language in older specs; canonical current docs (`PRD.md`, `DESIGN.md`, `design/ui-spec.html`) must be updated.

## 4. Design decisions

### D1 - User-facing noun is Folder

Use **Folder** anywhere the app is naming the generic container:

- tab/root title: Folders
- create/edit sheet: New Folder, Edit Folder
- delete/archive/restore copy: folder
- receipt filter/assignment label: Folder
- detail empty states: folder
- archived empty states and count: folder
- onboarding/export guidance when it refers to a saved container: folder

Keep **trip** only when it describes the real-world work-travel use case or the **Work Trip** profile. A sentence like "personally-paid work-trip expenses" in product positioning is still true; a button or filter called "Trip" is not.

Design grounding:

- `DESIGN.md` says "Standard navigation: three tabs, large titles at roots" and that "Lists group by what users think in"; after profiles, users think in folders, not only trips.
- `DESIGN.md` already defines the "Create Folder category composer" and the visible folder profile/category model. The remaining Trip language conflicts with that component rule.
- `DESIGN.md` also requires "One hero number per screen"; the rename must not change the featured-card layout or hierarchy.

### D2 - String catalog values change; keys stay stable

Change English values in `Localizable.xcstrings`. Do not rename keys.

| Key | Current visible value | Required visible value |
|---|---|---|
| `filter.allGroups` | All trips | All folders |
| `filter.group` | Trip | Folder |
| `filter.group.section` | Trip | Folder |
| `group.delete.title` | Delete %d trips? | plural variants: one = Delete %d folder?; other = Delete %d folders? |
| `group.detail.empty.title` | No receipts in this trip | No receipts in this folder |
| `group.detail.empty.message` | Receipts saved to this trip will appear here. | Receipts saved to this folder will appear here. |
| `group.editor.delete` | Delete Trip… | Delete Folder… |
| `onboarding.bullet.export.subtitle` | Create a finance-ready zip when the trip is done. | Create a finance-ready zip when the folder is ready. |
| `trips.archived.empty.title` | No archived trips | No archived folders |
| `trips.archived.empty.message` | When you archive a trip it moves here. | When you archive a folder it moves here. |
| `trips.archived.row` | plural variants: %d trip / %d trips | plural variants: %d folder / %d folders |

Already correct and unchanged:

| Key | Current visible value |
|---|---|
| `tab.groups` | Folders |
| `groups.create` | New Folder |
| `groups.create.row` | New Folder… |
| `groups.empty.title` | Add your first folder |
| `groups.empty.message` | Create a folder, then scan receipts into it. |
| `receipt.field.group` | Folder |
| `group.editor.edit.title` | Edit Folder |
| `folder.categories.*` values | already folder-based |

Keys with generic values and no visible rename needed:

| Key | Value | Reason |
|---|---|---|
| `trip.archive` | Archive | user sees only Archive |
| `trip.restore` | Restore | user sees only Restore |
| `trips.archived.title` | Archived | title is noun-neutral |
| `group.export` | Export | noun-neutral |
| `groups.unfiled.*` | Unfiled | pairs naturally with folders |
| `mac.sidebar.trip.help` | `%1$@ · %2$@` | key is internal; value is noun-neutral |

Audit note (2026-07-09): the tables above are exhaustive. The main-app catalog contains no other English values with trip language besides `folder.profile.workTrip` (intentionally kept). The other string surfaces were audited and are already clean — the share-extension catalog (`IntelliExpenseShare/Resources/Localizable.xcstrings`), `AppShortcuts.xcstrings`, both `InfoPlist.xcstrings` files, the widget/control target (`IntelliExpenseControls`), and the App Intents strings contain no trip language. The implementation does not need to touch them.

### D3 - iPhone surfaces to verify after the value changes

The following visible places are in scope even when the implementation is only a catalog update:

- Folders tab/root title (`tab.groups`) stays Folders.
- Folders home create CTA and create row stay New Folder/New Folder…
- Featured card and compact rows keep folder icons and user folder names; no title copy should say featured trip.
- Archived row count says "1 folder" / "N folders".
- Archived empty state says archived folders.
- Folder detail empty state says folder.
- Folder editor destructive row says Delete Folder…
- Delete confirmation says "Delete 1 folder?" / "Delete N folders?".
- Receipts filter menu says Folder and All folders.
- Review screen and receipt detail assignment rows say Folder.
- Onboarding export bullet says folder, not trip.

### D4 - Mac surfaces are part of the same frontend

The native Mac companion uses the same catalog keys and should inherit most changes. Still verify:

- File menu / toolbar New Folder and Export stay coherent.
- Sidebar section title reads Folders via `tab.groups`.
- Context menu Archive/Export actions remain noun-neutral.
- Receipt detail and review assignment fields say Folder.
- Empty states say folder.
- Any window/sidebar mockups in `design/ui-spec.html` switch from Trips to Folders.

### D5 - Canonical docs and mockups must follow the rename

Update canonical docs in the same implementation pass:

- `PRD.md`: change the generic UI label for `ExpenseGroup` from Trip/Trips to Folder/Folders. Keep "work-trip expenses" and **Work Trip** profile language where it describes the real-world use case or profile.
- `DESIGN.md`: rename "Featured trip card" to "Featured folder card", "Trip-detail breakdown rows" to "Folder-detail breakdown rows", and "trips by recency" to "folders by recency". Also update the remaining generic-container mentions outside the component names: the see-also line and agent-import placement note that say "Trips home", the Mac companion note's "New Trip" toolbar/menu command (becomes New Folder), and the example agent prompt's "Trip Detail screen" (becomes Folder Detail screen). Keep the layout rules intact: one hero number, inset-grouped lists, archive as the reflex gesture.
- `design/ui-spec.html`: update the visible mockup labels and explanatory prose: Trips home -> Folders home, New Trip -> New Folder, Archived Trips -> Archived Folders where the heading is generic, trip detail -> folder detail, back labels and tab labels -> Folders, and "3 trips" -> "3 folders".

Existing spec files can remain as history unless they are actively amended for the implementation. This spec becomes the controlling follow-up for the rename.

## 5. Edge cases

- **User-entered names:** never rewrite names such as "Berlin Trip" or "Bengaluru Conference". They are content, not app chrome.
- **Work Trip profile:** keep the profile display name. A folder can be a Work Trip folder.
- **Examples:** example folder names can still be travel-themed ("Berlin - June 2026"), but surrounding copy should call them folders.
- **Agent bridge:** manifest protocol field names can remain `trips`/`Trip` for compatibility; the app UI that confirms agent entries should show folder names without a generic Trip label.
- **Accessibility identifiers:** keep existing IDs stable. VoiceOver labels that come from localized string values must say Folder.
- **Pluralization:** fix the delete dialog while touching it; the current "Delete 1 trips?" is visible in UI tests and should not survive the rename.

## 6. Accessibility & localization

- New string-catalog keys: none.
- Changed English values: listed in D2.
- Converted plural variants: `group.delete.title` should become plural-aware; `trips.archived.row` should change its existing plural values from trip(s) to folder(s).
- VoiceOver: destructive actions and filter sections should announce Folder/Folder(s). Identifiers remain unchanged.
- Dynamic Type: no layout changes expected. Re-test the screenshot path in the edit sheet at large text sizes because the destructive row is near the bottom of a long category composer.

## 7. Test impact

- Update UI test expectations that look for old visible strings:
  - "Delete 1 trips?" -> "Delete 1 folder?"
  - any navigation/title assertions for "Trips" -> "Folders" where still present
  - any filter/menu assertions for "Trip" -> "Folder"
- Existing tests can keep helper/function names such as `createGroup`, `archiveTrip`, or `testTripsHome...`; those names are not user-visible.
- Add or update a catalog test that rejects generic English UI values containing `trip`/`trips`, with an allowlist for `folder.profile.workTrip` and product-positioning/onboarding text only if intentionally retained.
- Manual verification: iPhone dark-mode edit-folder screenshot path, Folders home, Archived, folder detail empty state, Receipts filter menu, Review assignment row, and Mac sidebar/detail.

## 8. Acceptance criteria

1. No generic app chrome visible to the user says Trip or Trips; it says Folder or Folders.
2. The screenshot mismatch is gone: the edit sheet title says Edit Folder and the destructive row says Delete Folder…
3. Delete confirmation uses correct pluralization: "Delete 1 folder?" and "Delete N folders?".
4. Receipts filters and assignment rows say Folder / All folders.
5. Archived count and empty state say folder(s).
6. The Work Trip profile name remains Work Trip, and user-entered folder names are untouched.
7. String keys, accessibility identifiers, model names, CloudKit schema, app group IDs, agent manifest protocol names, and CSV column headers remain stable unless a separate compatibility spec authorizes changing them.
8. `PRD.md`, `DESIGN.md`, and `design/ui-spec.html` all describe the current generic container as Folder/Folders.
9. Relevant UI/catalog tests pass, and a manual visual pass confirms there is no remaining visible Trip/Trips language in the iPhone and Mac frontend outside the Work Trip profile or user content.
