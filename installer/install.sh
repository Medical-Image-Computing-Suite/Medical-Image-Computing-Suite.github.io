#!/usr/bin/env bash
# MedICS CLI installer for macOS and Linux.
# Usage: ./install.sh [--yes] [--dir PATH] [--ext SPEC] [--no-desktop] [--no-menu] [--no-launch]
set -euo pipefail

PYTHON_VERSION="3.12"
LICENSE_URL="https://medical-image-computing-suite.github.io/license.html"
CATALOG_URL="https://medical-image-computing-suite.github.io/installer/catalog.json"
ICON_URL="https://medical-image-computing-suite.github.io/icon/icon.ico"

prompt() {
  local msg="$1"
  local value=""
  if [[ -t 0 ]]; then
    read -r -p "$msg" value || true
  elif [[ -r /dev/tty ]]; then
    read -r -p "$msg" value < /dev/tty || true
  fi
  printf '%s' "$value"
}

prompt_default() {
  local msg="$1"
  local default="$2"
  local value
  value="$(prompt "$msg [$default]: ")"
  if [[ -z "$value" ]]; then
    printf '%s' "$default"
  else
    printf '%s' "$value"
  fi
}

prompt_yes() {
  local msg="$1"
  local default="${2:-Y}"
  local hint value
  if [[ "$default" == "Y" ]]; then hint="Y/n"; else hint="y/N"; fi
  value="$(prompt "$msg [$hint]: ")"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  if [[ -z "$value" ]]; then
    [[ "$default" == "Y" ]]
    return
  fi
  if [[ "$value" =~ ^[Yy]([Ee][Ss])?$ ]]; then
    return 0
  fi
  if [[ "$value" =~ ^[Nn]([Oo])?$ ]]; then
    return 1
  fi
  echo "Unrecognized answer '$value'; using default: $default." >&2
  [[ "$default" == "Y" ]]
}

show_help() {
  cat <<'EOF'
MedICS CLI installer (macOS / Linux)

Usage:
  ./install.sh [options]

Options:
  --yes              Accept the license without prompting
  --dir PATH         Install directory
  --ext SPEC         Extensions: all, none, numbers (1,2), or pip package names
  --no-desktop       Skip Desktop shortcut / alias
  --no-menu          Skip Applications menu / ~/.local/bin
  --no-launch        Do not launch MedICS when finished
  --help             Show this help

Interactive prompts are used for anything you do not pass on the command line.
EOF
}

os_name="$(uname -s)"
default_dir=""
case "$os_name" in
  Darwin) default_dir="$HOME/Applications/MedICS" ;;
  *)      default_dir="$HOME/.local/share/medics" ;;
esac

accept=0
install_dir=""
ext_spec=""
ext_spec_set=0
desktop=1
menu=1
launch=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) show_help; exit 0 ;;
    --yes) accept=1 ;;
    --dir)
      [[ $# -ge 2 ]] || { echo "--dir requires a path" >&2; exit 1; }
      install_dir="$2"
      shift
      ;;
    --ext)
      [[ $# -ge 2 ]] || { echo "--ext requires a value" >&2; exit 1; }
      ext_spec="$2"
      ext_spec_set=1
      shift
      ;;
    --no-desktop) desktop=0 ;;
    --no-menu) menu=0 ;;
    --no-launch) launch=0 ;;
    *) echo "Unknown option: $1 (use --help)" >&2; exit 1 ;;
  esac
  shift
done

echo
echo "MedICS installer"
echo "================"
echo "Installs a portable Python ${PYTHON_VERSION} runtime, MedICS, and optional extensions."
echo "A network connection is required. No system Python is needed."
echo

script_dir=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

license_file=""
if [[ -n "$script_dir" ]]; then
  if [[ -f "$script_dir/../LICENSE" ]]; then
    license_file="$(cd "$script_dir/.." && pwd)/LICENSE"
  elif [[ -f "$script_dir/LICENSE" ]]; then
    license_file="$script_dir/LICENSE"
  fi
fi

echo "License: $LICENSE_URL"
if [[ -n "$license_file" ]]; then
  echo "---- license ----"
  cat "$license_file"
  echo "-----------------"
fi

if [[ "$accept" -eq 0 ]]; then
  answer="$(prompt "Type YES to accept the MedICS Software License Agreement: ")"
  if [[ "$answer" != "YES" ]]; then
    echo "License not accepted." >&2
    exit 1
  fi
fi

if [[ -z "$install_dir" ]]; then
  install_dir="$(prompt_default "Install directory" "$default_dir")"
fi
install_dir="${install_dir/#\~/$HOME}"
mkdir -p "$install_dir"
install_dir="$(cd "$install_dir" && pwd)"

ext_names=()
ext_packages=()
ext_descriptions=()
load_builtin_exts() {
  ext_names=("Retinal Layer Segmentation")
  ext_packages=("medics-ext-retinal-layer-segmentation")
  ext_descriptions=("AI-based retinal layer segmentation for OCT / OCTA volumes.")
}

if command -v python3 >/dev/null 2>&1; then
  if catalog_json="$(python3 - "$CATALOG_URL" <<'PY' 2>/dev/null
import json, sys, urllib.request
url = sys.argv[1]
req = urllib.request.Request(url, headers={"User-Agent": "MedICS-Installer"})
with urllib.request.urlopen(req, timeout=5) as resp:
    data = json.load(resp)
for ext in data.get("extensions") or []:
    print("\t".join([
        ext.get("name", ""),
        ext.get("package", ""),
        ext.get("description", "").replace("\t", " "),
    ]))
PY
)"; then
    if [[ -n "$catalog_json" ]]; then
      while IFS=$'\t' read -r name pkg desc; do
        [[ -n "$pkg" ]] || continue
        ext_names+=("$name")
        ext_packages+=("$pkg")
        ext_descriptions+=("$desc")
      done <<< "$catalog_json"
    fi
  fi
fi
if [[ ${#ext_packages[@]} -eq 0 ]]; then
  echo "Using built-in extension list (catalog not reachable)."
  load_builtin_exts
fi

echo
echo "Core package (always installed): medics"
echo "Optional extensions:"
if [[ ${#ext_packages[@]} -eq 0 ]]; then
  echo "  (none listed)"
else
  for i in "${!ext_packages[@]}"; do
    num=$((i + 1))
    echo "  [$num] ${ext_names[$i]}"
    echo "      ${ext_packages[$i]}"
    if [[ -n "${ext_descriptions[$i]}" ]]; then
      echo "      ${ext_descriptions[$i]}"
    fi
  done
fi

if [[ "$ext_spec_set" -eq 0 ]]; then
  ext_spec="$(prompt "Select extensions (numbers, all, or Enter for none): ")"
  custom="$(prompt "Additional pip packages (comma-separated, optional): ")"
  if [[ -n "$custom" ]]; then
    if [[ -n "$ext_spec" ]]; then
      ext_spec="$ext_spec,$custom"
    else
      ext_spec="$custom"
    fi
  fi
fi

packages=("medics")
if [[ -n "$ext_spec" && ! "$ext_spec" =~ ^(none|no)$ ]]; then
  if [[ "$ext_spec" =~ ^(all|\*)$ ]]; then
    packages+=("${ext_packages[@]}")
  else
    ext_spec="${ext_spec//,/ }"
    read -r -a parts <<< "$ext_spec"
    for part in "${parts[@]}"; do
      [[ -n "$part" ]] || continue
      if [[ "$part" =~ ^[0-9]+$ ]]; then
        idx=$((part - 1))
        if [[ $idx -lt 0 || $idx -ge ${#ext_packages[@]} ]]; then
          echo "Unknown extension number: $part" >&2
          exit 1
        fi
        packages+=("${ext_packages[$idx]}")
      elif [[ "$part" != "medics" ]]; then
        packages+=("$part")
      fi
    done
  fi
fi

# Unique packages, preserving order
unique=()
for pkg in "${packages[@]}"; do
  seen=0
  for u in "${unique[@]+"${unique[@]}"}"; do
    [[ "$u" == "$pkg" ]] && seen=1 && break
  done
  [[ $seen -eq 0 ]] && unique+=("$pkg")
done

if [[ "$accept" -eq 0 ]]; then
  if prompt_yes "Create a Desktop shortcut?" Y; then desktop=1; else desktop=0; fi
  if [[ "$os_name" == "Darwin" ]]; then
    if prompt_yes "Add MedICS.app to the Applications folder?" Y; then menu=1; else menu=0; fi
  else
    if prompt_yes "Add to the applications menu and ~/.local/bin?" Y; then menu=1; else menu=0; fi
  fi
  if prompt_yes "Launch MedICS when installation finishes?" Y; then launch=1; else launch=0; fi
fi

echo
echo "Install directory: $install_dir"
echo "Packages: ${unique[*]}"
echo

ensure_uv() {
  if command -v uv >/dev/null 2>&1; then
    command -v uv
    return
  fi
  if [[ -x "$HOME/.local/bin/uv" ]]; then
    echo "$HOME/.local/bin/uv"
    return
  fi
  if [[ -x "$HOME/.cargo/bin/uv" ]]; then
    echo "$HOME/.cargo/bin/uv"
    return
  fi
  echo "Installing uv..." >&2
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
  if command -v uv >/dev/null 2>&1; then
    command -v uv
    return
  fi
  echo "uv was installed but is not on PATH. Open a new terminal and re-run install.sh." >&2
  exit 1
}

uv="$(ensure_uv)"
echo "Using uv at $uv"
export UV_PYTHON_INSTALL_DIR="$install_dir/python"
export UV_LINK_MODE="copy"
unset VIRTUAL_ENV || true

echo "Installing Python ${PYTHON_VERSION}..."
"$uv" python install "$PYTHON_VERSION"

runtime="$install_dir/runtime"
if [[ -d "$runtime" ]]; then
  echo "Removing previous runtime..."
  rm -rf "$runtime"
fi
echo "Creating virtual environment..."
"$uv" venv "$runtime" --python "$PYTHON_VERSION"

python="$runtime/bin/python"
echo "Installing ${unique[*]}..."
"$uv" pip install --python "$python" "${unique[@]}"

exe="$runtime/bin/medics"
if [[ ! -x "$exe" ]]; then
  echo "MedICS executable was not created at $exe" >&2
  exit 1
fi
if [[ ! -x "$python" ]]; then
  echo "Python was not created at $python" >&2
  exit 1
fi

echo "Installing icon..."
res_dir="$install_dir/resources"
mkdir -p "$res_dir"

copy_or_fetch() {
  local name="$1"
  local url="$2"
  local dest="$res_dir/$name"
  local src
  for src in "$script_dir/resources/$name" "$script_dir/../icon/$name"; do
    if [[ -n "$script_dir" && -f "$src" ]]; then
      cp "$src" "$dest"
      return
    fi
  done
  echo "Downloading $name..."
  curl -fsSL "$url" -o "$dest"
}

copy_or_fetch "icon.ico" "$ICON_URL"

icon_ico="$res_dir/icon.ico"
if [[ ! -f "$icon_ico" ]]; then
  echo "icon.ico was not installed." >&2
  exit 1
fi

launcher="$install_dir/MedICS.sh"
cat > "$launcher" <<EOF
#!/usr/bin/env bash
cd "$install_dir" || exit 1
exec "$python" -m medics "\$@"
EOF
chmod +x "$launcher"

console_launcher="$install_dir/MedICS_console.sh"
cat > "$console_launcher" <<EOF
#!/usr/bin/env bash
cd "$install_dir" || exit 1
exec "$python" -m medics "\$@"
EOF
chmod +x "$console_launcher"

write_macos_app() {
  local app_path="$1"
  mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
  cat > "$app_path/Contents/MacOS/MedICS" <<EOF
#!/bin/bash
cd "$install_dir" || exit 1
exec "$python" -m medics "\$@"
EOF
  chmod +x "$app_path/Contents/MacOS/MedICS"
  cp "$icon_ico" "$app_path/Contents/Resources/icon.ico"
  cat > "$app_path/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>MedICS</string>
  <key>CFBundleDisplayName</key><string>MedICS</string>
  <key>CFBundleIdentifier</key><string>io.github.medical-image-computing-suite.medics</string>
  <key>CFBundleExecutable</key><string>MedICS</string>
  <key>CFBundleIconFile</key><string>icon.ico</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
}

write_desktop() {
  local path="$1"
  local name="$2"
  local exec_cmd="$3"
  local terminal="$4"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<EOF
[Desktop Entry]
Type=Application
Name=$name
Comment=Medical Image Computing Suite
Exec=$exec_cmd
Path=$install_dir
Icon=$icon_ico
Terminal=$terminal
StartupNotify=true
Categories=Science;Education;Graphics;
EOF
  chmod +x "$path"
}

shortcuts=()
if [[ "$os_name" == "Darwin" ]]; then
  app_in_install="$install_dir/MedICS.app"
  write_macos_app "$app_in_install"
  shortcuts+=("$app_in_install")
  console_cmd="$install_dir/MedICS_console.command"
  cat > "$console_cmd" <<EOF
#!/bin/bash
cd "$install_dir" || exit 1
exec "$python" -m medics "\$@"
EOF
  chmod +x "$console_cmd"
  shortcuts+=("$console_cmd")
  if [[ "$menu" -eq 1 ]]; then
    mkdir -p "$HOME/Applications"
    dest="$HOME/Applications/MedICS.app"
    if [[ "$dest" != "$app_in_install" ]]; then
      rm -rf "$dest"
      cp -R "$app_in_install" "$dest"
      shortcuts+=("$dest")
    fi
  fi
  if [[ "$desktop" -eq 1 ]]; then
    mkdir -p "$HOME/Desktop"
    osascript -e "tell application \"Finder\" to make alias file to POSIX file \"$app_in_install\" at POSIX file \"$HOME/Desktop\"" >/dev/null 2>&1 || \
      echo "Could not create Desktop alias for MedICS."
    shortcuts+=("$HOME/Desktop/MedICS")
    echo "Created Desktop shortcut: MedICS."
  fi
else
  write_desktop "$install_dir/MedICS.desktop" "MedICS" "\"$launcher\"" "false"
  write_desktop "$install_dir/MedICS_console.desktop" "MedICS_console" "\"$python\" -m medics" "true"
  shortcuts+=("$install_dir/MedICS.desktop" "$install_dir/MedICS_console.desktop")
  if [[ "$menu" -eq 1 ]]; then
    mkdir -p "$HOME/.local/bin"
    cat > "$HOME/.local/bin/medics" <<EOF
#!/usr/bin/env bash
exec "$python" -m medics "\$@"
EOF
    chmod +x "$HOME/.local/bin/medics"
    shortcuts+=("$HOME/.local/bin/medics")
    mkdir -p "$HOME/.local/share/applications"
    write_desktop "$HOME/.local/share/applications/medics.desktop" "MedICS" "\"$launcher\"" "false"
    shortcuts+=("$HOME/.local/share/applications/medics.desktop")
  fi
  if [[ "$desktop" -eq 1 ]]; then
    mkdir -p "$HOME/Desktop"
    write_desktop "$HOME/Desktop/MedICS.desktop" "MedICS" "\"$launcher\"" "false" || echo "Could not create MedICS Desktop shortcut."
    shortcuts+=("$HOME/Desktop/MedICS.desktop")
    echo "Created Desktop shortcut: MedICS."
  fi
fi

if [[ "$os_name" == "Darwin" ]]; then
  uninstall="$install_dir/Uninstall-MedICS.command"
else
  uninstall="$install_dir/Uninstall-MedICS.sh"
fi
{
  echo "#!/usr/bin/env bash"
  echo "set -euo pipefail"
  echo "echo 'Removing MedICS...'"
  for item in "${shortcuts[@]}"; do
    printf 'rm -rf %q\n' "$item"
  done
  printf 'rm -rf %q\n' "$install_dir"
  echo "echo 'MedICS has been removed.'"
} > "$uninstall"
chmod +x "$uninstall"

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}
{
  echo "{"
  echo "  \"install_dir\": \"$(json_escape "$install_dir")\","
  echo "  \"python\": \"$PYTHON_VERSION\","
  echo "  \"executable\": \"$(json_escape "$exe")\","
  echo "  \"launcher\": \"$(json_escape "$launcher")\","
  echo "  \"packages\": ["
  for i in "${!unique[@]}"; do
    comma=","
    [[ $i -eq $((${#unique[@]} - 1)) ]] && comma=""
    echo "    \"$(json_escape "${unique[$i]}")\"$comma"
  done
  echo "  ]"
  echo "}"
} > "$install_dir/install-manifest.json"

echo
echo "Installation complete."
echo "Launcher: MedICS"
echo "Console launcher (install folder): MedICS_console"
echo "Uninstall: $uninstall"

if [[ "$launch" -eq 1 ]]; then
  echo "Launching MedICS..."
  if [[ "$os_name" == "Darwin" ]]; then
    open -a "$install_dir/MedICS.app" 2>/dev/null || "$launcher" &
  else
    nohup "$launcher" >/dev/null 2>&1 &
    disown >/dev/null 2>&1 || true
  fi
fi
