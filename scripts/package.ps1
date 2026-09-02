<#
.SYNOPSIS
  Zip an addon folder for sharing. The archive extracts straight into Interface\AddOns.

.EXAMPLE
  .\scripts\package.ps1 -Flavor anniversary -Addon MalexisAuctionWatcher
#>
param(
    [Parameter(Mandatory = $true)][ValidateSet("era", "anniversary", "retail")][string]$Flavor,
    [Parameter(Mandatory = $true)][string]$Addon
)

$repoRoot = Split-Path -Parent $PSScriptRoot
$source = Join-Path $repoRoot "AddonProjects\$Flavor\$Addon"
if (-not (Test-Path $source)) { throw "No addon at $source" }

$toc = Get-Content (Join-Path $source "$Addon.toc")
$versionLine = $toc | Where-Object { $_ -match '^## Version:\s*(.+)$' } | Select-Object -First 1
$version = if ($versionLine -match '^## Version:\s*(.+)$') { $Matches[1].Trim() } else { "dev" }

$dist = Join-Path $repoRoot "dist"
New-Item -ItemType Directory -Force $dist | Out-Null
$zip = Join-Path $dist "$Addon-$version-$Flavor.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }

Compress-Archive -Path $source -DestinationPath $zip
Write-Host "Packaged $zip"
