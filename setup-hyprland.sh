#!/usr/bin/env bash
#
# Arch Linux setup script for Hyprland-Setup-Liquid-Glass dotfiles
#
# Deploys the macOS 27 (Golden Gate) Liquid Glass desktop setup:
#   - Unified single-window Liquid Glass Quickshell menu bar (Arch menu, active
#     app menu, Spaces strip, Now Playing pill, native overflow tray + Liquid
#     Glass tray menus, Wi-Fi, Sound + OSD HUD, Battery [laptop only],
#     Spotlight, Control Center with live Liquid Glass Tint slider & Edit
#     Controls, Calendar/Stats)
#   - Liquid Glass Wofi launcher (with pop-in animation & Kawase backdrop blur)
#   - Liquid Glass GNOME Nautilus (GTK4 / libadwaita) with smooth edges
#   - Hyprland Lua config with high-vibrancy Kawase blur & layer rules
#
# Usage:
#   chmod +x setup-hyprland.sh
#   ./setup-hyprland.sh
#   ./setup-hyprland.sh --profile desktop   # skip prompt (used by updater)
#   ./setup-hyprland.sh --profile laptop
#
# NOTE: Everything package-related runs with --noconfirm EXCEPT the `steam`
# install itself, which is left interactive so you can pick the correct
# vulkan driver provider (nvidia/amd/intel). `chsh` may also ask for your
# account password when changing the default shell.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell"
PROFILE_FILE="$STATE_DIR/device-profile"
SETTINGS_FILE="$STATE_DIR/settings.json"

log()  { echo -e "\e[1;32m[+]\e[0m $*"; }
warn() { echo -e "\e[1;33m[!]\e[0m $*"; }
err()  { echo -e "\e[1;31m[-]\e[0m $*" >&2; }

if [[ $EUID -eq 0 ]]; then
    err "Don't run this script as root directly — run it as your normal user."
    err "It will call sudo itself whenever it needs elevated privileges."
    exit 1
fi

### ---------------------------------------------------------------------
### 0. Device profile selection (Laptop vs Desktop)
### ---------------------------------------------------------------------
DEVICE_PROFILE="${DEVICE_PROFILE:-}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile)
            [[ $# -ge 2 ]] || { err "--profile requires 'laptop' or 'desktop'."; exit 2; }
            DEVICE_PROFILE="$2"
            shift 2
            ;;
        --profile=*)
            DEVICE_PROFILE="${1#*=}"
            shift
            ;;
        *)
            err "Unknown argument: $1"
            exit 2
            ;;
    esac
done

if [[ -z "$DEVICE_PROFILE" ]]; then
    SAVED_PROFILE=""
    if [[ -f "$PROFILE_FILE" ]]; then
        SAVED_PROFILE="$(tr -d '[:space:]' < "$PROFILE_FILE")"
    fi
    echo ""
    echo "Select your machine type:"
    echo "  1) Laptop  (includes battery indicator and screen brightness controls)"
    echo "  2) Desktop (omits battery and brightness features)"
    while true; do
        if [[ "$SAVED_PROFILE" == "desktop" ]]; then
            read -r -p "Are you on a laptop or desktop? [1/2, default 2 (desktop)]: " choice
            choice="${choice:-2}"
        elif [[ "$SAVED_PROFILE" == "laptop" ]]; then
            read -r -p "Are you on a laptop or desktop? [1/2, default 1 (laptop)]: " choice
            choice="${choice:-1}"
        else
            read -r -p "Are you on a laptop or desktop? [1/2]: " choice
        fi
        case "${choice,,}" in
            1|l|laptop)  DEVICE_PROFILE="laptop";  break ;;
            2|d|desktop) DEVICE_PROFILE="desktop"; break ;;
            *) warn "Please enter 1 (laptop) or 2 (desktop)." ;;
        esac
    done
fi

case "$DEVICE_PROFILE" in
    laptop|desktop) ;;
    *)
        err "Invalid profile '$DEVICE_PROFILE'. Expected 'laptop' or 'desktop'."
        exit 2
        ;;
esac

mkdir -p "$STATE_DIR"
printf '%s\n' "$DEVICE_PROFILE" > "$PROFILE_FILE"
log "Device profile set to: $DEVICE_PROFILE (saved to $PROFILE_FILE)"

# Keep sudo alive for the whole script
sudo -v
( while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) &
SUDO_KEEPALIVE_PID=$!
QUICKSHELL_TMPDIR=""
cleanup() {
    kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    [[ -n "$QUICKSHELL_TMPDIR" && -d "$QUICKSHELL_TMPDIR" ]] && rm -rf -- "$QUICKSHELL_TMPDIR"
}
trap cleanup EXIT

# Resolve the Quickshell source directory (supports uncompressed ./quickshell
# or compressed ./quickshell.zip without dirtying the git checkout).
QUICKSHELL_SRC=""
if [[ -d "$SCRIPT_DIR/quickshell" ]]; then
    QUICKSHELL_SRC="$SCRIPT_DIR/quickshell"
elif [[ -f "$SCRIPT_DIR/quickshell.zip" ]]; then
    log "Uncompressing quickshell.zip..."
    QUICKSHELL_TMPDIR="$(mktemp -d)"
    if command -v bsdtar >/dev/null 2>&1; then
        bsdtar -xf "$SCRIPT_DIR/quickshell.zip" -C "$QUICKSHELL_TMPDIR"
    elif command -v unzip >/dev/null 2>&1; then
        unzip -q "$SCRIPT_DIR/quickshell.zip" -d "$QUICKSHELL_TMPDIR"
    elif command -v python3 >/dev/null 2>&1; then
        python3 -m zipfile -e "$SCRIPT_DIR/quickshell.zip" "$QUICKSHELL_TMPDIR"
    else
        err "Cannot extract quickshell.zip: none of bsdtar, unzip, or python3 found."
        exit 1
    fi
    if [[ -d "$QUICKSHELL_TMPDIR/quickshell" ]]; then
        QUICKSHELL_SRC="$QUICKSHELL_TMPDIR/quickshell"
    else
        QUICKSHELL_SRC="$QUICKSHELL_TMPDIR"
    fi
else
    err "Missing quickshell source: expected $SCRIPT_DIR/quickshell or $SCRIPT_DIR/quickshell.zip"
    exit 1
fi

### ---------------------------------------------------------------------
### 1. Enable multilib
### ---------------------------------------------------------------------
log "Enabling multilib repository..."
if grep -q "^\[multilib\]" /etc/pacman.conf; then
    log "multilib already enabled, skipping."
else
    sudo cp /etc/pacman.conf /etc/pacman.conf.bak
    sudo sed -i '/^#\[multilib\]/,/^#Include = \/etc\/pacman.d\/mirrorlist/ s/^#//' /etc/pacman.conf
fi

log "Syncing package databases..."
sudo pacman -Syu --noconfirm

### ---------------------------------------------------------------------
### 2. Install official repo packages (noconfirm) - everything except steam
### ---------------------------------------------------------------------
mapfile -t RAW_QUICKSHELL_PACKAGES < "$QUICKSHELL_SRC/packages.txt"
QUICKSHELL_PACKAGES=()
for pkg in "${RAW_QUICKSHELL_PACKAGES[@]}"; do
    [[ -z "$pkg" ]] && continue
    if [[ "$DEVICE_PROFILE" == "desktop" && "$pkg" == "brightnessctl" ]]; then
        log "Desktop profile: skipping brightnessctl package."
        continue
    fi
    QUICKSHELL_PACKAGES+=("$pkg")
done

PACMAN_PACKAGES=(
    hyprland
    hyprlock
    hyprpaper
    hyprpolkitagent
    polkit
    udisks2
    gvfs
    discord
    code
    flatpak
    librewolf
    wofi
    kitty
    nautilus
    fastfetch
    btop
    rocm-smi-lib # AMD GPU monitoring in btop
    base-devel
    git
    go
    pavucontrol
    fish
    "${QUICKSHELL_PACKAGES[@]}"
)

log "Installing pacman packages: ${PACMAN_PACKAGES[*]}"
sudo pacman -S --needed --noconfirm "${PACMAN_PACKAGES[@]}"

log "Enabling NetworkManager and Bluetooth for subsequent boots..."
sudo systemctl enable NetworkManager.service bluetooth.service

### ---------------------------------------------------------------------
### 3. Install steam interactively so the vulkan driver provider prompt
###    stays selectable
### ---------------------------------------------------------------------
log "Installing steam (interactive — pick the correct vulkan driver / lib32 provider when prompted)..."
sudo pacman -S --needed steam

### ---------------------------------------------------------------------
### 4. Install yay (AUR helper)
### ---------------------------------------------------------------------
if ! command -v yay >/dev/null 2>&1; then
    log "Installing yay AUR helper..."
    BUILD_DIR="$(mktemp -d)"
    git clone --depth 1 https://aur.archlinux.org/yay.git "$BUILD_DIR/yay"
    (cd "$BUILD_DIR/yay" && makepkg -si --noconfirm)
    rm -rf "$BUILD_DIR"
else
    log "yay already installed, skipping."
fi

log "Installing kew music player from the AUR..."
yay -S --needed --noconfirm kew

### ---------------------------------------------------------------------
### 5. Flatpak remote and applications
### ---------------------------------------------------------------------
log "Setting up flathub remote..."
sudo flatpak remote-add --system --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

log "Installing Mission Center from Flathub..."
sudo flatpak install --system --assumeyes flathub io.missioncenter.MissionCenter

### ---------------------------------------------------------------------
### 6. Deploy Liquid Glass dotfiles (flat repo -> ~/.config/ subfolders)
### ---------------------------------------------------------------------
log "Deploying Liquid Glass config files..."

if [[ -d "$HOME/.config/hypr" ]]; then
    log "Clearing existing ~/.config/hypr contents..."
    rm -rf "$HOME/.config/hypr"
fi

mkdir -p "$HOME/.config/hypr" \
         "$HOME/.config/wofi" \
         "$HOME/.config/kitty" \
         "$HOME/.config/fastfetch" \
         "$HOME/.config/gtk-4.0" \
         "$HOME/.config/btop/themes"

copy_config() {
    local src="$1" dst="$2"
    if [[ -f "$src" ]]; then
        cp -f "$src" "$dst"
        log "  -> $dst"
    else
        err "  Missing source file: $src"
        exit 1
    fi
}

copy_config_dir() {
    local src="$1" dst="$2"
    if [[ -d "$src" ]]; then
        rm -rf -- "$dst"
        mkdir -p "$dst"
        cp -a "$src/." "$dst/"
        chmod +x "$dst/run.sh" "$dst/install-dependencies.sh" "$dst/scripts/"*.sh
        log "  -> $dst"
    else
        err "  Missing source directory: $src"
        exit 1
    fi
}

copy_config "$SCRIPT_DIR/hyprland.lua"        "$HOME/.config/hypr/hyprland.lua"
copy_config "$SCRIPT_DIR/hyprlock.conf"       "$HOME/.config/hypr/hyprlock.conf"
copy_config "$SCRIPT_DIR/hyprpaper.conf"      "$HOME/.config/hypr/hyprpaper.conf"
copy_config "$SCRIPT_DIR/mywallpaper.png"     "$HOME/.config/hypr/wallpaper.png"
copy_config "$SCRIPT_DIR/wofi-style.css"      "$HOME/.config/wofi/style.css"
copy_config "$SCRIPT_DIR/wofi-config"         "$HOME/.config/wofi/config"
copy_config "$SCRIPT_DIR/kitty.conf"          "$HOME/.config/kitty/kitty.conf"
copy_config "$SCRIPT_DIR/fastfetch.jsonc"     "$HOME/.config/fastfetch/config.jsonc"
copy_config_dir "$QUICKSHELL_SRC"             "$HOME/.config/quickshell"

# Apply device profile (disable battery & brightness on desktop installs)
if [[ "$DEVICE_PROFILE" == "desktop" ]]; then
    log "Applying desktop profile: disabling brightness and battery features..."
    # Remove brightness keybindings from deployed hyprland.lua
    sed -i '/XF86MonBrightness/d' "$HOME/.config/hypr/hyprland.lua"
    # Set desktopMode defaults in deployed SettingsService.qml
    sed -i \
        -e 's/property bool   desktopMode: false/property bool   desktopMode: true/' \
        -e 's/property bool   ccShowBrightness: true/property bool   ccShowBrightness: false/' \
        -e 's/property bool   ccShowBattery: true/property bool   ccShowBattery: false/' \
        -e 's/property bool   showBatteryPercent: true/property bool   showBatteryPercent: false/' \
        "$HOME/.config/quickshell/services/SettingsService.qml"
fi

# Persist desktopMode in ~/.local/state/quickshell/settings.json so existing
# state files never override the chosen machine profile.
python3 - "$SETTINGS_FILE" "$DEVICE_PROFILE" <<'PY'
import json, os, sys
path, profile = sys.argv[1], sys.argv[2]
data = {}
if os.path.exists(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        data = {}
is_desktop = (profile == "desktop")
data["desktopMode"] = is_desktop
if is_desktop:
    data["ccShowBrightness"] = False
    data["ccShowBattery"] = False
    data["showBatteryPercent"] = False
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f)
PY

# btop theme
BTOP_CONFIG="$HOME/.config/btop/btop.conf"
if [[ -f "$BTOP_CONFIG" ]] && ! cmp -s "$SCRIPT_DIR/btop.conf" "$BTOP_CONFIG"; then
    cp --backup=numbered -- "$BTOP_CONFIG" "$BTOP_CONFIG.backup"
    log "  Saved previous btop settings to $BTOP_CONFIG.backup"
fi
copy_config "$SCRIPT_DIR/readable-grayscale.theme" "$HOME/.config/btop/themes/readable-grayscale.theme"
copy_config "$SCRIPT_DIR/btop.conf" "$BTOP_CONFIG"

# Nautilus Liquid Glass GTK4 theme
GTK_CSS="$HOME/.config/gtk-4.0/gtk.css"
if [[ -f "$GTK_CSS" ]] && ! cmp -s "$SCRIPT_DIR/nautilus.css" "$GTK_CSS"; then
    cp --backup=numbered -- "$GTK_CSS" "$GTK_CSS.backup"
    log "  Saved previous GTK styling to $GTK_CSS.backup"
fi
copy_config "$SCRIPT_DIR/nautilus.css" "$GTK_CSS"
if command -v gsettings >/dev/null 2>&1; then
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
fi
log "Nautilus Liquid Glass theme installed. Restart Files to apply it."

# Ensure Kitty maximize suppression rule is present in hyprland.lua
ensure_kitty_maximize_rule() {
    local config_file="$HOME/.config/hypr/hyprland.lua"
    if grep -Fq 'name = "kitty-no-maximize"' "$config_file"; then
        log "  Kitty maximize suppression rule is present."
        return
    fi

    cat >> "$config_file" <<'LUA'

hl.window_rule({
    name = "kitty-no-maximize",
    match = { class = "^kitty$" },
    suppress_event = "maximize",
    no_blur = true,
})
LUA
    log "  Added Kitty maximize suppression rule."
}

ensure_kitty_maximize_rule

### ---------------------------------------------------------------------
### 7. Configure Fish shell
### ---------------------------------------------------------------------
FISH_CONFIG="$HOME/.config/fish/config.fish"
mkdir -p "$(dirname "$FISH_CONFIG")"

log "Adding fastfetch to Fish startup..."
if ! grep -qxF '    fastfetch' "$FISH_CONFIG" 2>/dev/null; then
    cat >> "$FISH_CONFIG" <<'FISH'

if status is-interactive
    fastfetch
end
FISH
    log "  Added."
else
    log "  Already present, skipping."
fi

if ! grep -qxF 'set -g fish_greeting' "$FISH_CONFIG" 2>/dev/null; then
    echo 'set -g fish_greeting' >> "$FISH_CONFIG"
fi

log "Setting Fish as the default login shell..."
if [[ "$(getent passwd "$USER" | cut -d: -f7)" == /usr/bin/fish ]]; then
    log "Fish is already the default login shell."
else
    chsh -s /usr/bin/fish "$USER"
fi

log "Done! Fully log out and start Hyprland again (or reboot) — hyprland.lua vs .conf priority is only checked once at startup, so 'hyprctl reload' alone will NOT pick this up."
warn "Remember: this script did NOT touch your GPU/vulkan driver packages beyond the steam prompt — install lib32-nvidia-utils / lib32-vulkan-radeon / lib32-vulkan-intel yourself if the prompt didn't select them."
