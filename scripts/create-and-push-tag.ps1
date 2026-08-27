$ErrorActionPreference = 'Stop'

git rev-parse -q --verify "refs/tags/$($env:TAG_NAME)" 2>$null
if ($LASTEXITCODE -eq 0) {
  Write-Host "Tag $($env:TAG_NAME) already exists. Skipping creation."
  exit 0
}

git tag $env:TAG_NAME $env:GITHUB_SHA
if ($LASTEXITCODE -ne 0) {
  throw 'Failed to create tag'
}
# Explicit auth required as credentials are not persisted in checkout-step
$EncodedCredential = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("x-access-token:$($env:GITHUB_TOKEN)"))
$AuthorizationHeader = "AUTHORIZATION: basic $EncodedCredential"
git -c http.extraheader="$AuthorizationHeader" push origin $env:TAG_NAME
if ($LASTEXITCODE -ne 0) {
  throw 'Failed to push tag'
}
Write-Host "Pushed tag $($env:TAG_NAME)"
