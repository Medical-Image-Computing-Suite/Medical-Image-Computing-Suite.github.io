@echo off
setlocal EnableExtensions EnableDelayedExpansion
rem MedICS CLI installer. This .bat bypasses PowerShell execution policy.
set "MEDICS_INSTALLER_SELF=%~f0"
set "MEDICS_INSTALLER_ARGS=%*"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "iex ([string]::Join([Environment]::NewLine, (Get-Content -LiteralPath $env:MEDICS_INSTALLER_SELF | Select-Object -Skip 7)))"
exit /b %ERRORLEVEL%

# --- PowerShell (do not change the Skip count above without updating this header) ---
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$PythonVersion = "3.12"
$LicenseUrl = "https://medical-image-computing-suite.github.io/license.html"
$CatalogUrl = "https://medical-image-computing-suite.github.io/installer/catalog.json"
$IconUrl = "https://medical-image-computing-suite.github.io/icon/icon.png"
$LogoUrl = "https://medical-image-computing-suite.github.io/icon/logo.png"
$DefaultExts = @(
    [pscustomobject]@{
        name        = "Retinal Layer Segmentation"
        package     = "medics-ext-retinal-layer-segmentation"
        description = "AI-based retinal layer segmentation for OCT / OCTA volumes."
    }
)

function Get-Tokens {
    $raw = $env:MEDICS_INSTALLER_ARGS
    if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
    $errs = $null
    $toks = [System.Management.Automation.PSParser]::Tokenize($raw, [ref]$errs)
    $out = @()
    foreach ($t in $toks) {
        if ($t.Type -in @("Command", "CommandArgument", "String", "Number")) {
            $out += $t.Content
        }
    }
    return $out
}

function Show-Help {
    Write-Host @"
MedICS CLI installer (Windows)

Usage:
  install.bat [options]

Options:
  --yes              Accept the license without prompting
  --dir PATH         Install directory
  --ext SPEC         Extensions: all, none, numbers (1,2), or pip package names
  --no-desktop       Skip Desktop shortcut
  --no-menu          Skip Start Menu shortcut
  --no-launch        Do not launch MedICS when finished
  --help             Show this help

Interactive prompts are used for anything you do not pass on the command line.
"@
}

function Read-Input([string]$Prompt, [string]$Default = "") {
    $suffix = if ($Default) { " [$Default]" } else { "" }
    $value = Read-Host "$Prompt$suffix"
    if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
    return $value
}

function Read-YesNo([string]$Prompt, [bool]$Default = $true) {
    $hint = if ($Default) { "Y/n" } else { "y/N" }
    $value = Read-Host "$Prompt [$hint]"
    if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
    return $value -match '^(y|yes)$'
}

function Get-Extensions {
    try {
        $remote = Invoke-RestMethod -Uri $CatalogUrl -TimeoutSec 5
        if ($remote.extensions) { return @($remote.extensions) }
    } catch {
        Write-Host "Using built-in extension list (catalog not reachable)."
    }
    return $DefaultExts
}

function Find-Uv {
    $cmd = Get-Command uv -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($path in @(
        (Join-Path $env:USERPROFILE ".local\bin\uv.exe"),
        (Join-Path $env:USERPROFILE ".cargo\bin\uv.exe")
    )) {
        if (Test-Path $path) { return $path }
    }
    return $null
}

function Ensure-Uv([string]$InstallDir) {
    $uv = Find-Uv
    if ($uv) {
        Write-Host "Using uv at $uv"
        return $uv
    }
    Write-Host "Installing uv..."
    irm https://astral.sh/uv/install.ps1 | iex
    $env:Path = "$env:USERPROFILE\.local\bin;$env:USERPROFILE\.cargo\bin;$env:Path"
    $uv = Find-Uv
    if (-not $uv) { throw "uv was installed but is not on PATH. Open a new terminal and re-run install.bat." }
    return $uv
}

function New-Shortcut([string]$LnkPath, [string]$Target, [string]$WorkDir, [string]$Arguments = "", [string]$IconPath = "") {
    $folder = Split-Path $LnkPath -Parent
    New-Item -ItemType Directory -Force -Path $folder | Out-Null
    $ws = New-Object -ComObject WScript.Shell
    $s = $ws.CreateShortcut($LnkPath)
    $s.TargetPath = $Target
    $s.Arguments = $Arguments
    $s.WorkingDirectory = $WorkDir
    $s.WindowStyle = 1
    if ($IconPath -and (Test-Path $IconPath)) {
        $s.IconLocation = "$IconPath,0"
    }
    $s.Save()
}

function Save-Url([string]$Url, [string]$Dest) {
    $request = [Net.HttpWebRequest]::Create($Url)
    $request.UserAgent = "MedICS-Installer"
    $request.Timeout = 20000
    $response = $request.GetResponse()
    $stream = $response.GetResponseStream()
    $file = [IO.File]::Create($Dest)
    $stream.CopyTo($file)
    $file.Close()
    $stream.Close()
    $response.Close()
}

function ConvertTo-Ico([string]$PngPath, [string]$IcoPath) {
    Add-Type -AssemblyName System.Drawing
    $img = [System.Drawing.Image]::FromFile($PngPath)
    $bmp = New-Object System.Drawing.Bitmap $img, 256, 256
    $hicon = $bmp.GetHicon()
    $icon = [System.Drawing.Icon]::FromHandle($hicon)
    $fs = [IO.File]::Create($IcoPath)
    $icon.Save($fs)
    $fs.Close()
    $icon.Dispose()
    $bmp.Dispose()
    $img.Dispose()
}

function Install-Branding([string]$InstallDir, [string]$SelfDir) {
    $res = Join-Path $InstallDir "resources"
    New-Item -ItemType Directory -Force -Path $res | Out-Null
    $pairs = @(
        @{ Name = "icon.png"; Url = $IconUrl },
        @{ Name = "logo.png"; Url = $LogoUrl }
    )
    foreach ($item in $pairs) {
        $dest = Join-Path $res $item.Name
        $copied = $false
        foreach ($candidate in @(
            (Join-Path $SelfDir "resources\$($item.Name)"),
            (Join-Path $SelfDir "..\icon\$($item.Name)")
        )) {
            if (Test-Path $candidate) {
                Copy-Item -Force $candidate $dest
                $copied = $true
                break
            }
        }
        if (-not $copied) {
            Write-Host "Downloading $($item.Name)..."
            Save-Url $item.Url $dest
        }
    }
    $ico = Join-Path $res "icon.ico"
    try {
        ConvertTo-Ico (Join-Path $res "icon.png") $ico
    } catch {
        Write-Host "Could not build icon.ico; shortcuts will use the default Python icon. $_"
        $ico = Join-Path $res "icon.png"
    }
    $splashPy = Join-Path $res "splash.py"
    $localSplash = Join-Path $SelfDir "resources\splash.py"
    if (Test-Path $localSplash) {
        Copy-Item -Force $localSplash $splashPy
    } else {
        Set-Content -LiteralPath $splashPy -Encoding ASCII -Value @'
#!/usr/bin/env python3
from __future__ import annotations
import sys, tkinter as tk
from pathlib import Path
DURATION_MS = 4000
MAX_WIDTH = 560
def main() -> int:
    resources = Path(__file__).resolve().parent
    logo = resources / "logo.png"
    if not logo.is_file():
        return 0
    try:
        root = tk.Tk()
    except tk.TclError:
        return 0
    root.overrideredirect(True)
    try:
        root.attributes("-topmost", True)
    except tk.TclError:
        pass
    root.configure(bg="#000000")
    img = tk.PhotoImage(file=str(logo))
    width, height = img.width(), img.height()
    if width > MAX_WIDTH:
        factor = max(1, round(width / MAX_WIDTH))
        img = img.subsample(factor, factor)
        width, height = img.width(), img.height()
    root.update_idletasks()
    x = max(0, (root.winfo_screenwidth() - width) // 2)
    y = max(0, (root.winfo_screenheight() - height) // 2)
    root.geometry(f"{width}x{height}+{x}+{y}")
    label = tk.Label(root, image=img, borderwidth=0, highlightthickness=0, bg="#000000")
    label.image = img
    label.pack()
    root.after(DURATION_MS, root.destroy)
    root.mainloop()
    return 0
if __name__ == "__main__":
    raise SystemExit(main())
'@
    }
    return $res
}

$tokens = @(Get-Tokens)
$accept = $false
$installDir = $null
$extSpec = $null
$desktop = $true
$menu = $true
$launch = $true

for ($i = 0; $i -lt $tokens.Count; $i++) {
    switch -Regex ($tokens[$i]) {
        '^(--help|/\?|-h)$' { Show-Help; exit 0 }
        '^(--yes|/Y)$' { $accept = $true }
        '^(--no-desktop)$' { $desktop = $false }
        '^(--no-menu)$' { $menu = $false }
        '^(--no-launch)$' { $launch = $false }
        '^(--dir|/D)$' {
            $i++
            if ($i -ge $tokens.Count) { throw "--dir requires a path" }
            $installDir = $tokens[$i]
        }
        '^(--ext)$' {
            $i++
            if ($i -ge $tokens.Count) { throw "--ext requires a value (all, none, 1,2, or package names)" }
            $extSpec = $tokens[$i]
        }
        default { throw "Unknown option: $($tokens[$i])  (use --help)" }
    }
}

$localApp = $env:LOCALAPPDATA
if (-not $localApp) { $localApp = Join-Path $env:USERPROFILE "AppData\Local" }
$defaultDir = Join-Path $localApp "Programs\MedICS"

Write-Host ""
Write-Host "MedICS installer"
Write-Host "================"
Write-Host "Installs a portable Python $PythonVersion runtime, MedICS, and optional extensions."
Write-Host "A network connection is required. No system Python is needed."
Write-Host ""

$licenseFile = $null
$selfDir = Split-Path $env:MEDICS_INSTALLER_SELF -Parent
foreach ($candidate in @(
    (Join-Path $selfDir "..\LICENSE"),
    (Join-Path $selfDir "LICENSE")
)) {
    if (Test-Path $candidate) { $licenseFile = (Resolve-Path $candidate).Path; break }
}

Write-Host "License: $LicenseUrl"
if ($licenseFile) {
    Write-Host "---- license ----"
    Get-Content -LiteralPath $licenseFile | Write-Host
    Write-Host "-----------------"
}
if (-not $accept) {
    $answer = Read-Host "Type YES to accept the MedICS Software License Agreement"
    if ($answer -ne "YES") { throw "License not accepted." }
}

if (-not $installDir) {
    $installDir = Read-Input "Install directory" $defaultDir
}
$installDir = [Environment]::ExpandEnvironmentVariables($installDir)
$installDir = [IO.Path]::GetFullPath($installDir)

$extensions = @(Get-Extensions)
Write-Host ""
Write-Host "Core package (always installed): medics"
Write-Host "Optional extensions:"
if ($extensions.Count -eq 0) {
    Write-Host "  (none listed)"
} else {
    for ($n = 0; $n -lt $extensions.Count; $n++) {
        $ext = $extensions[$n]
        Write-Host ("  [{0}] {1}" -f ($n + 1), $ext.name)
        Write-Host ("      {0}" -f $ext.package)
        if ($ext.description) { Write-Host ("      {0}" -f $ext.description) }
    }
}

if ($null -eq $extSpec) {
    $extSpec = Read-Input "Select extensions (numbers, all, or Enter for none)" ""
    $custom = Read-Input "Additional pip packages (comma-separated, optional)" ""
    if ($custom) {
        if ($extSpec) { $extSpec = "$extSpec,$custom" } else { $extSpec = $custom }
    }
}

$packages = New-Object System.Collections.Generic.List[string]
$packages.Add("medics") | Out-Null
$spec = if ($null -eq $extSpec) { "" } else { $extSpec.Trim() }
if ($spec -and $spec -notmatch '^(none|no)$') {
    if ($spec -match '^(all|\*)$') {
        foreach ($ext in $extensions) { $packages.Add([string]$ext.package) | Out-Null }
    } else {
        foreach ($part in ($spec -split '[,\s]+' | Where-Object { $_ })) {
            if ($part -match '^\d+$') {
                $idx = [int]$part - 1
                if ($idx -lt 0 -or $idx -ge $extensions.Count) { throw "Unknown extension number: $part" }
                $packages.Add([string]$extensions[$idx].package) | Out-Null
            } elseif ($part -ne "medics") {
                $packages.Add($part) | Out-Null
            }
        }
    }
}

$unique = [string[]]($packages | Select-Object -Unique)

if (-not $accept) {
    $desktop = Read-YesNo "Create a Desktop shortcut?" $true
    $menu = Read-YesNo "Create a Start Menu shortcut?" $true
    $launch = Read-YesNo "Launch MedICS when installation finishes?" $true
}

Write-Host ""
Write-Host "Install directory: $installDir"
Write-Host "Packages: $($unique -join ', ')"
Write-Host ""

New-Item -ItemType Directory -Force -Path $installDir | Out-Null
$uv = Ensure-Uv $installDir
$env:UV_PYTHON_INSTALL_DIR = Join-Path $installDir "python"
$env:UV_LINK_MODE = "copy"
$env:VIRTUAL_ENV = ""

Write-Host "Installing Python $PythonVersion..."
& $uv python install $PythonVersion
if ($LASTEXITCODE) { throw "uv python install failed." }

$runtime = Join-Path $installDir "runtime"
if (Test-Path $runtime) {
    Write-Host "Removing previous runtime..."
    Remove-Item -LiteralPath $runtime -Recurse -Force
}
Write-Host "Creating virtual environment..."
& $uv venv $runtime --python $PythonVersion
if ($LASTEXITCODE) { throw "uv venv failed." }

$python = Join-Path $runtime "Scripts\python.exe"
Write-Host "Installing $($unique -join ', ')..."
& $uv pip install --python $python @unique
if ($LASTEXITCODE) { throw "uv pip install failed." }

$exe = Join-Path $runtime "Scripts\medics.exe"
$pythonw = Join-Path $runtime "Scripts\pythonw.exe"
if (-not (Test-Path $exe)) { throw "MedICS executable was not created at $exe" }
if (-not (Test-Path $pythonw)) { throw "pythonw.exe was not created at $pythonw" }

Write-Host "Installing icon and splash resources..."
$resDir = Install-Branding $installDir $selfDir
$iconIco = Join-Path $resDir "icon.ico"
if (-not (Test-Path $iconIco)) { $iconIco = Join-Path $resDir "icon.png" }
$splashPy = Join-Path $resDir "splash.py"
$launchPy = Join-Path $installDir "launch.py"
Set-Content -LiteralPath $launchPy -Encoding ASCII -Value @"
import os
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parent
splash = root / "resources" / "splash.py"
python = sys.executable
kwargs = {"cwd": str(root), "close_fds": True}
if os.name == "nt":
    kwargs["creationflags"] = getattr(subprocess, "CREATE_NO_WINDOW", 0) | getattr(subprocess, "DETACHED_PROCESS", 0)
else:
    kwargs["start_new_session"] = True
if splash.is_file():
    subprocess.Popen([python, str(splash)], **kwargs)
os.execv(python, [python, "-m", "medics", *sys.argv[1:]])
"@

$launcher = Join-Path $installDir "MedICS.vbs"
Set-Content -LiteralPath $launcher -Encoding ASCII -Value @"
Set sh = CreateObject("Wscript.Shell")
sh.CurrentDirectory = "$installDir"
sh.Run """$pythonw"" ""$launchPy""", 0, False
"@

$launchArgs = "`"$launchPy`""
$consoleArgs = "-m medics"
$pythonConsole = Join-Path $runtime "Scripts\python.exe"

$folderLnk = Join-Path $installDir "MedICS.lnk"
$folderConsoleLnk = Join-Path $installDir "MedICS_console.lnk"
New-Shortcut $folderLnk $pythonw $installDir $launchArgs $iconIco
New-Shortcut $folderConsoleLnk $pythonConsole $installDir $consoleArgs $iconIco

$shortcuts = New-Object System.Collections.Generic.List[string]
$shortcuts.Add($folderLnk) | Out-Null
$shortcuts.Add($folderConsoleLnk) | Out-Null
if ($desktop) {
    $desktopDir = [Environment]::GetFolderPath("Desktop")
    $desktopLnk = Join-Path $desktopDir "MedICS.lnk"
    $desktopConsoleLnk = Join-Path $desktopDir "MedICS_console.lnk"
    New-Shortcut $desktopLnk $pythonw $installDir $launchArgs $iconIco
    New-Shortcut $desktopConsoleLnk $pythonConsole $installDir $consoleArgs $iconIco
    $shortcuts.Add($desktopLnk) | Out-Null
    $shortcuts.Add($desktopConsoleLnk) | Out-Null
    Write-Host "Created Desktop shortcuts: MedICS (default) and MedICS_console."
}
if ($menu) {
    $menuDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\MedICS"
    $menuLnk = Join-Path $menuDir "MedICS.lnk"
    $menuConsoleLnk = Join-Path $menuDir "MedICS_console.lnk"
    New-Shortcut $menuLnk $pythonw $installDir $launchArgs $iconIco
    New-Shortcut $menuConsoleLnk $pythonConsole $installDir $consoleArgs $iconIco
    $shortcuts.Add($menuLnk) | Out-Null
    $shortcuts.Add($menuConsoleLnk) | Out-Null
    $shortcuts.Add($menuDir) | Out-Null
    Write-Host "Created Start Menu shortcuts: MedICS (default) and MedICS_console."
}

$uninstall = Join-Path $installDir "Uninstall-MedICS.bat"
$uninstallLines = @(
    "@echo off",
    "echo Removing MedICS..."
)
foreach ($item in $shortcuts) {
    $uninstallLines += "if exist `"$item`" rmdir /s /q `"$item`" 2>nul"
    $uninstallLines += "if exist `"$item`" del /f /q `"$item`" 2>nul"
}
$uninstallLines += "rmdir /s /q `"$installDir`""
$uninstallLines += "echo MedICS has been removed."
Set-Content -LiteralPath $uninstall -Value $uninstallLines -Encoding ASCII

$manifest = @{
    install_dir = $installDir
    python      = $PythonVersion
    packages    = $unique
    executable  = $exe
    launcher    = $launcher
    shortcuts   = @($shortcuts)
} | ConvertTo-Json -Depth 4
Set-Content -LiteralPath (Join-Path $installDir "install-manifest.json") -Value $manifest -Encoding UTF8

Write-Host ""
Write-Host "Installation complete."
Write-Host "Default launcher: MedICS (splash, no console)"
Write-Host "Console launcher: MedICS_console (no splash, with console)"
Write-Host "Uninstall: $uninstall"

if ($launch) {
    Write-Host "Launching MedICS..."
    Start-Process -FilePath $pythonw -ArgumentList @($launchPy) -WorkingDirectory $installDir
}
