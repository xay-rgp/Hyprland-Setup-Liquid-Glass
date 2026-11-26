# Hyprland-Setup-Liquid-Glass

Arch Linux + Hyprland (Lua config) dotfiles replicating the **macOS 27 (Golden Gate) Liquid Glass** aesthetic across Quickshell, Wofi, Hyprlock, and GNOME Nautilus.

## What's Included

- **Quickshell macOS 27 Liquid Glass Menu Bar (`quickshell/`)**
  - Unified single-window transparent/frosted menu bar with crisp `Adwaita Sans` typography and vector-antialiased Liquid Glass popovers.
  - **Left**: Arch Linux System Menu, bold Active App Menu (Hyprland window actions), and Spaces/Workspaces strip.
  - **Right**: Now Playing glass pill, native macOS 27 Overflow tray (`«`/`»`) + Liquid Glass tray click menus, Wi-Fi, Sound (scroll + live Liquid Glass OSD HUD), Battery capsule, Spotlight launcher, Control Center, and Date & Time (Calendar + live system overview).
  - **Control Center**: Bento connectivity card (Wi-Fi, Bluetooth, Night Shift), Focus toggle, live **Liquid Glass Tint Slider**, **Bar Background** & **Reduce Glass** toggles, glossy Display & Sound sliders, Now Playing card, Battery status, and **Edit Controls** customization page.
- **Wofi Liquid Glass (`wofi-style.css`, `wofi-config`)**: Frosted glass launcher with Kawase backdrop blur, `popin 85%` open animation, app icons, and macOS blue selection pills.
- **Hyprlock Liquid Glass (`hyprlock.conf`)**: Frosted glass lock screen with high-vibrancy Kawase screenshot blur, top-center macOS clock & date typography, and a sleek floating Liquid Glass password pill with macOS accent states.
- **GNOME Nautilus Liquid Glass (`nautilus.css`)**: Translucent Finder-style GTK4/libadwaita theme with clean compositor-rounded edges.
- **Hyprland (`hyprland.lua`)**: High-vibrancy Kawase blur, `quickshell` & `wofi` layer rules, and smooth `nautilus` window rules.

## Usage

```bash
chmod +x setup-hyprland.sh
./setup-hyprland.sh
```

## Contributors

- **xay-rgp** — Repository author & maintainer
- **Antigravity (Google DeepMind)** — Contributor
