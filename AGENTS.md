# AGENTS.md

Read [CLAUDE.md](CLAUDE.md) — it is the single source of agent guidance for this repository.

Run all project generation, builds, package tests, app tests, Mac unit tests, and other non-UI checks locally. GitHub-hosted Mac runners are reserved exclusively for native Mac UI automation that would occupy the owner's desktop.

Hosted Mac minutes are limited. Never trigger `.github/workflows/macos-ui.yml` from a push or pull request, never use the full Mac UI class as a diagnostic loop, and never dispatch while another Mac job is queued or active. Before manual dispatch, check `docs/verification/github-macos-runner-usage.md`, state why UI automation is necessary, and select one exact method whenever possible. Record every job's GitHub duration in the ledger. Do not run `make test-focus-mac` or `make test-mac` locally unless the owner explicitly requests that fallback.

Spec drafts and implementation briefs belong in `docs/specs/`, not in the repository root.

Implement each spec on its own spec-named branch, using `codex/<spec-slug>` by default; do not implement specs directly on `main`.

Commits must be frequent and focused. Commit each complete logical unit after its relevant verification passes instead of accumulating a large dirty tree. A small spec may use one coherent commit; split a larger spec into multiple focused commits, never mix specs or unrelated work, stage only the files for the current unit, and leave unrelated dirty work alone.

After normal app changes, run `make install-device` before handoff; it is the canonical durable-phone lane, scopes Xcode 27 beta to that command, enables the image-input build condition, and installs on the paired iPhone without resetting app data. Keep machine-wide `xcode-select` on stable Xcode. Use `make install-device-stable` only for an explicit stable-Xcode fallback. For sandbox or side-by-side seeded testing, run `make sandbox-profile` and `make install-device-sandbox` instead so the durable app is not touched. If the beta toolchain, phone, or signing path is unavailable, stop and report the blocker.
