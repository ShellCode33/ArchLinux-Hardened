# ArchLinux Hardened

This repository contains my ArchLinux setup which focuses on desktop security.

Beside security, my setup also aims to use all the bleeding edge and state of the art software we currently have available, most notably:

- Btrfs : [copy-on-write](https://en.wikipedia.org/wiki/Copy-on-write) filesystem with snapshot support
- Wayland : because X11 is old, slow, and insecure
- NFTables : because firewalling with iptables syntax sucks

Because of its hardened nature, you might have to get your hands dirty to get things to work.
Therefore this setup is not recommended if you don't have good GNU/Linux knowledge already.

## Status

Even though I use it as my daily driver, this is still work in progress.

Some work is yet to be done regarding btrfs snapshots.

## Highlights

Physical tampering hardening:

- Secure boot without Microsoft's keys
- No GRUB-like bootloader, the kernel is booted into directly thanks to [unified kernel images](https://wiki.archlinux.org/title/Unified_kernel_image)
- Full disk encryption using LUKS 2

Exploit mitigation:

- GraphenOS' hardened kernel
- Kernel's lockdown mode set to "integrity"
- Firejail + AppArmor (see [FIREJAIL.md](docs/FIREJAIL.md) for the why)

Network hardening:

- Reverse Path Filtering set to strict
- ICMP redirects disabled
- The hardened kernel has very strong defaults regarding network security
- Strict firewalling rules (drop everything by default, see [NETWORKING.md](https://github.com/ShellCode33/ArchLinux-Hardened/blob/master/docs/NETWORKING.md))

System monitoring:

- Auditd reporting through desktop notifications
- Many systemd services helping you to manage your system to keep it secure

System resilience:

- LTS kernel fallback from the BIOS to fix a broken system
- Automated encrypted backups uploaded to a remote server (manual configuration required)
- Automated encrypted incremental backups to an external USB drive (manual configuration required)

This setup uses desktop notifications extensively, I think this is a good way of monitoring your PC.

I want to know what's going on at all times, if something fails I want to be aware of it as soon as possible in order to fix it.

Here's a sample of notifications you might get:

![alt notification](images/notifications.png)

## Additional documentation

- [Manage SSH and GPG secrets securely without a password thanks to KeePassXC](docs/HOW_TO_MANAGE_SECRETS.md)
- [Setup an auto-mounted encrypted standalone USB device](docs/HOW_TO_SECURE_USB_DEVICE.md)
- [Firefox hardening tips](docs/HOW_TO_FIREFOX.md)
- [FAQ and troubleshooting](docs/FAQ_AND_TROUBLESHOOTING.md)

## Installation

In order to have a proper secure boot, you will have to install your own keys in the BIOS firmware.
By default, almost all computers are shipped with Microsoft's keys. This is to ensure out of the box
secure boot on Windows. Note that [Microsoft offers a service](https://learn.microsoft.com/en-us/windows-hardware/drivers/dashboard/file-signing-manage)
that allows anyone to sign a UEFI firmware. So basically if you decide to use Microsoft's keys,
anyone who manages to get its UEFI firmware signed will be able to bypass your secure boot.
I don't want that. And I don't trust Microsoft. So I decided to enroll my own keys instead.

⚠ Replacing Microsoft's keys will probably break your Windows boot if you have one, this ArchLinux setup has not been tested with a Windows dual boot, use at your own risk. In any case, [backing up those keys](https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot#Backing_up_current_variables) won't hurt (note that some BIOS allow you to reset keys to their factory default, meaning Microsoft's keys).

- Set an admin password to restrict the access to your BIOS settings (add it to your password manager)
- Remove all the cryptographic keys from your BIOS and enter the "setup mode" (some BIOS won't let you enter the setup mode if the SB is enabled)
- Download and boot into the [ArchLinux ISO](https://archlinux.org/download/).

Let's go!

```sh
$ pacman -Sy git
$ git clone https://github.com/ShellCode33/ArchLinux-Hardened
$ cd ArchLinux-Hardened
$ ./install.sh
```

If you get gpg/keyring related errors, do the following :

```sh
$ killall gpg-agent
$ rm -rf /etc/pacman.d/gnupg # might say resource is busy, it's ok
$ pacman-key --init
$ pacman-key --populate
$ pacman -Sy archlinux-keyring
```

Once the installation is finished, reboot your computer and log into your freshly installed OS.

You must now make sure the secure boot is setup properly. Many things could go wrong with it.

The install script automatically tries to insert secure boot keys into your BIOS.

To make sure they are there, run:

```
$ sudo sbkeysync --verbose
```

You should see something like this:

```
Filesystem keystore:
  /etc/secureboot/keys/db/db.auth [3337 bytes]
  /etc/secureboot/keys/KEK/KEK.auth [3336 bytes]
  /etc/secureboot/keys/PK/PK.auth [3334 bytes]
firmware keys:
  PK:
    /CN=SecureBoot PK
  KEK:
    /CN=SecureBoot KEK
  db:
    /CN=SecureBoot db

[...]
```

If it works, great ! You can now go back to your BIOS and enable the secure boot again.

But if like me your BIOS sucks (ASUS 👀), it might not have worked and the keys are not there.

Before you try the following, put your BIOS into "setup mode" again.

You can try to run the following command:

```
sudo chattr -i /sys/firmware/efi/efivars/{PK,KEK,db}*
```

And then:

```
sudo sbkeysync --verbose --pk
```

To see if it helps. According to some issues on GitHub it worked for some, but not for me unfortunately.

The error I have and that you might have as well is the following:

```
Inserting key update /etc/secureboot/keys/KEK/KEK.auth into KEK
Error writing key update: Invalid argument
Error syncing keystore file /etc/secureboot/keys/KEK/KEK.auth
```

The `Invalid argument` part seems to indicate a firmware bug, but it's hard to know for sure.

In such cases, your last chance is to enroll keys manually into the BIOS.

Put the secure boot keys on your EFI partition like so:

```
sudo find /etc/secureboot -name '*.auth' -exec cp {} /efi \;
```

Go back to your BIOS and in the secure boot menu, enroll them and enable the secure boot.
Chances are, it should work now. You can confirm with `sudo sbkeysync --verbose`.

Don't forget to remove the keys from the EFI partition:

```
sudo shred -u /efi/db.auth /efi/KEK.auth /efi/PK.auth
```
