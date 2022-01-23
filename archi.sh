#!/bin/bash

# Thanks to https://github.com/classy-giraffe/easy-arch

set -eu
shopt -s extglob

# TODO add left right arrow support for inputs to move cursor
# TODO put the maximum of the user inputs (like hostname, user, passwords, ...) at the beginning

next() {
    clear
    printf "
    _             _     _       _     
   / \   _ __ ___| |__ (_)  ___| |__  
  / _ \ | '__/ __| '_ \| | / __| '_ \ 
 / ___ \| | | (__| | | | |_\__ \ | | |
/_/   \_\_|  \___|_| |_|_(_)___/_| |_|

--------------------------------------

"
}

show_drives() {
    lsblk -po NAME,RM,SIZE,RO,TYPE,PTTYPE,FSTYPE,MOUNTPOINTS
}

detect_efi() {
    # EFI detection
    if [ -e /sys/firmware/efi/efivars ]; then
        printf "This install script only supports BIOS mode for now.\n"
        exit 1
    fi
}

select_keyboard_layout() {
    while true; do
        printf "Select the keyboard layout:\n\t1) fr-latin9\n\t2) be-latin1\n\t3) us\n> "
        read -r kbd
        case $kbd in
            1|fr-latin9 ) loadkeys fr-latin9; break;;
            2|be-latin1 ) loadkeys be-latin1; break;;
            3|us ) break;;
            * ) printf "Invalid input.\n\n";;
        esac
    done
}

update_system_clock() {
    timedatectl set-ntp true
}

partition_drives() {
    while true; do
        show_drives
        printf "\nEnter a drive to partition ('/dev/sda' for example) and type 'done' when there is nothing else to do:\n> "
        read -r drive
        case $drive in
            done ) break;;
            * )
                if ! cfdisk "$drive"; then
                    printf "Invalid input.\n\n"
                fi
                next;;
        esac
    done
}

format_partitions() {
    while true; do
        show_drives
        printf "\nEnter a partition to format ('/dev/sda1' for example) and type 'done' when there is nothing else to do:\n> "
        read -r part
        case $part in
            done ) break;;
            * )
                if ! mkfs.ext4 "$part"; then
                    printf "Invalid input.\n\n"
                fi
                sleep 1;; # give time for lsblk to show updated fs
        esac
    done
}

mount_filesystems() {
    umount -R /mnt &> /dev/null|| true # prevent umount failure to exit this script

    while true; do
        show_drives
        printf "\nEnter the partition to use as root volume ('/dev/sda1' for example):\n> "
        read -r part
        if mount "$part" /mnt; then
            break
        fi
        printf "Invalid input.\n\n"
    done

    next

    while true; do
        show_drives
        printf "\nEnter a mountpoint ('/home' for example) or type 'done' if there is nothing else to do:\n> "
        read -r mountpoint
        case $mountpoint in
            done ) break;;
            /* )
                mkdir -p /mnt"$mountpoint"
                printf "Select the partition to mount for '%s' ('/dev/sda2' for example):\n> " "$mountpoint"
                read -r part
                if ! mount "$part" /mnt"$mountpoint"; then
                    printf "Invalid input.\n\n"
                else
                    printf "\n"
                fi;;
            * ) printf "Invalid input.\n\n";;
        esac
    done
}

setup_swapfile() {
    while true; do
        printf "\nEnter the swapfile size in MiB (0 = no swap):\n> "
        read -r ssize
        case $ssize in
            +(0) ) break;;
            +([0-9]) )
                if dd if=/dev/zero of=/mnt/swapfile bs=1M count="$ssize" status=progress; then
                    chmod 600 /mnt/swapfile
                    mkswap /mnt/swapfile
                    # swapon??
                    break
                fi;;
            * ) printf "Invalid input.\n\n";;
        esac
    done
}

detect_microcode() {
    case $(grep vendor_id /proc/cpuinfo) in
        *GenuineIntel* ) microcode="intel-ucode";;
        * ) microcode="amd-ucode";;
    esac
}

detect_virt() {
    hypervisor=$(systemd-detect-virt --vm)
    case $hypervisor in
        kvm )
            printf "KVM has been detected\n"
            printf "Installing guest tools\n"
            pacstrap /mnt qemu-guest-agent
            printf "Enabling specific services for the guest tools\n"
            systemctl enable qemu-guest-agent --root=/mnt;;
        vmware )
            printf "VMWare Workstation/ESXi has been detected\n"
            printf "Installing guest tools\n"
            pacstrap /mnt open-vm-tools
            printf "Enabling specific services for the guest tools\n"
            systemctl enable vmtoolsd --root=/mnt
            systemctl enable vmware-vmblock-fuse --root=/mnt;;
        oracle )
            printf "VirtualBox has been detected\n"
            printf "Installing guest tools\n"
            pacstrap /mnt virtualbox-guest-utils
            printf "Enabling specific services for the guest tools\n"
            systemctl enable vboxservice --root=/mnt;;
        microsoft )
            printf "Hyper-V has been detected\n"
            printf "Installing guest tools\n"
            pacstrap /mnt hyperv
            printf "Enabling specific services for the guest tools\n"
            systemctl enable hv_fcopy_daemon --root=/mnt
            systemctl enable hv_kvp_daemon --root=/mnt
            systemctl enable hv_vss_daemon --root=/mnt;;
        * ) ;;
    esac
}

install_base() {
    pacman -Sy --noconfirm archlinux-keyring

    detect_microcode
    detect_virt

    printf "Installing the base system\n"
    sed -i 's/#Color/Color/;s/^#ParallelDownloads.*$/ParallelDownloads = 10/;s/#\[multilib\]/\[multilib\]/;/\[multilib]/{n;s/#Include/Include/}' /etc/pacman.conf
    pacstrap /mnt base base-devel linux linux-firmware linux-headers $microcode networkmanager grub reflector zsh nano git wpa_supplicant os-prober dosfstools

    printf "Enabling base services\n"
    systemctl enable NetworkManager --root=/mnt
    systemctl enable fstrim.timer --root=/mnt
    printf -- "--save /etc/pacman.d/mirrorlist --protocol https --country BE,DE,FR,GB --latest 10 --sort rate" > /mnt/etc/xdg/reflector/reflector.conf
    systemctl enable reflector.timer --root=/mnt

    printf "Generating fstab\n"
    genfstab -U /mnt >> /mnt/etc/fstab
    printf "\n# swapfile\n/swapfile none swap defaults 0 0\n" >> /mnt/etc/fstab

    printf "Updating pacman config\n"
    sed -i 's/#Color/Color/;s/^#ParallelDownloads.*$/ParallelDownloads = 10/;s/#\[multilib\]/\[multilib\]/;/\[multilib]/{n;s/#Include/Include/}' /mnt/etc/pacman.conf
}

install_grub() {
    while true; do
        show_drives
        printf "\nEnter the drive where grub will be installed ('/dev/sda' for example):\n> "
        read -r drive
        if arch-chroot /mnt grub-install --target=i386-pc "$drive"; then
            sed -i 's/#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /mnt/etc/default/grub
            printf "\nEdit grub config? [y/N]:\n> "
            read -r sel
            case $sel in
                y|Y ) nano /mnt/etc/default/grub;;
            esac
            arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
            break;
        fi
    done
}

set_shell_timezone_clock_locales() {
    arch-chroot /mnt /bin/bash << EOF

    printf "Setting zsh as the root shell\n"
    chsh -s /bin/zsh &> /dev/null

    printf "Setting up the timezone\n"
    ln -sf "/usr/share/zoneinfo/$(curl -s http://ip-api.com/line?fields=timezone)" /etc/localtime &>/dev/null

    printf "Setting up the clock\n"
    hwclock --systohc

    printf "Generating the locales\n"
    printf "fr_FR.UTF-8 UTF-8\n" > /etc/locale.gen
    locale-gen &> /dev/null
    printf "LANG=fr_FR.UTF-8" > /etc/locale.conf

    printf "Setting up the console keyboard layout\n"
    printf "KEYMAP=%s\n" "$kbd" > /etc/vconsole.conf
EOF
}

ask_hostname() {
    while true; do
        printf "\nEnter the hostname ('arch-laptop' for example):\n> "
        read -r hostname
        case $hostname in
            "" ) printf "Invalid input.\n\n";;
            * )
                printf "%s" "$hostname" > /mnt/etc/hostname
                printf "127.0.0.1\tlocalhost\n::1\t\tlocalhost\n127.0.1.1\t%s.localdomain\t%s" "$hostname" "$hostname" >> /mnt/etc/hosts
                break;;
        esac
    done
}

ask_root_passwd() {
    while true; do
        while true; do
            printf "\nEnter the root password:\n> "
            read -rs rootpasswd
            case $rootpasswd in
                "" ) printf "Invalid input.\n\n";;
                * ) break;;
            esac
        done
    
        printf "\nEnter the root password again:\n> "
        read -rs rootpasswd2
        if [ "$rootpasswd" = "$rootpasswd2" ]; then
            printf "\n"
            break;
        else
            printf "The passwords dont match! Try again\n"
        fi
    done

    printf "root:%s" "$rootpasswd" | arch-chroot /mnt chpasswd
}

create_user() {
    while true; do
        printf "\nEnter the new username:\n> "
        read -r user
        case $user in
            "" ) printf "Invalid input.\n\n";;
            * ) arch-chroot /mnt useradd -m -G wheel -s /bin/zsh "$user"; break;;
        esac
    done

    while true; do
        while true; do
            printf "\nEnter the password for '%s':\n> " "$user"
            read -rs userpasswd
            case $userpasswd in
                "" ) printf "Invalid input.\n\n";;
                * ) break;;
            esac
        done
    
        printf "\nEnter the user password for '%s' again:\n> " "$user"
        read -rs userpasswd2
        if [ "$userpasswd" = "$userpasswd2" ]; then
            break
        else
            printf "The passwords dont match! Try again\n"
        fi
    done

    printf "%s:%s" "$user" "$userpasswd" | arch-chroot /mnt chpasswd
    sed -i 's/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /mnt/etc/sudoers
}

install_preset() {
    printf "Install the Gnome preset? [Y/n]:\n> "
    read -r sel
    case $sel in
        n|N ) return;;
    esac

    vdriver=""
    while [ "$hypervisor" = "none" ]; do
        printf "\nSelect the video driver to install:\n\t1) xf86-video-amdgpu (NEW)\n\t2) xf86-video-ati (OLD)\n\t3) xf86-video-intel\n\t4) nvidia\n\n> "
        read -r vdriver
        case $vdriver in
            1|xf86-video-amdgpu ) vdriver="xf86-video-amdgpu vulkan-radeon"; break;;
            2|xf86-video-ati ) vdriver=xf86-video-ati; break;;
            3|xf86-video-intel ) vdriver=xf86-video-intel; break;;
            4|nvidia ) vdriver=nvidia; break;;
            * ) printf "Invalid input.\n\n";;
        esac
    done

    printf "Installing the Gnome preset\n"
    pacstrap /mnt $vdriver gnome cups unrar vim firefox transmission-gtk rhythmbox thunderbird steam mpv libreoffice hplip keepassxc gparted ttf-dejavu noto-fonts-cjk neofetch ghex gnome-software-packagekit-plugin bat fzf chafa

    printf "Enabling services for the Gnome preset\n"
    systemctl enable cups.socket --root=/mnt
    systemctl enable gdm.service --root=/mnt

    # restore here gnome config
    # restore gnome extensions here
    # restore here corectrl config
    # init here hplip
    # install youtube-dl with python-pip

    # AUR
    printf "Enabling access to the AUR"
    git clone https://aur.archlinux.org/yay.git && cd yay && makepkg -si && cd .. && rm -rf yay
    printf "Installing the AUR packages"
    yay -S --noconfirm chrome-gnome-shell megasync-bin nautilus-megasync rhythmbox-plugin-alternative-toolbar ttf-ms-fonts visual-studio-code-bin nautilus-admin-git corectrl
}

epilogue() {
    printf "TODO end\n"
    exit # exit the chroot
}

# TODO test this as it is for now in a VM!!!

##################################################

# PREINSTALL

detect_efi
next
select_keyboard_layout
next
update_system_clock
next
partition_drives
next
format_partitions
next
mount_filesystems
next
setup_swapfile

# INSTALL

next
install_base
next
install_grub
set_shell_timezone_clock_locales
next
ask_hostname
ask_root_passwd
create_user
next
install_preset
next
epilogue
