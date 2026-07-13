# SPEC: Mac sidebar refinement — truncation fix, bottom-bar New Folder, destination badges, collapsible Folders

**Status:** Draft — ready for implementation (owner request, 2026-07-12)
**Owner screens:** Mac sidebar column ([MacContentView.swift](../../IntelliExpense/Mac/MacContentView.swift) — `sidebar`, `groupSidebarRow`), shared folder row macOS branch ([GroupsViews.swift](../../IntelliExpense/UI/GroupsViews.swift) — `GroupRow` `#if os(macOS)` branch only)
**Owner logic:** none new — counts come from the existing `activeGroups` / `unfiledReceipts` / `archivedGroups` / `archivedReceipts` queries already held by `MacLibraryView`
**Docs this spec amends:** `DESIGN.md` §10 "Native Mac Adaptation" (the Density bullet gains name-priority and badge rules; the Controls bullet gains the sidebar bottom bar; a new bullet affirms tinted folder glyph tiles against the macOS 26 monochrome-sidebar default), `design/ui-spec.html` Mac mockup (`.macside`: add an Unfiled row with a badge, change the Archived money-column count to a badge treatment, add a bottom-aligned "New Folder…" bar, remove nothing else). Amends `SPEC-mac-visual-polish.md` where it fixed the sidebar money column at a reserved trailing width, and `SPEC-mac-app.md` acceptance where "New Folder" is described as a list row.

## 1. Problem

Four related complaints about the Mac sidebar, visible in a synthetic reference screenshot (folders "Portfolio Refresh" and "Bengaluru Conference", ₹ totals):

1. **Folder names truncate almost immediately.** "Transformation" renders as "Transform…" in the sidebar even at default window sizes. The macOS `GroupRow` branch reserves a fixed trailing money slot (`minWidth: 88`) and additionally spends row width on a 26 pt glyph tile and an inline `pin.fill` indicator, inside a column allowed to shrink to 220 pt. With a long total such as `₹1,41,912.50` (Indian digit grouping makes lakh-scale totals 12+ characters), the name is the only flexible element, so it loses. The row's own tooltip already carries the full story (`mac.sidebar.trip.help`: date range + all totals), but the *name* — the primary text, which DESIGN.md §10 says comes first — is the one element that should never be sacrificed to a fixed-width secondary element.

2. **"New Folder…" is a fake list row.** The creation affordance is a `Button` styled as the last row of the Folders section. It is the least native element in the sidebar: it is not a navigation destination, yet it sits among destinations, takes a selection-shaped hit target, and scrolls with content. The current macOS Human Interface Guidance is explicit that actions belonging to a sidebar go in a **bottom-aligned bar** in the sidebar column, not in the list and not in the window toolbar (Notes, Mail, and Reminders all do this for their New Folder / New Mailbox / Add List affordances). The canonical Mac mockup in `ui-spec.html` shows *no* New Folder row at all — the shipped row is undocumented drift.

3. **Unfiled and Archived rows carry no glanceable weight.** They appear and disappear (sections gated on emptiness) but never say *how much* is behind them. The Mac mockup already shows Archived with a count (`12`) in its trailing column — the shipped app dropped that. Counts on system-destination rows are the standard Mac sidebar idiom (Mail unread counts, Notes folder counts) and are cheap: the queries already exist.

4. **The Folders section cannot be collapsed.** Every stock Mac sidebar with labeled groups (Mail, Notes, Reminders, Finder) lets the user disclose sections. With many folders plus Unfiled plus Archived, the sidebar becomes one long undifferentiated scroll. The system sidebar list style provides disclosure on section headers; the app never opted in.

## 2. Goals

- A folder's **name never truncates before the money column has given up its reserved slack** — the name is the layout-priority element; money stays right-aligned tabular and single-line but claims only its natural width.
- The sidebar column's width limits follow current HIG guidance (minimum in the 225–275 pt band) so the default window shows typical folder names untruncated.
- "New Folder…" moves out of the list into a **bottom-aligned bar in the sidebar column**, matching Notes/Mail/Reminders; ⌘N and the File menu keep working unchanged; the list contains only real destinations.
- **Unfiled shows a receipt-count badge; Archived shows a folder-count badge**, using the system sidebar badge treatment (quiet, trailing, system-styled — never brand-tinted, never red).
- The **Folders section is collapsible** via the system disclosure affordance, expanded by default, with its state restored per scene alongside the existing sidebar-selection restoration.
- The iOS Folders home is **visually and behaviorally unchanged** — every edit lands in `#if os(macOS)` branches or Mac-only files.
- `DESIGN.md` and `design/ui-spec.html` are amended in the same change (anti-drift rule).

## 3. Non-goals

- **No sidebar filter/search field.** HIG suggests one only when users accumulate many items; the receipt column already owns scoped search (SPEC-mac-desktop-behaviors). Revisit if real folder counts demand it.
- **No manual drag-to-reorder of folders.** Pinned-first ordering is settled policy (SPEC-folder-pinning-and-type-dot-removal §3) and this spec does not reopen it.
- **No change to the pin indicator's form.** The inline `pin.fill` matches both the ui-spec `pinmark` and the iOS row; relocating it (e.g., badging the glyph tile) would fork the shared pinning vocabulary. (Considered and rejected in D2.)
- **No hero-styled or enlarged money in the sidebar.** DESIGN.md §11: "One light-weight hero number per screen" — the detail column owns it; sidebar totals stay `subheadline`-class.
- **No custom selection painting, hover effects, or glass.** DESIGN.md §10: "Never custom-paint list selection"; §6 rations glass — the system sidebar material is already the only glass this column gets.
- **No red, no second accent, no count-in-red badges.** Badges use the system's default quiet badge styling.
- No change to drop-target behavior, context menus, inline rename, restoration of *selection*, or any command wiring beyond relocating the New Folder button's visual home.
- No iOS changes of any kind; no change to the `GroupRow` iOS branch, `FeaturedTripCard`, or `GroupsTabView`.

## 4. Design decisions

### D1 — Name owns the row; money claims natural width only

The macOS `GroupRow` branch drops the fixed `minWidth: 88` reservation on the total. The money text keeps `monospacedDigit`, single-line, trailing alignment, and `subheadline.semibold` weight — all unchanged — but sizes to its content. The folder name receives layout priority over every sibling so that when the row runs out of width the *money* compresses toward its natural width first and the name truncates last. The name stays one line (DESIGN.md §10 Density: "Sidebar folders show name + primary total on one line").

Rules this satisfies: §10 Density — "right-aligned tabular money, primary text first, secondary metadata quiet." A fixed 88 pt reservation served cross-row money alignment, but tabular numerals already guarantee digit alignment, and right-edge alignment comes from the trailing position; the reservation's only observable effect today is stealing width from the primary text. The existing tooltip (`mac.sidebar.trip.help` — date range · full multi-currency totals · pinned state) remains the overflow valve for everything the one-line row cannot show, exactly as §10 prescribes.

**Rejected:** truncating or abbreviating the *total* (e.g., "₹1.4L") — locale-dependent abbreviation is parser-adjacent knowledge the design system bans from UI code, and a wrong-looking amount is worse than a truncated name. **Rejected:** two-line rows (name over total) — violates the one-line Density rule and makes the Mac sidebar drift from the mockup's row anatomy.

### D2 — Keep the inline pin indicator, unchanged

The `pin.fill` caption-size indicator stays exactly where it is (between name and total). It matches the ui-spec Mac mockup's `pinmark`, matches the iOS row, and costs ~14 pt only on pinned rows. With D1's layout priority, the indicator compresses the money's slack, not the name.

**Rejected:** overlaying a pin badge on the `FolderProfileGlyph` tile — saves ~14 pt but forks the pinning vocabulary between platforms and would need new asset/AX treatment; SPEC-folder-pinning-and-type-dot-removal deliberately chose one shared indicator.

### D3 — Sidebar column width limits move to the HIG band

The sidebar column's limits change from min 220 / ideal 260 / max 320 to **min 240 / ideal 280 / max 360**. Current macOS guidance recommends a 225–275 pt minimum and 350–400 pt maximum for sidebars; 240/280 keeps the three-pane layout comfortable on a 13″ window while giving typical folder names (12–16 characters) room next to lakh-scale totals at the default width. The receipt-list and detail column limits are untouched.

### D4 — "New Folder…" becomes the sidebar's bottom bar

The `groups.create.row` button leaves the Folders `Section`. The sidebar column gains a **bottom-aligned bar** (the system safe-area bar affordance for sidebar columns — the same placement Notes uses for its New Folder control) containing a single borderless button: the existing `folder.badge.plus` symbol + the existing `groups.create.row` label, tinted with the standard control style (not brand-filled — the bar is chrome, not a call to action). Activating it sets the same create-folder state the row set; the `GroupEditorSheet` flow, ⌘N, and the File-menu command are untouched.

The bar is part of the sidebar column and collapses with it. Per HIG, no additional toolbar items are added to the sidebar's top toolbar area.

Rules this satisfies: §10 Controls — "use standard toolbar/menu commands for New Folder…"; the bottom bar *is* the standard sidebar placement for this action on macOS 26, and the menu command remains the canonical command surface. This also closes drift against the ui-spec mockup, which never showed a New Folder row.

**Rejected:** window-toolbar "+" button — the toolbar belongs to the content/detail import actions, and HIG warns extra sidebar-scoped toolbar items overflow at narrow widths. **Rejected:** keeping the row *and* adding the bar — two affordances for one action in one column.

**HIG caveat, accepted knowingly:** HIG says avoid putting *critical* information at the bottom of a sidebar because users may position windows with the bottom edge off-screen. New Folder is not critical-path (menu + ⌘N + empty-state guidance all remain); the bar placement is the platform convention precisely because it degrades safely.

### D5 — System badges on Unfiled and Archived; units match what the destination lists

- **Unfiled** shows a numeric badge = count of active unfiled receipts. The section already hides at zero, so the badge never shows 0.
- **Archived** shows a numeric badge = count of **archived folders** (the archived destination presents folders first; receipts inside them are one level down). If archived *loose receipts* exist but zero archived folders (edge case E6), the row shows no badge rather than a mixed-unit count.
- Folder rows do **not** get badges — their trailing column is money, and stacking a count next to a total re-creates the noise the type-dot removal spec eliminated.

Badges use the system sidebar badge appearance: trailing, quiet secondary styling, system-formatted numerals (locale-aware digit rendering comes free). No brand tint, no red (hard rule), no custom capsule. This restores the mockup's "Archived … 12" intent using the native idiom instead of the mockup's money-column hack.

**Rejected:** money totals on Unfiled/Archived — Unfiled may span currencies and "never sum across currencies" is a hard rule; a count is the honest scalar.

### D6 — Folders section is collapsible; state restores per scene

The "Folders" hierarchy (`tab.groups`) uses the system `DisclosureGroup` control (visible disclosure triangle, click or accessibility activation to collapse/expand), **expanded by default**. Unfiled and Archived remain plain, non-collapsible rows — they are single destinations, not groups. The expansion state persists per scene next to the existing `mac.sidebar.selection` scene storage and restores with the same graceful-fallback philosophy (§10 Restoration): a missing or corrupt value means expanded.

Interaction with selection: collapsing the section does not clear an existing folder selection; the content and detail columns keep showing the selected folder (system behavior). Collapsing removes folder rows as drop targets while collapsed (E7); Unfiled and Archived remain droppable.

Rules this satisfies: §10's "System `List` owns … keyboard traversal" — disclosure is the system's, not a custom control; HIG "Group hierarchy with disclosure controls."

### D7 — Tinted folder glyph tiles are affirmed against the macOS 26 monochrome default

macOS 26 defaults sidebar icons to monochrome (black/white per appearance) because tinted icons can clash with the floating glass material. Intelli-Expense's sidebar rows intentionally keep the **category-tinted `FolderProfileGlyph` tiles**: DESIGN.md §2/§11 make "profile SF Symbol + palette hue" the folder's identity, identical on iPhone and Mac, and the tile (a filled rounded tile, not a bare tinted glyph) reads as content identity rather than chrome tinting. This is a deliberate, documented deviation from the platform default, recorded as a new one-line bullet in §10 so a future agent doesn't "fix" it. The Unfiled (`tray`) and Archived (`archivebox`) symbols, which are chrome-like destinations rather than identities, stay un-tinted system symbols and therefore follow the monochrome default automatically.

### D8 — Empty-folders state

With the New Folder row gone, a library with zero active folders shows an empty Folders section under its header plus the bottom bar. The existing onboarding/empty-state guidance elsewhere already directs first-time users; the bottom bar's labeled button ("New Folder…") is itself the discoverable affordance, mirroring Notes with no folders. No new empty-state copy is added to the sidebar.

## 5. Edge cases

- **E1 — Lakh-scale and multi-currency totals (₹1,41,912.50).** With D1, the total renders fully at its natural width whenever the column affords it; when the column is at minimum and the name is long, the *name* truncates only after the money has no reserved slack left. Full totals remain in the tooltip. Verify with Indian-locale grouping specifically.
- **E2 — Very long folder name, pinned, long total, minimum column width.** Worst case: glyph tile + name + pin + total at 240 pt. Name truncates with ellipsis; row never wraps to two lines; tooltip carries the full name (system expansion tooltip on truncation is acceptable if free; not a requirement).
- **E3 — Content zoom (semantic font-scale steps, SPEC-mac-desktop-behaviors).** At the largest zoom step the row must still be one line: tile scales via its `ScaledMetric`, name and money scale with their text styles, and the truncation order of E1 still holds. The bottom bar label scales and may itself truncate rather than grow the bar to two lines.
- **E4 — Sidebar icon size (System Settings → Appearance).** Small/Medium/Large sidebar sizing changes row metrics; badges, disclosure, and the bottom bar are all system affordances and must inherit it without custom compensation.
- **E5 — Inline rename active.** The rename `TextField` replaces the row content and is unaffected by D1's priority rules (it already owns the full row width). Renaming while the section header is mid-collapse is impossible (collapse hides the row; system cancels field focus — accept system behavior).
- **E6 — Archived contains only loose receipts, zero archived folders.** Row visible (existing gate), no badge (D5). When the first folder is archived, the badge appears with 1.
- **E7 — Drag receipt while Folders is collapsed.** Folder rows are not visible and thus not droppable; Unfiled and Archived still accept drops. No springloading requirement is added; if the system provides hover-to-expand on section headers for free, accept it.
- **E8 — Collapse state restoration.** New scene → expanded. Restored scene with saved collapsed state → collapsed, and if the restored *selection* is a folder inside the collapsed section, selection is kept (content/detail follow it) without force-expanding.
- **E9 — Zero active folders (D8).** Header + empty section + bottom bar. ⌘N, File menu, bottom bar all still create; drop of a receipt onto the sidebar with no folders targets Unfiled/Archived rows only.
- **E10 — Badge counts under CloudKit sync.** Counts derive from the same live queries as the rows; a sync-inserted receipt/folder updates the badge with no extra invalidation work. No caching layer is introduced.
- **E11 — Window narrower than sidebar minimum.** System collapses the sidebar column (existing `NavigationSplitView` behavior); the bottom bar disappears with the column; ⌘N and menus remain the creation path — this is why D4's HIG caveat is safe.

## 6. Accessibility & localization

**New string-catalog keys:**

| Key | English value | Notes |
|---|---|---|
| `mac.sidebar.unfiled.badge.ax` | `%lld receipts` (plural rule: one = `%lld receipt`) | VoiceOver value appended to the Unfiled row so the badge number is announced with its unit. Plural variants required. |
| `mac.sidebar.archived.badge.ax` | `%lld folders` (plural rule: one = `%lld folder`) | Same, for Archived. |

**Reused keys (no value changes):** `tab.groups` (section header, now a disclosure header), `groups.create.row` (bottom-bar button label — the ellipsis stays correct because the button opens the editor sheet), `groups.unfiled.title`, `trips.archived.title`, `mac.sidebar.trip.help`, `folder.pinned`, `list.separator`, `metadata.separator`. No key is renamed. Badge numerals themselves are system-formatted and never enter the catalog; counts in the AX strings use format specifiers, never concatenation.

**Accessibility identifiers (new):**

| Identifier | Element |
|---|---|
| `mac.sidebar.newFolder` | Bottom-bar New Folder button (replaces the identifier-less list row) |
| `mac.sidebar.folders.header` | Folders disclosure label |
| `mac.sidebar.unfiled.row` | Unfiled destination row |
| `mac.sidebar.archived.row` | Archived destination row |

Existing identifiers (`mac.sidebar.rename.field`, `folder.action.pin`, `folder.action.unpin`) are unchanged.

**VoiceOver behavior:**
- Folder rows remain a single combined element: name, total, pinned state (existing `folder.pinned` value) — unchanged by D1/D2.
- Unfiled row announces label + badge unit string (`mac.sidebar.unfiled.badge.ax`); Archived likewise. The visual badge itself is not a separate element.
- The Folders section disclosure must be reachable and toggleable by keyboard/VoiceOver via the system header affordance; no custom rotor work.
- The bottom-bar button is a standard button: label "New Folder…", keyboard-focusable in the sidebar column's focus order after the list.

**Dynamic Type / content zoom:** all text uses semantic styles through the existing content-scaled font path; no fixed point sizes are introduced. At AX sizes the row remains one line with end-truncation (E2/E3) — this is the documented AX-size behavior for this layout.

## 7. Test impact

**Local (must pass before handoff):**
- `make test-mac-unit`: new/updated behavior tests for (a) Archived badge count = archived folders only, ignoring loose archived receipts (E6); (b) Unfiled badge count = active unfiled receipts; (c) collapse-state restoration default + graceful fallback (E8); (d) selection preserved across collapse (D6).
- `cd ExpenseCore && swift test`: unaffected (no shared-logic change) — run as regression.
- `make test-app`: iOS suite must be fully green with **zero snapshot/behavior deltas**, proving the shared-file edits stayed inside the macOS branch. This is required because `GroupsViews.swift` is a shared file, even though the iOS branch is untouched.
- Any existing Mac UI test that reaches New Folder through the list row must be updated to the `mac.sidebar.newFolder` bottom-bar button.

**Hosted Mac UI (one focused method, per runner policy):** a single method covering the highest-risk rendered interaction — create a folder via the bottom bar, verify the new row appears in the Folders section, collapse and re-expand the section, and assert the Unfiled badge is present with the seeded count. Dispatch per [docs/verification/github-macos-runner-usage.md](../verification/github-macos-runner-usage.md); no full-class run unless this spec's closeout warrants it.

**Not covered by automation (manual acceptance):** truncation-order visual check at 240 pt with Indian-locale totals (E1), sidebar icon-size Small/Large sweep (E4), VoiceOver announcement of badge units.

**Platform justification (per shared-UI rule):** iOS is exercised via `make test-app` but no iOS UI change exists — every diff line is inside `#if os(macOS)` or `IntelliExpense/Mac/`; the receipt list and detail columns are untouched, so no receipt-flow Mac UI method is needed beyond the one above.

## 8. Acceptance criteria

1. At the default sidebar width (~280 pt), "Transformation" with total `₹1,41,912.50` and a pin indicator renders **without name truncation**; at the 240 pt minimum the name truncates only after the money column has no reserved slack (no fixed trailing min-width remains in the macOS row).
2. Money in folder rows remains right-aligned, single-line, tabular, `subheadline`-weight — visually indistinguishable from today except for reclaimed width; the tooltip still shows date range, full multi-currency totals, and pinned state.
3. The Folders list contains **only destinations**: no button rows. "New Folder…" appears in a bottom-aligned sidebar bar with the `folder.badge.plus` symbol, opens the existing folder editor, and ⌘N / File-menu behavior is byte-identical.
4. Unfiled shows a system badge equal to the active unfiled receipt count; Archived shows a system badge equal to the archived folder count; neither badge is tinted or red; E6 shows no badge; VoiceOver reads counts with units via the two new plural keys.
5. The Folders section collapses/expands via the system disclosure, defaults to expanded, restores per scene with graceful fallback, and never clears or force-changes selection (E8).
6. Sidebar column limits are min 240 / ideal 280 / max 360; content and detail column limits unchanged.
7. iOS Folders home, featured card, compact rows, Unfiled and Archived sections are pixel- and behavior-identical; `make test-app` green with no test edits other than none.
8. `DESIGN.md` §10 and `design/ui-spec.html` Mac mockup are amended in the same change: Density bullet (name priority, natural-width money), Controls bullet (sidebar bottom bar), new tinted-glyph-tile deviation bullet (D7), mockup gains Unfiled row + badges + bottom bar and loses nothing else.
9. All new user-facing strings exist in `Localizable.xcstrings` with plural variants as tabled; no hardcoded strings; badge numerals are system-formatted.
10. New accessibility identifiers (`mac.sidebar.newFolder`, `mac.sidebar.unfiled.row`, `mac.sidebar.archived.row`) exist and are stable; existing identifiers unchanged.
11. One focused hosted Mac UI method passes covering bottom-bar creation, section collapse/expand, and badge presence; its runner-ledger entry is appended.
