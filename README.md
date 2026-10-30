This is my **configs** for my **arch linux**

chmod +x "path" in the scripts in the waybar to get them working aswell as rofi clipboard and calc and emoji (usually anything with an sh and py)

chmod +x ~/.config/mango/*.sh ~/.config/rofi/*.sh ~/.config/waybar/scripts/*

**pacman:**

waybar awww mako swayidle swaylock foot fish thunar yazi nvim btop mission-center rofi wireplumber pavucontrol wl-clipboard wl-clip-persist cliphist noto-fonts-emoji ttf-jetbrains-mono-nerd xdg-desktop-portal-wlr grim slurp swappy swayimg mpv python-pillow imagemagick wlopm xorg-xhost nwg-look

**aur:**

nvibrant wl-gammarelay-rs xfce-polkit wayfreeze-git

then after installing just git clone this repository
then cp -rf .config/* ~/.config/

**make thunar complete:**
sudo pacman -S gvfs gvfs-mtp gvfs-afc udisks2 thunar-volman tumbler ffmpegthumbnailer poppler-glib libgsf webp-pixbuf-loader thunar-archive-plugin thunar-media-tags-plugin catfish file-roller polkit-gnome

**optional installs if computer ever restarts:**
sudo pacman -S partitionmanager qalculate-qt steam qbittorrent prismlauncher obsidian obs-studio flatpak heroic krita supertux supertuxkart guvcview

yay -S vesktop-bin protonup-qt helium-browser-bin zen-browser-bin spotifast heroic-games-launcher-bin localsend-bin octopi photogimp

flatpak install sober (when installed flatpak)

**hide foot server and foot client keeping only foot**

mkdir -p ~/.local/share/applications
cp /usr/share/applications/footclient.desktop ~/.local/share/applications/
cp /usr/share/applications/foot-server.desktop ~/.local/share/applications/ 2>/dev/null || true

echo "NoDisplay=true" >> ~/.local/share/applications/footclient.desktop
echo "NoDisplay=true" >> ~/.local/share/applications/foot-server.desktop 2>/dev/null || true
