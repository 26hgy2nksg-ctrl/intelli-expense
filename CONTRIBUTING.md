# Contributing

Thanks for taking an interest in Intelli-Expense. The project is pre-1.0 and maintainer-reviewed; opening an issue or pull request does not imply a response time, roadmap commitment, or automatic merge.

## Prerequisites

- macOS with Xcode 26 or newer
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- An Apple-Intelligence-capable device for real Foundation Models behavior
- Your own Apple Developer team for personal-device signing

Simulator builds and deterministic tests do not require a paid Apple Developer account.

## Before changing code

Read `AGENTS.md` and `CLAUDE.md`, then follow the binding product and design contracts in `PRD.md`, `DESIGN.md`, and `design/ui-spec.html`. Feature briefs live in `docs/specs/`. Keep changes within the product's explicit non-goals and preserve its privacy boundary: no accounts, analytics, third-party AI services, or direct external writes to the app database.

## Build and test

```sh
make gen
make test
```

For a personal-device build, copy `Makefile.local.example` to `Makefile.local` and add only your own local signing/device values. Never commit that file, provisioning profiles, receipt data, device identifiers, or App Store Connect details.

## Pull requests

- Keep each change focused and explain the user-visible value.
- Add or update deterministic tests for behavior changes; use `Decimal` for money.
- Put every user-facing string in the String Catalog and preserve Dynamic Type and accessibility behavior.
- Use synthetic fixtures only. Do not submit real receipts, merchant identifiers, addresses, tax IDs, phone numbers, or financial activity.
- Update the PRD, design system, UI spec, or feature spec when a product contract changes.
- Confirm `make test` is green and include the relevant verification result.

The maintainer reviews all changes and may decline work that expands scope, weakens privacy, or adds long-term governance cost before 1.0.
