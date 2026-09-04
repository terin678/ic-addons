<#
.SYNOPSIS
  Start a new addon by copying ICTemplate and rewriting its three tokens.

.DESCRIPTION
  A rename touches five files inside the addon folder and three shared files outside it,
  and the linter enforces a three-way version match that a hand checklist gets wrong the
  first time. This does the copy, the rewrite and the registration, then runs the linter
  on the result, so a new addon is proven clean before it is ever loaded.

  The three tokens, and nothing else, carry the addon's name:
    ICTemplate   the .toc filename and title, the icon path, both saved-variable globals,
                 the chat prefix, the window frame name, the LibDataBroker object, and the
                 two globals a key binding calls
    ICTEMPLATE   SLASH_*, the SlashCmdList key, the BINDING_* globals, Bindings.xml
    ictpl        the slash command itself, and every mention of it in help text

  The guild mark at the front of the title and the `## Group: ICLibs` line are carried
  over untouched, and `-Category` defaults to the guild heading, so a new addon joins the
  family in the in-game AddOns list on the day it is made rather than whenever somebody
  notices it has not. Pass `-Category` only for an addon that should sit somewhere else;
  any other value takes the addon out from under the Impulse Control heading.

.EXAMPLE
  .\scripts\new-addon.ps1 -Name GuildRecruitment -Slash gr -Title "Guild Recruitment" `
      -Notes "Shared recruitment message and a log of who barked when" `
      -Minimal -Deploy
#>
param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Slash,
    [string]$Title,
    [string]$Notes = "",
    # The guild heading in the in-game AddOns list. Anything else takes the new addon out
    # from under it, which is the one part of a rename nobody notices until they log in.
    [string]$Category = "Impulse Control",
    [ValidateSet("era", "anniversary", "retail")][string]$Flavor = "anniversary",
    [string]$From = "ICTemplate",
    [string]$Version = "0.1.0",
    [switch]$Minimal,
    [switch]$Deploy,
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

# Set-Content -Encoding UTF8 writes a byte order mark on PowerShell 5.1, and a BOM in
# front of a .lua file is a parse error the client reports as a token it cannot
# recognise. Write plain UTF-8 instead, leaving the line endings exactly as they were
# read: .gitattributes wants LF in .lua, .toc and .xml.
$Utf8NoBom = New-Object System.Text.UTF8Encoding $false
function Write-Text {
    param([string]$Path, [string]$Text)
    [IO.File]::WriteAllText($Path, $Text, $Utf8NoBom)
}
$projects = Join-Path $repoRoot "AddonProjects\$Flavor"
$source = Join-Path $projects $From
$target = Join-Path $projects $Name

if (-not $Title) { $Title = $Name }

# ---------------------------------------------------------------- refuse early

if ($Name -notmatch '^[A-Z][A-Za-z0-9]*$') {
    throw "-Name must be PascalCase with no spaces: '$Name' is not. The folder, the .toc and the saved-variable globals are all built from it."
}
if ($Slash -notmatch '^[a-z][a-z0-9]*$') {
    throw "-Slash must be lower case letters and digits, with no leading slash: '$Slash' is not."
}
if (-not (Test-Path $source)) { throw "No addon to copy from at $source" }
if (Test-Path $target) { throw "$target already exists. Delete it or pick another name." }

# A slash collision is the failure nobody predicts: both addons load, one silently
# owns the command, and the other looks broken.
$taken = Select-String -Path (Join-Path $repoRoot "AddonProjects\*\*\*.lua") `
    -Pattern ('^\s*SLASH_\w+\d*\s*=\s*"/{0}"' -f [regex]::Escape($Slash)) -ErrorAction SilentlyContinue
if ($taken) {
    throw "/$Slash is already registered by $($taken[0].Path). Pick another."
}

$upper = $Name.ToUpper()
Write-Host "New addon $Name ($Flavor), slash /$Slash, from $From"
if ($WhatIf) { Write-Host "-WhatIf: nothing will be written." }

# --------------------------------------------------------------- copy and rename

if (-not $WhatIf) {
    Copy-Item $source $target -Recurse
    Rename-Item (Join-Path $target "$From.toc") "$Name.toc"
    $tga = Join-Path $target "$From.tga"
    if (Test-Path $tga) { Rename-Item $tga "$Name.tga" }
}

$fromUpper = $From.ToUpper()
# Read the source addon's own slash so it can be rewritten without being passed in.
$fromSlash = "ictpl"
$coreText = Get-Content (Join-Path $source "Core.lua") -Raw
if ($coreText -match 'SLASH_\w+1\s*=\s*"/(\w+)"') { $fromSlash = $Matches[1] }

$files = @()
if (-not $WhatIf) {
    # Top level only: the vendored libraries under Libs\ are nobody's to rewrite.
    $files = Get-ChildItem $target -File | Where-Object { $_.Extension -in ".lua", ".toc", ".xml" }
}

foreach ($file in $files) {
    $text = Get-Content $file.FullName -Raw
    $text = $text -creplace [regex]::Escape($fromUpper), $upper
    $text = $text -creplace [regex]::Escape($From), $Name
    $text = $text -creplace ('/{0}\b' -f [regex]::Escape($fromSlash)), "/$Slash"
    Write-Text $file.FullName $text
    Write-Host "  rewrote $($file.Name)"
}

# ------------------------------------------------------------------ toc header

if (-not $WhatIf) {
    $tocPath = Join-Path $target "$Name.toc"
    $toc = Get-Content $tocPath -Raw
    # The source addon's title carries the guild mark, and overwriting the whole
    # line would drop it -- so the new addon would fall out of the group's look on
    # the day it was made. Lift the |T...|t escape off the front and keep it.
    $mark = ""
    if ($toc -match '(?m)^## Title:\s*(\|T[^|]*\|t)') { $mark = $Matches[1] + " " }
    $toc = $toc -replace '(?m)^## Title:.*$', "## Title: $mark$Title"
    $toc = $toc -replace '(?m)^## Category:.*$', "## Category: $Category"
    if ($Notes) { $toc = $toc -replace '(?m)^## Notes:.*$', "## Notes: $Notes" }
    $toc = $toc -replace '(?m)^## Version:.*$', "## Version: $Version"
    $toc = $toc -replace '(?m)^## X-Category:.*\r?\n', ""
    Write-Text $tocPath $toc

    $corePath = Join-Path $target "Core.lua"
    $core = Get-Content $corePath -Raw
    $core = $core -replace 'local VERSION = "[^"]*"', "local VERSION = `"$Version`""
    Write-Text $corePath $core
}

# --------------------------------------------------------------------- minimal

if ($Minimal -and -not $WhatIf) {
    $drop = @("Demos.lua", "Snippet.lua", "UI_Gallery.lua", "UI_Table.lua")
    foreach ($file in $drop) {
        $path = Join-Path $target $file
        if (Test-Path $path) { Remove-Item $path }
    }

    $tocPath = Join-Path $target "$Name.toc"
    $lines = Get-Content $tocPath | Where-Object { $drop -notcontains $_.Trim() }
    Write-Text $tocPath (($lines -join "`n") + "`n")

    # The gallery's cases are fenced by markers put there for exactly this cut.
    $testsPath = Join-Path $target "Tests.lua"
    $tests = Get-Content $testsPath -Raw
    $tests = $tests -replace '(?s)-- >>> gallery tests.*?-- <<< gallery tests\r?\n?', ''
    Write-Text $testsPath $tests

    Write-Host "  -Minimal: dropped the gallery and its cases"
}

# ---------------------------------------------------------------- registration

function Add-Row {
    param([string]$Path, [string]$After, [string]$Row)
    if ($WhatIf) { Write-Host "  would add a row to $Path"; return }
    $text = Get-Content $Path -Raw
    if ($text -match [regex]::Escape($Row)) { return }
    $text = $text -replace [regex]::Escape($After), ($After + "`n" + $Row)
    Write-Text $Path $text
    Write-Host "  registered in $($Path.Substring($repoRoot.Length + 1))"
}

$flavorReadme = Join-Path $projects "README.md"
$lastRow = (Get-Content $flavorReadme | Where-Object { $_ -match '^\| \w' } | Select-Object -Last 1)
Add-Row -Path $flavorReadme -After $lastRow `
    -Row "| $Name | $Version | [Docs/$Name.md](../../Docs/$Name.md) |"

$rootReadme = Join-Path $repoRoot "README.md"
$lastAddon = (Get-Content $rootReadme | Where-Object { $_ -match '^\| \w+ \| \[' } | Select-Object -Last 1)
Add-Row -Path $rootReadme -After $lastAddon `
    -Row "| $Flavor | [$Name](AddonProjects/$Flavor/$Name) | $Notes Guide: [Docs/$Name.md](Docs/$Name.md) |"

$docsReadme = Join-Path $repoRoot "Docs\README.md"
# That index runs one guide per addon and then the shared references, so anchor on the last
# addon guide rather than the last row: appending blindly files the new addon after
# client-reference.md, which is how GuildRecruitment ended up there.
$lastDoc = (Get-Content $docsReadme |
    Where-Object { $_ -match '^\| \[' -and $_ -notmatch 'client-reference' } |
    Select-Object -Last 1)
Add-Row -Path $docsReadme -After $lastDoc -Row "| [$Name.md]($Name.md) | $Notes |"

$guide = Join-Path $repoRoot "Docs\$Name.md"
if (-not $WhatIf -and -not (Test-Path $guide)) {
    $stub = @"
# $Title

$Notes

## Install

``````powershell
.\scripts\deploy.ps1 -Flavor $Flavor -Addon $Name
``````

## Commands

| Command | Effect |
| --- | --- |
| ``/$Slash`` | Open or close the window |
| ``/$Slash test`` | Run the test suite |

## What the client will not let it do

Not written yet.

## Disclaimer

Not written yet.
"@
    Write-Text $guide ($stub + "`n")
    Write-Host "  wrote Docs\$Name.md"
}

# ---------------------------------------------------------------------- verify

if ($WhatIf) { Write-Host "-WhatIf: done, nothing written."; return }

Write-Host ""
Write-Host "Linting $Name..."
& python (Join-Path $repoRoot "scripts\lint.py") $Name
if ($LASTEXITCODE -ne 0) {
    throw "$Name does not lint clean. Fix the findings above before loading it."
}

if ($Deploy) {
    & (Join-Path $PSScriptRoot "deploy.ps1") -Flavor $Flavor -Addon $Name
}

Write-Host ""
Write-Host "$Name is ready. Next:"
Write-Host "  - delete what you do not need (Pulse.lua if nothing is on a timer)"
Write-Host "  - write Docs\$Name.md"
Write-Host "  - /$Slash in game"
