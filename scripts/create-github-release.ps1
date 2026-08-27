$ErrorActionPreference = 'Stop'

$ReleaseId = ''
$ExistingReleaseId = gh release view $env:TAG_NAME --json databaseId --jq '.databaseId' 2>$null
if ($LASTEXITCODE -eq 0) {
  Write-Host "Release $($env:TAG_NAME) already exists. Skipping creation."
  $ReleaseId = $ExistingReleaseId
} else {
  if ($env:CHANGELOG_BASE_TAG) {
    Write-Host "Generating release notes from $($env:CHANGELOG_BASE_TAG) to $($env:TAG_NAME)"
  } else {
    Write-Host "Generating release notes from initial commit to $($env:TAG_NAME)"
  }

  $ReleaseCreateArguments = @(
    'release', 'create', $env:TAG_NAME,
    '--title', $env:TAG_NAME,
    '--target', $env:GITHUB_SHA,
    '--generate-notes'
  )

  if ($env:IS_PRERELEASE -eq 'true') {
    $ReleaseCreateArguments += '--prerelease'
  }

  if ($env:IS_DRAFT_RELEASE -eq 'true') {
    $ReleaseCreateArguments += '--draft'
  }

  if ($env:CHANGELOG_BASE_TAG) {
    $ReleaseCreateArguments += @('--notes-start-tag', $env:CHANGELOG_BASE_TAG)
  }

  gh @ReleaseCreateArguments
  if ($LASTEXITCODE -ne 0) { throw 'Failed to create release' }

  $ReleaseId = (gh release view $env:TAG_NAME --json databaseId --jq '.databaseId')
  if ($LASTEXITCODE -ne 0) { throw 'Failed to resolve release id after creation' }
  Write-Host "Created release $($env:TAG_NAME) with id $ReleaseId"
}

if (-not $ReleaseId) {
  throw 'Failed to resolve release id - check if the release was created successfully'
}

"release_id=$ReleaseId" >> $env:GITHUB_OUTPUT

$ReleaseUrl = gh api "repos/$($env:GITHUB_REPOSITORY)/releases/$ReleaseId" --jq '.html_url' 2>$null
if ($LASTEXITCODE -ne 0 -or -not $ReleaseUrl) {
  throw "Failed to resolve release URL for release id $ReleaseId"
}
@(
  '### Release'
  ''
  "[$($env:TAG_NAME)]($ReleaseUrl)"
) -join "`n" >> $env:GITHUB_STEP_SUMMARY
