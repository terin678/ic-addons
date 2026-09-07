<#
.SYNOPSIS
  Build the CurseForge upload set: one zip per published addon, each holding only its own
  folder, plus a manifest with versions, checksums and the recent commits to paste into
  each project's changelog box.

.DESCRIPTION
  Lints, runs every addon's headless cases, then packages ICLibs and the published addons
  into dist\curseforge (git-ignored). Older zips of the same addon are removed first, so
  the folder always holds exactly the current set. Stops at the first lint or test failure:
  nothing half-built reaches the folder.

  ICLibs is its own CurseForge project. Every other addon lists it under ## Dependencies
  and must mark it as a Required Dependency in its CurseForge project relations; the
  manifest says so beside each row. Upload ICLibs first when it changed.

  -Addon narrows the set; -SkipTests skips the headless runs (lint still runs).

.EXAMPLE
  .\scripts\release.ps1
  .\scripts\release.ps1 -Addon MalexisAuctionWatcher
  .\scripts\release.ps1 -OutDir E:\CurseForge\ic-addons
#>
param(
    [ValidateSet("era", "anniversary", "retail")][string]$Flavor = "anniversary",
    [string[]]$Addon,
    [string]$OutDir,
    [switch]$SkipTests
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$scripts = $PSScriptRoot

# What goes up, in upload order: the library first, since everything else depends on it.
# AuctionatorSellingTweaks, CutMaster and ICTemplate stay local on purpose.
$PUBLISHED = @("ICLibs", "MalexisAuctionWatcher", "TradeMaster", "GuildRecruitment", "MarkedForDeath")
$set = if ($Addon) { $Addon } else { $PUBLISHED }
foreach ($name in $set) {
    if ($PUBLISHED -notcontains $name) { throw "$name is not in the published set ($($PUBLISHED -join ', '))" }
}

$dist = if ($OutDir) { $OutDir } else { Join-Path $repoRoot "dist\curseforge" }
if (-not [IO.Path]::IsPathRooted($dist)) { $dist = Join-Path $repoRoot $dist }
New-Item -ItemType Directory -Force $dist | Out-Null

# Where the tree stands. Warned, not refused: a hotfix from a branch is a real case, but
# the manifest records it so nobody uploads a build they thought was main.
Push-Location $repoRoot
try {
    $branch = (git branch --show-current).Trim()
    $commit = (git rev-parse --short HEAD).Trim()
    $dirty = @(git status --porcelain).Count -gt 0
} finally { Pop-Location }
if ($branch -ne "main") { Write-Warning "Building from branch '$branch', not main." }
if ($dirty) { Write-Warning "The working tree has uncommitted changes; the zips will contain them." }

# Lint, then the headless cases. A failure here is the whole point of running them first.
Write-Host "== Lint"
& python (Join-Path $scripts "lint.py")
if ($LASTEXITCODE -ne 0) { throw "lint failed; nothing packaged" }

if (-not $SkipTests) {
    foreach ($name in $set) {
        if (Test-Path (Join-Path $repoRoot "AddonProjects\$Flavor\$name\Tests.lua")) {
            Write-Host "== Tests: $name"
            & (Join-Path $scripts "run-tests.ps1") -Flavor $Flavor -Addon $name
            if ($LASTEXITCODE -ne 0) { throw "$name tests failed; nothing packaged" }
        }
    }
}

# Package. Each zip is the one folder, named <Addon>-<version>.zip, and its predecessors
# in the folder go, so what is there is what to upload.
$rows = @()
foreach ($name in $set) {
    $source = Join-Path $repoRoot "AddonProjects\$Flavor\$name"
    $toc = Get-Content (Join-Path $source "$name.toc")
    $version = "dev"
    $interface = "?"
    foreach ($line in $toc) {
        if ($line -match '^## Version:\s*(.+)$') { $version = $Matches[1].Trim() }
        if ($line -match '^## Interface:\s*(.+)$') { $interface = $Matches[1].Trim() }
    }
    $depends = @()
    foreach ($line in $toc) {
        if ($line -match '^## (Dependencies|RequiredDeps):\s*(.+)$') {
            $depends = @($Matches[2] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        }
    }

    Get-ChildItem $dist -Filter "$name-*.zip" | Remove-Item -Force

    Write-Host "== Package: $name $version"
    $zip = & (Join-Path $scripts "package.ps1") -Flavor $Flavor -Addon $name -NoDeps -OutDir $dist | Select-Object -Last 1
    $hash = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
    $size = [math]::Round((Get-Item $zip).Length / 1KB)

    Push-Location $repoRoot
    try {
        $log = @(git log --no-merges --format="- %s" -n 12 -- "AddonProjects/$Flavor/$name")
    } finally { Pop-Location }

    $rows += [pscustomobject]@{
        Name = $name; Version = $version; Interface = $interface; Zip = Split-Path -Leaf $zip
        SizeKB = $size; Sha256 = $hash; Depends = $depends; Log = $log
    }
}

# The manifest: the table to check against the CurseForge file list, and per addon the
# commits to paste into the changelog box, newest first.
$stamp = Get-Date -Format "yyyy-MM-dd HH:mm"
$lines = @(
    "# CurseForge upload set",
    "",
    "Built $stamp from ``$branch`` at ``$commit``$(if ($dirty) { ' (working tree had uncommitted changes)' }).",
    "Flavor ``$Flavor``. Each zip holds one addon folder and extracts into Interface\AddOns.",
    "",
    "Upload ICLibs first when it changed. On every other project, mark **ICLibs** as a",
    "Required Dependency under Relations; the zips do not carry it.",
    "",
    "| Addon | Version | Interface | Zip | KB | Requires | SHA-256 |",
    "| --- | --- | --- | --- | --- | --- | --- |"
)
foreach ($r in $rows) {
    $req = if ($r.Depends.Count -gt 0) { $r.Depends -join ", " } else { "-" }
    $lines += "| $($r.Name) | $($r.Version) | $($r.Interface) | ``$($r.Zip)`` | $($r.SizeKB) | $req | ``$($r.Sha256)`` |"
}
foreach ($r in $rows) {
    $lines += ""
    $lines += "## $($r.Name) $($r.Version)"
    $lines += ""
    $lines += "Recent commits touching it, for the changelog box:"
    $lines += ""
    if ($r.Log.Count -gt 0) { $lines += $r.Log } else { $lines += "- (no commits found)" }
}
$manifest = Join-Path $dist "MANIFEST.md"
[IO.File]::WriteAllLines($manifest, $lines, (New-Object System.Text.UTF8Encoding $false))

Write-Host ""
Write-Host "Release set in $dist"
foreach ($r in $rows) { Write-Host ("  {0,-24} {1,-8} {2}" -f $r.Name, $r.Version, $r.Zip) }
Write-Host "  MANIFEST.md lists checksums and the commits to paste into each changelog."
