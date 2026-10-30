$ErrorActionPreference = 'Stop'

$TagName = $env:TAG_NAME
$GithubSha = $env:GITHUB_SHA
$GithubToken = $env:GITHUB_TOKEN

git rev-parse -q --verify "refs/tags/$TagName" *> $null
if ($LASTEXITCODE -eq 0) {
  throw "Tag $TagName already exists. Aborting creation."
}

git tag $TagName $GithubSha
if ($LASTEXITCODE -ne 0) {
  throw "Failed to create tag $TagName"
}

# Explicit auth required as credentials are not persisted in checkout-step
$EncodedCredential = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("x-access-token:$GithubToken"))
$AuthorizationHeader = "AUTHORIZATION: basic $EncodedCredential"
git -c http.extraheader="$AuthorizationHeader" push origin $TagName
if ($LASTEXITCODE -ne 0) {
  throw "Failed to push tag $TagName"
}
Write-Host "Pushed tag $TagName"
