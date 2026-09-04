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

# Required addons from the same flavor (## Dependencies / ## RequiredDeps) ship in the zip,
# so one archive extracts into a working install.
$paths = @($source)
$depLine = $toc | Where-Object { $_ -match '^## (Dependencies|RequiredDeps):\s*(.+)$' } | Select-Object -First 1
if ($depLine -match '^## (Dependencies|RequiredDeps):\s*(.+)$') {
    foreach ($dep in ($Matches[2] -split ',')) {
        $dep = $dep.Trim()
        $depPath = Join-Path $repoRoot "AddonProjects\$Flavor\$dep"
        if ($dep -and (Test-Path $depPath)) { $paths += $depPath }
    }
}

# Written entry by entry rather than with Compress-Archive, which on Windows PowerShell
# 5.1 stores paths with backslashes. The zip spec requires forward slashes: Windows
# Explorer and 7-Zip cope with the backslashes, but macOS Archive Utility and most Linux
# tools do not, and extract the whole addon as one flat file literally named
# "MarkedForDeath\Core.lua". Anything meant to leave this guild has to open anywhere.
# Both: ZipFile and the CreateEntryFromFile extension are in .FileSystem, ZipArchiveMode
# is in the base assembly, and 5.1 loads neither on its own.
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::Open(
    $zip, [System.IO.Compression.ZipArchiveMode]::Create)
$count = 0
try {
    foreach ($path in $paths) {
        $folder = Split-Path -Leaf $path
        foreach ($file in (Get-ChildItem $path -Recurse -File)) {
            $relative = $file.FullName.Substring($path.Length).TrimStart([IO.Path]::DirectorySeparatorChar)
            $entry = ($folder + [IO.Path]::DirectorySeparatorChar + $relative).Replace([IO.Path]::DirectorySeparatorChar, '/')
            [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $archive, $file.FullName, $entry,
                [System.IO.Compression.CompressionLevel]::Optimal)
            $count++
        }
    }
} finally {
    $archive.Dispose()
}

Write-Host "Packaged $zip ($($paths.Count) folders, $count files)"
