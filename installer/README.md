# MedICS installer

A single CLI script per platform. It downloads a portable Python 3.11 via [uv](https://docs.astral.sh/uv/), installs `medics` plus optional extensions, and creates launchers/shortcuts.

The published MedICS wheels target CPython 3.11, and the installer pins `medics` to the first token-free (Free mode) release so it never installs an older build that forces the startup token dialog.

Python does not need to be installed first. A network connection is required.

## Prompts

The installer stays out of the way — it asks for only three things and each
accepts **Enter** as the default:

1. **Accept the license?** — Enter accepts.
2. **Install directory** — Enter keeps the default. Type a path, or type `b`
   to pick the folder in a native dialog (File Explorer on Windows, the
   Finder folder chooser on macOS, Zenity/KDialog on Linux).
3. **Select extensions** (only when some are listed) — Enter installs none.

Everything else uses sensible defaults: desktop/Start Menu shortcuts and a
launch when it finishes. Pass the flags below to change any of that up front
(for example `--dir` skips the folder prompt entirely).

## Run

From this `installer/` directory:

```bat
install.bat
```

```bash
chmod +x install.sh
./install.sh
```

One-liners from [Get started](https://medical-image-computing-suite.github.io/get-started.html#installer):

Command Prompt (cmd):

```bat
curl -L -o "%TEMP%\medics-install.bat" https://medical-image-computing-suite.github.io/installer/install.bat && "%TEMP%\medics-install.bat"
```

PowerShell:

```powershell
Invoke-WebRequest -Uri "https://medical-image-computing-suite.github.io/installer/install.bat" -OutFile "$env:TEMP\medics-install.bat"; & "$env:TEMP\medics-install.bat"
```

macOS and Linux:

```bash
curl -fsSL https://medical-image-computing-suite.github.io/installer/install.sh | bash
```

## Options

```text
--yes              Accept the license without prompting
--dir PATH         Install directory
--ext SPEC         all, none, numbers (1,2), or pip package names
--python VERSION   Python version for the runtime (default: 3.11)
--no-desktop       Skip Desktop shortcut
--no-menu          Skip Start Menu / Applications / ~/.local/bin
--no-launch        Do not launch MedICS when finished
--help             Show help
```

Example:

```bash
./install.sh --yes --dir ~/Apps/MedICS --ext 1
```

Choose a different Python runtime (default is 3.11):

```bat
install.bat --python 3.12
```

```bash
./install.sh --python 3.12
```

MedICS wheels are built for CPython 3.11, so `--python` values other than 3.11
may resolve to an older release that prompts for a token at startup. The
installer warns when this is the case.

## What it installs

| OS | Default directory |
| --- | --- |
| Windows | `%LOCALAPPDATA%\Programs\MedICS` |
| macOS | `~/Applications/MedICS` |
| Linux | `~/.local/share/medics` |

Contents: portable CPython, a `runtime` venv, `medics` and selected `medics-ext-*` packages, launchers, and an uninstall script.
