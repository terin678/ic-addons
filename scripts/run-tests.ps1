<#
.SYNOPSIS
  Run an addon's pure-module test suite headlessly with LuaJIT.

.EXAMPLE
  .\scripts\run-tests.ps1 -Flavor anniversary -Addon MarkedForDeath
#>
param(
    [Parameter(Mandatory = $true)][ValidateSet("era", "anniversary", "retail")][string]$Flavor,
    [Parameter(Mandatory = $true)][string]$Addon
)

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
