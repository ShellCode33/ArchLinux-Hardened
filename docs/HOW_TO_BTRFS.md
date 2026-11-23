# Btrfs administration

The UUID, subvolume names, and data paths below are examples. Substitute the values for your filesystem. Run one command at a time and stop if a command fails.

## Create a top-level subvolume

These steps assume the Btrfs top level (subvolume ID 5) is mounted at `/mnt`. You can use that mount on a running system while its other subvolumes stay mounted. [Btrfs subvolume documentation](https://btrfs.readthedocs.io/en/latest/btrfs-subvolume.html)

Check that the mount shows `/` in the `FSROOT` column.

```sh
findmnt --mountpoint /mnt -o TARGET,SOURCE,FSROOT
```

Create the new subvolume after confirming the mount.

```sh
sudo btrfs subvolume create /mnt/@example-data
```

Display the subvolume's details, including its ID.

```sh
sudo btrfs subvolume show /mnt/@example-data
```

Unmount the Btrfs top level when you are finished with it.

```sh
sudo umount /mnt
```

To mount it at boot, add an entry like this to `/etc/fstab`. The UUID identifies the Btrfs filesystem, and `subvol=` selects a path relative to its top level. You can also select a subvolume by its numeric `subvolid=`. If both options are present, they must identify the same subvolume. A restored or recreated subvolume can have a different ID even when its path stays the same. [Btrfs mount options](https://btrfs.readthedocs.io/en/latest/ch-mount-options.html#subvol-path)

```fstab
UUID=11111111-2222-3333-4444-555555555555  /srv/example-data  btrfs  noatime,nodiratime,compress=zstd,space_cache=v2,subvol=/@example-data  0 0
```

Reload systemd after editing fstab.

```sh
sudo systemctl daemon-reload
```

Mount the new subvolume before rebooting.

```sh
sudo mount --mkdir /srv/example-data
```

Confirm that the mount shows `/@example-data` in the `FSROOT` column.

```sh
findmnt --mountpoint /srv/example-data -o TARGET,SOURCE,FSROOT
```

After mounting the subvolume, set the ownership and permissions on the newly mounted directory.

## Move an existing directory into a subvolume

Suppose `/srv/example-data` already contains application data. Create `@example-data` as above, then stop the application and any units that can restart it. Check for mounted filesystems at or below the directory before moving it.

Rename the existing directory to keep a copy for rollback.

```sh
sudo mv -T --no-copy --update=none-fail /srv/example-data /srv/example-data.before-btrfs
```

`--no-copy` makes the command fail if the rename cannot be done. [mv manual](https://man.archlinux.org/man/mv.1.en)

Add the fstab entry and follow the mount steps above. Confirm that `FSROOT` is `/@example-data` before copying any files.

Copy the old directory's contents into the mounted subvolume. Archive mode preserves file attributes and hard links, and `-x` keeps traversal on the source filesystem. [cp manual](https://man.archlinux.org/man/cp.1.en)

```sh
sudo cp -ax --reflink=never /srv/example-data.before-btrfs/. /srv/example-data/
```

Restart the application and verify that it can read and write its data. Keep the original directory until you have tested the replacement. To roll back, stop the application, unmount the new subvolume, remove its fstab entry, remove the empty mountpoint with `rmdir`, and rename the original directory back.

Btrfs snapshots stop at subvolume boundaries. Future snapshots of the parent will exclude the new subvolume. Older snapshots may still reference data from before the migration. [Btrfs snapshot boundaries](https://btrfs.readthedocs.io/en/latest/btrfs-subvolume.html#nested-subvolumes)

## Run a filtered balance

A balance operates on the whole Btrfs filesystem, including all its subvolumes. Running it on `/` selects the filesystem mounted there. Any mountpoint on that same filesystem selects it as well. This example balances up to two data block groups and four metadata block groups that match the 50% usage filter. A balance can free block groups for reuse. Data referenced by snapshots continues to occupy space. [Btrfs balance documentation](https://btrfs.readthedocs.io/en/latest/btrfs-balance.html)

```sh
sudo btrfs balance start -dusage=50 -dlimit=2 -musage=50 -mlimit=4 /
```

## Disable copy-on-write for a directory

Use `chattr +C` on an empty destination directory before copying files into it. Setting `+C` on a directory affects only newly created files. Existing files keep their attributes and must be rewritten to convert them to NoCoW. NoCoW files lose data checksums and compression, and the `nodatacow` mount option applies across the Btrfs filesystem. [Btrfs mount options](https://btrfs.readthedocs.io/en/latest/ch-mount-options.html#datacow-nodatacow)

> **Warning**
>
> Avoid applying `+C` to files that already contain data, including through `chattr -R +C`. Btrfs documents changing this flag only on empty files. The `chattr` manual says that if the flag is set on a file with existing data blocks, when those blocks become fully stable is undefined. [Btrfs file attributes](https://btrfs.readthedocs.io/en/latest/ch-file-attributes.html) · [chattr manual](https://man.archlinux.org/man/chattr.1.en#ATTRIBUTES)

For an ordinary directory, stop its writers and rename it aside, then make a new directory at the original path. Set `+C` on the new directory and copy the old contents into it with `cp -a --reflink=never`.

To replace an existing subvolume such as `@example-state`, stop its users and unmount it first. For a system subvolume that cannot be taken offline while running, boot a live USB. With the top level mounted at `/mnt`, verify that mount as shown above before continuing.

Rename the existing subvolume to keep a copy for rollback.

```sh
sudo mv -T --no-copy --update=none-fail /mnt/@example-state /mnt/@example-state.before-nocow
```

Create an empty subvolume under the original name.

```sh
sudo btrfs subvolume create /mnt/@example-state
```

Set `+C` on the empty subvolume.

```sh
sudo chattr +C /mnt/@example-state
```

Copy the original files without reflinks so the new copies inherit NoCoW. The `-x` flag keeps traversal on the source filesystem.

```sh
sudo cp -ax --reflink=never /mnt/@example-state.before-nocow/. /mnt/@example-state/
```

Look up the replacement subvolume's ID.

```sh
sudo btrfs subvolume show /mnt/@example-state
```

If fstab uses `subvolid=`, update it to the replacement's ID before mounting. An entry that uses the path alone continues to select `@example-state`. From a live USB, edit the **installed system's** fstab. Mount the replacement, verify its data and attributes, and test the services that use it before deleting the original.
