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
- Download the custom ISO and its `.sha256` file from the [releases](https://github.com/ShellCode33/ArchLinux-Hardened/releases).
- Check the download with `sha256sum -c archlinux-hardened-YYYY.MM.DD-x86_64.iso.sha256` (replace the date with the one you downloaded).
- Write the ISO to a USB drive and boot it in UEFI mode. The installer does not support legacy BIOS installations.

⚠ The install script will erase the entire disk you select, including all its partitions. Make sure you have backed up anything you want to keep before you start.

The custom ISO is the official ArchLinux ISO with a small launcher added to it.
It clones the latest version of this repository and starts `./install` automatically.
Both the launcher and the installer allow up to 10 seconds for clock synchronization before
installing packages. If that fails, they show the current time and continue. The hardware clock
is only updated after synchronization succeeds.

If installing Git or downloading the setup fails, the launcher opens a recovery shell with advice based on the error.
Network failures get connection instructions; package or library incompatibilities suggest trying
a newer ISO. Certificate and signature failures also suggest checking the clock first. Use `iwctl` to connect to Wi-Fi, exit `iwctl`, then type `exit` again
to leave the shell and retry automatically. No need to restart the launcher yourself !

If you stopped the launcher and want to start it again from the normal live shell:

```sh
/run/archiso/bootmnt/hardened/start-install
```

The script will ask you which disk to use, your hardware, hostname, username and passwords.
Read the disk confirmation carefully. Once it starts filling the disk with random data,
go grab some coffee, it might take a while.
The fill writes exactly the disk's size, so `No space left on device` is a real error
and the installer will stop before partitioning.

## Using the official ArchLinux ISO

If you prefer, you can also boot the [official ArchLinux ISO](https://archlinux.org/download/)
in UEFI mode, connect to the internet and start the installer yourself.
Run the following commands as root in the live environment. First, enable time synchronization
and check the clock so HTTPS and package signature checks don't fail because of a wrong date:

```sh
timedatectl set-ntp true
timedatectl status
```

Look for `System clock synchronized: yes` and make sure the date and time are correct.
If it says `no`, give it a few seconds and run `timedatectl status` again.
`NTP service: active` alone doesn't mean the clock has synchronized yet !

Once synchronization is confirmed, save the time to the hardware clock:

```sh
hwclock --systohc --utc
```

If synchronization never succeeds, check your connection. Some networks block NTP;
you can still continue if you have checked that the system date and time are correct,
but skip the hardware clock command until synchronization is confirmed.

Then update the keyring before installing Git, and download the setup:

```sh
pacman -Sy --needed archlinux-keyring
pacman -S --needed git
git clone https://github.com/ShellCode33/ArchLinux-Hardened
cd ArchLinux-Hardened
./install
```

Run these one at a time and make sure each command succeeds before moving on to the next.

This only installs the tools needed in the disposable live environment. A full upgrade can
fill its RAM-backed filesystem. Refreshing the databases without a full upgrade is a tradeoff
here: with an old ISO, newer packages might be incompatible with its libraries. If that happens,
boot a recent ISO. Don't use this approach to maintain your installed system.

If you get gpg/keyring related errors, make sure your clock is correct and try again
with a recent ISO before messing with the keyring.

## If installation fails

Check the error and the `stdout.log` and `stderr.log` files in the cloned repository before
rebooting. With the custom ISO, they are under `/root/hardened-install.*/repo/`.
Copy any logs you want to keep somewhere persistent, the live environment won't keep them after reboot.

Exiting the launcher's recovery shell retries preparing and downloading the installer.
But once `./install` has started, running it again starts the installation from the beginning,
including erasing the disk you select. It doesn't resume where it failed !
If the random fill already completed during this live session, the installer offers to skip
repeating that step. This completion record is lost on reboot; partitioning and formatting
still run even when you reuse it.

## After installation

Once the installation is finished, reboot your computer and log into your freshly installed OS.

You must now make sure the secure boot is setup properly. Many things could go wrong with it.

The install script automatically tries to insert secure boot keys into your BIOS.

To make sure they are there, run:

```
sudo sbkeysync --verbose
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
