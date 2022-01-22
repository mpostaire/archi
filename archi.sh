#!/bin/bash

set -eu
shopt -s extglob

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

show_disks() {
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

partition_disks() {
    while true; do
        show_disks
        printf "\nEnter a disk to partition ('/dev/sda' for example) and type 'done' when there is nothing else to do:\n> "
        read -r disk
        case $disk in
            done ) break;;
            * ) if ! cfdisk "$disk"; then
                printf "Invalid input.\n\n"
            fi
            next;;
        esac
    done
}

format_partitions() {
    while true; do
        show_disks
        printf "\nEnter a partition to format ('/dev/sda1' for example) and type 'done' when there is nothing else to do:\n> "
        read -r part
        case $part in
            done ) break;;
            * ) if ! mkfs.ext4 "$part"; then
                printf "Invalid input.\n\n"
            fi
            sleep 1;; # give time for lsblk to show updated fs
        esac
    done
}

mount_filesystems() {
    umount -a > /dev/null 2>&1 || true # prevent umount failure to exit this script

    while true; do
        show_disks
        printf "\nEnter the partition to use as root volume ('/dev/sda1' for example):\n> "
        read -r part
        if mount "$part" /mnt; then
            break
        fi
        printf "Invalid input.\n\n"
    done

    next

    while true; do
        show_disks
        printf "\nEnter a mountpoint ('/home' for example) or type 'done' if there is nothing else to do:\n> "
        read -r mountpoint
        case $mountpoint in
            done ) break;;
            /* ) mkdir -p /mnt"$mountpoint"
                while true; do
                    printf "Select the partition to mount for '%s' ('/dev/sda2' for example):\n> " "$mountpoint"
                    read -r part
                    case $part in
                        done ) break;;
                        * ) if ! mount "$part" /mnt"$mountpoint"; then
                            printf "Invalid input.\n\n"
                            break
                        fi;;
                    esac
                done;;
            * ) printf "Invalid input.\n\n";;
        esac
    done
}

setup_swapfile() {
    while true; do
        printf "\nEnter the swapfile size (in MiB):\n> "
        read -r ssize
        case $ssize in
            +([0-9]) )
                if dd if=/dev/zero of=/mnt/swapfile bs=1M count="$ssize" status=progress; then
                    chmod 600 /mnt/swapfile
                    mkswap /mnt/swapfile
                    break
                fi
                printf "Invalid input.\n\n";;
            * ) printf "Invalid input.\n\n";;
        esac
    done
}

make_fstab() {
    printf "\n# swapfile\n/swapfile none swap defaults 0 0\n" >> /etc/fstab
}

##################################################

detect_efi
next
select_keyboard_layout
next
update_system_clock
next
partition_disks
next
format_partitions
next
mount_filesystems
next
setup_swapfile

# INSTALLATION
