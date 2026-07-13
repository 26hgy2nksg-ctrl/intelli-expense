# SPEC: Category color roles — retire the grey wall

**Status:** Draft — ready for implementation
**Owner screens:** Folder create/edit sheet ([GroupsViews.swift](../../IntelliExpense/UI/GroupsViews.swift)), Review & Confirm and Receipt Detail category selector ([CategoryDisplay.swift](../../IntelliExpense/UI/CategoryDisplay.swift), [ReviewViews.swift](../../IntelliExpense/UI/ReviewViews.swift)), folder detail breakdown rows and receipt list ([ReceiptsViews.swift](../../IntelliExpense/UI/ReceiptsViews.swift)), Mac detail pane ([MacReceiptDetailPane.swift](../../IntelliExpense/Mac/MacReceiptDetailPane.swift))
**Owner logic/assets:** [ExpenseCategory.swift](../../ExpenseCore/Sources/ExpenseCore/Domain/ExpenseCategory.swift), [CategoryCatalog.swift](../../ExpenseCore/Sources/ExpenseCore/Domain/CategoryCatalog.swift), [Assets.xcassets](../../IntelliExpense/Resources/Assets.xcassets)
**Docs this spec amends:** `DESIGN.md` §2 (token table; the "nine custom pairs" count), `design/ui-spec.html` (token/color-set list, category tile mockups), and `SPEC-expense-profiles-and-visible-categories.md` §D10 (superseded in part by this spec)

## 1. Problem

The expense-profiles feature expanded the built-in category catalog from 5 to ~70 entries, but kept the original five color roles (food/orange, lodging/indigo, travel/blue, transport/teal, generic/gray) per its D10 "color stays restrained" decision. In practice almost every new category was assigned `generic`, so entire profiles render as a wall of identical grey glyph tiles — the Business Purchases folder sheet shows Supplies, Software, Printing, Shipping, Professional Fees, and Equipment all in the same grey square. The grey repetition defeats the purpose the design system assigns to category color ("color that always means the same thing becomes navigation", DESIGN.md §2) and reads as unfinished rather than restrained.

## 2. Goals

- Every profile's default visible-category set shows meaningful color variety; no default profile renders more than its `Other` row (plus at most two paperwork categories) in grey.
- Color continues to mean *semantic role*, not per-category identity: a small, fixed set of roles that group related categories, exactly as the existing five roles do.
- Existing folders (created before this change) pick up the new colors without a data migration.
- All existing surfaces get the improvement for free through the shared `CategoryGlyph` tile and `FolderCategory.color` — no per-screen work.

## 3. Non-goals

- No per-category custom colors, no color picker, no rainbow taxonomy (DESIGN.md §2 hard rule stands).
- No change to custom folder-local categories: they stay neutral grey with a user-selectable symbol (profiles spec §D10 rule 2 stands).
- No change to symbols, category IDs, snapshot JSON shape, CSV export, or the `Other` category.
- No red or pink family colors anywhere (DESIGN.md "No red" hard rule).
- No changes to widgets: DESIGN.md already forbids expense-type color in widget surfaces.

## 4. Design decisions

### D1 — Expand the role palette from five roles to nine, not to per-category colors

DESIGN.md §2 constrains us: "Dynamic/custom categories reuse this restrained role palette; they never introduce a new color picker or rainbow taxonomy." The profiles spec §D10 additionally observed that "one permanent color per category becomes noisy". Both rules are satisfied by adding **four new semantic roles** that group the currently-grey categories the same way the original five group trip expenses:

| Role | Meaning | Example categories |
|---|---|---|
| `services` | Work performed by people: trades, professionals, care of things | Professional Fees, Labor, Repairs, Cleaning, Insurance, Staff |
| `goods` | Physical things purchased | Supplies, Materials, Tools, Paint, Gifts, Accessories |
| `tech` | Technology, connectivity, and equipment | Software, Equipment, Wi-Fi/Tech, Printing, Audio/Visual |
| `health` | Medical and wellbeing | Pharmacy, Consultation, Dental, Hospital, Therapy |

Considered and rejected:
- *Per-profile accent color* (all of a folder's categories share one hue): destroys the cross-folder rule that "category colors only ever mean category role — used identically" everywhere; the same Fuel glyph would change color between Vehicle Costs and Client Visit folders.
- *One color per category* (~70 hues): explicitly rejected by profiles spec §D10; indistinguishable hues at 22–28 pt tile sizes.
- *Hashing category ID to a palette*: colors would carry no meaning, violating "color that always means the same thing becomes navigation".

### D2 — Four new asset-catalog token pairs in the Apple system-hue families

DESIGN.md §2 requires every custom color to be a named asset-catalog pair with Any + Dark appearances ("Nine custom pairs, defined once… feature code references the named color") and to brighten in dark "the way Apple's do: deep pigment on white, luminous on black". The existing `ExpenseTaxi` sets the precedent for a custom-tuned hue that "brightens in step with" its system cousin.

New token pairs (light / dark), following that model:

| Token | Light | Dark | Basis |
|---|---|---|---|
| `ExpenseServices` | `#AF52DE` | `#BF5AF2` | systemPurple |
| `ExpenseGoods` | `#A2845E` | `#AC8E68` | systemBrown |
| `ExpenseTech` | `#1E96D1` | `#4CC2FF` | systemCyan family, deepened in light for white-glyph contrast and separation from `ExpenseFlight` blue |
| `ExpenseHealth` | `#0E9F8E` | `#3BD6C3` | mint family, deepened for white-glyph contrast and separation from `ExpenseTaxi` teal |

Values for `ExpenseTech`/`ExpenseHealth` may be tuned during implementation **within the same hue family** to pass the two checks in §5 (white-glyph legibility; side-by-side distinguishability from their neighbors) — the checks are acceptance criteria, the exact hex is not. This amends DESIGN.md's "Nine custom pairs" to **thirteen**; the DESIGN.md §2 token table, the dark-mode token pair table, and the `ui-spec.html` color-set list must all gain the four rows in the same change (anti-drift rule: mockups and rules never lag the shipped app).

Red and pink families were considered for health (Apple Health's identity) and rejected: DESIGN.md bans red outright, and pink is close enough to read as alarm.

### D3 — Role assignment for every built-in category

The single source of truth stays the built-in catalog in `CategoryCatalog.swift`; this table is the complete reassignment (categories not listed keep their current role):

| New role | Category IDs |
|---|---|
| `services` | `laundry`, `registration`, `professional_development`, `tips`, `professional_fees`, `advertising`, `utilities`, `bank_fees`, `insurance`, `labor`, `electrical`, `plumbing`, `service`, `repairs`, `washing`, `lease_finance`, `utilities_setup`, `cleaning`, `venue`, `staff`, `installation`, `repair`, `warranty_plan`, `service_visit`, `insurance_premium` |
| `goods` | `supplies`, `materials`, `client_materials`, `booth_display`, `building_materials`, `tools`, `fixtures`, `paint`, `rental_equipment`, `tires`, `oil`, `packing`, `storage`, `decor`, `gifts`, `purchase`, `accessories`, `replacement_parts` |
| `tech` | `business_calls`, `wifi_tech`, `printing`, `software`, `equipment`, `audio_visual` |
| `health` | `consultation`, `pharmacy`, `tests_labs`, `dental`, `vision`, `hospital`, `therapy`, `medical_equipment`, `medical` |
| `transport` (existing role, new members) | `shipping`, `delivery`, `movers`, `truck_rental` |
| `travel` (existing role, new member) | `baggage` |
| stays `generic` | `other` (locked, by definition), `permits`, `vehicle_registration`, all custom categories |

Rationale for the deliberate grey remainder: `permits` and `vehicle_registration` are pure paperwork with no natural role, and keeping a small grey contingent preserves grey's meaning ("uncategorized/administrative") instead of forcing every category into a colored bucket. Note `insurance_premium` sits in `services` alongside `insurance` — same real-world thing, same color, even though it appears in the Medical Claim profile.

### D4 — Built-in visual metadata resolves catalog-first; snapshots keep membership and order

Folder snapshots are self-contained (`FolderCategory` stores its own symbol and color role), so every existing folder has `generic` frozen into its persisted JSON. A data migration that rewrites every folder's snapshot was considered and rejected: it touches every `ExpenseGroup` record, generates CloudKit churn across devices, and still cannot fix peers that sync a stale snapshot later.

Instead, resolution order changes for **built-in IDs only**: when displaying a category whose ID exists in the built-in catalog, the catalog's current `symbolName` and `colorRole` win over the snapshot's stored copy. The snapshot remains authoritative for (a) which categories are visible and their order, and (b) all display metadata of custom categories (which never exist in the catalog). The stored metadata also remains the last-resort fallback for IDs the running catalog no longer knows (a newer peer's built-in). This means color/symbol refreshes ship as catalog edits forever after, with no migrations. The change lives in the shared resolver (`CategoryResolver` / the display extensions in `CategoryDisplay.swift`), so all surfaces — selector tiles, breakdown rows, featured chips, receipt rows, Mac pane — update together.

### D5 — CloudKit and old-version compatibility needs no version bump

New snapshots written by this version will carry the new role raw values (e.g. `services`) in their JSON. An older app version decoding that snapshot already falls back to `generic` for unknown role strings — it renders today's grey, which is a graceful degrade, not a break. The snapshot `version` stays 1: the shape is unchanged, and the existing unknown-role fallback is the compatibility mechanism (profiles spec §6 contract preserved).

### D6 — Selection tint follows automatically; verify, don't redesign

The category selector's selected state tints its background with the category color at low opacity and strokes with the full color. This behavior is unchanged; the four new hues simply flow through. The "one hero number per screen" and two-element glass rules are untouched — category color remains "an accent on glyph tiles and selected states only; it does not create large filled surfaces" (profiles spec §D10 rule 3, which this spec keeps).

## 5. Edge cases

- **Existing folders, existing receipts:** via D4, a folder created last week shows the new colors everywhere immediately, with no writes to its record. Its snapshot JSON is rewritten (picking up new role values) only when the user next edits the folder's categories, which is the existing save path.
- **Out-of-set "Current" chip** (receipt moved between folders): resolved through the same resolver, so it gets the new color plus the existing amber attention ring; the amber ring must remain distinguishable on all nine role colors, in both appearances.
- **Orphaned/unknown IDs:** unchanged — humanized grey fallback.
- **Mint-vs-teal adjacency:** the Medical Claim profile shows `transport` (teal) directly beside `health` (mint family) categories in one list. The two tiles must be distinguishable side by side at the smallest glyph size in both appearances; if not, deepen `ExpenseHealth` toward green per D2.
- **Cyan-vs-blue adjacency:** `travel` (blue) and `tech` (cyan) co-occur in Conference and Event profiles; same side-by-side check.
- **White glyph legibility:** all four new fills carry the standard white SF Symbol glyph; verify in dark mode especially (luminous fills), and under Increased Contrast (DESIGN.md dark-mode rule: "re-verify contrast in dark").
- **Old device on the same iCloud account:** sees grey for the new roles (D5) — acceptable and temporary.

## 6. Accessibility & localization

- **No new strings.** No `Localizable.xcstrings` changes: colors carry no text, and no user-facing copy changes. (Stated per the anti-drift rule that localization is enumerated, never implied — the enumeration here is the empty set.)
- **No new accessibility identifiers.** Existing `review.category.<id>` identifiers are unchanged.
- **Color is never the sole differentiator:** every surface already pairs the colored tile with an SF Symbol *and* a text label; VoiceOver output is unchanged.
- Dynamic Type and AX-size layouts are untouched (tile → row adaptation already exists in the selector).

## 7. Test impact

ExpenseCore (`swift test`):
- A catalog audit test asserting every built-in category's role matches the D3 table — in particular, that the only `generic` built-ins are exactly `other`, `permits`, `vehicle_registration`. This is the regression fence against future categories silently defaulting to grey.
- Resolver tests for D4: a snapshot containing a built-in ID with stale `generic` metadata resolves to the catalog's current role/symbol; a snapshot's custom category keeps its stored metadata; an ID unknown to both stays on the humanized grey fallback.
- A decoding test confirming an unknown role raw value still falls back to `generic` (D5 contract).

App target:
- The role→asset-token mapping in `CategoryDisplay.swift` must cover the four new roles (exhaustive by construction); a unit test asserts each role's named color loads from the asset catalog, catching a missing or misnamed colorset.
- Snapshot/UI verification of the folder sheet and category selector in light and dark via the existing test scheme.

## 8. Acceptance criteria

1. The New Folder sheet for each of the ten profiles shows at most `Other` plus two paperwork rows in grey; all other default categories render a non-grey role color.
2. A folder created before this change shows the new colors in its sheet, selector, breakdown rows, and receipt list without any migration step.
3. The four new color tokens exist as asset-catalog pairs with Any + Dark appearances; no raw hex and no `colorScheme` branches appear in feature code.
4. Side-by-side distinguishability: teal/mint tiles (Medical Claim) and blue/cyan tiles (Conference, Event) are tellable apart at selector tile size in light, dark, and Increased Contrast.
5. White glyphs are legible on all four new fills in both appearances.
6. The same category ID renders the same color on every surface (selector, breakdown, chips, receipt rows, Mac pane) and in both appearances.
7. `DESIGN.md` §2 and `design/ui-spec.html` are updated in the same commit: token table rows for the four pairs, custom-pair count corrected from nine to thirteen.
8. CSV export, snapshot JSON version, category IDs, and all localized strings are byte-identical to before this change.
9. All ExpenseCore and app tests in §7 pass; existing suites stay green.
