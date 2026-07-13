# SPEC — Review & Confirm: Save/Discard redesign

**Status:** proposed
**Owner screen:** Review & Confirm (`IntelliExpense/UI/ReviewViews.swift`, `ReceiptReviewView`) — also inherited by manual entry, which is the same form
**Docs this spec amends:** `DESIGN.md` §4 (Save bar rule), `design/ui-spec.html` §review (savebar mockups)

---

## 1. Problem

Field evidence (device screenshot, amount field focused, decimal pad up):

1. **Keyboard sandwich.** The Save/Discard bar is a `safeAreaInset(edge: .bottom)`, so when the keyboard appears the bar rides on top of it. Bar (~150pt of button + hint + Discard + padding + material slab) plus keyboard (~300pt) leaves roughly one visible form row. The user is editing the amount and can barely see it.
2. **Destructive action in the blast radius.** The plain-text **Discard** sits directly under Save and, with the keyboard up, directly above the top row of the number pad. A missed tap on "2" or on Save can discard the receipt. The confirmation alert only fires when the form is dirty — a *clean* form discards instantly.
3. **Redundant discard affordance.** The navigation bar ✕ (`review.close`) and the footer **Discard** (`review.discard`) run the identical `requestDiscard()` path. Two affordances for one destructive action is one too many.
4. **No way to put the keyboard away.** The decimal pad has no return key, there is no keyboard toolbar Done, and the `List` has no `scrollDismissesKeyboard`. The keyboard can effectively only be dismissed by tapping a non-input row.
5. **Design drift.** DESIGN.md specifies "floating glass, **full-width** Ledger Green button", but `.frame(maxWidth: .infinity)` is applied *outside* the `.borderedProminent` style, so the button renders at intrinsic width — the small centered pill in the screenshot. The `.padding().background(.regularMaterial)` wrapper reads as an opaque slab, not floating glass.
6. **Disabled-state hack.** The disabled Save is faked with `.disabled` + a transparent overlay `Button` to catch taps (`review.save.disabled`). Two accessibility elements for one control; fragile.

## 2. Goals

- Save remains the **single hero action**: full-width, Ledger Green, thumb-reachable, glass (DESIGN.md §6 allows exactly this custom glass element).
- Exactly **one** discard affordance, physically distant from Save and from the keyboard.
- The form — not chrome — owns the screen while the keyboard is up.
- The keyboard is always dismissible in one obvious tap.
- No regression to the existing laws: disabled-Save-explains-itself, `.success` haptic on save, discard confirms only when dirty.

## Non-goals

- No changes to field order, choice chips, duplicate banner, or the review form's data logic (`ReceiptReviewForm` is untouched).
- No changes to the discard *confirmation* semantics (dirty check, alert copy).
- No triage-first ("Option B") restructuring — that remains the ui-spec A/B candidate.

## 3. Design decisions

### D1 — The bar becomes Save-only, hosted in `safeAreaBar`

Replace the current `safeAreaInset` + `VStack` + `.regularMaterial` slab with:

- `safeAreaBar(edge: .bottom)` (iOS 26) on the `List`, containing **only** the Save button and, transiently, the missing-fields hint (D4).
- Button: `Button("common.save")`, `.buttonStyle(.glassProminent)`, `.tint(Color("LedgerGreen"))`, `.controlSize(.large)`, with `.frame(maxWidth: .infinity)` applied **to the label** so the button genuinely fills the width.
- Bar padding: 16pt horizontal, 8pt vertical — no custom background. `safeAreaBar` supplies the scroll-edge treatment; content scrolls visibly beneath, which is what "floating glass" was always supposed to mean.
- Identifier `review.save` unchanged.

DESIGN.md §6's budget of two custom glass elements is unchanged (capture accessory + this bar).

### D2 — Discard consolidates into the navigation bar ✕

- **Delete** the plain-text Discard button from the bar.
- The existing toolbar ✕ (`.cancellationAction`, identifier `review.close`, accessibility label `common.discard`) becomes the *only* discard affordance. Its behavior is unchanged: dirty → confirmation alert, clean → dismiss.
- **New guard:** the confirmation alert's destructive choice must never sit where a repeat-tap lands. The current alert layout is acceptable (system alert, buttons far from the ✕); no change needed beyond keeping `common.cancel` as the default/cancel role.
- Sheet swipe-to-dismiss continues to route through `onDisappear → discardIfUnsaved`; unchanged.

Rationale: top-leading ✕ to abandon, bottom hero button to commit is the standard iOS sheet grammar (Calendar, Contacts, Reminders). It maximizes the physical distance between "keep" and "destroy", and it removes the destructive control from above the keyboard entirely.

### D3 — Keyboard etiquette

1. Track focus with a single `@FocusState private var focusedField: Field?` enum covering the text fields (vendor, amount, currency, notes).
2. **While any field is focused, the Save bar is hidden** (`if focusedField == nil { … }` inside the `safeAreaBar` content, animated with the default transition). The form gets the full space between nav bar and keyboard — the entire problem in the screenshot disappears.
3. Add a keyboard toolbar: `ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("common.done") { focusedField = nil } }`. `common.done` already exists in the String Catalog. This is the dismissal path for the return-key-less decimal pad.
4. Add `.scrollDismissesKeyboard(.interactively)` to the `List` so a downward drag also works.
5. Dismissing focus restores the Save bar; Save is then one tap away, full-width, at the thumb.

### D4 — Honest disabled state, no overlay hack

Replace the `.disabled` + transparent-overlay pair with **one** always-enabled button whose action branches:

```swift
Button { form.canSave ? save() : (showMissingSaveFields = true) } label: { … }
```

- Visual: 60% opacity when `form.canSave == false` (per DESIGN.md), full opacity otherwise.
- Tapping early shows the existing `review.save.missing` footnote **inside the bar, above the button** (footnote, `.secondary`, centered) and scrolls the `List` (via `ScrollViewReader`) to the first missing required field, which already carries the warm attention edge.
- The hint auto-clears when `form.canSave` flips true.
- Accessibility: the single button exposes `accessibilityHint` describing the missing fields when incomplete; the `review.save.disabled` identifier is deleted.

### D5 — Documentation amendments (same commit)

- **DESIGN.md §4 Save bar** rule becomes: *"Save bar: `safeAreaBar` glass, one full-width Ledger Green button, nothing else. Discard lives only as the ✕ in the navigation bar. The bar yields to the keyboard; Done in the keyboard toolbar dismisses. Disabled = 60% opacity with the reason shown inline above the button when tapped early."*
- **design/ui-spec.html**: remove the `<div class="discard">Discard</div>` line from all three review-section savebar mockups and the "Save is glass, floating, singular" law gains: *"Discard is the ✕, top-leading, confirmed only when dirty."*

## 4. Layout spec

| Element | Value |
|---|---|
| Bar horizontal padding | 16pt |
| Bar vertical padding | 8pt |
| Save button | full width, `.controlSize(.large)`, `.glassProminent`, tint `LedgerGreen`, no fixed height (Dynamic Type sizes it) |
| Missing-fields hint | `.footnote`, `.secondary`, centered, multiline, 8pt above button |
| Bar background | none of ours — system scroll-edge/glass only |

All type is Dynamic; no fixed point sizes. Both color roles come from existing asset-catalog tokens; no new tokens, no `colorScheme` branches.

## 5. Accessibility & localization

- Identifiers: `review.save` (kept), `review.close` (kept, now sole discard), `review.discard` and `review.save.disabled` (deleted).
- VoiceOver: capture→review→save must remain completable — Save is always hittable (D4), ✕ retains label `common.discard`, Done button labeled `common.done`.
- Strings: **no new strings.** `common.done`, `common.save`, `common.discard`, `review.save.missing` all exist in `Localizable.xcstrings`.

## 6. Test impact

- **UI tests** (`IntelliExpenseUITests/IntelliExpenseUITests.swift:146,175,183`): replace `app.buttons["review.discard"].tap()` with `app.buttons["review.close"].tap()`; flows that had edits will now hit the existing confirmation alert exactly as before.
- **New UI test:** focus the amount field → assert `review.save` is not hittable (bar hidden) → tap keyboard Done → assert `review.save` exists and is hittable → tap → receipt saved.
- **New UI test:** with type/payment unset, tap `review.save` → assert `review.save.missing` text appears; complete fields → assert it disappears and Save saves.
- Unit tests (`ReceiptReviewFormTests`) are unaffected — no form-logic changes.

## 7. Acceptance criteria

1. With the keyboard up on any review field, no Save or Discard control is visible below the form; a Done button sits above the keyboard and dismisses it.
2. With the keyboard down, Save is a single full-width Ledger Green glass button at the bottom; list content is visible scrolling beneath it.
3. The only discard affordance is the navigation-bar ✕; discarding a dirty form still confirms, a clean form still dismisses silently.
4. Tapping Save while incomplete shows the missing-fields reason and scrolls to the first offending field; tapping Save while complete saves with the `.success` haptic and dismisses.
5. VoiceOver can complete capture → review → save end-to-end; no orphaned `review.discard`/`review.save.disabled` elements remain.
6. All ExpenseCore and app tests pass; the three migrated UI tests pass.

## 8. Out of scope (noted during review of this screen)

- "1 pages" pluralization bug in the page-count badge (`review.page.count`) — separate fix.
- Navigation title mismatch (`review.title` renders "Review & Confirm"; ui-spec mockups say "Review Receipt") — copy decision for a separate pass.
- Auto-scroll to first *ambiguous* field on screen appear (ui-spec verdict's "fold B in" item) — related but independent feature.
