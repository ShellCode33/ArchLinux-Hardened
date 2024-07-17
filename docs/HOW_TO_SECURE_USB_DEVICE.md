# Create a secure USB device

Goals:

- Be able to store data on the device (obviously...)
- Data must be encrypted so that only you can read it
- The USB device must be bootable to access encrypted data on any physical computer you have access to
- If the USB device is lost and someone plugs it in its own computer, contact details must be readable
- Using the device must be seamless, we already have a hardened setup, we don't want to bother having to type one more password

First, identify the USB device using lsblk, example:

```
$ lsblk
NAME          MAJ:MIN RM   SIZE RO TYPE  MOUNTPOINTS
sda             8:0    0 931.5G  0 disk
├─sda1          8:1    0   300M  0 part  /efi
└─sda2          8:2    0 931.2G  0 part
  └─cryptroot 254:0    0 931.2G  0 crypt /
sdb             8:16   1 115.7G  0 disk
└─sdb1          8:17   1 115.7G  0 part
```

Here we will use the device `/dev/sdb`.

WARNING: think twice before running any command or you might lose data !

## Prepare the device

Write random data to the whole device (this will take some time, plug the device to a USB 3 port if you have one):

```
sudo dd bs=1M if=/dev/urandom of=/dev/sdb status=progress
```

Remove any FS magic bytes (in case dd randomly created valid ones) otherwise some tools will complain:

```
lsblk -plnx size -o name /dev/sdb | sudo xargs -n1 wipefs --all
```

## Create partitions

- Partition 1: FAT32 partition which contains a README.txt with contact details in case the USB key is lost
- Partition 2: EFI partition with Microsoft signed bootloader (to access your data from any physical computer you have access to)
- Partition 3: LUKS encrypted partition which contains a minimal Linux install to access your data from any computer
- Partition 4: LUKS encrypted partition which will contain all your data

Create the partition table:

```
sudo sgdisk --clear /dev/sdb --new 1::+64MiB --new 2::+128MiB --typecode 2:ef00 /dev/sdb --new 3::+10GiB --new 4::0
```

(You could allocate only 5GiB to the Linux partition, but I'd rather be safe than sorry)

Name the partitions:

```
sudo sgdisk /dev/sdb --change-name=1:README --change-name=2:EFI --change-name=3:LINUX_ENCRYPTED --change-name=4:STORAGE_ENCRYPTED
```

Create the FAT32 partitions:

```
sudo mkfs.vfat -n "README" -F 32 /dev/sdb1
sudo mkfs.vfat -n "EFI" -F 32 /dev/sdb2
```

Create the LUKS layouts (LUKS 2 is not properly supported by GRUB yet):

```
sudo cryptsetup luksFormat --type luks1 --label LINUX /dev/sdb3
sudo cryptsetup luksFormat --type luks1 --label STORAGE /dev/sdb4
```

(Choose strong passphrases and add them to your password manager)

Define some variables we will need along the way:

```
boot_uuid="$(lsblk -o uuid /dev/sdb2 | tail -1)"
luks_root_uuid="$(sudo cryptsetup luksUUID /dev/sdb3)"
luks_storage_uuid="$(sudo cryptsetup luksUUID /dev/sdb4)"
```

Open the newly created LUKS containers:

```
sudo cryptsetup luksOpen /dev/sdb3 "$luks_root_uuid"
sudo cryptsetup luksOpen /dev/sdb4 "$luks_storage_uuid"
```

Use ext4 for the Linux partition:

```
sudo mkfs.ext4 -L LINUX "/dev/mapper/$luks_root_uuid"
```

If you plan to store incremental system backups of your main drive, you might want to format the storage partition using btrfs:

```
sudo mkfs.btrfs --label STORAGE "/dev/mapper/$luks_storage_uuid"
sudo mount "/dev/mapper/$luks_storage_uuid" /mnt
sudo btrfs subvolume create /mnt/@snapshots
sudo umount /mnt
```

Otherwise use the good old ext4 filesystem:

```
sudo mkfs.ext4 -L STORAGE "/dev/mapper/$luks_storage_uuid"
```

## Create the README.txt

Mount the README partition:

```
sudo mount /dev/sdb1 /mnt
```

Write contact details to a `.txt` file so that Windows users can read it easily :

```
sudo nvim /mnt/README.txt
```

Then umount:

```
sudo umount /mnt
```

## Configure Linux on the embedded USB device

We want it to :

- Be bootable on any secure boot enabled computer
- Auto-mount the storage partition

Debian has been chosen for two reasons:

- Because it's very stable, if we have to boot into this USB device it probably means something went wrong at some point and we don't want to deal with a broken install
- Because it supports secure boot out of the box, meaning we will be able to boot into it on any computer (as long as it allows us to boot into external USB)

You might want to read [Installing Debian GNU/Linux from a Unix/Linux System](https://www.debian.org/releases/stable/amd64/apds03.en.html). Otherwise, just follow along.

In order to install Debian on the USB device while using Arch, you must install the following package:

```
sudo pacman -S debootstrap
```

Mount the Linux partition previously created on the USB device:

```
sudo mount "/dev/mapper/$luks_root_uuid" /mnt
```

DANGER: be careful, your main drive is accessible from within the chroot as well !!

Then run debootstrap to install debian:

```
sudo debootstrap --arch amd64 --components main,contrib,non-free-firmware stable /mnt http://ftp.us.debian.org/debian
```

(Don't forget to use the `proxify` script if you use my setup)

When it's done, mount additional resources:

```
sudo mount --mkdir /dev/sdb2 /mnt/boot/efi
sudo mount -t proc proc /mnt/proc
sudo mount -t sysfs sys /mnt/sys
sudo mount -o bind /dev /mnt/dev
sudo mount --rbind /sys/firmware/efi/efivars /mnt/sys/firmware/efi/efivars/
```

Now is time to setup a few things:

```
echo backup-drive | sudo tee /mnt/etc/hostname
echo '127.0.0.1 backup-drive' | sudo tee -a /mnt/etc/hosts
echo | sudo tee /mnt/etc/motd
```

Add the security repos:

```
echo 'deb http://security.debian.org/ stable-security main contrib non-free-firmware' | sudo tee -a /mnt/etc/apt/sources.list
sudo LANG=C.UTF-8 TERM=xterm-color chroot /mnt bash --login -c 'apt-get update && apt-get upgrade -y'
```

Install additional packages:

```
sudo LANG=C.UTF-8 TERM=xterm-color chroot /mnt bash --login -c 'apt-get install -y linux-image-amd64 firmware-linux firmware-iwlwifi zstd grub-efi cryptsetup cryptsetup-initramfs btrfs-progs fdisk gdisk sudo neovim network-manager xserver-xorg xinit lightdm xfce4 dbus-x11 thunar xfce4-terminal firefox-esr keepassxc network-manager-gnome'
```

Create a swapfile:

```
sudo fallocate -l 1G /mnt/swapfile
sudo chmod 600 /mnt/swapfile
sudo mkswap /mnt/swapfile
```

Create a first keyfile which will allow the booted OS to auto-mount the storage partition:

```
sudo dd bs=512 count=4 if=/dev/random of="/mnt/root/luks_${luks_storage_uuid}.keyfile" iflag=fullblock
sudo chmod 400 "/mnt/root/luks_${luks_storage_uuid}.keyfile"
```

Create a second keyfile which will allow the initramfs to decrypt the root partition:

```
sudo dd bs=512 count=4 if=/dev/random of="/mnt/root/luks_${luks_root_uuid}.keyfile" iflag=fullblock
sudo chmod 400 "/mnt/root/luks_${luks_root_uuid}.keyfile"
```

Now we must enroll the newly created keyfiles so that we can open the USB device with it:

```
sudo cryptsetup luksAddKey /dev/sdb3 "/mnt/root/luks_${luks_root_uuid}.keyfile"
sudo cryptsetup luksAddKey /dev/sdb4 "/mnt/root/luks_${luks_storage_uuid}.keyfile"
```

And add the following to crypttab so that `cryptsetup-initramfs` knows which key to use to allow the initramfs to decrypt the root partition:

```
echo "$luks_root_uuid UUID=$luks_root_uuid /root/luks_${luks_root_uuid}.keyfile luks,discard" | sudo tee -a /mnt/etc/crypttab
```

Add the following to the cryptsetup-initramfs hook:

```
echo 'KEYFILE_PATTERN="/root/luks_*.keyfile"' | sudo tee -a /mnt/etc/cryptsetup-initramfs/conf-hook
```

Run the following command to open the LUKS storage partition automatically at boot:

```
echo "$luks_storage_uuid UUID=$luks_storage_uuid /root/luks_${luks_storage_uuid}.keyfile luks,discard" | sudo tee -a /mnt/etc/crypttab
```

Let's setup the fstab:

```
echo "/dev/mapper/$luks_root_uuid / ext4 defaults 0 1" | sudo tee /mnt/etc/fstab
echo '/swapfile none swap sw 0 0' | sudo tee -a /mnt/etc/fstab
echo "UUID=$boot_uuid /boot/efi vfat rw,relatime,fmask=0077,dmask=0077,codepage=437,iocharset=ascii,shortname=mixed,utf8,errors=remount-ro 0 0" | sudo tee -a /mnt/etc/fstab
```

If your external USB device **filesystem is btrfs**, run the following command:

```
echo "/dev/mapper/$luks_storage_uuid /storage btrfs defaults,noatime,nodiratime,subvol=@snapshots,compress=zstd,space_cache=v2    0  2" | sudo tee -a /mnt/etc/fstab
```

If your external USB device **filesystem is ext4**, run the following command:

```
echo "/dev/mapper/$luks_storage_uuid /storage ext4 defaults,noatime,nodiratime    0  2" | sudo tee -a /mnt/etc/fstab
```

Now let's setup the bootloader and the initramfs:

```
echo 'GRUB_ENABLE_CRYPTODISK=y' | sudo tee -a /mnt/etc/default/grub
echo "GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=${luks_root_uuid}:${luks_root_uuid}\"" | sudo tee -a /mnt/etc/default/grub
echo 'GRUB_DISTRIBUTOR="Backup-Drive"' | sudo tee -a /mnt/etc/default/grub
echo 'UMASK=0077' | sudo tee -a /mnt/etc/initramfs-tools/initramfs.conf

sudo chroot /mnt bash --login -c "update-initramfs -u -k all"
sudo chroot /mnt bash --login -c "update-grub"
sudo chroot /mnt bash --login -c "grub-install /dev/sdb"
```

Now is time to create a user:

```
username=YOUR_NAME
sudo chroot /mnt bash --login -c "useradd -m $username -s /bin/bash"
sudo chroot /mnt bash --login -c "passwd $username"
sudo chroot /mnt bash --login -c "usermod -aG sudo $username"
```

Make sure the user will be able to use /storage:

```
sudo mkdir /mnt/storage
sudo mount "/dev/mapper/$luks_storage_uuid" /mnt/storage
sudo chown -R 1000:1000 /mnt/storage
```

Autologin your user into the graphical session:

```
sudo sed -i "s/#autologin-user=/autologin-user=$username/g" /mnt/etc/lightdm/lightdm.conf
```

Modify your bashrc in case you forget later where is the mount point:

```
echo 'echo "Storage partition is mounted at /storage ;)"' | sudo tee -a "/mnt/home/$username/.bashrc"
```

Enable some useful systemd services:

```
sudo chroot /mnt bash --login -c 'systemctl enable NetworkManager'
```

Congratz your USB device is now ready !

You can unmount everything like so:

```
sudo umount --recursive /mnt
```

And close LUKS containers:

```
sudo cryptsetup luksClose "/dev/mapper/$luks_root_uuid"
sudo cryptsetup luksClose "/dev/mapper/$luks_storage_uuid"
```

And make sure everything is working properly ;)

## Auto-mount the external USB device on your PC

In this chapter we are only interested in the storage area of the USB device.

Make sure the **Linux partition** (not the storage one) of the USB drive is mounted:

```
sudo cryptsetup luksOpen /dev/sdb3 "$luks_root_uuid"
sudo mount "/dev/mapper/$luks_root_uuid" /mnt
```

And copy the previously created keyfile to the root of your main computer:

```
sudo cp "/mnt/root/luks_${luks_storage_uuid}.keyfile" "/root/luks_${luks_storage_uuid}.keyfile"
```

Warning: the keyfile should be readable only by root !!

Create a folder where the USB drive will be mounted:

```
sudo mkdir -m 700 -p "/media/usb/my_device"
```

Run the following command to open the LUKS container automatically using the keyfile:

```
echo "$luks_storage_uuid UUID=$luks_storage_uuid /root/luks_${luks_storage_uuid}.keyfile luks,discard,nofail" | sudo tee -a /etc/crypttab
```

If your external USB device **filesystem is btrfs**, run the following command:

```
echo "/dev/mapper/$luks_storage_uuid /media/usb/my_device btrfs defaults,noatime,nodiratime,subvol=@snapshots,compress=zstd,space_cache=v2,nofail    0  2" | sudo tee -a /etc/fstab
```

If your external USB device **filesystem is ext4**, run the following command:

```
echo "/dev/mapper/$luks_storage_uuid /media/usb/my_device ext4 defaults,noatime,nodiratime,nofail    0  2" | sudo tee -a /etc/fstab
```

And boom, you're done, you can now unmount the Linux partition:

```
sudo umount /mnt
```

You can also try to reboot your computer to make sure the USB device is properly mounted at boot.
