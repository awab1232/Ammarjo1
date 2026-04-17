# Mirrors scripts/setup-secrets.sh for Algolia secrets only (Windows PowerShell).
# Does not embed secrets in the file — set env vars first, then run.
#
# Example (same session):
#   $env:ALGOLIA_APP_ID = "your-app-id"
#   $env:ALGOLIA_SEARCH_API_KEY = "your-search-key"
#   $env:ALGOLIA_WRITE_API_KEY = "your-write-or-admin-key"
#   .\setup-secrets-algolia.ps1
#
# Optional: $env:GCP_PROJECT_ID = "your-project-id"
#
$ErrorActionPreference = "Stop"

function Get-Gcloud {
    $c = Get-Command gcloud -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    $candidates = @(
        "$env:ProgramFiles\Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd",
        "${env:ProgramFiles(x86)}\Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd",
        "$env:LocalAppData\Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd"
    )
    foreach ($p in $candidates) {
        if (Test-Path $p) { return $p }
    }
    throw "gcloud not found. Install Google Cloud SDK and add it to PATH, or reopen the terminal after install."
}

$Gcloud = Get-Gcloud
Write-Host "Using gcloud: $Gcloud"

$ProjectId = $env:GCP_PROJECT_ID
if (-not $ProjectId) { $ProjectId = $env:GOOGLE_CLOUD_PROJECT }
if (-not $ProjectId) {
    $ProjectId = (& $Gcloud config get-value project 2>$null).Trim()
}
if (-not $ProjectId) {
    throw "Set GCP project: gcloud config set project YOUR_PROJECT_ID or set env GCP_PROJECT_ID"
}
Write-Host "Project: $ProjectId"

function Ensure-SecretExists([string]$Name) {
    & $Gcloud secrets describe $Name --project=$ProjectId 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Creating secret: $Name"
        & $Gcloud secrets create $Name --project=$ProjectId --replication-policy=automatic
        if ($LASTEXITCODE -ne 0) { throw "secrets create failed for $Name" }
    } else {
        Write-Host "Secret already exists: $Name"
    }
}

function Add-SecretVersion([string]$Name, [string]$Value) {
    if ([string]::IsNullOrEmpty($Value)) {
        throw "Missing value for $Name (set env e.g. `$env:ALGOLIA_APP_ID)"
    }
    $tmp = [System.IO.Path]::GetTempFileName()
    try {
        [System.IO.File]::WriteAllText($tmp, $Value)
        & $Gcloud secrets versions add $Name --project=$ProjectId --data-file=$tmp
        if ($LASTEXITCODE -ne 0) { throw "secrets versions add failed for $Name" }
        Write-Host "Added new version for: $Name"
    } finally {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
}

Ensure-SecretExists "ALGOLIA_APP_ID"
Add-SecretVersion "ALGOLIA_APP_ID" $env:ALGOLIA_APP_ID

Ensure-SecretExists "ALGOLIA_SEARCH_API_KEY"
Add-SecretVersion "ALGOLIA_SEARCH_API_KEY" $env:ALGOLIA_SEARCH_API_KEY

Ensure-SecretExists "ALGOLIA_WRITE_API_KEY"
Add-SecretVersion "ALGOLIA_WRITE_API_KEY" $env:ALGOLIA_WRITE_API_KEY

Write-Host ""
Write-Host "Done. Bind to Cloud Run: deploy.sh with USE_SECRET_MANAGER=1 (see docs/SECRETS.md)."
Write-Host "The API reads ALGOLIA_WRITE_API_KEY or ALGOLIA_ADMIN_API_KEY — use WRITE secret name for deploy script."
