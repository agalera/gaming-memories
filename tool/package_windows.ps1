#Requires -Version 5.1

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

$releaseDir = Join-Path $projectRoot 'build\windows\x64\runner\Release'
$distDir = if ($env:DIST_DIR) { $env:DIST_DIR } else { 'dist' }
$distDir = Join-Path $projectRoot $distDir

$version = $env:GM_VERSION
if (-not $version) {
    $match = Select-String -Path (Join-Path $projectRoot 'pubspec.yaml') `
        -Pattern '^version:\s*([0-9][0-9.]*)\+' | Select-Object -First 1
    if (-not $match) {
        throw 'Could not read a version from pubspec.yaml. Set GM_VERSION.'
    }
    $version = $match.Matches[0].Groups[1].Value
}

if (-not (Test-Path (Join-Path $releaseDir 'gaming_memories.exe'))) {
    throw "Windows build not found at $releaseDir. Run 'make build-windows BUILD_MODE=release' first."
}

$sevenZip = (Get-Command '7z' -ErrorAction SilentlyContinue)?.Source
if (-not $sevenZip) {
    $sevenZip = Join-Path $env:ProgramFiles '7-Zip\7z.exe'
}
if (-not (Test-Path $sevenZip)) {
    throw '7z was not found. Install 7-Zip and put it on PATH.'
}

# Flutter links the app against the Visual C++ runtime but does not copy it, so
# the three libraries travel with the build.
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path $vswhere)) {
    throw "vswhere was not found at $vswhere."
}
$vsPath = & $vswhere -latest -products * -property installationPath
$redistRoot = Join-Path $vsPath 'VC\Redist\MSVC'
$redistVersion = Get-ChildItem $redistRoot -Directory |
    Where-Object { $_.Name -match '^\d+\.' } |
    Sort-Object { [version]$_.Name } -Descending |
    Select-Object -First 1
$crtDir = Get-ChildItem (Join-Path $redistVersion.FullName 'x64') -Directory -Filter 'Microsoft.VC*.CRT' |
    Select-Object -First 1
if (-not $crtDir) {
    throw "No Microsoft.VC*.CRT directory under $($redistVersion.FullName)\x64."
}

foreach ($dll in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
    $source = Join-Path $crtDir.FullName $dll
    if (-not (Test-Path $source)) {
        throw "Runtime library not found: $source"
    }
    Copy-Item $source (Join-Path $releaseDir $dll) -Force
}

Copy-Item (Join-Path $projectRoot 'LICENSE') (Join-Path $releaseDir 'LICENSE.txt') -Force

New-Item -ItemType Directory -Force -Path $distDir | Out-Null
$work = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Force -Path $work | Out-Null

try {
    $archive = Join-Path $work 'payload.7z'
    & $sevenZip a -t7z -mx=9 -mmt=on $archive (Join-Path $releaseDir '*') | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "7z failed to build $archive." }

    $zipPath = Join-Path $distDir "gaming-memories-$version-windows-x64.zip"
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
    & $sevenZip a -tzip -mx=9 $zipPath (Join-Path $releaseDir '*') | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "7z failed to build $zipPath." }

    $sfx = Join-Path $projectRoot 'build\7zSD.sfx'
    if (-not (Test-Path $sfx)) {
        throw "7zSD.sfx was not found at $sfx. Run tool/fetch_sfx_module.ps1 first."
    }

    # The self-executing .exe is the SFX module, its config and the archive
    # joined end to end. The module unpacks to a temporary folder, starts
    # RunProgram from it, and clears the folder once the app exits.
    $exePath = Join-Path $distDir "gaming-memories-$version-windows-x64.exe"
    Remove-Item $exePath -Force -ErrorAction SilentlyContinue
    $output = [System.IO.File]::Create($exePath)
    try {
        foreach ($part in @($sfx, (Join-Path $projectRoot 'packaging\windows\sfx-config.txt'), $archive)) {
            $input = [System.IO.File]::OpenRead($part)
            try { $input.CopyTo($output) } finally { $input.Dispose() }
        }
    } finally {
        $output.Dispose()
    }

    Write-Host "Windows artifacts written to $distDir."
} finally {
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}
