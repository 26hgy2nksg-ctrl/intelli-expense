# Spec: Choice-chip selection state on Review & Confirm

**Status:** ready for implementation
**Scope:** view layer (`IntelliExpense/UI/ReviewViews.swift`), form model (`IntelliExpense/Review/ReceiptReviewForm.swift`), String Catalog, unit tests. No changes to `ExpenseCore`, extraction, merge policy, or persistence.

---

## 1. Problem

On the Review & Confirm screen, ambiguous extracted fields render "Which is correct?" candidate chips (`ChoiceChips` in `IntelliExpense/UI/ReviewViews.swift`). Tapping a chip updates the field value, but the chips themselves never change appearance, so the user cannot tell which option is currently chosen. Field-verified on device (screenshot, 2026-07-05).

Root causes, confirmed in code:

1. `ChoiceChips` (ReviewViews.swift:230) never receives the current field value. All chips render identically with `.buttonStyle(.bordered)`; there is no selected state anywhere.
2. Chips render in the default blue tint, violating DESIGN.md's single-accent rule ("deliberately *not* default-blue").
3. The orange "Which is correct?" caption (`AttentionFieldEdge`) persists after a choice is made, implying the question is still open.
4. The **date** `ChoiceChips` is its own `List` row placed *after* the amount field (ReviewViews.swift:50–54), not adjacent to the `DatePicker` (line 41). On screen it appears as an orphan block the user cannot associate with any field. Currency/type/payment chips are similarly separate `List` rows split from their fields by row separators.
5. No `.selection` haptic on chip pick, despite DESIGN.md reserving the `chip_selection: .selection` token.
6. No `.isSelected` accessibility trait — VoiceOver users get zero indication of the chosen option.

## 2. Binding design references (read before coding)

The design system already specifies the missing state. These are requirements, not suggestions:

- `design/ui-spec.html` — `.cchip.sel` (lines ~91, ~188): selected chip = Ledger Green border, Ledger Green Soft fill, Ledger Green text. Layout of value + small reason line per the Review screen mockups. On layout, ui-spec.html wins.
- `DESIGN.md:181` — "Choice chips (ambiguity) are bordered rectangles … selected = Ledger Green fill".
- `DESIGN.md:273` — "Uncertain field → two chips + Edit + warm edge tint. **Confirmed → green check.**"
- `DESIGN.md:70` — haptic token `chip_selection: .selection`.
- Asset-catalog tokens already exist: `LedgerGreen.colorset`, `LedgerGreenSoft.colorset`, `AttentionFieldEdge.colorset` (in `IntelliExpense/Resources/Assets.xcassets`). Do **not** add hex literals or new colorsets.
- CLAUDE.md constraints apply: every user-facing string in `Localizable.xcstrings`; Dynamic Type only (no fixed point sizes); no red anywhere; no `colorScheme` branches in feature code.

Verified API availability (offline Apple docset; app targets iOS 26):

- `View.sensoryFeedback(_:trigger:)` — iOS 17.0+ (`/documentation/swiftui/view/sensoryfeedback(_:trigger:)`).
- `AccessibilityTraits.isSelected` — iOS 13.0+ (`/documentation/swiftui/accessibilitytraits/isselected`).

## 3. Requirements

### R1 — Selection is derived from the live field value (model layer)

Add per-field selection predicates to `ReceiptReviewForm` (`IntelliExpense/Review/ReceiptReviewForm.swift`). Selection must be **computed by comparing the choice's value against the form's current field value** — never stored as a "last tapped index". This keeps the UI truthful: if the user free-types a third value into the text field, both chips deselect automatically.

Comparison rules per field:

| Field | Predicate |
|---|---|
| vendor | `vendor.trimmingCharacters(in: .whitespacesAndNewlines) == choice.value.trimmingCharacters(in: .whitespacesAndNewlines)` |
| totalAmount | parsed `Decimal` of `amountText` (trimmed) `== choice.value`; unparseable text → not selected |
| date | `Calendar.current.isDate(date, inSameDayAs: choice.value)` |
| currency | `currencyCode.uppercased() == choice.value.uppercased()` (trim both) |
| expenseType | `expenseType == choice.value` (nil → not selected) |
| paymentMethod | `paymentMethod == choice.value` (nil → not selected) |

Suggested API (one method per field to avoid overload ambiguity between the two `String` fields):

```swift
func isVendorChoiceSelected(_ choice: ReceiptFieldChoice<String>) -> Bool
func isTotalAmountChoiceSelected(_ choice: ReceiptFieldChoice<Decimal>) -> Bool
func isDateChoiceSelected(_ choice: ReceiptFieldChoice<Date>) -> Bool
func isCurrencyChoiceSelected(_ choice: ReceiptFieldChoice<String>) -> Bool
func isExpenseTypeChoiceSelected(_ choice: ReceiptFieldChoice<ExpenseType>) -> Bool
func isPaymentMethodChoiceSelected(_ choice: ReceiptFieldChoice<PaymentMethod>) -> Bool
```

### R2 — Selected chip styling per design spec (view layer)

Rework the chip label in `ChoiceChips` to a custom style; pass an `isSelected: (ReceiptFieldChoice<Value>) -> Bool` closure into the component and wire each call site to the matching R1 predicate.

- **Selected:** `Color("LedgerGreenSoft")` fill, `Color("LedgerGreen")` border (~1.5pt, `RoundedRectangle(cornerRadius: 11, style: .continuous)` per ui-spec), `Color("LedgerGreen")` value text, plus a small leading `checkmark.circle.fill` (SF Symbol) so selection does not rely on color alone (HIG / color-blind users).
- **Unselected:** neutral border (`Color.secondary` at low opacity, e.g. `.opacity(0.25)`), `.primary` value text, clear fill.
- Use `.buttonStyle(.plain)` with explicit `background`/`overlay`/`foregroundStyle` — this removes the current default-blue tint. **No blue may remain.**
- Reason/evidence subtitle stays `.caption2` + `.secondary` in both states.
- Value text: raise `lineLimit` to 2 so options like "RAMADA BY WYNDHAM NAVI MUMBAI" remain comparable; keep the reason at `lineLimit(1)`.
- Fonts stay semantic text styles only (`.subheadline`, `.caption2`, …) — no fixed sizes.

### R3 — Prompt resolves once answered

In `ChoiceChips`, when any choice is selected (per R1), replace the orange "Which is correct?" caption with a confirmed caption: `checkmark.circle.fill` + new localized string `review.choice.confirmed` ("Confirmed"), both in `Color("LedgerGreen")`. When no choice matches (initial ambiguity, or user typed a custom value), keep the existing orange `review.choice.prompt` caption. Chips remain visible and tappable in both states so the user can switch.

### R4 — Attach every chip group to its field (layout)

Restructure the "Fields" section of `ReceiptReviewView` so each `ChoiceChips` lives **in the same `List` row as its field**, mirroring what `ChoiceTextField` already does for vendor/amount:

- `DatePicker` + `dateChoices` chips → one row (`VStack(alignment: .leading, spacing: 8)`). This fixes the orphaned date block.
- currency `TextField` + `currencyChoices` → one row.
- `ExpenseTypeSelector` + `expenseTypeChoices` → one row.
- payment segmented `Picker` + `paymentMethodChoices` → one row.

No visual separator may appear between a field and its own chips.

### R5 — Selection haptic

Add `.sensoryFeedback(.selection, trigger:)` so a chip pick fires the selection haptic (DESIGN.md `chip_selection` token). A simple approach: trigger on the relevant form field value (vendor string, amount text, date, …) or on a monotonically bumped local `@State` counter incremented inside `choose`. Must not fire on initial render.

### R6 — Accessibility

- Selected chip: `.accessibilityAddTraits(.isSelected)`; unselected: no trait.
- Chip accessibility label = formatted value; reason text as `accessibilityValue` (or appended to the label) so VoiceOver reads both.
- Keep the existing `.accessibilityElement(children: .contain)` on the group.
- Add stable accessibility identifiers for UI tests: pass an identifier prefix into `ChoiceChips` per field (e.g. `review.choice.vendor`) and tag chips `"\(prefix).\(index)"`.

### R7 — Localization

New String Catalog entries in `IntelliExpense/Resources/Localizable.xcstrings` (English only, following existing `review.*` key style):

- `review.choice.confirmed` — "Confirmed"

No other new user-facing strings. Do not hardcode any literal in views.

### R8 — Out of scope (do not build)

- The ui-spec's dashed "Edit" chip — the text field above is the editor; cut per "cut scope, not quality".
- Changes to merge policy, choice generation, or `ExpenseCore`.
- The richer per-field prompt copy ("Two possible totals found — …") — keep the single `review.choice.prompt`.
- Any red styling; any dashboard/summary changes.

## 4. Implementation notes

- `ChoiceChips` and `ChoiceTextField` are `private` in `ReviewViews.swift`; extend their initializers with the `isSelected` closure (and identifier prefix) rather than introducing new files.
- `parsedAmount` on the form is currently `private`; the amount predicate can reuse it internally — no need to expose it.
- `ReceiptFieldChoice` is `Equatable`; predicates compare **values**, not whole choices, because two choices can carry the same value with different reasons — if so, both may show as selected; that is acceptable and expected.
- Chips only render when `choices.count > 1` — keep this guard.

## 5. Tests (TDD — write these first)

Unit tests in `IntelliExpenseTests/ReceiptReviewFormTests.swift` (XCTest, `@MainActor`, existing builder style with `MergedReceipt`/`MergedField` — see `testReviewFormPrefillsPrimaryValuesAndSurfacesTwoAlternates` for the pattern):

1. **Initial selection reflects primary:** build a form with two vendor/amount/date options; assert the predicate is true for the primary choice and false for the alternate.
2. **Choosing flips selection:** call `chooseTotalAmount` with the alternate; assert predicates flip.
3. **Free-typed value deselects all:** set `amountText = "999.99"` (matching neither choice); assert both amount predicates false. Same for vendor with a custom string.
4. **Unparseable amount:** `amountText = "abc"` → both predicates false (no crash).
5. **Date same-day semantics:** date choice at a different time of the same day still selected; different day not selected.
6. **Currency case-insensitivity:** `currencyCode = "inr"` matches choice `"INR"`.
7. **Nil expenseType/paymentMethod:** predicates false.

## 6. Acceptance criteria

- [ ] On a receipt with ambiguous vendor/amount/date, exactly the chip matching the current field value shows the Ledger Green selected treatment (soft fill, green border, green text, checkmark); the other chip is neutral. No blue appears anywhere on the screen's chips.
- [ ] Tapping the other chip moves the selected treatment and updates the field; a selection haptic fires on device.
- [ ] Editing the text field to a custom value deselects both chips and the caption reverts to the orange "Which is correct?".
- [ ] When a chip is selected, the caption reads "Confirmed" with a green check instead of the orange prompt.
- [ ] The date chips render directly beneath the date picker (same row, no separator); likewise currency/type/payment chips beneath their controls.
- [ ] VoiceOver announces "selected" on the chosen chip and reads value + reason on each chip.
- [ ] All new strings resolve from the String Catalog (no key names visible in UI).
- [ ] Everything renders correctly in light **and** dark mode via the asset tokens (no `colorScheme` branches) and at large Dynamic Type sizes.

## 7. Verification commands

```bash
# Unit tests (includes new ReceiptReviewFormTests cases)
xcodebuild -project IntelliExpense.xcodeproj -scheme IntelliExpense \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' test

# Build only
xcodebuild -project IntelliExpense.xcodeproj -scheme IntelliExpense \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' build
```

Manual pass: scan (or simulate) a receipt that produces ≥2 candidates for vendor, amount, and date; walk the acceptance criteria in both color schemes and at an XL Dynamic Type size.
