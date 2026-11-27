<#
.SYNOPSIS
  Builds the Windows download from the current source tree:

    dist\Baddel-<version>-windows-x64.zip
    dist\Baddel-<version>-windows-x64.zip.sha256

  The ZIP holds one folder with Baddel.exe (self-contained, no .NET install
  needed), LICENSE.txt, README.txt and SHA256SUMS.txt.

.PARAMETER Dotnet
  Path to dotnet.exe. Defaults to the one on PATH.

.NOTES
  Signing is opt-in and uses only a certificate you already have. Set
  BADDEL_SIGN_THUMBPRINT to the thumbprint of a code-signing certificate in
  your certificate store (signtool.exe must be on PATH). Without it the
  executable is not signed, and README.txt in the ZIP says so.
#>
param([string]$Dotnet = "dotnet")
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$version = (Get-Content (Join-Path $root "VERSION") -Raw).Trim()
$name = "Baddel-$version-windows-x64"
$dist = Join-Path $root "dist"
$stage = Join-Path $dist $name
$zip = Join-Path $dist "$name.zip"

if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Force $stage | Out-Null
Remove-Item $zip, "$zip.sha256" -ErrorAction SilentlyContinue

& $Dotnet publish (Join-Path $root "windows\src\Baddel.App\Baddel.App.csproj") `
  -c Release -r win-x64 --self-contained true `
  -p:PublishSingleFile=true -p:EnableCompressionInSingleFile=true `
  -p:IncludeNativeLibrariesForSelfExtract=true -p:DebugType=none `
  -o (Join-Path $dist "publish") --nologo -v q
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed" }
Copy-Item (Join-Path $dist "publish\Baddel.exe") $stage
Remove-Item (Join-Path $dist "publish") -Recurse -Force
Copy-Item (Join-Path $root "LICENSE") (Join-Path $stage "LICENSE.txt")

$signing = "not code-signed"
if ($env:BADDEL_SIGN_THUMBPRINT) {
  & signtool sign /sha1 $env:BADDEL_SIGN_THUMBPRINT /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 (Join-Path $stage "Baddel.exe")
  if ($LASTEXITCODE -ne 0) { throw "signtool failed" }
  $signing = "code-signed"
}

@"
Baddel $version for Windows
Copyright (c) 2026 Mahmood. Released under the MIT License (see LICENSE.txt).
https://github.com/Mahmood83367/baddel

Requirements: Windows 10 or 11, 64-bit (x64). Nothing else to install.

This build is $signing.

Install
  This is a portable app: there is no installer and nothing is written
  outside this folder except your settings (%APPDATA%\Baddel\settings.json).
  1. Extract the whole folder somewhere you can keep it, for example
     %LOCALAPPDATA%\Programs\Baddel.
  2. Run Baddel.exe. It appears as a blue icon in the notification area.
  3. If Windows SmartScreen shows a warning, that is Windows protecting you
     from software it cannot identify because this build is not code-signed.
     Only if you trust this download: choose "More info", then "Run anyway".
     Baddel never changes this protection for you.
  To start it with Windows, put a shortcut to Baddel.exe in the folder that
  opens when you run:  shell:startup
  To remove it, exit Baddel from its icon and delete this folder.

Use
  Shortcut (default Ctrl+Alt+Space):
    once   fixes the selected text, or the last word before the caret
    twice  fixes the whole focused field
  An Undo button appears next to the text for a few seconds.
  Right-click the icon for Settings and About.

Limits
  Baddel does not run elevated, so it cannot edit windows of programs that
  run as administrator. Password fields are always skipped.

Verify this download
  In PowerShell, inside this folder:
    Get-FileHash Baddel.exe -Algorithm SHA256
  and compare with SHA256SUMS.txt.

Redistribution
  Copies and forks that redistribute Baddel must keep the copyright notice
  and the license notice in LICENSE.txt.
"@ | Set-Content (Join-Path $stage "README.txt") -Encoding utf8

# Hash files use LF line endings so `shasum -c` and `sha256sum -c` accept them.
function Write-Lf([string]$path, [string[]]$lines) {
  [IO.File]::WriteAllText($path, (($lines -join "`n") + "`n"), [Text.Encoding]::ASCII)
}

$sums = foreach ($file in "Baddel.exe", "LICENSE.txt", "README.txt") {
  "{0}  {1}" -f (Get-FileHash (Join-Path $stage $file) -Algorithm SHA256).Hash.ToLower(), $file
}
Write-Lf (Join-Path $stage "SHA256SUMS.txt") $sums

Compress-Archive -Path $stage -DestinationPath $zip -CompressionLevel Optimal
Remove-Item $stage -Recurse -Force
$hash = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
Write-Lf "$zip.sha256" @("$hash  $name.zip")
Write-Host "Created dist\$name.zip"
Write-Host "$hash  $name.zip"
