<#
.SYNOPSIS
  Link an addon from this repo into a WoW client's AddOns folder with a directory junction.

.EXAMPLE
  .\scripts\deploy.ps1 -Flavor anniversary -Addon MalexisAuctionWatcher
  .\scripts\deploy.ps1 -Flavor anniversary -Addon MalexisAuctionWatcher -Copy   # copy instead of link
#>
param(
    [Parameter(Mandatory = $true)][ValidateSet("era", "anniversary", "retail")][string]$Flavor,
    [Parameter(Mandatory = $true)][string]$Addon,
    [string]$WowRoot = "D:\Program Files (x86)\World of Warcraft",
    [switch]$Copy
)

$flavorFolder = @{ era = "_classic_era_"; anniversary = "_anniversary_"; retail = "_retail_" }[$Flavor]
$repoRoot = Split-Path -Parent $PSScriptRoot
$source = Join-Path $repoRoot "AddonProjects\$Flavor\$Addon"
$addonsDir = Join-Path $WowRoot "$flavorFolder\Interface\AddOns"
$target = Join-Path $addonsDir $Addon

if (-not (Test-Path $source)) { throw "No addon at $source" }
if (-not (Test-Path $addonsDir)) { throw "No AddOns folder at $addonsDir" }

if (Test-Path $target) {
    $item = Get-Item $target -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        Write-Host "Removing existing junction $target"
        [IO.Directory]::Delete($target)
    } else {
        $backup = "$target.bak-" + (Get-Date -Format "yyyyMMdd-HHmmss")
        Write-Host "Existing folder moved to $backup"
        Move-Item $target $backup
    }
}

if ($Copy) {
    Copy-Item $source $target -Recurse
    Write-Host "Copied $source -> $target"
} else {
    New-Item -ItemType Junction -Path $target -Target $source | Out-Null
    Write-Host "Linked $target -> $source"
}
# Required addons from the same flavor are linked too, so the game can load this one.
$toc = Get-Content (Join-Path $source "$Addon.toc")
$depLine = $toc | Where-Object { $_ -match '^## (Dependencies|RequiredDeps):\s*(.+)$' } | Select-Object -First 1
if ($depLine -match '^## (Dependencies|RequiredDeps):\s*(.+)$') {
    foreach ($dep in ($Matches[2] -split ',')) {
        $dep = $dep.Trim()
        $depSource = Join-Path $repoRoot "AddonProjects\$Flavor\$dep"
        $depTarget = Join-Path $addonsDir $dep
        if ($dep -and (Test-Path $depSource) -and -not (Test-Path $depTarget)) {
            if ($Copy) { Copy-Item $depSource $depTarget -Recurse } else { New-Item -ItemType Junction -Path $depTarget -Target $depSource | Out-Null }
            Write-Host "Linked dependency $depTarget -> $depSource"
        }
    }
}
Write-Host "Now /reload in game."
