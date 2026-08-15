# MedICS installer

A single CLI script per platform. It downloads a portable Python 3.12 via [uv](https://docs.astral.sh/uv/), installs `medics` plus optional extensions, and creates launchers/shortcuts.

Python does not need to be installed first. A network connection is required.

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

```bat
curl -L -o "%TEMP%\medics-install.bat" https://medical-image-computing-suite.github.io/installer/install.bat && "%TEMP%\medics-install.bat"
```

```bash
curl -fsSL https://medical-image-computing-suite.github.io/installer/install.sh | bash
```

## Options

```text
--yes              Accept the license without prompting
--dir PATH         Install directory
--ext SPEC         all, none, numbers (1,2), or pip package names
--no-desktop       Skip Desktop shortcut
--no-menu          Skip Start Menu / Applications / ~/.local/bin
--no-launch        Do not launch MedICS when finished
--help             Show help
```

Example:

```bash
./install.sh --yes --dir ~/Apps/MedICS --ext 1
```

## What it installs

| OS | Default directory |
| --- | --- |
| Windows | `%LOCALAPPDATA%\Programs\MedICS` |
| macOS | `~/Applications/MedICS` |
| Linux | `~/.local/share/medics` |

Contents: portable CPython, a `runtime` venv, `medics` and selected `medics-ext-*` packages, launchers, and an uninstall script.
