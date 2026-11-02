# =============================================================================
# free-ai-lab - Lesson 11: is my Windows laptop ready for OpenJarvis?
#
# Check only (changes nothing):
#   irm https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/scripts/11-check-laptop.ps1 | iex
#
# Check AND fix the Python PATH (puts your newest supported Python first, for your user only):
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/scripts/11-check-laptop.ps1))) -Fix
#
# Run it in a NORMAL PowerShell window (not "Run as administrator").
# It never deletes anything and never asks for keys or passwords.
# Works in Windows PowerShell 5.1 and PowerShell 7.
# =============================================================================
param([switch]$Fix)

$script:fails = 0
$script:warns = 0
function Ok($m)   { Write-Host "  [ok]   $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  [warn] $m" -ForegroundColor Yellow; $script:warns++ }
function Bad($m)  { Write-Host "  [fail] $m" -ForegroundColor Red; $script:fails++ }
function Info($m) { Write-Host "         $m" }
function Step($m) { Write-Host ""; Write-Host "== $m" -ForegroundColor Cyan }

Write-Host "free-ai-lab - laptop check for OpenJarvis" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
Step "1/8  Windows and PowerShell window"
$build = [Environment]::OSVersion.Version.Build
if ($build -ge 17763) { Ok "Windows build $build" } else { Bad "Windows build $build is too old (need Windows 10 1809+ or Windows 11)" }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdmin) {
    Warn "This window runs as Administrator (that's why the prompt says C:\WINDOWS\system32)."
    Info "Close it and open PowerShell from the Start menu normally, so OpenJarvis installs for YOUR user."
} else {
    Ok "Normal (non-admin) window"
}

# ---------------------------------------------------------------------------
Step "2/8  Python (OpenJarvis needs 3.10 - 3.13)"
$pythons = @()
if (Get-Command py -ErrorAction SilentlyContinue) {
    foreach ($line in (py -0p 2>$null)) {
        if ($line -match '-V:(\d+)\.(\d+)\S*\s+\*?\s*(\S.*python\.exe)\s*$') {
            $pythons += [pscustomobject]@{ Major = [int]$matches[1]; Minor = [int]$matches[2]; Path = $matches[3].Trim() }
        }
    }
}
if ($pythons.Count -eq 0) {
    Bad "No Python found by the 'py' launcher."
    Info "Install Python 3.13 (64-bit) from https://www.python.org/downloads/windows/ and tick 'Add python.exe to PATH'."
}
foreach ($p in $pythons) {
    $v = "$($p.Major).$($p.Minor)"
    if ($p.Major -eq 3 -and $p.Minor -ge 10 -and $p.Minor -le 13) { Ok "Python $v  ($($p.Path))" }
    else { Warn "Python $v is installed but NOT supported (3.14+ has no numpy wheels for Windows yet). Uninstall it in Settings > Apps if you don't need it." }
}
$good = $pythons | Where-Object { $_.Major -eq 3 -and $_.Minor -ge 10 -and $_.Minor -le 13 } | Sort-Object Minor -Descending | Select-Object -First 1

$cmd = Get-Command python -ErrorAction SilentlyContinue
$current = $null
if ($cmd -and $cmd.Source -notlike "*WindowsApps*") {
    $out = (& python --version) 2>&1 | Out-String
    if ($out -match 'Python (\d+)\.(\d+)') { $current = [pscustomobject]@{ Major = [int]$matches[1]; Minor = [int]$matches[2] } }
}
$pathOk = $current -and $current.Major -eq 3 -and $current.Minor -ge 10 -and $current.Minor -le 13
if ($pathOk) {
    Ok "'python' runs Python $($current.Major).$($current.Minor)"
} elseif ($good) {
    $dir = Split-Path $good.Path
    if ($Fix) {
        $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
        $parts = @()
        if ($userPath) { $parts = $userPath.Split(';') | Where-Object { $_ -and $_ -ne $dir -and $_ -ne "$dir\Scripts" } }
        $newPath = (@($dir, "$dir\Scripts") + $parts) -join ';'
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        $env:Path = "$dir;$dir\Scripts;" + $env:Path
        $out = (& python --version) 2>&1 | Out-String
        Ok "Fixed: Python $($good.Major).$($good.Minor) is now first on your user PATH ($($out.Trim()))"
        Info "Open NEW PowerShell windows from now on so they see it too."
    } else {
        Bad "'python' is missing or not a supported version, although Python $($good.Major).$($good.Minor) is installed."
        Info "Re-run this script with -Fix (see the top of the lesson) to put it first on your PATH."
    }
} else {
    Bad "'python' does not run a supported Python."
}

# ---------------------------------------------------------------------------
Step "3/8  git (the installer downloads OpenJarvis with git)"
$git = Get-Command git -ErrorAction SilentlyContinue
if ($git) { Ok ((& git --version) 2>&1 | Out-String).Trim() }
else {
    Bad "git is not installed or not on PATH."
    Info "Install 'Git for Windows' (64-bit) from https://git-scm.com/download/win, keep the default options, then open a NEW window."
}

# ---------------------------------------------------------------------------
Step "3b   Microsoft C++ Build Tools (OpenJarvis compiles part of itself on Windows)"
function Test-MsvcLinker {
    foreach ($cmd in @(Get-Command link.exe -All -CommandType Application -ErrorAction SilentlyContinue)) {
        $item = Get-Item -LiteralPath $cmd.Source -ErrorAction SilentlyContinue
        if ($item -and $item.VersionInfo.CompanyName -match '^Microsoft' -and $item.VersionInfo.OriginalFilename -ieq 'link.exe') { return $true }
    }
    if (-not ${env:ProgramFiles(x86)}) { return $false }
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) { return $false }
    $found = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -find 'VC\Tools\MSVC\**\bin\Host*\*\link.exe' 2>$null
    foreach ($linker in $found) { if (Test-Path -LiteralPath $linker -PathType Leaf) { return $true } }
    return $false
}
if (Test-MsvcLinker) { Ok "C++ build tools present" }
else {
    Bad "Microsoft C++ Build Tools not found (the OpenJarvis installer stops without them)."
    Info "Download 'Build Tools for Visual Studio' from https://visualstudio.microsoft.com/downloads/ (scroll to 'Tools for Visual Studio'),"
    Info "tick 'Desktop development with C++', Install (about 7 GB, 20-40 minutes), then restart the laptop."
}

# ---------------------------------------------------------------------------
Step "3c   Rust (OpenJarvis's native part is written in Rust)"
$cargo = Get-Command cargo -ErrorAction SilentlyContinue
if (-not $cargo -and (Test-Path "$HOME\.cargo\bin\cargo.exe")) { $cargo = "$HOME\.cargo\bin\cargo.exe" }
if ($cargo) { Ok ((& $cargo --version) 2>&1 | Out-String).Trim() }
else {
    Bad "Rust isn't installed. Without it, OpenJarvis downloads a temporary copy, which Windows Security may block."
    Info "Install it from https://rustup.rs (rustup-init.exe, 64-bit, press Enter for the defaults), then open a NEW PowerShell."
}
if (Test-Path "$env:LOCALAPPDATA\puccinialin") {
    Warn "Leftover temporary Rust from a failed install: $env:LOCALAPPDATA\puccinialin (safe to delete)"
}

# ---------------------------------------------------------------------------
Step "4/8  Ollama (local models, the laptop's offline fallback)"
if (Get-Command ollama -ErrorAction SilentlyContinue) {
    Ok ((& ollama --version) 2>&1 | Out-String).Trim()
    try {
        $tags = Invoke-RestMethod -Uri "http://127.0.0.1:11434/api/tags" -TimeoutSec 5
        Ok "Ollama is running"
        if ($tags.models.Count -eq 0) { Warn "No models yet. Lesson 12 picks one." }
        foreach ($m in $tags.models) { Info ("model: {0}  ({1:N1} GB)" -f $m.name, ($m.size / 1GB)) }
    } catch {
        Bad "Ollama is installed but not running. Open 'Ollama' from the Start menu, then re-run this check."
    }
} else {
    Bad "Ollama is not installed. Get it from https://ollama.com/download/windows"
}

# ---------------------------------------------------------------------------
Step "5/8  Leftovers from earlier OpenJarvis / OpenClaw / Hermes installs"
$left = @(
    "$HOME\.openjarvis",
    "$HOME\OpenJarvis",
    "$env:LOCALAPPDATA\OpenJarvis",
    "$env:LOCALAPPDATA\com.openjarvis.desktop",
    "$env:LOCALAPPDATA\OpenClawTray",
    "$env:APPDATA\OpenClawTray",
    "$env:LOCALAPPDATA\hermes"
) | Where-Object { (Test-Path $_) -and (Get-ChildItem $_ -Force -ErrorAction SilentlyContinue | Select-Object -First 1) }
if ($left) { foreach ($l in $left) { Warn "Not empty: $l  (see Lesson 11, Part C)" } } else { Ok "No old install folders with content" }

$tasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -match 'jarvis|openclaw|hermes' })
if ($tasks.Count -gt 0) { foreach ($t in $tasks) { Warn "Old scheduled task: $($t.TaskName)" } } else { Ok "No old scheduled tasks" }

$procs = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -match 'jarvis|openclaw|hermes' })
if ($procs.Count -gt 0) { foreach ($p in $procs) { Warn "Still running: $($p.Name) ($($p.Path))" } } else { Ok "No old processes running" }

# ---------------------------------------------------------------------------
Step "6/8  Disk space (OpenJarvis needs about 5 GB)"
$drive = (Split-Path $env:LOCALAPPDATA -Qualifier).TrimEnd(':')
$free = (Get-PSDrive $drive).Free / 1GB
if ($free -ge 10) { Ok ("{0:N0} GB free on {1}:" -f $free, $drive) }
elseif ($free -ge 5) { Warn ("Only {0:N0} GB free on {1}: - enough, but tight with models" -f $free, $drive) }
else { Bad ("Only {0:N1} GB free on {1}: - free up space first" -f $free, $drive) }

# ---------------------------------------------------------------------------
Step "7/8  Hardware (decides how much the laptop can run locally)"
$ram = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB
Info ("RAM: {0:N0} GB" -f $ram)
foreach ($g in (Get-CimInstance Win32_VideoController)) { Info "GPU: $($g.Name)" }
if ($ram -ge 16) { Ok "16 GB+ RAM: small local models (up to ~4B) are usable as an offline fallback" }
else { Warn "Under 16 GB RAM: keep local models tiny; the server's free cloud models do the thinking" }

# ---------------------------------------------------------------------------
Step "8/8  Tailscale (how the server will reach the laptop, Lesson 13)"
$ts = Get-Command tailscale -ErrorAction SilentlyContinue
if (-not $ts -and (Test-Path "$env:ProgramFiles\Tailscale\tailscale.exe")) { $ts = "$env:ProgramFiles\Tailscale\tailscale.exe" }
if ($ts) {
    $st = (& $ts status 2>&1 | Out-String)
    if ($LASTEXITCODE -eq 0) { Ok "Tailscale is connected" } else { Warn "Tailscale is installed but not connected. Open it and log in with the same account as the server." }
} else {
    Warn "Tailscale not found. Install it from https://tailscale.com/download/windows (same account as the server)."
}

# ---------------------------------------------------------------------------
Write-Host ""
if ($script:fails -eq 0) {
    Write-Host "RESULT: ready for Lesson 12 ($($script:warns) warning(s) to read above)." -ForegroundColor Green
} else {
    Write-Host "RESULT: $($script:fails) problem(s) to fix first, $($script:warns) warning(s). Fix the [fail] lines and run this check again." -ForegroundColor Red
}
