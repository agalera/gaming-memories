#Requires -Version 5.1

# Downloads 7zSD.sfx, the 7-Zip self-extracting module that makes the Windows
# release a single self-executing .exe. The module ships in the LZMA SDK; the
# 7-Zip Extra package has not carried an SFX module since 7-Zip 19. It is not
# redistributed in this repository, so the packaging step fetches it and checks
# the SDK archive against a pinned digest first.

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$url = 'https://www.7-zip.org/a/lzma2501.7z'
$expectedSha256 = 'CBC3BABD589D971E45971D787FF100BE8AAA5EAB15B2694497EC3E447009E1F2'
$destination = Join-Path $projectRoot 'build\7zSD.sfx'

if (Test-Path $destination) {
    Write-Host "7zSD.sfx is already present at $destination."
    exit 0
}

$sevenZip = (Get-Command '7z' -ErrorAction SilentlyContinue)?.Source
if (-not $sevenZip) {
    $sevenZip = Join-Path $env:ProgramFiles '7-Zip\7z.exe'
}
if (-not (Test-Path $sevenZip)) {
    throw '7z was not found. Install 7-Zip and put it on PATH.'
}

$work = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Force -Path $work | Out-Null

try {
    $archive = Join-Path $work 'lzma-sdk.7z'
    Invoke-WebRequest -Uri $url -OutFile $archive -UseBasicParsing

    $actual = (Get-FileHash $archive -Algorithm SHA256).Hash
    if ($actual -ne $expectedSha256) {
        throw "Checksum mismatch for $url. Expected $expectedSha256, got $actual."
    }

    & $sevenZip e $archive "-o$work" 'bin/7zSD.sfx' -y | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "7z failed to extract bin/7zSD.sfx from $archive." }

    $extracted = Join-Path $work '7zSD.sfx'
    if (-not (Test-Path $extracted)) {
        throw "7zSD.sfx was not found inside $url."
    }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
    Move-Item $extracted $destination -Force
    Write-Host "7zSD.sfx written to $destination."
} finally {
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}
