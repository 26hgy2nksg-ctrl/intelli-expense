# SPEC - Expense profiles and editable visible categories

**Status:** proposed
**Owner screens:** Folder/trip home (`IntelliExpense/UI/GroupsViews.swift`), group editor (`IntelliExpense/UI/GroupsViews.swift`), receipt review (`IntelliExpense/UI/ReviewViews.swift`), receipt detail (`IntelliExpense/UI/ReceiptsViews.swift`, `IntelliExpense/Mac/MacReceiptDetailPane.swift`), Mac sidebar/detail (`IntelliExpense/Mac/MacContentView.swift`), agent import (`IntelliExpense/AgentImport/AgentImportBridge.swift`)
**Docs this spec amends:** `PRD.md` §4.1/§4.2/§4.6/§5.1/§5.2/§5.3a/§5.4/§7/§8/§11, `DESIGN.md` §2/§4, `design/ui-spec.html` Trips home, create/edit group, Review & Confirm, trip detail, Receipts filters, Mac list/detail

---

## 1. Problem

Intelli-Expense is intentionally optimized for one strong use case: work-trip receipts. The current user-facing category set is fixed to Food, Hotel, Flight, Taxi, and Other, and the implementation reinforces that fixed set everywhere:

- `ExpenseType` is a five-case enum in `ExpenseCore/Sources/ExpenseCore/Domain/ExpenseDomain.swift`.
- `Receipt.expenseTypeRawValue` is already stored as a raw string in SwiftData, but the app wraps it back into `ExpenseType` and falls back to `.other`.
- Review, filters, featured-card chips, and trip-detail breakdown rows iterate over `ExpenseType.allCases`.
- Agent structured imports reject any sidecar `expenseType` outside the five enum raw values.
- CSV export writes `expense_type` as the raw enum value.

That makes the current app clean for trips, but too narrow for adjacent receipt folders where the same capture-confirm-export loop is valuable: conferences, day visits, home projects, medical claims, vehicle costs, tax/business receipts, events, moving, and warranty records.

The product risk is sprawl. Competing expense tools often grow into budgets, mileage, approvals, accounting sync, dashboards, teams, and policy engines. This app should not. The right expansion is smaller: make the receipt folder carry a **profile** with sensible default categories, let the user edit those visible categories per folder, and keep every screen quiet by showing only categories relevant to that folder.

## 2. Goals

- Preserve the core loop: scan/import/manual entry -> review -> save into one folder -> browse totals -> export.
- Add folder profiles with preselected category sets, starting with Work Trip as the current behavior.
- Let each folder edit its visible categories: remove unused defaults, add preset categories, add folder-local custom categories, and reorder.
- Keep unused categories out of the UI. Review selectors show only the current folder's category set; breakdowns show only categories that have receipts; filter menus prioritize visible and used categories.
- Preserve existing data. Current receipts with `food`, `hotel`, `flight`, `taxi`, and `other` must survive migration without changing their raw values.
- Keep export and agent bridge simple. CSV still has one `expense_type` column, and agent sidecars still provide one category raw value.
- Keep profile/category choices local-first and CloudKit-safe from day one.

## 3. Non-goals

- No reimbursement workflow, submission status, approvals, policies, or accounting sync.
- No budgets, analytics dashboards, charts, or category spend insights beyond the existing totals/breakdowns.
- No global category-management screen in v1. Category editing belongs to the folder being configured.
- No direct Concur/SAP export integration. Existing zip/CSV contract remains the handoff.
- No tax/legal classification promises. Presets are organization aids, not advice.
- No per-category color explosion. The app stays calm and native; categories do not become a rainbow dashboard.
- No line items and no receipt item taxonomy.

## 4. Grounding And Research

### Codebase facts

- `Receipt.expenseTypeRawValue` is already a `String`, which is the migration seam; the blocker is the `ExpenseType` enum wrapper and every UI loop over `ExpenseType.allCases`.
- `ExpenseSummary.expenseType` and `TotalsCalculator.breakdownByExpenseType` currently key breakdowns by the enum, so the pure domain layer must move to stable category IDs before dynamic profiles can work.
- Review's selector is a five-tile `ExpenseTypeSelector`; it cannot simply grow to many categories without a layout rule.
- `SummaryCSVExporter` already emits the raw category string in the `expense_type` column, so the CSV can remain compatible if category IDs are stable ASCII identifiers.
- `AgentImportBridge` validates `record.expenseType` against the enum today; it must validate against the target folder's category set or a known legacy/preset category catalog.

### External research used

The research used `web-search-plus` with Tavily, Serper, Perplexity, and Parallel Search/Extract.

- Apple Human Interface Guidelines, read through Sosumi, shaped the Create Folder interaction: lists/tables are the native home for selecting, adding, deleting, and reordering; iOS/iPadOS list editing uses explicit edit controls; drag and drop should be supported where it helps, but Apple explicitly recommends providing alternate ways to accomplish the same actions. This spec therefore does not make cross-list drag/drop the primary add/remove path.
- IRS Topic 511 lists business travel costs such as airplane/train/bus/car travel, taxi/transport between airport/hotel/work locations, baggage/sample shipping, car use, tolls, parking fees, lodging, meals, laundry, business calls, tips, and other ordinary travel expenses.
- Conference-category sources from Fyle and Ramp separate registration fees, airfare/train/bus, lodging, meals, ground transportation, professional development/training, and exhibitor costs such as booth rental, display materials, setup, shipping, and promotional materials.
- IRS Publication 502 and Cigna's HSA/FSA material support medical/dental/vision/prescription/hospital/lab/transport recordkeeping shapes, and explicitly mention keeping receipts, EOBs, prescriptions, and other support.
- Vehicle-expense sources from H&R Block and Fyle list fuel/gas/oil, maintenance/repairs, tires, insurance, registration/license fees, tolls, parking, washing, lease/depreciation, and related costs.
- Microsoft and Smartsheet expense-template guidance supports using expense reports for household, event, project, construction, transportation, and recurring professional expense tracking, with categories adapted to the project rather than one global taxonomy.

## 5. Design Decisions

### D1 - Rename the generic container to Folder when profiles ship

The data model remains `ExpenseGroup`, but the broad feature should not keep a top-level UI that says only "Trips" once non-trip profiles exist. The user-facing container becomes **Folder** in general surfaces:

- Tab: `Folders`
- Create row: `New Folder...`
- Detail title remains the user-provided folder name.
- Profile-specific empty copy can still say "Start your first trip" only when the selected profile is Work Trip and there are no non-trip folders.
- `Unfiled` remains unchanged; it pairs naturally with the folder metaphor.

Rationale: the previous Trips rename was correct for the v1 trip-only product, but this feature makes the generic nature of `ExpenseGroup` real. "Folder" matches the current filing/export metaphor and avoids promising reimbursement, reports, budgets, or projects.

### D2 - A folder profile is a preset, not a rigid type

Each folder stores:

- a stable `profileID` such as `workTrip`, `conference`, or `medicalClaim`
- an ordered category snapshot copied from that profile at creation time
- any folder-local custom categories added by the user

Changing a profile preset later must not silently rewrite existing folders. Presets are starting points; the folder owns its editable visible list after creation.

### D3 - Categories become stable IDs with display metadata

Replace the app's enum-only category model with a category catalog:

- stable ASCII `id`, e.g. `food`, `hotel`, `registration`, `pharmacy`, `parking_tolls`
- localized display name key for built-in categories
- validated SF Symbol name, plus a documented fallback symbol
- color role
- optional custom display name for folder-local categories

The existing five raw values stay canonical and unmigrated:

| Existing ID | Display |
|---|---|
| `food` | Food |
| `hotel` | Hotel |
| `flight` | Flight |
| `taxi` | Taxi |
| `other` | Other |

Implementation should keep compatibility helpers for legacy `ExpenseType` only where needed during migration, but new UI/domain logic should operate on category IDs, not enum cases.

### D4 - Create Folder includes a lightweight category composer

The current New Trip sheet is too plain for the broader model because it only asks for name/date/notes. When profiles ship, folder creation must show the folder's receipt shape before the user saves it.

The post-implementation **Create Folder** sheet has two visible sections:

1. **Details**
   - Name
   - Profile row, defaulting to Work Trip but letting the user choose Conference, Medical Claim, Home Project, Vehicle Costs, and the rest of the preset set
   - Optional dates, shown for date-bound profiles and still toggleable for others
   - Notes
2. **Categories**
   - A **Selected** area showing the profile's default visible categories in order
   - A **Suggestions** area showing profile-specific add-ons not currently selected
   - A **Browse Existing Categories** row for built-in categories that belong to other profiles or are not in the profile's short suggestion set
   - An **Add Custom Category** row

The category composer rules:

- Defaults are not hidden in a second screen. The user sees the starting category set before saving the folder.
- Suggestions sit directly below the selected set. For Conference, the defaults include Registration, Flight, Hotel, Food, Taxi, Materials, Other; suggestions include Booth/Display, Shipping, Wi-Fi/Tech, Printing, and Professional Development.
- Suggestions are shortcuts, not the whole universe. If a user wants a category that is built in but not suggested for the current profile, `Browse Existing Categories` opens a searchable catalog of built-in categories across all profiles.
- The catalog sheet groups results as Suggested for this profile, Used in other profiles, and All categories. Already-selected categories are shown as selected/disabled or hidden by default, and adding a category uses the existing category ID, symbol, color, and localized name instead of creating a duplicate custom category.
- `Add Custom Category` stays after Browse Existing Categories and is only for labels that do not already exist in the built-in catalog. When a search query matches a built-in category, show the existing category result before offering custom creation.
- Tap is the primary interaction: tap a suggestion's plus control to add it; tap a selected category's remove control to remove it. Removed defaults move back into Suggestions, so the action is reversible before save.
- Drag/long-press reorder is supported only inside the Selected set as a progressive enhancement. It is not the only way to add or remove categories.
- `Other` is always present and pinned to the end; it cannot be removed or dragged above specific categories.
- Save requires a folder name and at least one non-Other selected category.
- A profile change before the user edits categories replaces the selected/default set. After the user manually edits categories, changing profile asks whether to replace the category set or keep the edited set.
- Hard cap visible categories at nine including Other. If the user tries to add beyond that, ask them to remove or combine categories first.
- At large Dynamic Type, the composer becomes a vertical list: selected categories first with remove/reorder controls, suggestions below with add buttons.

This gives the user what they asked for in the Conference example: remove Materials, add Booth/Display or a custom category, and save the folder without opening a global category manager.

### D5 - Folder-visible categories remain editable after creation, with guardrails

Folder settings gain the same **Categories** composer:

- The editor shows the ordered visible category list.
- Users can remove unused categories.
- Users can add from suggested categories for the folder profile.
- Users can add a custom folder-local category with a short name and suggested symbol.
- Users can reorder categories.
- `Other` is always present and pinned to the end; it cannot be removed.

If the user tries to remove a category already used by receipts in that folder:

1. Show a sheet explaining that receipts already use it.
2. Offer **Reassign receipts** to another visible category.
3. Offer **Keep category**.
4. Do not fully remove the category while receipts still reference it.

If a category was removed earlier but later appears because an imported/legacy receipt uses it, render it in a small "Used in this folder" section in filters and breakdowns until reassigned. This protects old data without polluting normal entry.

### D6 - Review category selector is profile-scoped

The review screen keeps the same mental model: choose one category before saving. It no longer loops over all possible categories.

Rules:

- If capture starts from a folder, show that folder's visible categories.
- If the user changes the selected folder in review, update the category selector to that folder's visible list.
- If the current category is not visible in the new folder, keep it selected in a temporary "Current" chip and mark the field for attention until the user chooses a visible category.
- If no folder is selected, use a compact Unfiled default set: Food, Travel, Supplies, Medical, Vehicle, Other. The moment a folder is chosen, switch to that folder's set.
- The model/parser may suggest any built-in category ID, but the merge layer should prefer visible categories for the chosen folder. If the best model suggestion is outside the visible set, show it only as an alternate with a reason, not as a surprise primary.

Layout:

- Keep icon+label tiles for up to five categories.
- For six to eight categories, use a two-row adaptive tile grid inside the same field block.
- Hard cap visible categories at nine including Other. If a user tries to add beyond that, ask them to remove or combine categories first.
- At accessibility sizes, tiles become a vertical list of buttons. No horizontal scrolling for the primary category selector.

### D7 - Breakdowns and filters show relevant categories only

Folder detail:

- Breakdown rows show only categories used by active receipts in that folder.
- Row order follows the folder's category order; used categories outside the visible list appear after visible categories under a "Used" ordering rule.
- No empty rows for visible-but-unused categories.

Featured card:

- Show count chips for categories used in the folder, capped to categories that fit; fall back to compact glyph dots exactly as the current design does.

Receipts tab filters:

- The type/category filter menu shows built-in/folder-visible categories relevant to the selected folder filter first.
- If no folder filter is selected, show "Recently used categories" and "All categories with receipts", not every built-in preset category.

### D8 - Preset profiles and visible categories

The preset list should be deliberately small and receipt-first. Each profile starts with 5-8 visible categories including Other. Users can edit per folder.

| Profile | Default visible categories | Suggested add-ons |
|---|---|---|
| Work Trip | Flight, Hotel, Food, Taxi, Other | Parking/Tolls, Laundry, Baggage, Business Calls |
| Conference | Registration, Flight, Hotel, Food, Taxi, Materials, Other | Booth/Display, Shipping, Wi-Fi/Tech, Printing, Professional Development |
| Client Visit / Day Trip | Food, Taxi, Parking/Tolls, Fuel, Supplies, Other | Train/Bus, Client Materials, Tips |
| Business Purchases / Tax | Supplies, Software, Printing, Shipping, Professional Fees, Equipment, Other | Advertising, Utilities, Bank Fees, Insurance |
| Home Project | Materials, Tools, Labor, Delivery, Permits, Fixtures, Other | Paint, Electrical, Plumbing, Rental Equipment |
| Medical Claim | Consultation, Pharmacy, Tests/Labs, Dental, Vision, Hospital, Transport, Other | Insurance Premium, Therapy, Medical Equipment |
| Vehicle Costs | Fuel, Service, Repairs, Parking, Tolls, Registration, Insurance, Other | Tires, Washing, Oil, Lease/Finance |
| Moving / Relocation | Movers, Packing, Storage, Fuel, Hotel, Food, Delivery, Other | Truck Rental, Utilities Setup, Cleaning |
| Event / Function | Venue, Catering, Decor, Printing, Supplies, Travel, Other | Audio/Visual, Staff, Gifts |
| Warranty / Big Purchase | Purchase, Accessories, Delivery, Installation, Repair, Warranty Plan, Other | Replacement Parts, Service Visit |
| Custom Folder | Food, Supplies, Transport, Other | All built-in categories available through Add |

Naming notes:

- `Food` remains the display name for the existing `food` ID. Do not introduce both `Food` and `Meals` in the same folder by default.
- `Taxi` remains the display name for the existing `taxi` ID in Work Trip and Conference to preserve the current product language. Broader profiles may use `Transport` or `Parking/Tolls` as separate category IDs.
- `Materials` in Conference is intentionally editable; the user's example of removing Materials and adding something else must be a first-class path, not a workaround.

### D9 - Category symbols use SF Symbols first

The category expansion must preserve the thing that makes the current Trips UI feel good: clear SF Symbol identities beside short labels. Apple positions SF Symbols as the native icon language for objects and concepts in toolbars, tab bars, menus, and inline UI; they align with the system font, weights, and scales, and can adapt to appearance/accessibility settings.

Rules:

- Every built-in category has a required `symbolName`.
- Every built-in `symbolName` must be validated against the app's minimum supported OS during implementation, with a test or explicit fallback.
- Prefer familiar object symbols over abstract accounting icons. The label carries precision; the glyph creates quick recognition.
- Reuse a good generic symbol when categories are accounting nuances of the same real-world object. Do not invent weak one-off icons for every category.
- Custom folder-local categories default to `tag.fill`. V1 may offer a small curated symbol picker; it must not expose the full SF Symbols library.
- Custom SF Symbols are allowed only for high-value gaps after product usage proves the need. They must follow Apple's custom-symbol guidance: simple, recognizable, inclusive, directly related, and visually consistent with system symbols.
- Do not use SF Symbols, or confusingly similar custom symbols, in the app icon, logo, or trademark-like brand surfaces.

Initial built-in symbol catalog:

| Category group | Categories and symbols |
|---|---|
| Current / Work Trip | Food `fork.knife`; Hotel `bed.double.fill`; Flight `airplane`; Taxi `car.fill`; Other `tag.fill`; Parking/Tolls `parkingsign.circle.fill`; Laundry `washer.fill`; Baggage `suitcase.rolling.fill`; Business Calls `phone.fill` |
| Conference | Registration `ticket.fill`; Materials `doc.text.fill`; Booth/Display `rectangle.3.group.fill`; Shipping `shippingbox.fill`; Wi-Fi/Tech `wifi`; Printing `printer.fill`; Professional Development `graduationcap.fill` |
| Client Visit / Day Trip | Fuel `fuelpump.fill`; Supplies `bag.fill`; Train/Bus `train.side.front.car`; Client Materials `doc.text.fill`; Tips `hand.thumbsup.fill` |
| Business Purchases / Tax | Software `laptopcomputer`; Professional Fees `briefcase.fill`; Equipment `desktopcomputer`; Advertising `megaphone.fill`; Utilities `bolt.fill`; Bank Fees `banknote.fill`; Insurance `shield.fill` |
| Home Project | Materials `hammer.fill`; Tools `wrench.and.screwdriver.fill`; Labor `person.fill`; Delivery `truck.box.fill`; Permits `doc.text.fill`; Fixtures `lightbulb.fill`; Paint `paintbrush.fill`; Electrical `bolt.circle.fill`; Plumbing `drop.fill`; Rental Equipment `wrench.adjustable.fill` |
| Medical Claim | Consultation `stethoscope`; Pharmacy `pills.fill`; Tests/Labs `testtube.2`; Dental `cross.case.fill`; Vision `eyeglasses`; Hospital `building.2.fill`; Transport `car.fill`; Insurance Premium `shield.fill`; Therapy `brain.head.profile`; Medical Equipment `cross.case.fill` |
| Vehicle Costs | Fuel `fuelpump.fill`; Service `wrench.fill`; Repairs `wrench.and.screwdriver.fill`; Parking `parkingsign.circle.fill`; Tolls `road.lanes`; Registration `doc.text.fill`; Insurance `shield.fill`; Tires `tirepressure`; Washing `water.waves`; Oil `oilcan.fill`; Lease/Finance `creditcard.fill` |
| Moving / Relocation | Movers `box.truck.fill`; Packing `shippingbox.fill`; Storage `archivebox.fill`; Delivery `truck.box.fill`; Truck Rental `box.truck.fill`; Utilities Setup `bolt.fill`; Cleaning `bubbles.and.sparkles.fill` |
| Event / Function | Venue `building.columns.fill`; Catering `fork.knife.circle.fill`; Decor `party.popper.fill`; Supplies `bag.fill`; Travel `airplane`; Audio/Visual `display`; Staff `person.2.fill`; Gifts `gift.fill` |
| Warranty / Big Purchase | Purchase `cart.fill`; Accessories `puzzlepiece.extension.fill`; Delivery `truck.box.fill`; Installation `square.and.arrow.down.fill`; Repair `wrench.fill`; Warranty Plan `checkmark.seal.fill`; Replacement Parts `puzzlepiece.extension.fill`; Service Visit `calendar.badge.clock` |
| Fallbacks | Default custom category `tag.fill`; unknown-but-known-later category `tag.fill`; document/permit fallback `doc.text.fill`; money/finance fallback `banknote.fill`; protection/insurance fallback `shield.fill` |

### D10 - Category color stays restrained

The current design gives each of five expense types a distinct color. With dozens of possible categories, one permanent color per category becomes noisy and hard to localize visually.

Rules:

- Built-in categories reuse a small palette of existing semantic category roles: food/orange, lodging/indigo, travel/blue, transport/teal, generic/gray, plus Ledger Green only for selection/save actions.
- Custom categories default to neutral gray with a user-selectable SF Symbol. Do not add custom color pickers in v1.
- A category color is an accent on glyph tiles and selected states only; it does not create large filled surfaces.

### D11 - Export keeps the `expense_type` column

CSV remains stable:

- The header stays `expense_type`.
- Values are category IDs, not localized display names.
- Custom folder-local categories export their stable folder-local IDs, e.g. `custom_booth_setup`, and the optional localized comment row explains that category labels are folder-defined.
- No new totals section, no multi-table CSV, no JSON export.

This keeps the current one-row-per-receipt contract intact while allowing downstream users to map IDs to their own systems.

### D12 - Agent imports validate against folder context

Structured agent sidecars keep one field named `expenseType` for compatibility in the first implementation pass, but the spec treats it as a category ID.

Validation rules:

- If the sidecar targets a folder, accept category IDs in that folder's visible category set.
- Accept legacy five IDs everywhere.
- If the ID is a known built-in category but not visible in the target folder, ingest as a draft needing review and mark category for attention.
- If the ID is unknown, reject the structured sidecar with the existing validation failure path.
- The manifest should include each folder's profile ID and visible category IDs/names so trusted agents do not have to guess.

## 6. Data Model Impact

### ExpenseCore

- Introduce a string-backed category ID concept for totals, merge policy, export, and tests.
- Replace `ExpenseSummary.expenseType: ExpenseType` with a dynamic category ID while keeping adapter coverage for the existing five IDs.
- Replace `breakdownByExpenseType` with breakdown by category ID.
- Add a built-in category/profile catalog in pure code, with tests for stable IDs, default profile sets, symbol names/fallbacks, uniqueness, and Other-last ordering.

### SwiftData

- Add `ExpenseGroup.profileIDRawValue`, defaulting existing groups to `workTrip`.
- Add a CloudKit-safe ordered category snapshot on `ExpenseGroup`. A JSON string is acceptable if it keeps the model simple, versioned, and testable; a separate model is acceptable only if it does not complicate CloudKit optionality/inverse rules.
- Keep `Receipt.expenseTypeRawValue` as the persisted field name for migration safety, or add a new `categoryIDRawValue` only if the migration is explicitly tested. The user-visible concept becomes Category.
- Existing receipts must keep raw values unchanged.

### Localization

Every built-in profile and built-in category display name requires a `Localizable.xcstrings` key. Custom folder-local category names are user-authored data and are not catalog strings.

Required key families:

- `folder.profile.workTrip`
- `folder.profile.conference`
- `folder.profile.clientVisit`
- `folder.profile.businessPurchases`
- `folder.profile.homeProject`
- `folder.profile.medicalClaim`
- `folder.profile.vehicleCosts`
- `folder.profile.moving`
- `folder.profile.event`
- `folder.profile.warranty`
- `folder.profile.custom`
- `expense.category.<id>` for every built-in category ID
- `folder.categories.title`
- `folder.categories.add`
- `folder.categories.usedByReceipts`
- `folder.categories.reassign`
- `folder.categories.otherLocked`

## 7. UI And Flow

### Create folder

Creating a folder becomes:

1. Name.
2. Profile picker with concise rows: Work Trip, Conference, Client Visit, Home Project, Medical Claim, Vehicle Costs, Business Purchases, More.
3. Optional dates remain available for trip-like profiles and hidden by default for non-date-bound folders.
4. Category composer in the same sheet:
   - Selected defaults are visible as compact selected category pills/rows.
   - Suggestions are visible immediately below as addable pills/rows with plus controls.
   - `Browse Existing Categories` opens a searchable built-in category catalog for categories not in the short suggestion set.
   - `Add Custom Category` is a normal row at the bottom of the category card.
   - Removing a default moves it to Suggestions.
   - Adding a suggestion moves it to Selected.
   - Adding from the catalog moves that existing category to Selected without creating a custom duplicate.
   - Reorder uses drag/long-press or edit-mode handles inside Selected only.
   - `Other` remains locked at the end.

Do not show paragraphs explaining profiles. The labels and category preview should be enough.

Post-implementation Conference example:

- Title: `New Folder`
- Details card: Name = `AWS Summit 2026`, Profile = `Conference`, Dates toggle, Notes
- Categories card:
  - Selected: Registration, Flight, Hotel, Food, Taxi, Materials, Other
  - Suggestions: Booth/Display, Shipping, Wi-Fi/Tech, Printing, Professional Development
  - Browse Existing Categories
  - Add Custom Category

If the user removes Materials, it disappears from Selected and reappears in Suggestions. If the user taps Booth/Display, it appears in Selected before Other. If the user needs Parking, Pharmacy, or another built-in category from a different profile, Browse Existing Categories finds and adds it before Other without making it custom. Save keeps that edited snapshot on the folder.

### Edit folder

The existing group editor adds:

- Profile row (read-only after creation in v1, with "Duplicate as another profile" deferred)
- Categories row
- Existing name/date/notes rows

Changing a category list should not require leaving the editor.

### Review and receipt detail

- Rename field label from `Expense type` to `Category`.
- Show the folder-scoped category selector.
- Receipt detail uses the same category picker behavior, scoped to the receipt's assigned folder.
- If moving a receipt to another folder, validate its category against the destination folder and ask for reassignment when needed.

### Mac

The Mac app uses the same profile/category catalog and folder snapshots. Do not invent a Mac-only category model.

## 8. Edge Cases

- Existing app data: all existing groups become Work Trip folders; all receipts keep their category IDs.
- Existing `other` receipts: remain Other and do not require review.
- Removed unused category: disappears from selector/filter immediately.
- Removed used category: blocked until reassigned, or retained as used-only.
- Custom category deleted before sync completes: local save must be atomic; CloudKit peers must not see receipts pointing to missing display metadata.
- Folder with no visible category except Other: disallow; require at least one non-Other category.
- Receipt moved between folders: if category ID is not visible in destination, prompt for reassignment.
- Unfiled receipt: use Unfiled default set; category can be changed later after assigning to a folder.
- Import sidecar with known but hidden category: draft needing review, not silent save.
- Export custom category: write stable ID, not display name.

## 9. Accessibility And Localization

- Category selector tiles/list buttons must have labels with category display name and selected state.
- At large Dynamic Type, selector becomes a vertical list; no clipped category names.
- Category editor reorder controls must be VoiceOver reachable.
- Custom category names are user data; they should be mirrored as typed and not run through localization.
- RTL layout uses leading/trailing throughout.
- No new hardcoded user-facing strings; all built-in names and UI copy are catalog-backed.

## 10. Test Impact

### ExpenseCore tests

- Built-in profile catalog has unique IDs, stable default sets, and Other last.
- Built-in category catalog has a non-empty SF Symbol name and a safe fallback for every category.
- Existing five legacy IDs map to built-in categories.
- Totals and breakdowns group by dynamic category ID and preserve per-currency math.
- CSV export writes category IDs unchanged.
- Category IDs reject non-ASCII/unsafe custom values.

### App tests

- Migration creates Work Trip profile/category snapshots for existing groups.
- Review selector shows Work Trip categories for an existing trip.
- Conference folder starts with Registration, Flight, Hotel, Food, Taxi, Materials, Other.
- Create Folder shows Conference defaults and Conference suggestions before save.
- Removing Materials from the Create Folder category composer moves it to Suggestions without leaving the screen.
- Adding Booth/Display from Suggestions moves it into Selected before Other.
- Browse Existing Categories can add a built-in category from another profile without creating a custom category.
- Searching for a built-in category in the catalog shows the existing category before offering custom creation.
- Removing unused Materials from a Conference folder hides it from review/filter UI.
- Adding a custom Conference category shows it in review, receipt detail, and filter menu.
- Attempting to remove a used category requires reassignment.
- Moving a receipt to a folder where its category is not visible prompts reassignment.
- Unfiled review uses the Unfiled default set.
- Agent manifest includes folder profile and visible category IDs.
- Structured agent import accepts a visible category ID and drafts a hidden-but-known category ID for review.

### UI tests

- Create a Medical Claim folder and verify the category selector contains medical categories, not flight/hotel.
- Create a Home Project folder and verify categories fit at default size and accessibility size.
- Create a Conference folder, remove Materials, add Booth/Display, and verify the edited snapshot is saved.
- Verify folder detail breakdown shows only categories with receipts, not every visible category.
- Verify Receipts filter menu does not list unused categories when scoped to a folder.

## 11. Acceptance Criteria

1. Existing data opens without user action: existing groups become Work Trip folders and existing receipts keep `food`, `hotel`, `flight`, `taxi`, or `other`.
2. Creating a Conference folder starts with Registration, Flight, Hotel, Food, Taxi, Materials, and Other.
3. The user can remove unused Materials from that Conference folder and add a folder-local custom category; review and receipt detail show the edited list immediately.
4. The app prevents deleting a category that already has receipts unless those receipts are reassigned.
5. Review, receipt detail, folder detail breakdowns, and filters show only categories relevant to the selected folder plus categories already used by receipts.
6. A Medical Claim folder never shows Flight or Hotel by default; a Work Trip folder preserves the current trip category feel.
7. CSV export keeps the existing `expense_type` column and writes stable category IDs.
8. Agent sidecars can target visible category IDs using the existing `expenseType` field name; unknown IDs fail validation.
9. All new strings are in `Localizable.xcstrings`; custom category names are stored as user data.
10. The feature does not add reimbursement status, budgets, dashboards, direct accounting sync, or new network calls.

## 12. Open Questions

- Should the tab label switch to Folders in the same implementation pass, or should this spec be split into "data/profile model first" and "copy rename second"? This spec recommends same pass to avoid a non-trip feature inside a Trips tab.
- Should profile selection be read-only after folder creation for v1? This spec recommends read-only plus editable categories, because changing a folder's profile after receipts exist creates more edge cases than it solves.
- Should custom categories be reusable across folders in v1? This spec recommends folder-local only; a later "reuse in another folder" affordance can copy a category definition without introducing a global management screen.
