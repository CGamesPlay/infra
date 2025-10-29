# Storage Management

## Expanding the storage drive

The storage drive can be expanded. Once you increase the physical size of the disk, reboot to have cloud-init automatically resize the encrypted container to fit. Unseal the vault, and then run `resize2fs /dev/mapper/data` to expand the filesystem.
