# ArchLinux Hardened

⚠ WORK IN PROGRESS ⚠

This repository contains my ArchLinux setup which focuses on Desktop security. See the Features section for an overview of what this does.

Beside security, my setup also aims to use all the bleeding edge most advanced technologies. Most notably:

- Btrfs : [copy-on-write](https://en.wikipedia.org/wiki/Copy-on-write) filesystem with snapshot support
- LUKS2 : for its state of the art cryptography
- Wayland : because X11 is old, slow, and insecure
- NFTables : because firewalling with iptables syntax sucks

Because of its hardened nature, you might have to get your hands dirty to get things to work.
Therefore this setup is not recommended if you don't have good GNU/Linux knowledge already.

## FAQ

- I tested it in a VM, it doesn't work, why ?
- Pacman/Yay doesn't want me to install packages, wtf ?
- Help! My PC won't boot anymore!
- How can I SSH into my PC ?

## Installation

In order to have a proper secure boot, we will have to install our own keys in the BIOS firmware.
By default, almost all computers are shipped with Microsoft's keys. This is to ensure secure boot
on Windows by default. Note that [Microsoft offers a service](https://learn.microsoft.com/en-us/windows-hardware/drivers/dashboard/file-signing-manage)
that allows anyone to sign a UEFI firmware. So basically if you decide to use Microsoft's keys,
anyone who manages to get its UEFI firmware signed will be able to bypass your secure boot.
I don't want that. And I don't trust Microsoft. So I decided so enroll my own keys instead.

⚠  Replacing Microsoft's keys will probably break your Windows boot if you have one, in any case, [backing up those keys](https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot#Backing_up_current_variables) won't hurt.

- Disable the secure boot in your BIOS settings.
- Remove all the cryptographic keys from it
- Download and boot into the [ArchLinux ISO](https://archlinux.org/download/).

Let's go!

```sh
$ loadkeys fr-latin1 # cause I'm french :)
$ pacman -S git
$ git clone https://github.com/ShellCode33/ArchLinuxHardened
$ cd ArchLinuxHardened
$ ./install.sh
```

If you got gpg/keyring related errors, try the following :

```sh
$ killall gpg-agent
$ rm -rf /etc/pacman.d/gnupg # might say resource is busy, it's ok
$ pacman-key --init
$ pacman-key --populate
$ pacman -Sy archlinux-keyring
```

## Features

- Secure boot
- Linux hardened and Linux LTS fallback
- Full disk encryption
- AppArmor
- Auditd notifications
