# SPEC — Native Mac folder-editor modal adaptation

**Status:** implemented and verified (2026-07-11)
**Owner screens/files:** Mac New/Edit Folder presentation (`IntelliExpense/Mac/MacContentView.swift`), shared folder editor (`IntelliExpense/UI/GroupsViews.swift`, `GroupEditorSheet`), folder category modal family (`IntelliExpense/UI/CategoryComposer.swift`: `BrowseCategoriesSheet`, `AddCustomCategorySheet`, `ReassignCategorySheet`), new shared platform-presentation support (`IntelliExpense/UI/PlatformPresentationSupport.swift`), Mac UI coverage (`IntelliExpenseMacUITests/IntelliExpenseMacUITests.swift`), Mac source-contract coverage (`IntelliExpenseTests/MacVisualPolishTests.swift`)
**Docs this spec amends:** `DESIGN.md` §10 (Mac modal/form adaptation rules), `design/ui-spec.html` `#mac` (New/Edit Folder, Browse Categories, and Add Custom Category modal states), `CLAUDE.md` (current iPhone-only platform statement and shared-UI verification guidance)
**Related specs:** `SPEC-mac-app.md` (native Mac doctrine), `SPEC-mac-visual-polish.md` (existing detail-pane adaptation), `SPEC-expense-profiles-and-visible-categories.md` (folder editor and category behavior; behavior remains authoritative)

---

## 1. Problem and confirmed root cause

The Mac shell and receipt detail pane are platform-adapted, but the New/Edit Folder modal family is not. Current screenshots show three distinct symptoms:

1. **New Folder** uses the automatic macOS `Form` presentation: labels and controls float in a loose columns layout, category rows inherit phone-oriented density, and the content has no coherent grouped reading column.
2. **Browse Existing Categories** collapses to navigation/search chrome plus a Done button. Its `List` receives no useful content viewport, so no category rows are visible even though the model supplies them.
3. **Add Custom Category** exposes the same automatic columns form inside a nearly parent-width nested sheet. The name row and symbol grid read as an enlarged phone form rather than a bounded Mac editor.

This is one causal chain, not three independent polish defects:

- `MacContentView` presents the shared `GroupEditorSheet` directly for both create and edit.
- `GroupEditorSheet` contains a plain `Form` and has no Mac form style or presentation-sizing contract.
- `CategoryComposerSections` presents `BrowseCategoriesSheet` and `AddCustomCategorySheet` from inside that form. Both nested sheets also rely on automatic presentation sizing; the browse sheet's flexible `List` has no intrinsic height with which to establish a useful Mac sheet.
- `AddCustomCategorySheet` is another plain `Form`, so macOS selects its automatic form style rather than the grouped form language already used by `MacReceiptReviewPane` and `MacReceiptDetailPane`.
- The original profile/category feature specified only “The Mac app uses the same profile/category catalog and folder snapshots.” It correctly kept the model shared, but did not define Mac presentation geometry or modal interaction. The implementation therefore passed macOS build verification while retaining iPhone presentation assumptions.
- Existing Mac UI tests never open New Folder or either nested category sheet. They cover the empty receipt detail state and the receipt-detail toolbar/pager only, so the broken modal geometry has no regression guard.
- Repository guidance still calls the product “iPhone only” in `CLAUDE.md`, despite the native Mac target being present in `project.yml`, `PRD.md`, and `DESIGN.md`. That documentation drift makes future shared-screen work likely to repeat the omission.

The defect is therefore a missing **shared behavior / platform-native presentation** boundary. Data, validation, localization, and category behavior should remain shared; form style, sheet sizing, density, focus, and keyboard behavior must adapt on macOS.

### Apple API grounding

The offline Apple docset (version 24703) confirms the intended native tools:

- SwiftUI `FormStyle.grouped`, path `/documentation/swiftui/formstyle/grouped`, supports macOS 13.0+ and provides visually grouped sections with leading-aligned labels and trailing-aligned controls.
- SwiftUI `View.presentationSizing(_:)`, path `/documentation/swiftui/view/presentationsizing(_:)`, supports macOS 15.0+ and exists specifically to define the size proposed to sheet content and how a presentation reacts to content-size changes.
- `PresentationSizing.form`, path `/documentation/swiftui/presentationsizing/form`, is the system sizing intended for forms.
- `PresentationSizing.page`, path `/documentation/swiftui/presentationsizing/page`, provides a page-like proposal intended for informational or compositional content, which fits searchable category catalogs better than an intrinsically sized toolbar shell.
- `PresentationSizing.fitted`, path `/documentation/swiftui/presentationsizing/fitted`, documents that resizable Mac presentations must also declare sensible frame bounds. This spec does not use fitted sizing as a substitute for choosing the correct form/page role.

## 2. Goals

- Make New Folder and Edit Folder feel like native Mac editors while preserving the exact shared folder/profile/category behavior.
- Give every nested category modal a deliberate Mac presentation role so content never collapses, over-expands, or inherits an accidental phone shape.
- Reuse the grouped-form anatomy already proven in the Mac review and receipt-detail panes.
- Preserve iPhone layout and behavior exactly; this is a macOS presentation adaptation, not a cross-platform redesign.
- Add end-to-end Mac UI coverage that opens, interacts with, dismisses, and returns from every affected modal state.
- Correct repository guidance so future shared UI specs must state and verify their Mac effect.

## 3. Non-goals

- No category-model, folder-profile, persistence, CloudKit, export, or agent-bridge changes.
- No changes to the order, copy, validation, nine-category cap, `Other` lock, suggestion logic, built-in matching, or reassignment semantics from `SPEC-expense-profiles-and-visible-categories.md`.
- No Mac-only duplicate of `GroupEditorSheet` or the composer model.
- No custom window chrome, custom sheet background, fake glass, manually drawn title bar, or new color/type token.
- No broad audit or redesign of unrelated Mac sheets such as receipt image viewing, export readiness, or Settings.
- No iPad target and no iPhone visual change.

## 4. Design decisions

### D1 — Keep one editor behavior; add a narrow platform-presentation seam

`GroupEditorSheet`, `FolderCategoryComposerModel`, `BrowseCategoriesSheet`, `AddCustomCategorySheet`, and `ReassignCategorySheet` remain shared views and state. A small support surface in `IntelliExpense/UI/PlatformPresentationSupport.swift` owns the platform-specific form style, presentation role, and bounded Mac geometry used by this modal family. On iOS the support surface preserves the current presentation unchanged.

Rule satisfied: `DESIGN.md` §10 says the Mac app is the same product, not a second design system. `SPEC-mac-app.md` D4 says shared behavior stays shared while density and idiom adapt. This seam follows the existing `ToolbarPlacementSupport.swift` pattern rather than spreading conditional branches through feature code.

Considered and rejected: a Mac-only `MacGroupEditorSheet`. It would duplicate profile-change prompts, save validation, category invariants, reassignment behavior, and localization, creating two editors that can drift.

### D2 — Assign semantic presentation roles instead of hardcoding one sheet rectangle

The Mac modal family has two roles:

- **Form editors:** New/Edit Folder and Add Custom Category use the system form presentation role. They should open at a comfortable Mac form width, remain vertically scrollable when content grows, and avoid expanding to the parent window's width.
- **Catalog/selection sheets:** Browse Existing Categories and Reassign Receipts use the system page presentation role. Their list receives a real content viewport on first presentation, remains scrollable, and may resize within sensible bounds without collapsing to toolbar height.

The sizing role is applied to the presented content root, where SwiftUI evaluates presentation sizing. Any explicit frame bounds exist only to establish safe minimum/maximum behavior for the Mac's resizable catalog sheets; they are not a universal fixed width/height and do not override system Dynamic Type or localization growth.

Rule satisfied: `DESIGN.md` §6 budgets sheet chrome to the system, and §10 requires native Mac adaptation. Apple documents `presentationSizing` as the system mechanism for exactly this responsibility.

Considered and rejected: one fixed 500×600 frame on every sheet. It would treat short forms and searchable catalogs as the same surface, clip at large text sizes, and recreate the hardcoded-layout problem this spec is fixing.

### D3 — New/Edit Folder uses the established grouped Mac form anatomy

On macOS, `GroupEditorSheet` uses the grouped form style already present in `MacReceiptReviewPane` and `MacReceiptDetailPane`:

- Details, Categories, Suggestions, and category actions read as visually grouped sections in one leading-aligned content column.
- The form owns scrolling; title and Cancel/Save remain in the system navigation/toolbar chrome.
- Save is the default keyboard action when enabled. Cancel responds to the standard cancel action. Existing disabled-state logic remains authoritative.
- Name receives initial focus for a new folder. Edit Folder keeps predictable keyboard traversal without stealing focus from the existing value.
- Category glyphs, remove controls, locked `Other`, suggestion pills, Ledger Green accent, and semantic colors remain unchanged.

Rules satisfied: `DESIGN.md` §4 says “The New Folder sheet stays an inset-grouped form,” §11 says “Inset-grouped lists, 16pt margins, system radii,” and the base-4/8 grid remains authoritative. The Mac adaptation changes system metrics, not typography roles or token values.

### D4 — Browse Existing Categories is a real searchable catalog on first frame

The Mac browse sheet opens with a usable list viewport containing the current sections and rows; it must never render only a title, search field, divider, and Done button.

- The sheet uses the catalog/page presentation role from D2.
- Search remains in system toolbar/search chrome and receives focus when the user explicitly clicks it; opening the sheet does not hide the catalog behind an empty search state.
- Suggested, other-profile, and all-category sections retain their current ordering and data semantics.
- Adding a category dismisses the browse sheet and returns focus to the Browse Existing Categories row in the parent editor; the newly added category is immediately visible before locked `Other`.
- Empty search uses the existing `ContentUnavailableView.search` state inside the same stable viewport, so clearing the query restores rows without resizing the sheet around the state change.
- Done remains the explicit no-change dismissal action.

Rule satisfied: `DESIGN.md` §4 defines Browse Existing Categories as the escape hatch into the built-in catalog; a collapsed list makes that required path functionally unavailable.

### D5 — Add Custom Category is a compact grouped editor, not a stretched phone form

On macOS, Add Custom Category uses the grouped form style and form presentation role:

- Name and Symbol remain separate grouped sections.
- The curated symbol grid keeps the existing symbols, selection color, and model behavior. It adapts its column count within the form's proposed width rather than forcing the sheet wider.
- The name field receives initial focus. Add becomes the default action only when `customCategory` is valid; Cancel remains the standard cancel action.
- A built-in name match remains visible before the custom-creation path and uses the existing-category action unchanged.
- Adding or choosing an existing category dismisses to the parent editor, restores focus to Add Custom Category, and shows the new selection before locked `Other`.

Rule satisfied: `DESIGN.md` §4 requires a curated symbol picker and the single Ledger Green accent; grouped system surfaces preserve that language without new decoration.

### D6 — Reassignment receives the same catalog contract before it becomes the next defect

`ReassignCategorySheet` is reached from the same editor when a used category is removed. Although it is not shown in the supplied screenshots, it has the same `NavigationStack` + flexible `List` + automatic sheet sizing shape as the collapsed browse sheet. It therefore adopts the catalog/page role from D2 in this spec.

The copy, receipt count, destination choices, Keep Category action, and atomic reassignment behavior remain unchanged. The first destination row must be visible when the sheet opens, and focus returns to the category row after dismissal.

This is in scope because it is the same confirmed root-cause pattern in the same user flow, not a broad adjacent-sheet cleanup.

### D7 — Preserve nested-sheet hierarchy and system chrome

Browse, Add Custom, and Reassign remain child sheets over New/Edit Folder. The parent editor stays dimmed and inactive while a child is open; only one child can be presented at a time. Dismissing a child never dismisses the parent or loses unsaved name/profile/category edits.

No custom material, background, radius, shadow, or overlay is added. The system continues to own sheet curvature, focus ring, dimming, toolbar, and Liquid Glass treatment.

Rules satisfied: `DESIGN.md` glass budget says sheets are system-owned, and the dark-mode rule says layout does not fork by appearance.

### D8 — Make cross-platform impact an explicit repository contract

The implementation change amends:

- `DESIGN.md` §10 with a Mac modal rule: shared form behavior remains shared, Mac forms use grouped style, and every Mac sheet must declare a semantic form/page presentation role when automatic sizing cannot express its content.
- `design/ui-spec.html` `#mac` with canonical Mac mockups for New/Edit Folder, Browse Existing Categories, and Add Custom Category, plus the modal-role mapping.
- `CLAUDE.md` so platform guidance says iPhone + native macOS rather than iPhone-only, and shared UI work must verify both affected platform lanes or explicitly state why one is unaffected.

This closes the documentation condition that allowed a shared iPhone feature to be considered complete after only a macOS build.

## 5. Edge cases

- **Small app window (900×600 minimum):** the parent and nested sheets remain fully operable; content scrolls within its surface rather than clipping toolbar actions.
- **Large app window:** form sheets stay bounded and readable instead of stretching with the parent; catalog sheets remain page-like rather than becoming full-window overlays.
- **Nine selected categories:** the parent editor scrolls; Save remains reachable in the toolbar and locked `Other` remains last.
- **All built-ins already selected:** Browse shows the existing selected/disabled state in a stable viewport; it does not collapse because few actionable rows remain.
- **Empty search result:** the search-empty state fills the catalog body; clearing search restores rows without changing the sheet's outer size.
- **Long localized profile/category names:** labels wrap or yield horizontal space; no minimum-scale-factor or truncation workaround. The symbol grid yields columns before text clips.
- **Accessibility text sizes:** grouped sections expand and scroll vertically; action chrome stays reachable; no fixed-height content region clips rows.
- **Rapid child switching:** Browse must fully dismiss before Add Custom can present, and vice versa; no overlapping sheet state or lost parent edits.
- **Cancel child after parent edits:** all parent edits remain exactly as they were before child presentation.
- **Edit Folder with a used category:** Reassign opens with destination rows visible, Keep Category dismisses only the child, and successful reassignment returns to the still-open editor.
- **Light/dark, Increased Contrast, Reduce Transparency:** geometry is unchanged; semantic surfaces and system sheet chrome adapt without feature-level appearance branches.
- **RTL:** all alignment uses leading/trailing semantics; grouped form labels and controls mirror through the system.

## 6. Accessibility and localization

### Localization

No user-facing copy changes. No new String Catalog keys, changed values, or plural variants are required. Existing keys remain authoritative:

| Surface | Existing keys reused |
|---|---|
| New/Edit Folder | `groups.create`, `group.editor.edit.title`, `common.cancel`, `common.save`, `group.editor.*` |
| Browse | `folder.categories.browse`, `folder.categories.browse.*`, `common.done` |
| Add Custom | `folder.categories.addCustom`, `folder.categories.custom.*`, `folder.categories.add.action` |
| Reassign | `folder.categories.reassign.*`, `folder.categories.keep`, `groups.receipt.count` |

Locale-formatted dates and counts continue through Foundation and the existing localized format strings.

### Accessibility identifiers

Existing control identifiers remain stable. Add only root/body identifiers required for reliable Mac UI assertions:

| Identifier | Element |
|---|---|
| `mac.folderEditor.sheet` | New/Edit Folder presented root |
| `mac.folderEditor.form` | Scrollable grouped form body |
| `mac.folderCategories.browse.sheet` | Browse presented root |
| `mac.folderCategories.browse.list` | Browse catalog list/body |
| `mac.folderCategories.custom.sheet` | Add Custom presented root |
| `mac.folderCategories.custom.form` | Add Custom grouped form body |
| `mac.folderCategories.reassign.sheet` | Reassign presented root |
| `mac.folderCategories.reassign.list` | Reassign list/body |

VoiceOver reads the title first, then grouped sections in visual order, then toolbar actions. Category rows remain combined elements with their existing label and selected/disabled state. Full Keyboard Access order follows the same visual order. After child dismissal, focus returns to the invoking row in the parent editor.

## 7. Test impact and verification

### Tests that should have caught this

The current Mac UI suite has no folder-editor flow, and `MacVisualPolishTests` asserts only receipt-detail source contracts. A successful Mac build therefore proved compilation and signing compatibility, not modal usability or geometry. The existing iPhone category UI tests cannot catch macOS automatic form style or sheet intrinsic sizing.

### Required automated coverage

Extend `IntelliExpenseMacUITests/IntelliExpenseMacUITests.swift` with seeded, independent tests:

1. **New Folder grouped editor:** open New Folder from the toolbar/menu; assert the root, form body, Details, Categories, and Save/Cancel controls exist; enter a name and traverse the profile/categories controls using keyboard navigation.
2. **Browse catalog first-frame content:** open Browse; assert the list body and at least one category row are visible without resizing the sheet; search for a known built-in category, add it, and verify the child dismisses while the parent remains open with the category selected.
3. **Browse empty-result stability:** enter a guaranteed-missing query, assert the search-empty state is visible inside the same non-collapsed sheet, clear it, and assert rows return.
4. **Add Custom editor:** open Add Custom; assert the grouped form, name field, symbol choices, Cancel, and disabled Add exist; enter a unique name, choose a symbol, add it, and verify the parent remains open with the custom category selected.
5. **Used-category reassignment:** launch a seeded folder whose receipt uses a removable category; attempt removal, assert the reassignment list has a visible destination on first frame, choose Keep Category, and verify only the child dismisses.
6. **Nested cancellation preservation:** edit name/profile/categories, open and cancel each child surface, and verify all unsaved parent values persist.

Frame assertions must verify behavior, not exact pixels: the child body has a positive usable viewport, first content is visible, toolbar controls do not overlap content, and form/page surfaces remain bounded within the host window. Do not snapshot one machine's exact sheet dimensions.

Extend `IntelliExpenseTests/MacVisualPolishTests.swift` (or a focused successor file) with source-contract checks that:

- all four modal roots use the shared platform-presentation support;
- Mac form surfaces resolve to grouped style;
- form and catalog roles remain distinct;
- `DESIGN.md`, `design/ui-spec.html`, and `CLAUDE.md` contain the new cross-platform contract.

### Regression and manual verification

- Existing iPhone category-composer UI tests pass unchanged, proving no iPhone presentation regression.
- Mac build and Mac UI-test lanes pass with the configured Mac development profile.
- Manual Mac pass at minimum and large window sizes, light/dark, an accessibility text size, Full Keyboard Access, and VoiceOver.
- Manual comparison against the three supplied failure states: no loose automatic columns in either form, no toolbar-only browse sheet, and no parent-width custom editor.

At spec-authoring time, the local `make test-mac` lane reaches the Mac target but stops before test execution because the configured Mac development profile does not include the selected Apple Development certificate. Implementation verification must repair or select a matching signing profile/certificate and then run the lane; a build-only substitute does not satisfy this spec.

## 8. Acceptance criteria

1. New Folder and Edit Folder on macOS render as bounded grouped forms using system sheet chrome; Details, Categories, Suggestions, Browse, Add Custom, Cancel, and Save are readable and keyboard reachable at first presentation.
2. Browse Existing Categories opens with a visible, scrollable catalog body and at least one category row when data exists; it never collapses to title/search/Done chrome. Search, empty results, add, and Done all work without resizing away the usable viewport.
3. Add Custom Category opens as a compact grouped form with Name and Symbol sections; the symbol grid adapts within the form width, and Add/Cancel preserve their current validation and dismissal semantics.
4. Reassign Receipts uses the same non-collapsing catalog presentation; Keep Category or a destination choice dismisses only the child sheet and preserves the parent editor state.
5. Nested sheets use only system material, dimming, focus rings, toolbar, and curvature. No custom glass, fixed universal sheet rectangle, raw color, fixed font size, or appearance-specific layout branch is introduced.
6. iPhone layout and behavior are unchanged. Shared category state, validation, localization, persistence, CloudKit, export, and agent behavior are unchanged on both platforms.
7. All new root/body accessibility identifiers exist; VoiceOver and Full Keyboard Access follow visual order; focus returns to the invoking parent control after child dismissal.
8. Mac UI tests exercise New/Edit Folder, Browse, Add Custom, and Reassign end-to-end, including first-frame content visibility and parent-state preservation. Existing iPhone tests remain green.
9. `DESIGN.md` §10, `design/ui-spec.html` `#mac`, and `CLAUDE.md` are amended in the implementation change so shared UI work can no longer be considered complete without explicit Mac impact and verification.
10. The repaired Mac signing/test lane passes; the implementation is not complete if only compilation succeeds or if modal tests are skipped.
