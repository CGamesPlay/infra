# Private development server

This directory contains scripts to create a private development server with automatic shutdown capabilities (a.k.a. sace-to-zero). To accomplish this, we create a cloud storage volume from which we boot an ephemeral server.

The most straightforward way to accomplish this is to create a server snapshot which has the bootloader configured to boot from an attached cloud volume. However, Hetzner restoration from snapshots is slow and while booting from an external volume works, it's officially unsupported and has reliability issues (the order in which the drives are attached is arbitrary). Instead, we use a standard disk image, boot directly into rescue mode, and from rescue mode kexec into the kernel installed on the ephemeral drive.

## Setting up Hetzner Cloud

I recommend creating a new Project with a new API key in Hetzner Cloud specifically for your dev server. This is because the server itself will have an access key to the project to be able to automatically shutdown, and by using a separate project, you prevent a compromised server from being able to affect your other projects.

## Creating the snapshot and volume

Use `hetzner-boot-volume create` to create a new bootable volume.

**TODO:** this command is not yet implemented. It needs to replace the `robo create-bootable-volume` script, but the setup is much simpler.

1. Clone the base image to the cloud volume.
2. Make the necessary changes to cloud-init.
3. Install `/sbin/kexec-boot.sh`.

:warning: The following is outdated information:

Set the environment variable `HCLOUD_TOKEN` to your Hetzner API key for the custom project you created.

Use the script `robo create-bootable-volume NAME SSH_KEY` to create a volume named NAME and a corresponding server snapshot. The snapshot and volume are not tied to one another; if you have multiple bootable volumes, you only need a single snapshot to boot from any of them.

The volume will be formatted as a single file system (no partition table), consuming the full size of the volume. You can resize this using Hetzner console later if you need additional space.

The snapshot will have the default two small boot partitions that Hetzner includes in their images, then a 4G swap partition, then an ephemeral storage partition which is automatically resized to consume the full disk by cloud-init on server boot.

```
NAME   MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
sda      8:0    0 38.1G  0 disk
├─sda1   8:1    0    1M  0 part
├─sda2   8:2    0  256M  0 part /boot/efi
├─sda3   8:3    0    4G  0 part [SWAP]
└─sda4   8:4    0    4G  0 part /media/ephemeral
sdb      8:16   0   10G  0 disk /
```

## Initial boot

The create-bootable-volume script will perform an initial boot using cloud-config provided in the script. However, beyond the initial boot, there is a caveat regarding cloud-init.

Because the drive is now persistent but the instance ID of the machine will change with every boot, cloud-init wants to do things like regenerate the SSH host keys and reset the root password on every boot. To prevent this, the volume is configured to run most once-per-instance modules as once modules instead. This means that on the initial boot, your cloud-config will work as normal, but afterwards it will be almost completely ignored. We can't completely disable cloud-init because we need it to configure the networking of the instance.

Note that since these modules will only run exactly once, any ssh keys set when creating a new instance of the server will be ignored, and the root password displayed when not using SSH keys will be a useless random string.

## Ready to use

The create-bootable-volume script shows a command that you can use to create a new server using the volume. Inside the machine, running `poweroff` will semi-gracefully shut down the server, and then delete it. Semi-gracefully means that most system services will be stopped and the disk will be synced, but the drive will not be unmounted cleanly and some core systemd services (responsible for network, logging, etc.) are still running during when the system is halted.
