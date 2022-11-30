#!/bin/bash
set -e
cd "$(dirname "$0")"

# Secure boot + encryption setup has been heavily inspired by:
# https://gist.github.com/huntrar/e42aee630bee3295b2c671d098c81268

HOSTNAME=laptop
USERNAME=shellcode
GRUB_RESOLUTION=1080p 

ask_yes_no() {
    case $1 in
        [Yy]* ) return 0 ;;
        * ) return 1 ;;
    esac
}

install_archlinux() {
    timedatectl set-ntp true
    localectl set-keymap --no-convert fr-latin1 # Load french azerty keymap

    lsblk
    
    if [ -d /sys/firmware/efi ]
    then
        echo "UEFI boot detected, DISK ENCRYPTION ENABLED"
    else
        echo "legacy BIOS boot detected, DISK ENCRYPTION DISABLED"
    fi

    read -r -p "Which disk do you want to install to ? (usually /dev/sda) " disk_to_use
    read -r -p "You're about to erase ALL $disk_to_use are you sure ? [y/N] " yn

    if ! ask_yes_no "$yn"
    then
        exit 1
    fi

    echo "Writing random bytes to $disk_to_use, go grab coffee this might take a while"
    dd if=/dev/random of="$disk_to_use" status=progress

    if [ -d /sys/firmware/efi ]
    then
        echo -n "Creating partitions and filesystems... "
        parted "$disk_to_use" mklabel gpt --script
        parted "$disk_to_use" mkpart efi fat32 1MiB 65MiB --script
        parted "$disk_to_use" set 1 esp on --script
        parted "$disk_to_use" mkpart primary ext4 65MiB 100% --script
        mkfs.fat -F 32 "${disk_to_use}1"
        cryptsetup luksFormat --batch-mode --type luks1 --use-random --key-slot 1 --key-size 512 --hash sha512 --pbkdf-force-iterations 200000 "${disk_to_use}2"
        cryptsetup open "${disk_to_use}2" encrypted_root
        pvcreate /dev/mapper/encrypted_root
        vgcreate vg /dev/mapper/encrypted_root
        lvcreate -l 100%FREE vg -n root
        mkfs.ext4 /dev/vg/root
        echo "Done !"

        echo -n "Mounting installation... "
        mount --mkdir /dev/vg/root /mnt
        mount --mkdir "${disk_to_use}1" /mnt/efi
        echo "Done !"
    else
        echo -n "Creating partitions and filesystems... "
        parted "$disk_to_use" mklabel msdos --script
        parted "$disk_to_use" mkpart primary ext4 1MiB 100% --script
        parted "$disk_to_use" set 1 boot on --script
        parted "$disk_to_use" mkpart primary ext4 301MiB 100% --script
        mkfs.ext4 "${disk_to_use}1"
        mkfs.ext4 "${disk_to_use}2"
        echo "Done !"

        echo -n "Mounting installation... "
        mount --mkdir "${disk_to_use}2" /mnt
        mount --mkdir "${disk_to_use}1" /mnt/boot
        echo "Done !"
    fi

    if [ -d /sys/firmware/efi ]
    then
        pacstrap -K /mnt base base-devel \
                         linux linux-firmware \
                         intel-ucode \
                         mkinitcpio \
                         lvm2 \
                         efibootmgr \
                         grub \
                         networkmanager
    else
        pacstrap -K /mnt base base-devel \
                         linux linux-firmware \
                         intel-ucode \
                         mkinitcpio \
                         grub \
                         networkmanager
    fi

    echo -n "Generating /etc/fstab... "
    genfstab -U /mnt >> /mnt/etc/fstab
    sed -i 's/relatime/noatime/g' /mnt/etc/fstab
    echo "Done !"

    # TODO : echo laptop > /etc/hostname ?
    # TODO : set /etc/hosts accordingly ?
    # Basic configuration
    arch-chroot /mnt /bin/bash -c 'ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime && \
                                   hwclock --systohc && \
                                   sed -i "s/^#en_US.UTF-8/en_US.UTF-8/g" /etc/locale.gen && \
                                   sed -i "s/^#fr_FR.UTF-8/fr_FR.UTF-8/g" /etc/locale.gen && \
                                   locale-gen && \
                                   echo LANG=\"en_US.UTF-8\" > /etc/locale.conf && \
                                   echo LC_MESSAGES=\"en_US.UTF-8\" >> /etc/locale.conf && \
                                   echo LC_MONETARY=\"fr_FR.UTF-8\" >> /etc/locale.conf && \
                                   echo LC_PAPER=\"fr_FR.UTF-8\" >> /etc/locale.conf && \
                                   echo LC_MEASUREMENT=\"fr_FR.UTF-8\" >> /etc/locale.conf && \
                                   echo LC_ADDRESS=\"fr_FR.UTF-8\" >> /etc/locale.conf && \
                                   echo LC_TIME=\"fr_FR.UTF-8\" >> /etc/locale.conf && \
                                   echo "KEYMAP=fr-latin1" > /etc/vconsole.conf && \
                                   echo DONE!
                                   '

    # If EFI is in use, so is encryption, additional configuration is required
    if [ -d /sys/firmware/efi ]
    then
        ROOT_UUID=$(lsblk "$disk_to_use" -f | grep crypto_LUKS | awk '{ print $4 }')

        if [ -z "$ROOT_UUID" ]
        then
            echo "crypto_LUKS partition not found..."
            exit 1
        fi

        # Add crypto keyfile so that passphrase is asked only once (by grub and not by initramfs)
        mkdir /mnt/root/secrets
        chmod 700 /mnt/root/secrets
        head -c 64 /dev/urandom > /mnt/root/secrets/crypto_keyfile.bin
        chmod 600 /mnt/root/secrets/crypto_keyfile.bin
        cryptsetup -v luksAddKey --pbkdf-force-iterations 1000 "${disk_to_use}2" /mnt/root/secrets/crypto_keyfile.bin

        # Add encryption hooks to initcpio
        arch-chroot /mnt /bin/bash -c "sed -i 's/^HOOKS.*block/\0 encrypt lvm2/g' /etc/mkinitcpio.conf && \
                                       sed -i 's+^FILES=()+FILES=(/root/secrets/crypto_keyfile.bin)+g' /etc/mkinitcpio.conf && \
                                       mkinitcpio -p linux"

        # Configure and install grub
        arch-chroot /mnt /bin/bash -c "sed -i 's/^#GRUB_ENABLE_CRYPTODISK/GRUB_ENABLE_CRYPTODISK/g' /etc/default/grub && \
                                       sed -i 's/GRUB_TERMINAL_INPUT=console/GRUB_TERMINAL_INPUT=at_keyboard/g' /etc/default/grub && \
                                       sed -i 's+^GRUB_CMDLINE_LINUX=\"\"+GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=$ROOT_UUID:encrypted_root root=/dev/vg/root cryptkey=rootfs:/root/secrets/crypto_keyfile.bin\"+g' /etc/default/grub && \
                                       grub-install --target=x86_64-efi --efi-directory=/efi"
    else
        # Install grub
        arch-chroot /mnt /bin/bash -c "grub-install $disk_to_use"
    fi

    # Setup users and passwords
    echo "Set root password:"
    arch-chroot /mnt /bin/bash -c "passwd"
    echo "Set $USERNAME password:"
    arch-chroot /mnt /bin/bash -c "useradd --create-home --groups wheel $USERNAME && \
                                   passwd $USERNAME"

    # Temporarly give sudo NOPASSWD rights to user
    echo "shellcode ALL=(ALL) NOPASSWD:ALL" > "/mnt/etc/sudoers.d/$USERNAME"

    # Install AUR helper
    arch-chroot /mnt /bin/su -l "$USERNAME" -c 'mkdir /tmp/yay.$$ && \
                                                cd /tmp/yay.$$ && \
                                                curl "https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h=yay-bin" -o PKGBUILD && \
                                                makepkg -si --noconfirm'

    # Install ckbcomp from AUR to generate GRUB fr keymap
    arch-chroot /mnt /bin/su -l "$USERNAME" -c 'yay --noconfirm -S ckbcomp xkeyboard-config'

    # Generate GRUB fr keymap
    arch-chroot /mnt /bin/bash -c 'mkdir -p /boot/grub/layouts && \
                                   grub-kbdcomp -o /boot/grub/layouts/fr.gkb fr' # wrapper arround ckbcomp

    # shellcheck disable=SC2016
    echo -e 'insmod keylayouts\n' \
            'keymap /boot/grub/layouts/fr.gkb\n\n' \
            'insmod gfxterm_background\n' \
            'loadfont $prefix/themes/darkmatter/hackb_18.pf2\n' \
            'loadfont $prefix/themes/darkmatter/norwester_16.pf2\n' \
            'loadfont $prefix/themes/darkmatter/norwester_20.pf2\n' \
            'loadfont $prefix/themes/darkmatter/norwester_22.pf2\n' \
            'insmod png\n' \
            'set theme=$prefix/themes/darkmatter/theme.txt\n' \
            'export theme' >> /mnt/etc/grub.d/40_custom

    # Generate grub configuration
    arch-chroot /mnt /bin/bash -c "grub-mkconfig -o /boot/grub/grub.cfg"

    # Apply grub theme
    arch-chroot /mnt /bin/bash -c "cd /tmp && \
                                   curl -O https://gitlab.com/VandalByte/darkmatter-grub-theme/-/archive/6094e5ee0e4bd7f204e1da3808aee70ba0d93256/darkmatter-grub-theme-6094e5ee0e4bd7f204e1da3808aee70ba0d93256.tar.gz && \
                                   tar xf darkmatter-grub-theme-6094e5ee0e4bd7f204e1da3808aee70ba0d93256.tar.gz && \
                                   mkdir -p /boot/grub/themes/darkmatter && \
                                   cd darkmatter-grub-theme-6094e5ee0e4bd7f204e1da3808aee70ba0d93256/ && \
                                   cp base/$GRUB_RESOLUTION/* /boot/grub/themes/darkmatter/ && \
                                   cp assets/backgrounds/arch-$GRUB_RESOLUTION.png /boot/grub/themes/darkmatter/background.png && \
                                   cp assets/fonts/$GRUB_RESOLUTION/* /boot/grub/themes/darkmatter/ && \
                                   cp -r assets/icons-$GRUB_RESOLUTION/color/ /boot/grub/themes/darkmatter/icons/"



    if [ -d /sys/firmware/efi ]
    then
        # shellcheck disable=SC2016
        arch-chroot /mnt /bin/bash -c 'cd / && grub-mkstandalone --directory /usr/lib/grub/x86_64-efi/ \
                                                                 --format=x86_64-efi \
                                                                 --compress="xz" \
                                                                 --modules="part_gpt crypto cryptodisk luks disk diskfilter lvm" \
                                                                 --fonts="unicode" \
                                                                 --output="/efi/EFI/arch/grubx64.efi" \
                                                                 "boot/grub/grub.cfg=/boot/grub/grub.cfg" \
                                                                 "boot/grub/layouts/fr.gkb=/boot/grub/layouts/fr.gkb" \
                                                                 $(find boot/grub/themes/darkmatter -type f -exec echo {}=/{} \;)'
    fi

    # Configure systemd services
    arch-chroot /mnt /bin/bash -c "systemctl enable NetworkManager"

    # Remove sudo NOPASSWD rights to user
    rm "/mnt/etc/sudoers.d/$USERNAME"

    # Hardenning
    arch-chroot /mnt /bin/bash -c "chmod 700 /boot"
}

install_archlinux "$@"
