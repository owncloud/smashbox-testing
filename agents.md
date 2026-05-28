# agents.md — smashbox-testing

## Repository Overview

Smashbox Testing defines the Drone CI configuration for running nightly smashbox end-to-end tests against multiple ownCloud server tarballs. It is a CI pipeline definition repository with no application code.

- **Classification:** Infrastructure / Tooling
- **Activity Status:** Archived/Legacy
- **License:** MIT
- **Language:** Starlark (Drone CI pipeline definitions)

## Architecture & Key Paths

- `README.md` — Repository documentation
- `LICENSE` — MIT license file

This is a minimal repository containing CI pipeline definitions.

## Development Conventions

- Drone CI Starlark pipeline definitions
- Nightly test execution against ownCloud server tarballs

## Build & Test Commands

No build or test commands. CI pipelines run on Drone CI.

## Important Constraints

- **MIT license:** Already a permissive license, compatible with the OSPO Apache 2.0 migration target.
- **Archived/Legacy:** This repository is no longer actively maintained.
- **Drone CI dependency:** Pipeline definitions are specific to Drone CI infrastructure.
- Do not introduce new **copyleft-licensed dependencies** (GPL, AGPL, LGPL, MPL) without explicit discussion in an issue first. This is especially important for repos that are migrating to or already under Apache 2.0, as copyleft dependencies would block or complicate that migration.


## OSPO Policy Constraints

### GitHub Actions
- **Only** use actions owned by `owncloud`, created by GitHub (`actions/*`), verified on the GitHub Marketplace, or verified by the ownCloud Maintainers.
- Pin all actions to their full commit SHA (not tags): `uses: actions/checkout@<SHA> # vX.Y.Z`
- Never introduce actions from unverified third parties.

### Dependency Management
- Dependabot is configured for automated dependency updates.
- Review and merge Dependabot PRs as part of regular maintenance.
- Do not introduce new dependencies without discussion in an issue first.

### Git Workflow
- **Rebase policy**: Always rebase; never create merge commits. Use `git pull --rebase` and `git rebase` before pushing.
- **Signed commits**: All commits **must** be PGP/GPG signed (`git commit -S -s`).
- **DCO sign-off**: Every commit needs a `Signed-off-by` line (`git commit -s`).
- **Conventional Commits & Squash Merge**: Use the [Conventional Commits](https://www.conventionalcommits.org/) format where the repository enforces it. Many repos use squash merge, where the PR title becomes the commit message on the default branch — apply Conventional Commits format to PR titles as well. A reusable GitHub Actions workflow enforces this.

## Context for AI Agents

- This repository is archived/legacy and contains only CI pipeline configuration.
- No code to build or test locally.
- The smashbox test framework itself lives at https://github.com/owncloud/smashbox.
