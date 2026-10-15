# Bichitos

iPhone app: procedural pixel-art creatures in a sandbox world. Read `docs/CONCEPT.md` and `docs/DESIGN.md` first.

- Swift, SwiftUI + SpriteKit, iOS 17+, no third-party dependencies. Same structure as `sanlega/musiquillas`.
- The Xcode project is generated from `ios/project.yml` by XcodeGen; never commit `.xcodeproj`.
- The generator (`Recipe` → pixels) and the simulation are pure Swift (Foundation only, no UIKit/SpriteKit) so they run headless in tests and in the catch-up fast-forward.
- Development happens on Windows: there is no local Swift toolchain. Code is compiled and tested only by the `ios-build-check` GitHub Actions workflow (macOS runner). Push a branch, open a PR, read the CI log.

## Agent skills

### Issue tracker

Issues live in GitHub Issues on `sanlega/bichitos`, via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical labels with default names (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `GLOSSARY.md` and `docs/adr/` at the repo root, created when needed. See `docs/agents/domain.md`.
