# Installation

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
