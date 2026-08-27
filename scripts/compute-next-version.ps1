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
