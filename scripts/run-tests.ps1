<#
.SYNOPSIS
  Run an addon's pure-module test suite headlessly with LuaJIT.

.EXAMPLE
  .\scripts\run-tests.ps1 -Flavor anniversary -Addon MarkedForDeath
#>
param(
    [Parameter(Mandatory = $true)][string]$Flavor,
    [Parameter(Mandatory = $true)][string]$Addon
)

# Flavors live in one table, flavors.psd1: the game folder, the interface, what ships.
$flavors = Import-PowerShellDataFile (Join-Path $PSScriptRoot "flavors.psd1")
if (-not $flavors.ContainsKey($Flavor)) {
    Write-Error "Unknown flavor '$Flavor'. Known: $(($flavors.Keys | Sort-Object) -join ', ')"
    exit 1
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$addonDir = Join-Path $repoRoot "AddonProjects\$Flavor\$Addon"

if (-not (Test-Path $addonDir)) {
    Write-Error "No addon folder at $addonDir"
    exit 1
}

$luajit = Get-Command luajit -ErrorAction SilentlyContinue
if (-not $luajit) {
    # winget puts it here and adds it to the persisted PATH, but a shell opened
    # before the install will not see it. Fall back rather than fail.
    $fallback = Join-Path $env:LOCALAPPDATA "Programs\LuaJIT\bin\luajit.exe"
    if (Test-Path $fallback) {
        $luajit = Get-Item $fallback
    } else {
        Write-Error "luajit is not on PATH. Install it with: winget install --id DEVCOM.LuaJIT"
        exit 1
    }
}

$exe = if ($luajit.Source) { $luajit.Source } else { $luajit.FullName }
& $exe (Join-Path $PSScriptRoot "test-harness.lua") ($addonDir -replace '\\', '/')
exit $LASTEXITCODE
