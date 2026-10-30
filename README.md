# Arch Linux Dotfiles & Post-Install Setup

This readme documents all required packages and configurations to set up my setup.

---

## 1. Package Installations

### Pacman Packages

`sudo pacman -S fastfetch waybar awww mako swayidle swaylock foot fish thunar yazi nvim btop mission-center rofi wireplumber pavucontrol wl-clipboard wl-clip-persist cliphist noto-fonts-emoji ttf-jetbrains-mono-nerd xdg-desktop-portal-wlr grim slurp swappy swayimg mpv python-pillow imagemagick wlopm xorg-xhost nwg-look`

### AUR Packages

`yay -S nvibrant wl-gammarelay-rs xfce-polkit wayfreeze-git`

---

## 2. Dotfiles

After installing the packages above:

1. Git clone this repository.
2. Copy the configs over:
`cp -rf .config/* ~/.config/`
3. Make sure all script files (.sh, .py) in your config directories are executable so Waybar, Rofi clipboard, calculator, and emoji pickers work.
`chmod +x ~/.config/mango/*.sh ~/.config/rofi/*.sh ~/.config/waybar/scripts/*`
---

## 3. Complete Thunar

For full file manager

`sudo pacman -S gvfs gvfs-mtp gvfs-afc udisks2 thunar-volman tumbler ffmpegthumbnailer poppler-glib libgsf webp-pixbuf-loader thunar-archive-plugin thunar-media-tags-plugin catfish file-roller polkit-gnome`

---

## 4. Optional for complete system

Install extra applications if needed:

* **Pacman:**
`sudo pacman -S partitionmanager qalculate-qt steam qbittorrent prismlauncher obsidian obs-studio flatpak krita supertux supertuxkart guvcview `
* **AUR:**
`yay -S vesktop-bin protonup-qt helium-browser-bin zen-browser-bin spotifast heroic-games-launcher-bin localsend-bin octopi photogimp rustdesk-bin onlyoffice-bin`
* **Flatpak:**
`flatpak install sober` *(needs flatpak to be installed first)*

---

## 5. Clean up Rofi

Hide extra `footclient` and `foot-server` desktop entries for a clean launcher:


mkdir -p ~/.local/share/applications

cp /usr/share/applications/footclient.desktop ~/.local/share/applications/

cp /usr/share/applications/foot-server.desktop ~/.local/share/applications/ 2>/dev/null || true


echo "NoDisplay=true" >> ~/.local/share/applications/footclient.desktop

echo "NoDisplay=true" >> ~/.local/share/applications/foot-server.desktop 2>/dev/null || true 
