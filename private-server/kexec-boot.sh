#!/bin/bash
set -eux

ROOT_DRIVE_UUID=$(df --output=source /mnt | tail -n1 | xargs lsblk -no uuid)
EPHEMERAL_DRIVE=$(lsblk -SAno name,model | grep 'QEMU HARDDISK' | awk '{print $1}')

# Prepare the ephemeral drive
sgdisk "/dev/$EPHEMERAL_DRIVE" -o
sgdisk "/dev/$EPHEMERAL_DRIVE" \
	-n 0:0:+4G -t 0:8200 -c 0:swap \
	-n 0:0:0 -t 0:8300 -c 0:ephemeral
udevadm settle
mkswap /dev/disk/by-partlabel/swap
mkfs.ext4 /dev/disk/by-partlabel/ephemeral

# Boot into the system
/mnt/usr/sbin/kexec -l /mnt/boot/vmlinuz --initrd /mnt/boot/initrd.img \
	--command-line "root=UUID=$ROOT_DRIVE_UUID ro consoleblank=0 systemd.show_status=true console=tty1 console=ttyS0"
nohup bash -c "sleep 1; /mnt/usr/sbin/kexec -e" &
