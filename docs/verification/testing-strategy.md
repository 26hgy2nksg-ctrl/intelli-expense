# Intelli-Expense testing strategy

Use the lowest layer that can prove the behavior. GitHub-hosted Mac runners exist only to keep native Mac UI automation from occupying the owner's desktop; their limited minutes are not a general CI budget.

## Verification ladder

| Change or question | Normal proof | Escalate when |
|---|---|---|
| Parser, money, export, shared pure logic | `make test-core` locally | App integration is involved |
| iPhone models, services, persistence, or UI | Focused/full `make test-app` locally as appropriate | Real device behavior is required |
| Mac model, undo, search, zoom, or drag materialization logic | `make test-mac-unit` locally | Rendered AppKit/XCUI interaction is irreducible |
| One Mac window, sheet, menu, keyboard, focus, drag, or accessibility behavior | Manual hosted workflow with the exact method filter | Focused method is green and closeout needs the whole class |
| Release closeout | Full affected lanes once | Production code changes after the receipt |

Project generation, compilation, package resolution, unit tests, source scans, and unsigned build-for-testing all run locally. A successful compile does not replace affected UI coverage, but it must precede hosted UI time.

## Hosted Mac UI boundary

`.github/workflows/macos-ui.yml` is `workflow_dispatch` only. It selects one class or method under `IntelliExpenseMacUITests/IntelliExpenseMacUITests`, runs on `macos-26` with Xcode 26.5, regenerates the project, rejects drift, and disables signing for CI. It has no push/PR trigger and no write permission.

Before a dispatch:

1. Run relevant local non-UI verification and fix all compile/configuration failures.
2. Check [github-macos-runner-usage.md](github-macos-runner-usage.md) and confirm existing evidence does not already answer the question.
3. State why rendered native Mac UI interaction is required.
4. Select one exact method. Select the whole class only for a deliberate closing receipt.
5. Confirm no hosted Mac run is already queued or running.

Dispatch after the workflow exists on the default branch:

```sh
gh workflow run macos-ui.yml --ref <branch> \
  -f reason='<why native Mac UI interaction is required>' \
  -f test_filter=IntelliExpenseMacUITests/IntelliExpenseMacUITests/<method>
```

Inspect with `gh run list --workflow macos-ui.yml` and download evidence with `gh run download <run-id>`. Every attempt retains a raw log, `.xcresult`, result summary, and usage estimate for 14 days.

## Failure and rerun policy

When a hosted run fails, record the exact method and assertion, then stop. Diagnose locally with core/app/Mac unit coverage whenever possible. If UI interaction cannot be represented headlessly, make a relevant change and rerun only that method. Do not rerun the entire class to inspect one failure.

A second hosted attempt requires either a relevant code/configuration change or the single allowed retry of a pre-assertion initialization failure on a fresh runner. Two identical initialization failures are a hosted-runner blocker; do not install a self-hosted runner. Once focused failures are clear, use at most one full-class closeout run.

`make test-focus-mac TEST=<target/class[/method]>` and `make test-mac` are local fallbacks only when the owner explicitly requests them. Do not occupy the owner's desktop by default.

## Minute accounting

After every hosted job, append GitHub's job `started_at` and `completed_at` duration to the usage ledger. Round each job up to the next whole minute. Failed setup and cancelled jobs still count; concurrent jobs are counted separately. GitHub billing is authoritative for the remaining account allowance, while the repository ledger is the durable project record.
