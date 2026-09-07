# action-epoch-semver-version

Provides a reusable epoch semantic versioning action for use across repositories

## Epoch Semantic Versioning action

This action generates an epoch semantic version of the form `vYYYY.WW.P` (e.g. `v2026.8.2`), where `YYYY` is the ISO year, `WW` is the ISO calendar week, and `P` is the patch level.

The bump type is determined from commit messages:

- **Release** — triggered by `feat:`, `feat(<scope>):`, `BREAKING CHANGE:`, or any type ending in `!:` (e.g. `fix!:`).
  - If the current calendar week/year **differs** from the previous stable tag: advance to the current year and week, reset patch to `0`.
  - If the current calendar week/year is the **same** as the previous stable tag: increment patch (behaves like a patch bump).
- **Patch** — any other commit message: increment the patch level and keep the year and week of the previous stable tag, regardless of the current date.

**Repository structure:**

- `action.yml` — The action definition with inputs, outputs, and composite steps.
- `scripts/` — PowerShell scripts executed by the action:
  - `compute-next-version.ps1` — Calculates the next version based on commit history.
  - `create-and-push-tag.ps1` — Creates and pushes the Git tag.
  - `create-github-release.ps1` — Creates the GitHub release with release notes.
  - `write-step-summary.ps1` — Generates the GitHub Actions step summary.

### Calling the action

```yaml
# action.yml in a consumer repository
name: Release

on:
  push:
    branches:
      - main

jobs:
  version:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    outputs:
      version: ${{ steps.version.outputs.version }}
      tag: ${{ steps.version.outputs.tag }}
      bump_type: ${{ steps.version.outputs.bump_type }}
      previous_tag: ${{ steps.version.outputs.previous_tag }}
      commit_subject: ${{ steps.version.outputs.commit_subject }}
      release_id: ${{ steps.version.outputs.release_id }}
    steps:
      - name: Generate epoch semantic version
        id: version
        uses: glueckkanja/action-epoch-semver-version@SHA # v1.0.0
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          prefix: license-module # optional: prefix for tags like license-module-vX.Y.Z
          suppress_release: "false" # optional: set true to skip creating a GitHub release
          is_draft_release: "false" # optional: set true to create a draft GitHub release
          suppress_tag: "false" # optional: set true to skip both tag and release creation
          check_last_commit_only: "false" # optional: set true to only inspect the latest commit
          is_prerelease: "false" # optional: set true to generate a prerelease version
          prerelease_name: "" # optional: set a prerelease suffix name (for example 'rc', 'alpha', 'beta'); keep empty to create a prerelease without suffix

  publish:
    runs-on: ubuntu-latest
    needs: version
    steps:
      - name: Show generated version
        run: |
          echo "Version:    ${{ needs.version.outputs.version }}"
          echo "Tag:        ${{ needs.version.outputs.tag }}"
          echo "Bump:       ${{ needs.version.outputs.bump_type }}"
          echo "Prev tag:   ${{ needs.version.outputs.previous_tag }}"
          echo "Commit:     ${{ needs.version.outputs.commit_subject }}"
          echo "Release ID: ${{ needs.version.outputs.release_id }}"
```

### Permissions

- `contents: write` — Required on the **caller's job**. Allows the action to create tags and releases. Pass `${{ secrets.GITHUB_TOKEN }}` via the `github_token` input.

### Inputs

- `github_token` _(string, required)_ – GitHub token with `contents: write` permission. Pass `${{ secrets.GITHUB_TOKEN }}`.
- `prefix` _(string, default: empty)_ – Optional prefix prepended to generated tags (for example `license-module-vYYYY.WW.P`).
- `suppress_release` _(string `"true"/"false"`, default: `"false"`)_ – When `"true"`, skips creating a GitHub release while still creating tags (unless suppressed below).
- `is_draft_release` _(string `"true"/"false"`, default: `"false"`)_ – When `"true"`, creates the GitHub release as a draft.
- `suppress_tag` _(string `"true"/"false"`, default: `"false"`)_ – When `"true"`, skips creating both the Git tag and the GitHub release.
- `check_last_commit_only` _(string `"true"/"false"`, default: `"false"`)_ – When `"true"`, only the most recent commit is inspected to determine the bump type instead of all commits since the previous tag.
- `is_prerelease` _(string `"true"/"false"`, default: `"false"`)_ – When `"true"`, marks the GitHub release as prerelease.
- `prerelease_name` _(string, default: empty)_ – Optional prerelease identifier name (for example `rc`, `alpha`, `beta`). If set, the version includes a suffix (for example `v2026.8.2-rc.1`). If empty, the version remains plain epoch semver (for example `v2026.8.2`) while still creating a prerelease release.

### Outputs

- `version` – The calculated semantic version (for example `2026.8.2`).
- `tag` – The tag name that would be created (for example `v2026.8.2` or `module-v2026.8.2`).
- `bump_type` – The bump classification applied (`release` or `patch`).
- `previous_tag` – The most recent matching tag prior to this run, if any.
- `commit_subject` – The commit message subject that determined the bump decision.
- `release_id` – Numeric ID of the created (or existing) GitHub release. Empty when release creation is suppressed via `suppress_release` or `suppress_tag`.

The run summary also includes a direct link to the created GitHub release for quick access.

### Bump rules

The action inspects commit messages and applies the following precedence:

- **Release**: If any commit matches `feat:`, `feat(<scope>):`, `BREAKING CHANGE:`, or any type ending in `!:` (for example `feat!:`, `fix!:`, `chore!:`, `feat(scope)!:`).
- **Patch**: Any other commit message.

If no existing epoch-versioned tags are found, versioning starts from `{currentYear}.{currentWeek}.0` (for a release bump) or `{currentYear}.{currentWeek}.1` (for a patch bump).

Each run also publishes (or updates) a Git tag matching the new version. By default tags look like `vYYYY.WW.P`, but you can provide a `prefix` input (for example `license-module`) to emit tags such as `license-module-vYYYY.WW.P`. The action creates a GitHub release with auto-generated release notes for the generated tag. Existing tags or releases are detected and left untouched.
