# Administration tips for btrfs

Tips and tricks for managing your btrfs submodules.

## Create top-level subvolumes

Mount the top-level subvolume (which is of ID 5):
```
sudo mount /dev/mapper/archlinux -o subvolid=5 /mnt
```

Create the subvolume:

```
sudo btrfs subvolume create /mnt/@my-new-subvolume
```

Now that your subvolume has been created, get its ID:

```
sudo btrfs subvolume list / | grep my-new-subvolume
```

You can add it to `/etc/fstab` if need be.

## Balancing

This is done automatically already on a daily basis by [btrfs-balance.service](https://github.com/ShellCode33/ArchLinux-Hardened/blob/master/rootfs/etc/systemd/system/btrfs-balance.service).

But if you want to run it manually, you can use the following command:

```
sudo btrfs balance start -dusage=50 -dlimit=2 -musage=50 -mlimit=4 /
```

Where `/` is the path to the subvolume to balance.

Official documentation [there](https://btrfs.readthedocs.io/en/latest/btrfs-balance.html).

## Disable CoW on an existing folder

Do not use the `nodatacow` mount option, it wont work !! Use `chattr +C` instead.

From [btrfs(5)](https://man.archlinux.org/man/btrfs.5#MOUNT_OPTIONS):

    within a single file system, it is not possible to mount some subvolumes with nodatacow and others with datacow. The mount option of the first mounted subvolume applies to any other subvolumes.

Setting `chattr +C` on an existing folder is undefined behavior.
To workaround that, first make sure the folder is not in use (for system directories you will have to boot into a live CD).

Let's say we want to disable CoW on `/var` which is the mount point of the subvolume `@var`.

Mount the top-level volume from your LiveCD:

```
mount /dev/mapper/archlinux -o subvolid=5 /mnt
```

Rename the folder you want to disable CoW for:

```
mv /mnt/@var /mnt/@old_var
```

Create the new `@var` subvolume:

```
btrfs subvolume create /mnt/@var
```

Disable CoW:

```
chattr +C /mnt/@var
```

Copy the old content the new subvolume:

```
cp -a --reflink=never /mnt/@old_var/. /mnt/@var
```

Remove the old subvolume:

```
btrfs subvolume delete /mnt/@old_var
```

And wait for it to complete:

```
btrfs subvolume sync /mnt
```

You must now change `/etc/fstab` to match the new subvolid.

These instructions were given for subvolumes, but the same logic also applies to regular folders. Except no subvolume has to be created/deleted.
