#!/bin/bash
set -e
cd "$(dirname "$0")"

# Secure boot + encryption setup has been heavily inspired by:
# https://gist.github.com/huntrar/e42aee630bee3295b2c671d098c81268

GRUB_RESOLUTION=1080p 
GRUB_THEME_COMMIT=6094e5ee0e4bd7f204e1da3808aee70ba0d93256

ask_yes_no() {
    case $1 in
        [Yy]* ) return 0 ;;
        * ) return 1 ;;
    esac
}

ask_password() {
    read -r -p "Set $1 password: " -s password
    >&2 echo
    read -r -p "Confirm $1 password: " -s password_check
    >&2 echo

    until [ "$password" == "$password_check" ]
    do
        >&2 echo
        >&2 echo "Passwords do not match!"
        >&2 echo
        read -r -p "Set $1 password: " -s password
        >&2 echo
        read -r -p "Confirm $1 password: " -s password_check
        >&2 echo
    done

    echo "$password" # return value, yes bash sucks
}

install_archlinux() {
    
    if [ ! -d /sys/firmware/efi ]
    then
        echo "legacy BIOS boot detected, this install script only works with UEFI."
        exit 1
    fi

    timedatectl set-ntp true
    localectl set-keymap --no-convert fr-latin1 # Load french azerty keymap

    lsblk

    read -r -p "Which disk do you want to install to ? (usually /dev/sda) " disk_to_use
    read -r -p "You're about to erase ALL $disk_to_use are you sure ? [y/N] " yn

    if ! ask_yes_no "$yn"
    then
        exit 1
    fi

    read -r -p "What username do you want to use ? " USERNAME
    read -r -p "What hostname do you want to use ? " HOSTNAME

    grub_password="$(ask_password GRUB)"
    luks_password="$(ask_password LUKS)"
    user_password="$(ask_password "$USERNAME")"
    root_password="$(tr -dc '[:alnum:]' < /dev/urandom | fold -w "${1:-40}" | head -n 1)" # random root password, use sudo instead
    echo

    echo "Writing random bytes to $disk_to_use, go grab coffee this might take a while"
    dd if=/dev/random of="$disk_to_use" status=progress

    # Creating partitions and filesystems...
    parted "$disk_to_use" mklabel gpt --script
    parted "$disk_to_use" mkpart efi fat32 1MiB 65MiB --script
    parted "$disk_to_use" set 1 esp on --script
    parted "$disk_to_use" mkpart primary btrfs 65MiB 100% --script
    mkfs.fat -F 32 "${disk_to_use}1"

    echo -n "$luks_password" | cryptsetup luksFormat --batch-mode --type luks1 --use-random --key-slot 1 --key-size 512 --hash sha512 --pbkdf-force-iterations 200000 "${disk_to_use}2" -
    echo -n "$luks_password" | cryptsetup open "${disk_to_use}2" archlinux -
    mkfs.btrfs --force --label archlinux /dev/mapper/archlinux

    mount -t btrfs /dev/mapper/archlinux /mnt

    # Create btrfs subvolumes
    btrfs subvolume create /mnt/@
    btrfs subvolume create /mnt/@home
    btrfs subvolume create /mnt/@swap
    btrfs subvolume create /mnt/@snapshots

    # unmount root to remount using the btrfs subvolume
    umount /mnt
    mount_opt="defaults,ssd,noatime,nodiratime,space_cache=v2"
    mount -o subvol=@,$mount_opt /dev/mapper/archlinux /mnt
    mount --mkdir -o subvol=@home,$mount_opt /dev/mapper/archlinux /mnt/home
    mount --mkdir -o subvol=@swap,$mount_opt /dev/mapper/archlinux /mnt/.swap
    mount --mkdir -o subvol=@snapshots,$mount_opt /dev/mapper/archlinux /mnt/.snapshots

    # Create swapfile
    btrfs filesystem mkswapfile /mnt/.swap/swapfile
    mkswap /mnt/.swap/swapfile # according to btrfs doc it shouldn't be needed, but I don't only half of the swapfile is used
    swapon /mnt/.swap/swapfile

    # Mount UEFI partition
    mount --mkdir "${disk_to_use}1" /mnt/efi

    # keyring from ISO might be outdated, upgrading it just in case
    pacman -Sy --noconfirm archlinux-keyring

    pacstrap -K /mnt base \
                     base-devel \
                     linux-hardened \
                     linux-firmware \
                     intel-ucode \
                     mkinitcpio \
                     btrfs-progs \
                     efibootmgr \
                     efitools \
                     sbsigntools \
                     grub \
                     dhcpcd \
                     iwd

    # Set low swappiness so that Linux doesn't abuse it
    echo "vm.swappiness=10" > /mnt/etc/sysctl.d/99-swappiness.conf

    echo -n "Generating /etc/fstab... "
    genfstab -U /mnt >> /mnt/etc/fstab
    echo "Done !"

    # Basic configuration
    arch-chroot /mnt /bin/bash -c 'ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime && \
                                   hwclock --systohc && \
                                   sed -i "s/^#en_US.UTF-8/en_US.UTF-8/g" /etc/locale.gen && \
                                   sed -i "s/^#fr_FR.UTF-8/fr_FR.UTF-8/g" /etc/locale.gen && \
                                   locale-gen'

    # TODO : set /etc/hosts ?
    echo "$HOSTNAME" > /mnt/etc/hostname
    cp archlinux/etc/locale.conf /mnt/etc/locale.conf
    cp archlinux/etc/vconsole.conf /mnt/etc/vconsole.conf

    # Add crypto keyfile so that passphrase is asked only once (by grub and not by initramfs)
    mkdir /mnt/root/secrets
    chmod 700 /mnt/root/secrets
    head -c 64 /dev/urandom > /mnt/root/secrets/crypto_keyfile.bin
    chmod 600 /mnt/root/secrets/crypto_keyfile.bin
    echo -n "$luks_password" | cryptsetup -v luksAddKey --pbkdf-force-iterations 1000 "${disk_to_use}2" /mnt/root/secrets/crypto_keyfile.bin -

    # shellcheck disable=SC2016
    # Create secure boot keys
    arch-chroot /mnt /bin/bash -c 'cd /root/secrets && \
                                   uuidgen --random > GUID.txt && \
                                   openssl req -newkey rsa:4096 -nodes -keyout PK.key -new -x509 -sha256 -days 3650 -subj "/CN=EFI Platform Key/" -out PK.crt && \
                                   openssl x509 -outform DER -in PK.crt -out PK.cer && \
                                   cert-to-efi-sig-list -g "$(< GUID.txt)" PK.crt PK.esl && \
                                   sign-efi-sig-list -g "$(< GUID.txt)" -k PK.key -c PK.crt PK PK.esl PK.auth && \
                                   sign-efi-sig-list -g "$(< GUID.txt)" -c PK.crt -k PK.key PK /dev/null rm_PK.auth && \
                                   openssl req -newkey rsa:4096 -nodes -keyout KEK.key -new -x509 -sha256 -days 3650 -subj "/CN=EFI Key Exchange Key/" -out KEK.crt && \
                                   openssl x509 -outform DER -in KEK.crt -out KEK.cer && \
                                   cert-to-efi-sig-list -g "$(< GUID.txt)" KEK.crt KEK.esl && \
                                   sign-efi-sig-list -g "$(< GUID.txt)" -k PK.key -c PK.crt KEK KEK.esl KEK.auth && \
                                   openssl req -newkey rsa:4096 -nodes -keyout db.key -new -x509 -sha256 -days 3650 -subj "/CN=EFI Signature Database key/" -out db.crt && \
                                   openssl x509 -outform DER -in db.crt -out db.cer && \
                                   cert-to-efi-sig-list -g "$(< GUID.txt)" db.crt db.esl && \
                                   sign-efi-sig-list -g "$(< GUID.txt)" -k KEK.key -c KEK.crt db db.esl db.auth'

    # Remove fallback initramfs images (I think it's generated during mkinitcpio installation)
    rm /mnt/boot/*fallback*

    # Remove initramfs fallback image generation from initcpio
    arch-chroot /mnt /bin/bash -c "sed -i \$'s/^PRESETS=.*/PRESETS=(\'default\')/g' /etc/mkinitcpio.d/linux-hardened.preset && \
                                   sed -i 's/^fallback_image/#fallback_image/g' /etc/mkinitcpio.d/linux-hardened.preset && \
                                   sed -i 's/^fallback_options/#fallback_options/g' /etc/mkinitcpio.d/linux-hardened.preset"

    # Add encryption hooks to initcpio
    arch-chroot /mnt /bin/bash -c "sed -i 's/^HOOKS.*block/\0 encrypt btrfs/g' /etc/mkinitcpio.conf && \
                                   sed -i 's+^FILES=()+FILES=(/root/secrets/crypto_keyfile.bin)+g' /etc/mkinitcpio.conf"

    # Generate the initramfs
    arch-chroot /mnt /bin/bash -c "mkinitcpio -p linux-hardened"

    # Configure and install grub
    arch-chroot /mnt /bin/bash -c "sed -i 's/^#GRUB_ENABLE_CRYPTODISK/GRUB_ENABLE_CRYPTODISK/g' /etc/default/grub && \
                                   sed -i 's/GRUB_TERMINAL_INPUT=.*/GRUB_TERMINAL_INPUT=at_keyboard/g' /etc/default/grub && \
                                   sed -i 's/^#GRUB_DISABLE_SUBMENU=.*/GRUB_DISABLE_SUBMENU=true/g' /etc/default/grub && \
                                   sed -i 's+^GRUB_CMDLINE_LINUX=.*+GRUB_CMDLINE_LINUX=\"lsm=landlock,lockdown,yama,integrity,apparmor,bpf cryptdevice=${disk_to_use}2:archlinux root=/dev/mapper/archlinux cryptkey=rootfs:/root/secrets/crypto_keyfile.bin\"+g' /etc/default/grub && \
                                   grub-install --target=x86_64-efi --efi-directory=/efi"

    # Setup passwords
    grub_password_hash="$(echo -e "$grub_password\n$grub_password" | grub-mkpasswd-pbkdf2 | grep PBKDF2 | awk '{ print $7 }')"
    arch-chroot /mnt /bin/bash -c "echo 'root:${root_password}' | chpasswd"
    arch-chroot /mnt /bin/bash -c "useradd --create-home --groups wheel $USERNAME && \
                                   echo '${USERNAME}:${user_password}' | chpasswd"

    # Temporarly give sudo NOPASSWD rights to user
    echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/mnt/etc/sudoers.d/$USERNAME"

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
    # Make booting unrestricted (grub password not required)
    sed -i 's/menuentry.*${CLASS}/\0 --unrestricted/g' /mnt/etc/grub.d/10_linux

    # Add --class efi to the corresponding grub entry to display the proper icon
    sed -i $'s/$LABEL\'/$LABEL\' --class efi/g' /mnt/etc/grub.d/30_uefi-firmware

    # Add custom grub settings
    cp archlinux/etc/grub.d/40_custom /mnt/etc/grub.d/40_custom
    sed -i "s/{{grub_password_hash}}/$grub_password_hash/g" /mnt/etc/grub.d/40_custom

    # Generate grub configuration
    arch-chroot /mnt /bin/bash -c "grub-mkconfig -o /boot/grub/grub.cfg"

    # Apply grub theme
    arch-chroot /mnt /bin/bash -c "cd /tmp && \
                                   curl -O https://gitlab.com/VandalByte/darkmatter-grub-theme/-/archive/$GRUB_THEME_COMMIT/darkmatter-grub-theme-$GRUB_THEME_COMMIT.tar.gz && \
                                   tar xf darkmatter-grub-theme-$GRUB_THEME_COMMIT.tar.gz && \
                                   mkdir -p /boot/grub/themes/darkmatter && \
                                   cd darkmatter-grub-theme-$GRUB_THEME_COMMIT/ && \
                                   cp base/$GRUB_RESOLUTION/* /boot/grub/themes/darkmatter/ && \
                                   cp assets/backgrounds/arch-$GRUB_RESOLUTION.png /boot/grub/themes/darkmatter/background.png && \
                                   cp assets/fonts/$GRUB_RESOLUTION/* /boot/grub/themes/darkmatter/ && \
                                   cp -r assets/icons-$GRUB_RESOLUTION/color/ /boot/grub/themes/darkmatter/icons/"

    # shellcheck disable=SC2016
    arch-chroot /mnt /bin/bash -c 'cd / && \
                                   grub-mkstandalone --directory /usr/lib/grub/x86_64-efi/ \
                                                     --format=x86_64-efi \
                                                     --compress="xz" \
                                                     --modules="part_gpt crypto cryptodisk luks disk diskfilter btrfs" \
                                                     --fonts="unicode" \
                                                     --output="/efi/EFI/arch/grubx64.efi" \
                                                     "boot/grub/grub.cfg=/boot/grub/grub.cfg" \
                                                     "boot/grub/layouts/fr.gkb=/boot/grub/layouts/fr.gkb" \
                                                     $(find boot/grub/themes/darkmatter -type f -exec echo {}=/{} \;) && \
                                   sbsign --key /root/secrets/db.key --cert /root/secrets/db.crt --output /efi/EFI/arch/grubx64.efi /efi/EFI/arch/grubx64.efi'

    mkdir -p /mnt/etc/pacman.d/hooks

    # Copy pacman hooks over
    cp archlinux/etc/pacman.d/hooks/97-btrfs-snapshot.hook /mnt/etc/pacman.d/hooks/97-btrfs-snapshot.hook
    cp archlinux/etc/pacman.d/hooks/98-secureboot-grub.hook /mnt/etc/pacman.d/hooks/98-secureboot-grub.hook

    # Configure systemd services
    arch-chroot /mnt /bin/bash -c "systemctl enable btrfs-scrub@-.timer"
    arch-chroot /mnt /bin/bash -c "systemctl enable dhcpcd"
    arch-chroot /mnt /bin/bash -c "systemctl enable iwd"

    # Remove sudo NOPASSWD rights to user
    rm "/mnt/etc/sudoers.d/$USERNAME"

    # Hardenning
    arch-chroot /mnt /bin/bash -c "chmod 700 /boot"
    sed -i 's/0022/0077/g' /mnt/etc/fstab # efi partition will be mounted with 700 permissions

    # Copy UEFI keys to /efi partition so that the UEFI firmware can load them
    arch-chroot /mnt /bin/bash -c 'cp /root/secrets/*.cer /root/secrets/*.esl /root/secrets/*.auth /efi/ && \
                                   shred -u /efi/rm_PK.auth' # rm_PK.auth can be used to remove enrolled UEFI keys

    # TODO : use btrfs snapshots to rollback broken update
    # TODO : use proper backup that does not rely on filesystem features !!
    # NOTES : btrfs snapshots are not proper backups.

    echo ""
    echo "Now is time to enroll your secure boot keys into your UEFI firmware !"
    echo ""
    echo "But first make sure you securely backup:"
    echo "  - Your previous UEFI keys (probably OEM ones)"
    echo "  - Your /root/secrets folder (encrypted to an external drive)"
    echo ""
    echo "You can then reboot into the UEFI firmware settings by running the following settings :"
    echo "  systemctl reboot --firmware"
    echo ""
    echo "You will find your UEFI keys on the EFI partition (${disk_to_use}1)"
}

install_archlinux "$@"
