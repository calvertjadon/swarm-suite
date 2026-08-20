#!/usr/bin/env pwsh
# Install the swarm gauntlet suite into the user-level OMP agent directory.
# Windows counterpart of install.sh. Idempotent: existing differing files are
# backed up (timestamped .backup).
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$Root = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($env:PI_CODING_AGENT_DIR)) {
    $Dest = Join-Path $HOME '.omp\agent'
} else {
    $Dest = $env:PI_CODING_AGENT_DIR
}

$agentsDst   = Join-Path $Dest 'agents'
$commandsDst = Join-Path $Dest 'commands'
$gatesDst    = Join-Path $Dest 'skills\swarm\templates\gates'
$toolsDst    = Join-Path $Dest 'skills\swarm\templates\tools'

foreach ($d in @($agentsDst, $commandsDst, $gatesDst, $toolsDst)) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
}

function Copy-File {
    param([string]$Src, [string]$Dst)
    if ((Test-Path $Dst) -and
        ((Get-FileHash $Src).Hash -ne (Get-FileHash $Dst).Hash)) {
        $bak = "$Dst.backup.$(Get-Date -Format 'yyyyMMddHHmmss')"
        Copy-Item $Dst $bak
        Write-Host "Backed up existing $Dst -> $bak"
    }
    Copy-Item $Src $Dst -Force
    Write-Host "Installed $Dst"
}

Get-ChildItem (Join-Path $Root 'global\agents') -Filter *.md | ForEach-Object {
    Copy-File $_.FullName (Join-Path $agentsDst $_.Name)
}
Get-ChildItem (Join-Path $Root 'global\commands') -Filter *.md | ForEach-Object {
    Copy-File $_.FullName (Join-Path $commandsDst $_.Name)
}
Copy-File (Join-Path $Root 'global\skills\swarm\SKILL.md') (Join-Path $Dest 'skills\swarm\SKILL.md')
Get-ChildItem (Join-Path $Root 'global\skills\swarm\templates\gates') -File | ForEach-Object {
    Copy-File $_.FullName (Join-Path $gatesDst $_.Name)
}
Get-ChildItem (Join-Path $Root 'global\skills\swarm\templates\tools') -File | ForEach-Object {
    Copy-File $_.FullName (Join-Path $toolsDst $_.Name)
}

# Enable isolated coder workspaces (idempotent; needs the omp CLI on PATH).
if (Get-Command omp -ErrorAction SilentlyContinue) {
    omp config set task.isolation.mode auto
    Write-Host 'Set task.isolation.mode = auto'
} else {
    Write-Host 'NOTE: omp not on PATH - add to ~/.omp/agent/config.yml:'
    Write-Host 'task:'
    Write-Host '  isolation:'
    Write-Host '    mode: auto'
}

Write-Host ''
Write-Host 'Swarm suite installed.'
Write-Host 'Restart any running OMP session before testing discovery.'
Write-Host 'Per-repo onboarding:  cd <repo> && /swarm init   (see README.md)'
