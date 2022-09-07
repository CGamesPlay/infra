# Private development server

This directory contains scripts to create a private development server with automatic shutdown capabilities.

## Setting up Hetzner Cloud

I recommend creating a new Project with a new API key in Hetzner Cloud specifically for your dev server. This is because the server itself will have an access key to the project to be able to automatically shutdown, and by using a separate project, you prevent a compromised server from being able to affect your other projects.

## Creating the snapshot and volume

Set the environment variable `HCLOUD_TOKEN` to your Hetzner API key for the custom project you created.

Use the script `robo new-template NAME SSH_KEY` to create a volume named NAME and a corresponding server snapshot. The snapshot and volume are not tied to one another; if you have multiple bootable volumes, you only need a single snapshot to boot from any of them.

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

The new-template script shows a command that you can use to create a new server using the volume. If you want to use cloud-init to customize the machine, you should create the server using your desired cloud-config now as an initial boot.

Because the drive is now persistent but the instance ID of the machine will change with every boot, cloud-init wants to do things like regenerate the SSH host keys and reset the root password on every boot. To prevent this, the template is configured to run most once-per-instance modules as once modules instead. This means that on the initial boot, your cloud-config will work as normal, but afterwards it will be almost completely ignored. We can't completely disable cloud-init because we need it to configure the networking of the instance.

Note that since these modules will only run exactly once, any ssh keys set when creating a new instance of the server will be ignored, and the root password displayed when not using SSH keys will be a useless random string.
