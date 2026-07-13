# SPEC: Per-category distinct colors and per-profile folder identity

**Status:** Draft — ready for implementation
**Owner screens:** Folder create/edit sheet ([GroupsViews.swift](../../IntelliExpense/UI/GroupsViews.swift)), Review & Confirm and Receipt Detail category selector ([CategoryDisplay.swift](../../IntelliExpense/UI/CategoryDisplay.swift), [ReviewViews.swift](../../IntelliExpense/UI/ReviewViews.swift)), Folders home category dots and folder detail breakdown/receipt rows ([GroupsViews.swift](../../IntelliExpense/UI/GroupsViews.swift), [ReceiptsViews.swift](../../IntelliExpense/UI/ReceiptsViews.swift)), Mac detail pane ([MacReceiptDetailPane.swift](../../IntelliExpense/Mac/MacReceiptDetailPane.swift))
**Owner logic/assets:** [ExpenseCategory.swift](../../ExpenseCore/Sources/ExpenseCore/Domain/ExpenseCategory.swift), [CategoryCatalog.swift](../../ExpenseCore/Sources/ExpenseCore/Domain/CategoryCatalog.swift), [FolderProfile.swift](../../ExpenseCore/Sources/ExpenseCore/Domain/FolderProfile.swift), [Assets.xcassets](../../IntelliExpense/Resources/Assets.xcassets)
**Docs this spec amends:** `DESIGN.md` (frontmatter `colors.expense_types`, §2 token table and hard rules, dark-mode "thirteen custom pairs" count, §11 agent guide), `design/ui-spec.html` (color-set list, category tile/dot mockups). Supersedes `SPEC-category-color-roles.md` and `SPEC-expense-profiles-and-visible-categories.md` §D10 where they conflict.

## 1. Problem

The category color system assigns colors by *semantic role* (nine roles: food, lodging, travel, transport, services, goods, tech, health, generic). That was designed to keep color restrained, but in profile-heavy folders it produces the opposite of a design system doing work: the Medical Claim profile maps Consultation, Pharmacy, Tests/Labs, Dental, Vision, Hospital, Therapy, and Medical Equipment **all** to the `health` role, so the Edit Folder sheet, category selector, breakdown rows, and folder-card color dots render a monotonous wall of identical mint tiles. Compare the Work Trip folder card ("Bengaluru Conference"), whose four legacy categories happen to have four distinct hues — blue, indigo, orange, teal dots — and reads as polished and scannable. The owner has explicitly reversed the earlier direction: distinct per-category color *is* the desired look, and the earlier category-role restraint rules in `DESIGN.md` §2 and profiles-spec §D10 are to be removed.

The insight that makes this safe: a folder never shows more than 9 visible categories (snapshot cap, including Other), and every profile's default set is 5–8. A palette of ~12 distinguishable hues can give **every category in a profile a unique color** without ever putting two similar hues side by side — colorful, but bounded, so it cannot become overwhelming.

The same monotony problem exists one level up: every folder on the Folders tab wears the identical `folder.fill` glyph in Ledger Green on a Ledger Green Soft tile, so a home screen with several folders is a column of interchangeable green squares. Folders already know their `profileID`, so each preset profile gets a permanent identity — a relevant SF Symbol plus a hue from the same category palette — making each folder card recognizable at a glance (D8/D9).

## 2. Goals

- Within any profile's default category set **and** its suggestion chips, no two categories share a color. Within any user-edited folder snapshot (≤9 categories), collisions remain impossible for built-ins from one profile and are actively avoided for additions.
- Each built-in category keeps **one permanent color everywhere** — the same category is the same color in the selector, breakdown rows, receipt rows, folder-card dots, filter menus, and suggestion chips, across all folders and both appearances. Color still "always means the same thing"; the *thing* changes from role to category identity.
- Custom categories stop defaulting to grey: they receive a deterministic auto-assigned color that avoids hues already in the folder.
- All surfaces improve for free through the shared `CategoryGlyph` and `FolderCategory.color` path — no per-screen work.
- Every preset profile has a permanent folder identity (SF Symbol + palette hue), pairwise distinct across the profile catalog, shown wherever a folder is represented by a glyph tile: Folders home cards, archived folder rows, move-to-folder pickers, and the profile picker itself.
- `DESIGN.md` and `ui-spec.html` are amended in the same change so the docs never lag the app.

## 3. Non-goals

- **No color picker.** Colors are assigned by the catalog (built-ins) or deterministically (customs); users never choose a color. (Superseding §D10 removes the *rationale* for restraint, not the no-picker rule.)
- **No red, no pink.** The `DESIGN.md` "No red" hard rule stands untouched; the palette below contains no red-family hue, and the plum hue must stay unambiguously purple-side.
- **No green category hue.** Ledger Green remains the single brand accent (Save, selection, links); a green category color would dilute it. Mint is the closest the palette gets and already exists.
- No changes to symbols, category IDs, snapshot JSON *shape* (only the `colorRoleRawValue` vocabulary evolves — see D4), CSV export, or the always-grey pinned `Other`.
- No widget changes: `DESIGN.md` §Widgets still forbids category color in widget surfaces; the Quick Capture widget keeps its current folder presentation.
- No per-folder icon or color customization: identity belongs to the *profile*, not the folder. Two Work Trip folders look alike and are told apart by name, dates, and their category dots — exactly like two playlists sharing an icon in Music.
- No bulk data migration of existing folder snapshots (see D5).

## 4. Design decisions

### D1 — Color identity moves from role to category, scoped by the visible-set cap

`DESIGN.md` §2 previously tied category colors to role identity and profiles-spec §D10 argued against permanent per-category color. **Both passages are amended by this spec** (owner decision, 2026-07-09): the role indirection is deleted, and each built-in category gets a permanent hue.

What made "one color per category" noisy in the D10 analysis was imagining ~70 simultaneous colors. That never happens: the folder snapshot cap is 9 (`FolderCategorySnapshot.maximumVisibleCategories`), and profile defaults are 5–8. The binding constraint is therefore *per-profile distinctness*, which a 12-hue palette satisfies exactly (largest set: Conference, 11 non-Other categories across defaults + suggestions — see D3's verification table).

The rule that survives, rewritten for `DESIGN.md` §2:

> Category color means category identity: each built-in category has one permanent hue from the 12-hue category palette, identical in review chips, list badges, breakdown rows, folder-card dots, and glyph tiles, across every folder and both appearances. Within one profile, no two categories share a hue — the folder view is colorful because the categories are distinct, never because color is decorative. Users never pick colors; there is no color picker.

Considered and rejected:
- *Keep roles, add more roles*: any role grouping reproduces the Medical Claim failure — a profile whose categories are all one domain collapses to one color by construction.
- *Per-folder dynamic assignment* (colors assigned per snapshot, so the same category could differ between folders): breaks cross-folder recognition ("Fuel is always amber") and makes the Unfiled selector, filter menus, and moved receipts flicker colors. Permanent per-category assignment gives distinctness *and* recognition.
- *Hashing IDs to hues*: non-curated collisions inside a profile are exactly the failure being fixed.

### D2 — The category palette: 12 named asset-catalog pairs, hue-named

`DESIGN.md` dark-mode rules require every custom color to be one named asset-catalog pair (Any + Dark), brightening "the way Apple's do", referenced by name only, no `colorScheme` branches. The nine existing pairs keep their exact values but are **renamed by hue**, because role names would permanently mislead (e.g. orange no longer means food — Advertising and Repairs are also orange). Three new pairs join them.

| Token (asset pair) | Light | Dark | Provenance |
|---|---|---|---|
| `CategoryOrange` | `#FF9500` | `#FF9F0A` | existing `ExpenseFood` (systemOrange), values unchanged |
| `CategoryIndigo` | `#5856D6` | `#5E5CE6` | existing `ExpenseHotel` (systemIndigo), values unchanged |
| `CategoryBlue` | `#007AFF` | `#0A84FF` | existing `ExpenseFlight` (systemBlue), values unchanged |
| `CategoryTeal` | `#2AA8BD` | `#3FC2D9` | existing `ExpenseTaxi`, values unchanged |
| `CategoryPurple` | `#AF52DE` | `#BF5AF2` | existing `ExpenseServices` (systemPurple), values unchanged |
| `CategoryBrown` | `#A2845E` | `#AC8E68` | existing `ExpenseGoods` (systemBrown), values unchanged |
| `CategoryCyan` | `#1E96D1` | `#4CC2FF` | existing `ExpenseTech`, values unchanged |
| `CategoryMint` | `#0E9F8E` | `#3BD6C3` | existing `ExpenseHealth`, values unchanged |
| `CategoryGray` | `#8E8E93` | `#8E8E93` | existing `ExpenseOther` (systemGray), values unchanged |
| `CategoryAmber` | `#B26B00` | `#E5A421` | **new** — deep gold, clearly warmer/darker than `CategoryOrange` in light, distinctly yellow-gold in dark |
| `CategoryPlum` | `#96419B` | `#D678DB` | **new** — magenta-leaning purple; must stay clearly purple-side (never pink/rose) per the no-red rule |
| `CategorySlate` | `#5D6B85` | `#93A2C0` | **new** — steel blue-grey; the "paperwork" hue (permits, registrations, premiums), visibly a color yet calmer than the rest |

Tuning latitude: the three new pairs may be adjusted during implementation **within the same hue family** to pass the checks in §7 (white-glyph legibility per existing `CategoryGlyph` precedent; side-by-side distinguishability from their nearest neighbors — Amber↔Orange↔Brown, Plum↔Purple↔Indigo, Slate↔Gray↔Cyan — at 22–28 pt tile size and at the ~7 pt folder-card dot size, in both appearances). The checks are acceptance criteria; the exact hex is not.

Doc updates in the same change: `DESIGN.md` frontmatter `colors.expense_types` becomes `colors.category_palette` with these 12 entries (drop the per-hue `symbol:` field — symbols belong to categories now, not hues); §2 table replaces the nine role rows with these 12 rows; "Thirteen custom pairs" becomes **sixteen** (verify the count when editing: 12 category pairs + LedgerGreen + LedgerGreenSoft + attention edge + duplicate surface, matching however the current thirteen is itemized); §11's role list is replaced by "Category palette: 12 hues (orange, amber, brown, mint, teal, cyan, blue, indigo, purple, plum, slate, gray); each category owns one permanent hue; no two categories in a profile share one." `ui-spec.html`'s color-set list and category mockups (Edit Folder sheet, selector tiles, folder-card dots) gain the same palette.

### D3 — Permanent hue assignment for every built-in category

The single source of truth stays the catalog in `CategoryCatalog.swift`. The assignment below is complete (every built-in ID) and was verified against every profile in `FolderProfile.swift`: **no profile's defaults ∪ suggestions contains a duplicate hue.** Metaphor guided the choices where a natural one exists (bulb → amber, water drop → blue, bubbles → mint, gift → gold/amber); distinctness constraints decided the rest.

| Hue | Category IDs |
|---|---|
| orange | `food`, `advertising`, `labor`, `pharmacy`, `repairs`, `catering`, `purchase` |
| amber | `fuel`, `booth_display`, `utilities`, `fixtures`, `gifts`, `repair` |
| brown | `baggage`, `materials`, `supplies`, `building_materials`, `medical_equipment`, `tires`, `packing`, `replacement_parts` |
| mint | `laundry`, `shipping`, `tips`, `rental_equipment`, `consultation`, `medical`, `lease_finance`, `cleaning`, `warranty_plan` |
| teal | `taxi`, `transport`, `vehicle`, `tools`, `service`, `bank_fees`, `truck_rental`, `installation` |
| cyan | `parking_tolls`, `parking`, `wifi_tech`, `software`, `delivery`, `dental`, `audio_visual` |
| blue | `flight`, `travel`, `equipment`, `plumbing`, `hospital`, `washing`, `movers` |
| indigo | `hotel`, `train_bus`, `insurance`, `vision`, `venue`, `service_visit` |
| purple | `business_calls`, `registration`, `professional_fees`, `paint`, `tests_labs`, `tolls`, `storage`, `staff`, `accessories` |
| plum | `professional_development`, `electrical`, `therapy`, `oil`, `decor` |
| slate | `printing`, `client_materials`, `permits`, `vehicle_registration`, `insurance_premium`, `utilities_setup` |
| gray | `other` only (locked; grey returns to meaning exactly one thing: the always-included catch-all) |

Per-profile verification (defaults + suggestions, `other` excluded), for the implementer to re-check and for tests to encode:

| Profile | Hues in order | Count |
|---|---|---|
| Work Trip | blue, indigo, orange, teal + cyan, mint, brown, purple | 8 distinct |
| Conference | purple, blue, indigo, orange, teal, brown + amber, mint, cyan, slate, plum | 11 distinct |
| Client Visit | orange, teal, cyan, amber, brown + indigo, slate, mint | 8 distinct |
| Home Project | brown, teal, orange, cyan, slate, amber + purple, plum, blue, mint | 10 distinct |
| Medical Claim | mint, orange, purple, cyan, indigo, blue, teal + slate, plum, brown | 10 distinct |
| Vehicle Costs | amber, teal, orange, cyan, purple, slate, indigo + brown, blue, plum, mint | 11 distinct |
| Business Purchases | brown, cyan, slate, mint, purple, blue + orange, amber, teal, indigo | 10 distinct |
| Moving | blue, brown, purple, amber, indigo, orange, cyan + teal, slate, mint | 10 distinct |
| Event | indigo, orange, plum, slate, brown, blue + cyan, purple, amber | 9 distinct |
| Warranty | orange, purple, cyan, teal, amber, mint + brown, indigo | 8 distinct |
| Custom profile seed | orange, brown, teal | 3 distinct |
| Unfiled default set | orange, blue, brown, mint, teal | 5 distinct |

Deliberate cross-references preserved by the table: the four legacy hues are untouched (`food` orange, `hotel` indigo, `flight` blue, `taxi` teal — existing folders' look is stable); the car/transport family (`taxi`, `transport`, `vehicle`) is uniformly teal and the parking family (`parking`, `parking_tolls`) uniformly cyan, so near-synonyms across profiles read as kin; paperwork (`permits`, `vehicle_registration`, `client_materials`, `printing`, `insurance_premium`, `utilities_setup`) is uniformly slate — colored now, per the owner's direction, but the calmest hue, preserving a visual "administrative" register. `insurance` (indigo) and `insurance_premium` (slate) intentionally diverge — Medical Claim contains both `vision` (indigo) and `insurance_premium`, so the old same-color tie had to break; slate's paperwork register fits premiums.

### D4 — `CategoryColorRole` becomes a hue enum; legacy raw values decode forever

The persisted snapshot JSON stores `colorRoleRawValue` strings, so the vocabulary is a compatibility surface. The enum's cases become the 12 hues (`orange`, `amber`, `brown`, `mint`, `teal`, `cyan`, `blue`, `indigo`, `purple`, `plum`, `slate`, `gray`). Decoding accepts the nine legacy raw values permanently, mapped to their historical hue: `food`→orange, `lodging`→indigo, `travel`→blue, `transport`→teal, `services`→purple, `goods`→brown, `tech`→cyan, `health`→mint, `generic`→gray. Unknown values keep falling back to gray (existing behavior). Encoding always writes the new hue values. The snapshot `version` stays 1 — the JSON shape is unchanged and old readers were already tolerant of unknown role strings via the gray fallback.

`CategoryDisplay.swift`'s single switch maps each hue case to its `Category<Hue>` asset name. Rejected alternative: keeping role cases and adding a second per-category lookup table — two sources of truth for one pixel, and the role names would lie.

### D5 — No data migration; built-ins self-heal, customs heal on folder save

Unchanged from the previous color spec's D4 reasoning: snapshots are self-contained, and rewriting every `ExpenseGroup` generates CloudKit churn without fixing stale peers. Instead:

- **Built-ins**: `CategoryResolver` already resolves catalog-first, so every built-in category shows its new hue immediately on every surface, regardless of what role string is frozen in the snapshot.
- **Custom categories**: existing customs have `generic` frozen in their snapshots and would stay gray. When the Edit Folder sheet saves, any custom category whose stored hue is gray is auto-assigned per D6 and written back as part of the normal snapshot save. Until the user next edits that folder, its old customs stay gray — acceptable, invisible churn-free, and self-correcting exactly when the user is looking at the category list.

### D6 — Custom categories get a deterministic auto-assigned hue

Grey-by-default customs would reintroduce monotony in custom-heavy folders. On creation (and on the D5 heal), a custom category takes the first hue from the fixed priority order **orange, teal, purple, amber, cyan, indigo, mint, blue, brown, plum, slate** that is not already used by the folder's current snapshot; if all eleven are in use (only possible transiently, since the cap is 9 including gray Other), take the least-used in that same order. Gray is never auto-assigned. The result is stored in the snapshot as usual, so it is stable thereafter and syncs like any other snapshot field. No color picker (non-goal); the symbol picker flow is untouched.

Determinism matters: the same folder state always yields the same color, so tests are exact and CloudKit peers converge. The priority order deliberately interleaves hue families so the first few customs in a sparse folder are maximally far apart.

### D7 — Where the color shows up is unchanged

No surface gains or loses color treatment: `CategoryGlyph` tiles, selector tile tint/ring, breakdown rows, receipt-row badges, folder-card category dots, filter menus, and suggestion chips all keep their existing geometry and simply render more distinct hues. The existing restraint rules that keep this from becoming overwhelming stay in force verbatim: category color is an accent on glyphs and selected states, never a large filled surface; one hero number per screen; Ledger Green remains the only action/selection accent. This is what bounds "colorful": more hues, same small surfaces.

### D8 — Every preset profile gets a permanent identity: symbol + palette hue

The profile catalog in `FolderProfile.swift` gains display identity alongside its existing metadata, mirroring how `BuiltInCategory` carries `symbolName` + color. No new color assets: profile identities draw from the D2 category palette, and the ten preset profiles take ten pairwise-distinct hues so the Folders tab and the profile picker never show two presets in the same color.

| Profile | Symbol | Hue |
|---|---|---|
| Work Trip | `suitcase.fill` | blue |
| Conference | `person.3.fill` | purple |
| Client Visit / Day Trip | `person.2.fill` | cyan |
| Home Project | `hammer.fill` | amber |
| Medical Claim | `cross.case.fill` | mint |
| Vehicle Costs | `car.fill` | teal |
| Business Purchases / Tax | `cart.fill` | indigo |
| Moving / Relocation | `shippingbox.fill` | brown |
| Event / Function | `party.popper.fill` | plum |
| Warranty / Big Purchase | `checkmark.seal.fill` | orange |
| Custom | `folder.fill` | Ledger Green (unchanged current look) |

Rationale and constraints:

- Symbols follow the catalog's "SF Symbols first … reuse strong generic symbols" rule; every symbol above is already validated in the category catalog or is a long-established system symbol, with `folder.fill` as the universal fallback for unknown profile IDs.
- **Custom keeps today's green folder.** It is the "just a folder" preset, so the app-default look *is* its identity, and it keeps the current visual as the neutral baseline among the colored presets. Ledger Green here is grandfathered decoration (the folder tile already uses it today), not a new accent use; slate was considered for Custom and rejected as reading "disabled".
- A profile's icon hue may coincide with one of its categories' hues on the same folder card (Medical Claim's mint cross beside a mint Consultation dot). Accepted: the icon tile and the dot row are different shapes at different sizes and are never interleaved; forcing icon-vs-category distinctness would over-constrain both tables.
- *Considered and rejected — per-folder user-chosen icon/color*: contradicts "presets, not rigid types" (profiles spec §D2) by making identity another editing chore, and adds a picker the design system has twice declined.

### D9 — Rendering: same tile geometry, hue-tinted

The folder glyph tile keeps its exact current geometry (size, corner radius, placement) in all three `GroupsViews.swift` sites and any picker rows; only the colors change: glyph in the profile hue, tile fill in the same hue at soft-tint opacity. Precedent for opacity-tinted fills of a named color is the category selector's selected-tile background (`category.color.opacity(0.14)`, per the choice-chip spec) — no new `*Soft` asset pairs, no raw hex. The "New Folder…" action row and other folder *actions* stay Ledger Green: green remains the color of doing, profile hues the color of being.

Legacy folders with no stored `profileID` already resolve to Work Trip everywhere (the documented lazy-migration default); they adopt the Work Trip suitcase identity with no migration. Unknown profile IDs (e.g. a future preset synced from a newer build) fall back to the Custom identity (`folder.fill` + Ledger Green).

The profile picker in the folder create/edit sheet shows each profile's identity glyph next to its name, so the choice previews the folder's future appearance. The Edit Folder "Profile" value row may also carry the glyph; the archived-folders entry row keeps its `archivebox` affordance (it is a container of folders, not a profile).

## 5. Edge cases

- **Folder edited beyond its profile** (user browses in built-ins from other profiles): cross-profile combinations can collide (e.g. adding `pharmacy` to a folder containing `food` — both orange). Accepted: permanent per-category identity is the higher-value invariant (D1), the snapshot cap keeps collisions rare, and symbols + labels still disambiguate. The Browse list is grouped by profile, where distinctness holds row-by-row.
- **Receipt whose category is out-of-set** (moved folders): the "Current" attention chip renders with the category's permanent hue as today; no change.
- **Orphaned/unknown category IDs**: unchanged — `CategoryResolver` falls back to gray + `tag.fill`.
- **Stale CloudKit peer running the previous build** reads a snapshot written by this build: unknown hue raw values (e.g. `plum`) hit the existing gray fallback; nothing breaks. Built-ins still render from that old build's catalog.
- **`Other`** remains gray and locked in every flow, including D6 auto-assignment.
- **Folder identity when the user has heavily edited categories**: the icon reflects the folder's *profile*, not its current category set — a Medical Claim folder keeps the mint cross even if the user swapped in conference categories. Identity is stable by design; the category dots reflect actual contents.
- **Changing a folder's profile in the edit sheet** (where allowed today): the identity glyph follows the new profile immediately, since it derives from the stored `profileID` with no per-folder state.
- **Increased Contrast / grayscale**: color was never the sole carrier — every surface pairs hue with a unique SF Symbol and a text label; the folder-card dots remain a summary adjacent to explicit text ("12 receipts"), not an information-bearing legend.

## 6. Accessibility & localization

- **No new or changed user-facing strings.** No `Localizable.xcstrings` changes; category display names, keys, and plural variants are untouched. (Per house rules this is stated, not implied: the key/value table for this spec is empty.)
- **No new accessibility identifiers.** Existing `review.category.<id>` identifiers and VoiceOver labels (category display names) are unchanged; color is never announced.
- The folder identity glyph is decorative: it stays hidden from VoiceOver (the folder row/card is already a grouped element labeled by folder name, total, and receipt count), and profile rows in the picker keep the localized profile name as their label.
- Dynamic Type behavior of the selector (tiles → grid → AX rows) is untouched.
- Contrast: the white glyph on each of the three new light-appearance hues must be at least as legible as the existing worst case (`ExpenseFood` orange, the established precedent); verify in both appearances and under Increased Contrast per `DESIGN.md` dark-mode rules.

## 7. Test impact

- **ExpenseCore — catalog invariants (new test file):** every built-in category has a hue; `other` is gray and is the only gray; for every profile in `FolderProfileCatalog.all` (plus the custom-profile seed and `FolderCategorySnapshot.unfiledDefault`), `defaultCategoryIDs ∪ suggestedCategoryIDs` maps to pairwise-distinct hues (gray/`other` excluded). This test makes D3's table executable so future catalog/profile edits cannot silently reintroduce a collision.
- **ExpenseCore — codable compatibility:** each of the nine legacy raw values decodes to its mapped hue; unknown strings decode to gray; encoding emits new-vocabulary values; a snapshot round-trip preserves hues.
- **ExpenseCore — custom auto-assignment:** deterministic first-available assignment against a seeded snapshot; least-used fallback when all hues are taken; gray never assigned; D5 heal assigns only to gray customs and leaves colored ones alone.
- **ExpenseCore — profile identity invariants:** every profile in `FolderProfileCatalog.all` has a symbol and a hue; hues are pairwise distinct across the ten presets; Custom resolves to `folder.fill`; an unknown profile ID falls back to the Custom identity.
- **App target:** the `CategoryColorRole → asset name` mapping covers every case and every named asset exists (extend the existing asset-presence style of test if present, else add one); update any tests referencing renamed `Expense*` color assets or legacy role raw values (`ReceiptsViews`/selector snapshot-style tests, if any).
- New app-target test files require `xcodegen generate` before they build.
- Manual verification per `CLAUDE.md`: Medical Claim Edit Folder sheet and folder detail against the amended `ui-spec.html` (the `design-spec` preview server), light and dark.

## 8. Acceptance criteria

1. The Medical Claim Edit Folder sheet shows ten distinct hues across its default + suggested categories (per D3's table); no two rows share a color. The same holds for every other profile.
2. Folder-card category dots on Folders home show one dot per used category in distinct hues for any single-profile folder.
3. A given built-in category renders the identical hue in the folder sheet, category selector, breakdown rows, receipt rows, filter menu, suggestion chips, and Mac detail pane, in light and dark.
4. Legacy folders (pre-change snapshots) show the new hues for built-ins with no migration, no CloudKit write storm, and no version bump; their gray customs adopt a color after the folder is next saved.
5. A newly created custom category receives a non-gray hue absent from the folder's snapshot; creating the same custom in the same folder state always yields the same hue.
6. `Other` is gray everywhere; Ledger Green appears on no category surface; no red or pink hue exists in the palette; plum reads as purple, not pink, in both appearances.
7. The three new hues are distinguishable from their nearest palette neighbors at glyph-tile and folder-dot sizes in both appearances, and white glyphs on them are no less legible than on `CategoryOrange`.
8. On the Folders tab, folders of different profiles show different identity glyphs (symbol + hue) with the current tile geometry; two Medical Claim folders show the same mint cross; a legacy pre-profile folder shows the Work Trip suitcase; the "New Folder…" row and archived entry row are unchanged.
9. The profile picker previews each preset's identity glyph; changing a folder's profile updates its glyph everywhere with no migration.
10. `DESIGN.md` (frontmatter palette, §2 table + rewritten hard rule, "sixteen custom pairs", §11 guide, and a new folder-identity rule alongside the category-color rule) and `design/ui-spec.html` (Folders home and folder sheet mockups) are updated in the same commit; the removed category-role restraint passages no longer appear anywhere in the docs.
11. `cd ExpenseCore && swift test` and the app simulator test suite pass.
