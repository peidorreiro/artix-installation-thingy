#!/usr/bin/env bash

# Importing Variables
args=("$@")
formfactor=${args[0]}
threadsminusone=${args[1]}
gpu=${args[2]}
boot=${args[3]}
disk=${args[4]}
username=${args[5]}
userpassword=${args[6]}
timezone=${args[7]}
swap=${args[8]}
intel_vaapi_driver=${args[9]}
res_x=${args[10]}
res_y_half=${args[11]}

# cd into repo directory
cd /mnt

# configuring locale and clock Settings
echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf
ln -s "$timezone" /etc/localtime
locale-gen

# networkmanager configuration
pacman -S networkmanager-openrc --noconfirm
rc-update add NetworkManager

# bootloader installation and configuration
pacman -S grub efibootmgr os-prober mtools dosfstools --noconfirm
echo -e "[Trigger]\nOperation=Install\nOperation=Upgrade\nType=Package\nTarget=grub\n\n[Action]\nDescription=Re-install grub after package upgrade.\nWhen=PostTransaction\nNeedsTargets" | install -Dm 0644 /dev/stdin /etc/pacman.d/hooks/grub.hook
if [ "$boot" == 1 ]; then
    echo "Exec=/bin/sh -c 'grub-install --target=x86_64-efi --efi-directory=/boot/EFI --bootloader-id=GRUB --recheck && grub-mkconfig -o /boot/grub/grub.cfg'" >> /etc/pacman.d/hooks/grub.hook
    grub-install --target=x86_64-efi --efi-directory=/boot/EFI --bootloader-id=GRUB --recheck
fi
if [ "$boot" == 2 ]; then
    echo "Exec=/bin/sh -c 'grub-install --target=i386-pc "$disk" && grub-mkconfig -o /boot/grub/grub.cfg'" >> /etc/pacman.d/hooks/grub.hook
    grub-install --target=i386-pc "$disk"
fi
install -m 0644 /usr/share/locale/en\@quot/LC_MESSAGES/grub.mo /boot/grub/locale/en.mo
install -m 0644 ./config-files/grub /etc/default/grub
if [ "$gpu" == 'NVIDIA' ]; then
    echo "GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 quiet nowatchdog mem_sleep_default=deep nvidia-drm.modeset=1\"" >> /etc/default/grub
elif [ "$gpu" == 'AMD' ]; then
    echo "GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 quiet nowatchdog mem_sleep_default=deep amdgpu.ppfeaturemask=0xffffffff\"" >> /etc/default/grub
else
    echo "GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 quiet nowatchdog mem_sleep_default=deep\"" >> /etc/default/grub
fi
grub-mkconfig -o /boot/grub/grub.cfg

# account setup
groupadd libvirt
useradd -m -g users -G wheel,uucp,libvirt "$username"
echo "$userpassword
$userpassword
" | passwd "$username"

# opendoas configuration
echo "permit persist keepenv :wheel as root
permit nopass :wheel as root cmd /usr/bin/poweroff
permit nopass :wheel as root cmd /usr/bin/reboot
" > /etc/doas.conf
ln -s /usr/bin/doas /usr/local/bin/sudo

# pacman configuration
install -m 0644 ./config-files/pacman.conf /etc/pacman.conf
install -m 0644 ./config-files/makepkg.conf /etc/makepkg.conf
install -Dm 0644 ./config-files/makepkg-rust.conf /etc/makepkg.conf.d/rust.conf
install -m 0644 ./config-files/paccache-clean.hook /etc/pacman.d/hooks/paccache-clean.hook
install -m 0644 ./config-files/modemmanager.hook /etc/pacman.d/hooks/modemmanager.hook
install -m 0644 ./config-files/dash-link.hook /etc/pacman.d/hooks/dash-link.hook
if [ "$gpu" == 'NVIDIA' ]; then
    install -m 0644 ./config-files/nvidia.hook /etc/pacman.d/hooks/nvidia.hook
    install -m 0644 ./config-files/nvidia-lts.hook /etc/pacman.d/hooks/nvidia-lts.hook
fi

# shell configuration
pacman -Sy zsh zsh-autosuggestions zsh-syntax-highlighting --noconfirm
install -m 0644 -o $username -g users ./config-files/shell-profile /home/"$username"/.profile
install -m 0644 -o $username -g users ./config-files/zshrc /home/"$username"/.zshrc
chsh -s /bin/dash "$username"
ln -sfT dash /usr/bin/sh

# installing hardware-specific packages
if [ "$gpu" == 'AMD' ]; then
    pacman -S mesa vulkan-icd-loader vulkan-radeon libva-utils --needed --noconfirm
elif [ "$gpu" == 'Intel' ]; then
    pacman -S mesa vulkan-icd-loader vulkan-intel --needed --noconfirm
    if [ "$intel_vaapi_driver" == 1 ]; then
        pacman -S libva-intel-driver libva-utils --needed --noconfirm
    fi
    if [ "$intel_vaapi_driver" == 2 ]; then
        pacman -S intel-media-driver libva-utils --needed --noconfirm
    fi
elif [ "$gpu" == 'NVIDIA' ]; then
    pacman -S nvidia nvidia-utils nvidia-settings vulkan-icd-loader --needed --noconfirm
    echo 'options nvidia "NVreg_DynamicPowerManagement=0x02"' > /etc/modprobe.d/nvidia.conf
    echo 'options nvidia-drm modeset=1' > /etc/modprobe.d/zz-nvidia-modeset.conf
fi

# disable kernel watchdog
echo 'blacklist iTCO_wdt' > /etc/modprobe.d/blacklist.conf

# install laptop/desktop specific content (powertop on laptops; ntp local service startup script on desktops)
if [ "$formfactor" == 2 ] || [ "$formfactor" == 1 ]; then
    pacman -S powertop --needed --noconfirm
else
    install -m 0755 ./programs/ntp-rclocal/20-ntp.start /etc/local.d/20-ntp.start
    echo "0" > /etc/local.d/.ntpsync
fi

# set home directory permissions
mkdir -p /home/"$username"/{.config,.local/share}
chmod 700 /home/"$username"
chown "$username":users /home/"$username"/{.config,.local}
chown "$username":users /home/"$username"/.local/share
chmod 755 /home/"$username"/{.config,.local/share}

## XFCE Desktop Environment
if [ "$formfactor" == 1 ] || [ "$formfactor" == 2 ] || [ "$formfactor" == 3 ]; then
    # Core XFCE packages
    pacman -S \
        xfce4 \
        xfce4-goodies \
        xorg xorg-server xorg-xinit xterm xclip \
        xdg-desktop-portal xdg-desktop-portal-gtk \
        pipewire pipewire-pulse pipewire-jack pipewire-alsa wireplumber \
        lightdm lightdm-gtk-greeter \
        fastfetch htop neovim \
        firefox \
        thunar thunar-volman \
        tumbler \
        --needed --noconfirm

    # Automatically install XFCE power manager for laptops (formfactor 1 or 2)
    if [ "$formfactor" == 1 ] || [ "$formfactor" == 2 ]; then
        pacman -S xfce4-power-manager --needed --noconfirm
    fi

    # Set up display manager with OpenRC (no autologin)
    rc-update add lightdm default 2>/dev/null || true

    # directory ownership
    chown -R "$username":users /home/"$username"/.config
fi
    
# asus g14 2020 configuration
if [ "$formfactor" == 1 ]; then
    echo 'options snd_hda_intel power_save=1' > /etc/modprobe.d/audio_powersave.conf
    install -m 0755 ./programs/g14-tunables/30-tunables.start /etc/local.d/30-tunables.start
    install -m 0755 ./programs/g14-bashpower/15-bashpower.start /etc/local.d/15-bashpower.start
    install -m 0755 ./programs/NVIDIA-FCKR/NVIDIA-FCKR /usr/local/bin/NVIDIA-FCKR
    pacman -S mesa vulkan-icd-loader vulkan-radeon libva-utils acpi_call iw --needed --noconfirm
    NVIDIA-FCKR integrated
fi

# misc configuration
install -m 0755 ./programs/powerset/powerset.sh /usr/local/bin/powerset.sh
install -m 0755 ./programs/zsh-histclean/histclean /usr/local/bin/histclean
echo -e "#!/bin/sh\nfstrim -Av &" | install -m 0755 /dev/stdin /etc/local.d/99-trim.start
if [ "$swap" -gt 0 ]; then
    echo 'vm.swappiness=10' > /etc/sysctl.d/99-swappiness.conf
else
    echo 'vm.swappiness=0' > /etc/sysctl.d/99-swappiness.conf
fi
echo -e ""$username"        soft    memlock        64\n"$username"        hard    memlock        2097152\n"$username"        hard    nofile        524288\n# End of file" > /etc/security/limits.conf  # increase memlock and add support for esync
echo 'vm.max_map_count=2147483642' > /etc/sysctl.d/90-override.conf  # increase max virtual memory maps (helps with some Wine games)
echo 'ntsync' > /etc/modules-load.d/ntsync.conf
mkdir -p /etc/xdg/nvim/colors
install -m 0644 ./config-files/sysinit.vim /etc/xdg/nvim/sysinit.vim
install -m 0644 ./config-files/gruvbox.vim /etc/xdg/nvim/colors/gruvbox.vim
rc-update add local
rc-update add lightdm
rc-service lightdm start

# echo completion message
echo -e "\n---------------------------------------------------------"
echo Installation completed!
echo Please poweroff and remove the installation media before powering back on.
echo -e "---------------------------------------------------------\n"
exit
