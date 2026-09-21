#Requires -Version 5.1

# Downloads 7zSD.sfx, the 7-Zip self-extracting module that makes the Windows
# release a single self-executing .exe. The module is not redistributed in this
# repository, so the packaging step fetches it and checks it against a pinned
# digest of the whole 7-Zip Extra archive.

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$url = 'https://www.7-zip.org/a/7z2501-extra.7z'
$expectedSha256 = 'CD3CF38085C2CC6839CF72716DAFB3175AE425F4FD34FAAFC6C0B64D618D307F'
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
    $archive = Join-Path $work '7z-extra.7z'
    Invoke-WebRequest -Uri $url -OutFile $archive -UseBasicParsing

    $actual = (Get-FileHash $archive -Algorithm SHA256).Hash
    if ($actual -ne $expectedSha256) {
        throw "Checksum mismatch for $url. Expected $expectedSha256, got $actual."
    }

    & $sevenZip e $archive "-o$work" '7zSD.sfx' -r -y | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "7z failed to extract 7zSD.sfx from $archive." }

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
