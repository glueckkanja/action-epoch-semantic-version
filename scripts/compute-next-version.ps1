$ErrorActionPreference = 'Stop'

$Prefix = $env:PREFIX
$CheckLastCommitOnly = $env:CHECK_LAST_COMMIT_ONLY -eq 'true'
$IsPrerelease = $env:IS_PRERELEASE -eq 'true'
$PrereleaseName = $env:PRERELEASE_NAME
$HasPrereleaseSuffix = -not [string]::IsNullOrWhiteSpace($PrereleaseName)

if ($Prefix) {
  $TagMatch = "$Prefix-v*"
  $PrefixWithDash = "$Prefix-"
} else {
  $TagMatch = "v*"
  $PrefixWithDash = ""
}

# Get all tags matching the pattern, sorted by version descending
$TagOutput = git tag -l "$TagMatch" --sort=-version:refname
$AllTags = @($TagOutput | Where-Object { $_ })

# Find the last stable version (no prerelease identifier)
$LastStableTag = ''
$LastStableYear = 0
$LastStableWeek = 0
$LastStablePatch = 0

# find latest stable epoch semver version (year >= 2020, week 1-53) - standard semver tags are ignored
foreach ($Tag in $AllTags) {
  $StrippedTag = $Tag -replace "^$([regex]::Escape($PrefixWithDash))", ''
  $Version = $StrippedTag -replace '^v', ''
  if ($Version -notmatch '-' -and $Version -match '^(\d+)\.(\d+)\.(\d+)$') {
    $CandidateYear = [int]$Matches[1]
    $CandidateWeek = [int]$Matches[2]
    if ($CandidateYear -ge 2020 -and $CandidateWeek -ge 1 -and $CandidateWeek -le 53) {
      $LastStableTag = $Tag
      $LastStableYear = $CandidateYear
      $LastStableWeek = $CandidateWeek
      $LastStablePatch = [int]$Matches[3]
      break
    }
  }
}

# Determine which commits to check based on mode
$LogLimit = $CheckLastCommitOnly ? @('-1') : @()
$LogRange = $LastStableTag ? @("$LastStableTag..HEAD") : @()
$CommitSubjects = @(git log @LogLimit --pretty=%s @LogRange)
$CommitSubjects = @($CommitSubjects | Where-Object { $_ })

# Scan commits for bump level: release patterns (BREAKING CHANGE:, feat:, <any>!:) vs patch
$ReleasePattern = '^\S*!:'
$FeatPattern = '^feat(\([^)]*\))?:'
$BreakingChangePattern = '^BREAKING CHANGE:'

$IsBreakingChangeOrFeature = $false
$CommitSubject = ''

foreach ($Subject in $CommitSubjects) {
  if (-not $CommitSubject) {
    $CommitSubject = $Subject
  }

  if ($Subject -match $ReleasePattern -or $Subject -match $BreakingChangePattern) {
    $IsBreakingChangeOrFeature = $true
    $CommitSubject = $Subject
    break
  } elseif ($Subject -match $FeatPattern -and -not $IsBreakingChangeOrFeature) {
    $IsBreakingChangeOrFeature = $true
    $CommitSubject = $Subject
  }
}

if ($CommitSubjects.Count -eq 0) {
  $CommitSubject = 'No commits since last release'
}

# Get current year and calendar week
$Now = Get-Date -AsUTC
$CurrentWeek = [System.Globalization.ISOWeek]::GetWeekOfYear($Now)
$CurrentYear = [System.Globalization.ISOWeek]::GetYear($Now)

# Determine version
$SameEpoch = $LastStableTag -and ($CurrentYear -le $LastStableYear) -and ($CurrentWeek -le $LastStableWeek)

if ($IsBreakingChangeOrFeature -and -not $SameEpoch) {
  $NewYear = $CurrentYear
  $NewWeek = $CurrentWeek
  $NewPatch = 0
  $BumpType = 'release'
} else {
  $NewYear = $LastStableTag ? $LastStableYear : $CurrentYear
  $NewWeek = $LastStableTag ? $LastStableWeek : $CurrentWeek
  $NewPatch = $LastStablePatch + 1
  $BumpType = 'patch'
}

$TargetBaseVersion = "$NewYear.$NewWeek.$NewPatch"

# Find the last prerelease for this target base version and name
$LastPrereleaseTag = ''
$LastPrereleaseVersion = 0

if ($IsPrerelease -and $HasPrereleaseSuffix) {
  $EscapedName = [regex]::Escape($PrereleaseName)
  foreach ($Tag in $AllTags) {
    $StrippedTag = $Tag -replace "^$([regex]::Escape($PrefixWithDash))", ''
    $Version = $StrippedTag -replace '^v', ''
    if ($Version -match "^(\d+\.\d+\.\d+)-${EscapedName}\.(\d+)$" -and $Matches[1] -eq $TargetBaseVersion) {
      $LastPrereleaseTag = $Tag
      $LastPrereleaseVersion = [int]$Matches[2]
      break
    }
  }
}

# Build the final version string and determine changelog base tag
if ($IsPrerelease -and $HasPrereleaseSuffix) {
  $PrereleaseVersion = $LastPrereleaseVersion + 1
  $NewVersion = "$NewYear.$NewWeek.$NewPatch-$PrereleaseName.$PrereleaseVersion"
  $ChangelogBaseTag = $LastPrereleaseTag ? $LastPrereleaseTag : $LastStableTag
} else {
  $NewVersion = "$NewYear.$NewWeek.$NewPatch"
  $ChangelogBaseTag = $LastStableTag
}

# When no prerelease suffix is provided, derive the predecessor
# from GitHub release metadata (the "latest" / "prerelease" flags) rather than
# from local tag ordering. With a suffix we keep name-neighbor matching.
if (-not $HasPrereleaseSuffix) {
  $NoSuffixTagPattern = '^v\d+\.\d+\.\d+$'

  try {
    if ($IsPrerelease) {
      # Prerelease without a suffix: only treat the newest no-suffix prerelease as the
      # predecessor when it is the direct neighbor of this run (no stable release
      # published between them). If the newest no-suffix stable is more recent, the
      # prerelease was superseded and we must compare against the stable instead.
      $ReleasesJson = gh api "repos/$env:GITHUB_REPOSITORY/releases?per_page=100" 2>$null
      if ($LASTEXITCODE -eq 0 -and $ReleasesJson) {
        $Releases = $ReleasesJson | ConvertFrom-Json
        $Candidates = @($Releases | Where-Object {
            -not $_.draft -and $_.tag_name -match $NoSuffixTagPattern
          })

        $LatestPrereleaseRelease = $Candidates |
        Where-Object { $_.prerelease } |
        Sort-Object -Property published_at -Descending |
        Select-Object -First 1
        $LatestStableRelease = $Candidates |
        Where-Object { -not $_.prerelease } |
        Sort-Object -Property published_at -Descending |
        Select-Object -First 1

        $LatestPrereleasePublishedAt = $LatestPrereleaseRelease ? [datetime]$LatestPrereleaseRelease.published_at : [datetime]::MinValue
        $LatestStablePublishedAt = $LatestStableRelease ? [datetime]$LatestStableRelease.published_at : [datetime]::MinValue

        if ($LatestPrereleaseRelease -and $LatestPrereleasePublishedAt -gt $LatestStablePublishedAt) {
          # Select direct prerelease neighbor as changelog base
          $ChangelogBaseTag = $LatestPrereleaseRelease.tag_name
        } elseif ($LatestStableRelease) {
          # use latest stable release as changelog base
          $ChangelogBaseTag = $LatestStableRelease.tag_name
        }
      } else {
        Write-Host 'GitHub API returned no releases for prerelease predecessor lookup; falling back to git-tag-derived predecessor.'
      }
    } else {
      # Stable release: use whatever GitHub currently flags as "latest".
      $LatestReleaseJson = gh api "repos/$env:GITHUB_REPOSITORY/releases/latest" 2>$null
      if ($LASTEXITCODE -eq 0 -and $LatestReleaseJson) {
        $LatestRelease = $LatestReleaseJson | ConvertFrom-Json
        if ($LatestRelease.tag_name -match $NoSuffixTagPattern) {
          $ChangelogBaseTag = $LatestRelease.tag_name
        }
      } else {
        Write-Host '::warning::GitHub API returned no "latest" release; falling back to git-tag-derived predecessor.'
      }
    }
  } catch {
    Write-Host "::warning::GitHub API predecessor lookup failed, falling back to git-tag-derived predecessor: $_"
  }
}

$NewTag = "${PrefixWithDash}v${NewVersion}"

# Write outputs
"bump_type=$BumpType" >> $env:GITHUB_OUTPUT
"previous_tag=$LastStableTag" >> $env:GITHUB_OUTPUT
"previous_tag_for_changelog=$ChangelogBaseTag" >> $env:GITHUB_OUTPUT
"version=$NewVersion" >> $env:GITHUB_OUTPUT
"tag=$NewTag" >> $env:GITHUB_OUTPUT
"commit_subject=$CommitSubject" >> $env:GITHUB_OUTPUT

Write-Host "Determined $BumpType bump from '$CommitSubject' -> $NewTag"
Write-Host "Changelog will be generated from: $($ChangelogBaseTag ? $ChangelogBaseTag : 'initial commit')"