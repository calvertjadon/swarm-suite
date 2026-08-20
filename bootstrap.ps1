#!/usr/bin/env pwsh
# One-command installer for the OMP swarm suite (github.com/calvertjadon/swarm-suite).
# Windows counterpart of bootstrap.sh: downloads the repo tarball, installs to
# $env:SWARM_SUITE_DIR (default ~/.local/share/swarm-suite), runs install.ps1.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Repo = 'calvertjadon/swarm-suite'
$Ref  = 'main'
if ([string]::IsNullOrWhiteSpace($env:SWARM_SUITE_DIR)) {
    $Dest = Join-Path $HOME '.local\share\swarm-suite'
} else {
    $Dest = $env:SWARM_SUITE_DIR
}

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("swarm-suite-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null

try {
    $tarPath = Join-Path $tmp 'suite.tar.gz'
    Write-Host "swarm-suite: downloading $Repo@$Ref ..."
    Invoke-WebRequest -Uri "https://codeload.github.com/$Repo/tar.gz/refs/heads/$Ref" -OutFile $tarPath

    tar -xzf $tarPath -C $tmp
    $top = Get-ChildItem $tmp -Directory | Select-Object -First 1
    if (-not $top) { throw 'archive has no top-level directory' }

    New-Item -ItemType Directory -Force -Path (Split-Path $Dest -Parent) | Out-Null
    if (Test-Path $Dest) {
        $backup = "$Dest.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
        Move-Item $Dest $backup
        Write-Host "swarm-suite: existing install moved to $backup"
    }
    Move-Item $top.FullName $Dest

    Set-Location $Dest
    & (Join-Path $Dest 'install.ps1')

    Write-Host ''
    Write-Host "swarm-suite installed to $Dest"
    Write-Host "Verify:   bash $Dest\tests\gates-test.sh   (expect 30 pass, 0 fail)"
    Write-Host 'Onboard:  cd <repo> && git init && /swarm init'
}
finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
