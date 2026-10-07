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

$PythonVersion = "3.11"   # override with: --python 3.12
# The Windows wheels on PyPI are built for CPython 3.11 only; a 3.12 runtime
# resolves to the outdated 2026.7.9 release, which still forces the startup
# token dialog.  Pin the first token-free (Free mode) release so the installer
# never silently downgrades to it.  The pin is only applied on 3.11.
$MinMedicsVersion = "202608250449"
$LicenseUrl = "https://medical-image-computing-suite.github.io/license.html"
$CatalogUrl = "https://medical-image-computing-suite.github.io/installer/catalog.json"
$IconUrl = "https://medical-image-computing-suite.github.io/icon/icon.ico"
$DefaultExts = @(
    [pscustomobject]@{
        name        = "Retinal Layer Segmentation"
        package     = "medics-ext-retinal-layer-segmentation"
        description = "AI-based retinal layer segmentation for OCT / OCTA volumes."
    }
)

function Get-Tokens {
    # Split the raw command line ourselves instead of using PSParser.  PSParser
    # parses a *leading* "--flag" as an operator plus a command name ("--yes"
    # becomes "--", "yes"), which made every option fail when it came first.
    # This splitter honours double quotes and keeps the leading dashes intact.
    $raw = $env:MEDICS_INSTALLER_ARGS
    if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
    $out = New-Object System.Collections.Generic.List[string]
    $sb = New-Object System.Text.StringBuilder
    $inQuote = $false
    foreach ($ch in $raw.ToCharArray()) {
        if ($ch -eq '"') { $inQuote = -not $inQuote; continue }
        if (-not $inQuote -and [char]::IsWhiteSpace($ch)) {
            if ($sb.Length -gt 0) { $out.Add($sb.ToString()); [void]$sb.Clear() }
            continue
        }
        [void]$sb.Append($ch)
    }
    if ($sb.Length -gt 0) { $out.Add($sb.ToString()) }
    return $out.ToArray()
}

function Show-Help {
    Write-Host @"
MedICS CLI installer (Windows)

Usage:
  install.bat [options]

Options:
  --yes              Accept the license without prompting
  --dir PATH         Install directory (skip the prompt)
  --ext SPEC         Optional extensions to add: all, or pip package names
  --python VERSION   Python version for the runtime (default: 3.11)
  --no-desktop       Skip Desktop shortcut
  --no-menu          Skip Start Menu shortcut
  --no-launch        Do not launch MedICS when finished
  --help             Show this help

Only two things are ever asked: the license and the install folder. Press Enter
at either prompt to take the default (accept license, default folder). At the
folder prompt, type B to choose the folder in File Explorer. Shortcuts and
launching are on by default; pass the flags above to change them.

No extensions are installed; add them later or pass --ext explicitly.
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
    if ([string]::IsNullOrWhiteSpace($value)) {
        return [bool]$Default
    }
    $value = $value.Trim()
    if ($value -match '^(?i)y(es)?$') { return $true }
    if ($value -match '^(?i)n(o)?$') { return $false }
    Write-Host "Unrecognized answer '$value'; using default: $(if ($Default) { 'Yes' } else { 'No' })."
    return [bool]$Default
}

function Select-Folder([string]$Title, [string]$Initial = "") {
    # Native File Explorer folder picker.  Returns the chosen path, or $null
    # when the user cancels.  Tries WinForms first, then the shell COM dialog.
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop | Out-Null
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = $Title
        $dlg.ShowNewFolderButton = $true
        if ($Initial -and (Test-Path -LiteralPath $Initial)) { $dlg.SelectedPath = $Initial }
        # Own it by a top-most form so it appears in front of the console.
        $owner = New-Object System.Windows.Forms.Form
        $owner.TopMost = $true
        $owner.ShowInTaskbar = $false
        $owner.StartPosition = "CenterScreen"
        try {
            if ($dlg.ShowDialog($owner) -eq [System.Windows.Forms.DialogResult]::OK) {
                return $dlg.SelectedPath
            }
            return $null
        } finally {
            $owner.Dispose()
            $dlg.Dispose()
        }
    } catch {
        # Fall through to the shell COM dialog below.
    }
    try {
        $shell = New-Object -ComObject Shell.Application
        $folder = $shell.BrowseForFolder(0, $Title, 0, $Initial)
        if ($folder) { return $folder.Self.Path }
        return $null
    } catch {
        Write-Host "Could not open the folder picker. Please type a path instead." -ForegroundColor Yellow
        return $null
    }
}

function Read-Directory([string]$Prompt, [string]$Default) {
    # Enter accepts the default; "b" opens the native folder picker.
    while ($true) {
        $value = Read-Host "$Prompt [$Default]  (Enter = default, B = browse)"
        if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
        $value = $value.Trim()
        if ($value -match '^(?i)b(rowse)?$') {
            $picked = Select-Folder "Select the MedICS install directory" $Default
            if ($picked) { return $picked }
            Write-Host "No folder selected; keeping the default."
            continue
        }
        return $value
    }
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

function Repair-Pythonw([string]$Runtime) {
    $cfg = Join-Path $Runtime "pyvenv.cfg"
    $pyHome = $null
    if (Test-Path $cfg) {
        foreach ($line in Get-Content -LiteralPath $cfg) {
            if ($line -match '^\s*home\s*=\s*(.+)$') {
                $pyHome = $Matches[1].Trim()
                break
            }
        }
    }
    $candidates = @()
    if ($pyHome) {
        $candidates += Join-Path $pyHome "Lib\venv\scripts\nt\pythonw.exe"
        $candidates += Join-Path $pyHome "pythonw.exe"
    }
    $dest = Join-Path $Runtime "Scripts\pythonw.exe"
    foreach ($src in $candidates) {
        if (Test-Path $src) {
            Copy-Item -Force $src $dest
            Write-Host "Using windowed Python launcher: $src"
            return
        }
    }
    Write-Host "Warning: pythonw.exe is a console trampoline; the MedICS shortcut may show a terminal."
}

function Get-DesktopDir {
    try {
        $ws = New-Object -ComObject WScript.Shell
        $path = [string]$ws.SpecialFolders.Item("Desktop")
        if ($path -and (Test-Path -LiteralPath $path)) { return $path }
    } catch {}
    $path = [Environment]::GetFolderPath("Desktop")
    if ($path -and (Test-Path -LiteralPath $path)) { return $path }
    $fallback = Join-Path $env:USERPROFILE "Desktop"
    New-Item -ItemType Directory -Force -Path $fallback | Out-Null
    return $fallback
}

function Test-InstallFlag([string]$Name) {
    $value = [Environment]::GetEnvironmentVariable($Name, "Process")
    if ($null -eq $value) { return $true }
    return $value -ne "0"
}

function Set-InstallFlag([string]$Name, [bool]$Enabled) {
    [Environment]::SetEnvironmentVariable($Name, $(if ($Enabled) { "1" } else { "0" }), "Process")
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
    Start-Sleep -Milliseconds 100
    if (-not (Test-Path -LiteralPath $LnkPath)) {
        Write-Warning "Shortcut was not found after save: $LnkPath"
    }
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

function Install-Branding([string]$InstallDir, [string]$SelfDir) {
    $res = Join-Path $InstallDir "resources"
    New-Item -ItemType Directory -Force -Path $res | Out-Null
    $dest = Join-Path $res "icon.ico"
    $copied = $false
    foreach ($candidate in @(
        (Join-Path $SelfDir "resources\icon.ico"),
        (Join-Path $SelfDir "..\icon\icon.ico")
    )) {
        if (Test-Path $candidate) {
            Copy-Item -Force $candidate $dest
            $copied = $true
            break
        }
    }
    if (-not $copied) {
        Write-Host "Downloading icon.ico..."
        Save-Url $IconUrl $dest
    }
    if (-not (Test-Path $dest)) {
        throw "icon.ico was not installed."
    }
    return $res
}

$tokens = @(Get-Tokens)
$accept = $false
$installDir = $null
$extSpec = $null
Set-InstallFlag "MEDICS_INSTALL_DESKTOP" $true
Set-InstallFlag "MEDICS_INSTALL_MENU" $true
Set-InstallFlag "MEDICS_INSTALL_LAUNCH" $true

for ($i = 0; $i -lt $tokens.Count; $i++) {
    switch -Regex ($tokens[$i]) {
        '^(--help|/\?|-h)$' { Show-Help; exit 0 }
        '^(--yes|/Y)$' { $accept = $true }
        '^(--no-desktop)$' { Set-InstallFlag "MEDICS_INSTALL_DESKTOP" $false }
        '^(--no-menu)$' { Set-InstallFlag "MEDICS_INSTALL_MENU" $false }
        '^(--no-launch)$' { Set-InstallFlag "MEDICS_INSTALL_LAUNCH" $false }
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
        '^(--python)$' {
            $i++
            if ($i -ge $tokens.Count) { throw "--python requires a version (e.g. 3.11, 3.12)" }
            $PythonVersion = $tokens[$i].Trim()
        }
        default { throw "Unknown option: $($tokens[$i])  (use --help)" }
    }
}

if ($PythonVersion -notmatch '^\d+\.\d+(\.\d+)?$') {
    throw "Invalid --python version '$PythonVersion'. Use a form like 3.11 or 3.12."
}
# Major.minor, so both "3.11" and "3.11.9" compare equal.
$PythonMajorMinor = (($PythonVersion -split '\.')[0..1] -join '.')

# The Windows wheels are published for CPython 3.11 only; every other
# interpreter resolves to the older 2026.7.9 build, which still forces the
# startup token dialog.  The lower bound can therefore only be honored on 3.11.
if ($PythonMajorMinor -eq "3.11") {
    $MedicsSpec = "medics>=$MinMedicsVersion"
} else {
    $MedicsSpec = "medics"
}

$localApp = $env:LOCALAPPDATA
if (-not $localApp) { $localApp = Join-Path $env:USERPROFILE "AppData\Local" }
$defaultDir = Join-Path $localApp "Programs\MedICS"

Write-Host ""
Write-Host "MedICS installer"
Write-Host "================"
Write-Host "Installs a portable Python $PythonVersion runtime and MedICS."
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
    # Enter accepts the license and everything else defaults to yes.
    if (-not (Read-YesNo "Accept the MedICS Software License Agreement?" $true)) {
        throw "License not accepted."
    }
}

if (-not $installDir) {
    if ($accept) {
        $installDir = $defaultDir
    } else {
        $installDir = Read-Directory "Install directory" $defaultDir
    }
}
$installDir = [Environment]::ExpandEnvironmentVariables($installDir)
$installDir = [IO.Path]::GetFullPath($installDir)

Write-Host ""
if ($PythonMajorMinor -eq "3.11") {
    Write-Host "Core package (always installed): medics (>= $MinMedicsVersion)"
} else {
    Write-Host "Core package (always installed): medics"
    Write-Host "Warning: Python $PythonVersion is not 3.11. Published MedICS wheels target" -ForegroundColor Yellow
    Write-Host "CPython 3.11; on $PythonMajorMinor the installer may resolve to an older build that" -ForegroundColor Yellow
    Write-Host "prompts for a token at startup. Use --python 3.11 for the current release." -ForegroundColor Yellow
}

# Extensions are opt-in only (--ext); the default install is core-only.
$spec = if ($null -eq $extSpec) { "" } else { $extSpec.Trim() }

$packages = New-Object System.Collections.Generic.List[string]
$packages.Add($MedicsSpec) | Out-Null
if ($spec -and $spec -notmatch '^(none|no)$') {
    $extensions = @(Get-Extensions)
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
Repair-Pythonw $runtime
if (-not (Test-Path $pythonw)) { throw "pythonw.exe was not created at $pythonw" }

Write-Host "Installing icon..."
$resDir = Install-Branding $installDir $selfDir
$iconIco = Join-Path $resDir "icon.ico"

$medicsArgs = "-m medics"
$pythonConsole = Join-Path $runtime "Scripts\python.exe"
$launcher = $pythonw

$folderLnk = Join-Path $installDir "MedICS.lnk"
$folderConsoleLnk = Join-Path $installDir "MedICS_console.lnk"
New-Shortcut $folderLnk $pythonw $installDir $medicsArgs $iconIco
New-Shortcut $folderConsoleLnk $pythonConsole $installDir $medicsArgs $iconIco

$shortcuts = New-Object System.Collections.Generic.List[string]
$shortcuts.Add($folderLnk) | Out-Null
$shortcuts.Add($folderConsoleLnk) | Out-Null
$createDesktop = Test-InstallFlag "MEDICS_INSTALL_DESKTOP"
$createMenu = Test-InstallFlag "MEDICS_INSTALL_MENU"
if ($createDesktop) {
    $desktopDir = Get-DesktopDir
    $desktopLnk = Join-Path $desktopDir "MedICS.lnk"
    New-Shortcut $desktopLnk $pythonw $installDir $medicsArgs $iconIco
    if (Test-Path -LiteralPath $desktopLnk) {
        $shortcuts.Add($desktopLnk) | Out-Null
        Write-Host "Created Desktop shortcut: $desktopLnk"
    } else {
        throw "Failed to create Desktop shortcut: $desktopLnk"
    }
}
if ($createMenu) {
    $menuDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\MedICS"
    $menuLnk = Join-Path $menuDir "MedICS.lnk"
    New-Shortcut $menuLnk $pythonw $installDir $medicsArgs $iconIco
    $shortcuts.Add($menuLnk) | Out-Null
    $shortcuts.Add($menuDir) | Out-Null
    Write-Host "Created Start Menu shortcut: MedICS."
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
Write-Host "Launcher: MedICS"
Write-Host "Console launcher (install folder): MedICS_console"
Write-Host "Uninstall: $uninstall"

if (Test-InstallFlag "MEDICS_INSTALL_LAUNCH") {
    Write-Host "Launching MedICS..."
    Start-Process -FilePath $pythonw -ArgumentList @("-m", "medics") -WorkingDirectory $installDir
}
