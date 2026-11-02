# MindPalace installer for Windows (PowerShell).
# Finds Git Bash (Claude Code on Windows already requires Git for Windows) and runs install.sh with the same arguments.
#   powershell -ExecutionPolicy Bypass -File install.ps1 --yes --vault ~/MindPalace --name "Ada" --lang English
$ErrorActionPreference = "Stop"

$candidates = @()
if ($env:CLAUDE_CODE_GIT_BASH_PATH) { $candidates += $env:CLAUDE_CODE_GIT_BASH_PATH }
$candidates += @(
  "$env:ProgramFiles\Git\bin\bash.exe",
  "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
  "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
)
$gitCmd = Get-Command git.exe -ErrorAction SilentlyContinue
if ($gitCmd) { $candidates += (Join-Path (Split-Path (Split-Path $gitCmd.Source)) "bin\bash.exe") }

$bash = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $bash) {
  Write-Host "Git Bash not found. Install Git for Windows first:  winget install Git.Git" -ForegroundColor Yellow
  exit 1
}

$script = Join-Path $PSScriptRoot "install.sh"
Write-Host "Using $bash"
& $bash $script @args
exit $LASTEXITCODE
